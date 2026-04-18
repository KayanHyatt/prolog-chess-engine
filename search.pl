:- module(search, [
    best_move/5,
    best_move_timed/6,
    reset_tables/0
]).

:- use_module(library(lists)).
:- use_module(position).
:- use_module(movegen).
:- use_module(eval).

/*
Speed-optimized search:
- Removed gives_check from move ordering (was cloning entire position per move)
- quiet_move no longer calls gives_check (just checks capture/promotion)
- All other improvements retained: check extensions, futility, MVV-LVA,
  delta pruning, lazy eval in qsearch, 100k TT
*/

:- dynamic tt/5.
:- dynamic killer/3.
:- dynamic hist/2.
:- dynamic search_deadline/1.
:- dynamic node_counter/1.

inf(1000000).

reset_tables :-
    retractall(tt(_,_,_,_,_)),
    retractall(killer(_,_,_)),
    retractall(hist(_,_)).

% --- Iterative deepening + time control ---

best_move_timed(Pos, Color, MaxDepth, TimeMs, BestMove, BestScore) :-
    get_time(Now),
    Deadline is Now + (TimeMs/1000.0),
    retractall(search_deadline(_)),
    asserta(search_deadline(Deadline)),
    retractall(node_counter(_)),
    asserta(node_counter(0)),
    inf(I),
    loop_depth(1, MaxDepth, Pos, Color, -I, I, none, 0, BestMove, BestScore).

loop_depth(D, MaxD, _Pos, _Color, _A, _B, CurM, CurS, CurM, CurS) :- D > MaxD, !.
loop_depth(D, MaxD, Pos, Color, Alpha0, Beta0, CurM, CurS, BestM, BestS) :-
    ( catch(aspiration_search(Pos, Color, D, CurS, Alpha0, Beta0, M, S), timeout, fail)
    -> CurM2=M, CurS2=S
    ;  CurM2=CurM, CurS2=CurS
    ),
    ( time_up -> BestM = CurM2, BestS = CurS2
    ; D1 is D+1,
      loop_depth(D1, MaxD, Pos, Color, Alpha0, Beta0, CurM2, CurS2, BestM, BestS)
    ).

aspiration_search(Pos, Color, Depth, Prev, A0, B0, BestMove, BestScore) :-
    Window is 50,
    ( Prev =:= 0 -> Alpha is A0, Beta is B0
    ; Alpha is max(A0, Prev-Window), Beta is min(B0, Prev+Window)
    ),
    catch(alphabeta_root(Pos, Color, Depth, Alpha, Beta, M0, S0), timeout, throw(timeout)),
    ( S0 =< Alpha ->
        catch(alphabeta_root(Pos, Color, Depth, A0, Beta, BestMove, BestScore), timeout, throw(timeout))
    ; S0 >= Beta ->
        catch(alphabeta_root(Pos, Color, Depth, Alpha, B0, BestMove, BestScore), timeout, throw(timeout))
    ; BestMove = M0, BestScore = S0
    ).

best_move(Pos, Color, Depth, BestMove, BestScore) :-
    inf(I), Alpha0 is -I, Beta0 is I,
    alphabeta_root(Pos, Color, Depth, Alpha0, Beta0, BestMove, BestScore).

alphabeta_root(Pos, Color, Depth, Alpha, Beta, BestMove, BestScore) :-
    ordered_moves(Pos, Color, Depth, Moves),
    search_root(Pos, Color, Depth, Alpha, Beta, Moves, none, -1000000000, BestMove, BestScore).

search_root(_,_,_,_,_,[],CurM,CurS,CurM,CurS).
search_root(Pos, Color, Depth, Alpha, Beta, [M|Ms], CurM, CurS, BestM, BestS) :-
    position:make_move(Pos, M, Undo),
    other_color(Color, Opp),
    % Check extension at root
    ( movegen:in_check(Pos, Opp) -> D1 is Depth ; D1 is Depth-1 ),
    A1 is -Beta, B1 is -Alpha,
    alphabeta(Pos, Opp, D1, A1, B1, _, ReplyScore),
    position:unmake_move(Pos, Undo),
    Score is -ReplyScore,
    ( Score > CurS -> CurM2=M, CurS2=Score ; CurM2=CurM, CurS2=CurS ),
    Alpha2 is max(Alpha, Score),
    ( Alpha2 >= Beta -> BestM=CurM2, BestS=CurS2
    ; search_root(Pos, Color, Depth, Alpha2, Beta, Ms, CurM2, CurS2, BestM, BestS)
    ).

% --- Main alpha-beta ---

alphabeta(Pos, Color, Depth, Alpha, Beta, BestMove, BestScore) :-
    tick,
    ( time_up -> throw(timeout) ; true ),
    ( Depth =< 0 ->
        quiescence(Pos, Color, Alpha, Beta, BestMove, BestScore), !
    ; tt_probe(Pos, Color, Depth, Alpha, Beta, ProbeMove, ProbeScore, Hit),
      Hit == true ->
        BestMove = ProbeMove, BestScore = ProbeScore, !
    ; null_move_prune(Pos, Color, Depth, Alpha, Beta, CutScore) ->
        BestMove = none, BestScore = CutScore, !
    ; \+ movegen:legal_move(Pos, Color, _) ->
        terminal_score(Pos, Color, BestScore), BestMove = none, !
    ; ordered_moves(Pos, Color, Depth, Moves),
      ( Depth =< 3 ->
          catch(eval:evaluate_for(Color, Pos, SE), _, SE = 0)
      ; SE = 0
      ),
      search_pvs(Pos, Color, Depth, Alpha, Beta, Moves, 1, none, -1000000000, SE, BestMove, BestScore),
      tt_store(Pos, Color, Depth, Alpha, Beta, BestScore, BestMove)
    ).

terminal_score(Pos, Color, Score) :-
    ( movegen:in_check(Pos, Color) -> Score is -999999 ; Score is 0 ).

% --- TT ---
tt_key(Pos, Color, Hash) :- position:zobrist_key(Pos, K), term_hash(K-Color, Hash).

tt_probe(Pos, Color, Depth, Alpha, Beta, BestMove, Score, Hit) :-
    tt_key(Pos, Color, H),
    ( tt(H, D0, Flag, S0, M0), D0 >= Depth ->
        ( Flag == exact -> BestMove=M0, Score=S0, Hit=true
        ; Flag == lower, S0 >= Beta -> BestMove=M0, Score=S0, Hit=true
        ; Flag == upper, S0 =< Alpha -> BestMove=M0, Score=S0, Hit=true
        ; Hit = false )
    ; Hit = false ).

tt_bestmove(Pos, Color, Move) :-
    tt_key(Pos, Color, H), tt(H,_,_,_,Move), Move \== none, !.

tt_store(Pos, Color, Depth, Alpha, Beta, Score, BestMove) :-
    tt_key(Pos, Color, H),
    ( Score =< Alpha -> Flag = upper ; Score >= Beta -> Flag = lower ; Flag = exact ),
    retractall(tt(H,_,_,_,_)),
    assertz(tt(H, Depth, Flag, Score, BestMove)),
    cap_tt(100000).

cap_tt(Max) :-
    ( predicate_property(tt(_,_,_,_,_), number_of_clauses(N)) -> true ; N = 0 ),
    Excess is N - Max,
    ( Excess > 0 -> retract_n(Excess) ; true ).

retract_n(0) :- !.
retract_n(N) :- N>0, (retract(tt(_,_,_,_,_))->true;true), N1 is N-1, retract_n(N1).

% --- Quiescence with lazy eval + delta pruning ---

quiescence(Pos, Color, Alpha, Beta, none, Score) :-
    tick,
    ( time_up -> throw(timeout) ; true ),
    eval:evaluate_lazy(Color, Pos, Alpha, Beta, Stand),
    ( Stand >= Beta -> Score = Stand, !
    ; Alpha1 is max(Alpha, Stand),
      tactical_moves(Pos, Color, TMs),
      q_search(Pos, Color, Alpha1, Beta, TMs, Stand, Score)
    ).

q_search(_,_,_,_,[],Best,Best).
q_search(Pos, Color, Alpha, Beta, [M|Ms], CurBest, BestScore) :-
    ( is_capture(Pos, Color, M, CapV) ->
        DeltaMargin is CurBest + CapV + 200,
        ( DeltaMargin < Alpha ->
            q_search(Pos, Color, Alpha, Beta, Ms, CurBest, BestScore)
        ; q_one(Pos, Color, Alpha, Beta, M, Ms, CurBest, BestScore)
        )
    ; q_one(Pos, Color, Alpha, Beta, M, Ms, CurBest, BestScore)
    ).

q_one(Pos, Color, Alpha, Beta, M, Ms, CurBest, BestScore) :-
    position:make_move(Pos, M, Undo),
    other_color(Color, Opp),
    A1 is -Beta, B1 is -Alpha,
    quiescence(Pos, Opp, A1, B1, _, ReplyScore),
    position:unmake_move(Pos, Undo),
    Score is -ReplyScore,
    CurBest2 is max(CurBest, Score),
    Alpha2 is max(Alpha, Score),
    ( Alpha2 >= Beta -> BestScore = CurBest2
    ; q_search(Pos, Color, Alpha2, Beta, Ms, CurBest2, BestScore)
    ).

tactical_moves(Pos, Color, Moves) :-
    findall(S-M,
        ( movegen:legal_move(Pos, Color, M),
          tac_score(Pos, Color, M, S), S > 0 ),
        Pairs0),
    keysort(Pairs0, Pairs), reverse(Pairs, Rev),
    findall(M, member(_-M, Rev), Moves).

tac_score(Pos, Color, M, S) :-
    ( is_promotion(M) -> Promo = 100000 ; Promo = 0 ),
    ( is_capture(Pos, Color, M, CapV) -> Cap = 50000 + CapV ; Cap = 0 ),
    S is Promo + Cap.

% --- Move ordering: NO gives_check (too slow), uses MVV-LVA + killer + history ---

ordered_moves(Pos, Color, Depth, Moves) :-
    ( tt_bestmove(Pos, Color, TTMove) -> true ; TTMove = none ),
    findall(S-M,
        ( movegen:legal_move(Pos, Color, M),
          move_score(Pos, Color, Depth, M, S) ),
        Pairs0),
    keysort(Pairs0, Pairs), reverse(Pairs, Rev),
    findall(M, member(_-M, Rev), Ms0),
    ( TTMove \== none, select(TTMove, Ms0, Rest) -> Moves = [TTMove|Rest] ; Moves = Ms0 ).

move_score(Pos, Color, Depth, M, Score) :-
    ( is_promotion(M) -> Promo = 100000 ; Promo = 0 ),
    ( mvv_lva(Pos, Color, M, CScore) -> Cap = 50000 + CScore ; Cap = 0 ),
    killer_bonus(Depth, M, K),
    history_bonus(M, H),
    tt_bonus(Pos, Color, M, TTB),
    Score is Promo + Cap + K + H + TTB.

mvv_lva(Pos, Color, M, Score) :-
    uci_fromto(M, From, To),
    other_color(Color, Enemy),
    position:piece(Pos, Enemy, VT, To),
    position:piece(Pos, Color, AT, From),
    victim_value(VT, VV), att_val(AT, AV),
    Score is VV*10 - AV.

uci_fromto(Move, From, To) :-
    sub_string(Move, 0, 2, _, FS), sub_string(Move, 2, 2, _, TS),
    position:sq_index(FS, From), position:sq_index(TS, To).

att_val(pawn,1). att_val(knight,3). att_val(bishop,3).
att_val(rook,5). att_val(queen,9). att_val(king,10).

tt_bonus(Pos, Color, M, 200000) :- tt_bestmove(Pos, Color, M), !.
tt_bonus(_,_,_,0).

killer_bonus(Depth, M, 9000) :- killer(Depth, M, _), !.
killer_bonus(Depth, M, 8000) :- killer(Depth, _, M), !.
killer_bonus(_, _, 0).

history_bonus(M, H) :- move_key(M, K), (hist(K, V) -> H is min(7000, V) ; H = 0).
move_key(M, M).

% --- PVS + LMR + Check extensions + Futility ---

search_pvs(_,_,_,_,_,[],_,CurM,CurS,_,CurM,CurS).
search_pvs(Pos, Color, Depth, Alpha, Beta, [M|Ms], I, CurM, CurS, SE, BestM, BestS) :-
    % Futility pruning at low depth for quiet moves
    ( Depth =< 2, I > 1,
      \+ is_capture(Pos, Color, M, _),
      \+ is_promotion(M),
      fut_margin(Depth, Margin),
      SE + Margin =< Alpha
    -> I1 is I+1,
       search_pvs(Pos, Color, Depth, Alpha, Beta, Ms, I1, CurM, CurS, SE, BestM, BestS)
    ;
      position:make_move(Pos, M, Undo),
      other_color(Color, Opp),
      D1 is Depth-1,
      % Check extension: search deeper when giving check
      ( movegen:in_check(Pos, Opp) -> SD is D1+1 ; SD = D1 ),

      ( I =:= 1 ->
          A1 is -Beta, B1 is -Alpha,
          alphabeta(Pos, Opp, SD, A1, B1, _, RS), Score is -RS
      ;   A1 is -(Alpha+1), B1 is -Alpha,
          alphabeta(Pos, Opp, SD, A1, B1, _, R1S), S1 is -R1S,
          ( S1 > Alpha, S1 < Beta ->
              A2 is -Beta, B2 is -Alpha,
              alphabeta(Pos, Opp, SD, A2, B2, _, R2S), Score is -R2S
          ; Score = S1 )
      ),

      position:unmake_move(Pos, Undo),
      ( Score > CurS -> CurM2=M, CurS2=Score ; CurM2=CurM, CurS2=CurS ),
      Alpha2 is max(Alpha, Score),
      ( Alpha2 >= Beta ->
          note_killer(Depth, M), note_history(M, Depth),
          BestM=CurM2, BestS=CurS2
      ; I1 is I+1,
        lmr_loop(Pos, Color, Depth, Alpha2, Beta, Ms, I1, CurM2, CurS2, SE, BestM, BestS)
      )
    ).

fut_margin(1, 250).
fut_margin(2, 450).
fut_margin(_, 0).

lmr_loop(_,_,_,_,_,[],_,CurM,CurS,_,CurM,CurS).
lmr_loop(Pos, Color, Depth, Alpha, Beta, [M|Ms], I, CurM, CurS, SE, BestM, BestS) :-
    % Futility in LMR loop
    ( Depth =< 2, I > 1,
      \+ is_capture(Pos, Color, M, _), \+ is_promotion(M),
      fut_margin(Depth, Margin), SE + Margin =< Alpha
    -> I1 is I+1,
       lmr_loop(Pos, Color, Depth, Alpha, Beta, Ms, I1, CurM, CurS, SE, BestM, BestS)
    ;
      D1 is Depth-1,
      % LMR: reduce late quiet moves
      ( Depth >= 3, I > 3,
        quiet_move(Pos, Color, M),
        lmr_red(Depth, I, Red), Red > 0
      ->
        position:make_move(Pos, M, Undo),
        other_color(Color, Opp),
        ( movegen:in_check(Pos, Opp) -> SD is D1+1 ; SD = D1 ),
        Dred is max(0, SD-Red),
        A1 is -(Alpha+1), B1 is -Alpha,
        alphabeta(Pos, Opp, Dred, A1, B1, _, R1S), S1 is -R1S,
        ( S1 > Alpha ->
            A2 is -Beta, B2 is -Alpha,
            alphabeta(Pos, Opp, SD, A2, B2, _, R2S), Score is -R2S
        ; Score = S1 ),
        position:unmake_move(Pos, Undo)
      ;
        position:make_move(Pos, M, Undo),
        other_color(Color, Opp),
        ( movegen:in_check(Pos, Opp) -> SD is D1+1 ; SD = D1 ),
        A1 is -(Alpha+1), B1 is -Alpha,
        alphabeta(Pos, Opp, SD, A1, B1, _, R0S), S1 is -R0S,
        ( S1 > Alpha, S1 < Beta ->
            A2 is -Beta, B2 is -Alpha,
            alphabeta(Pos, Opp, SD, A2, B2, _, RRS), Score is -RRS
        ; Score = S1 ),
        position:unmake_move(Pos, Undo)
      ),

      ( Score > CurS -> CurM2=M, CurS2=Score ; CurM2=CurM, CurS2=CurS ),
      Alpha2 is max(Alpha, Score),
      ( Alpha2 >= Beta ->
          note_killer(Depth, M), note_history(M, Depth),
          BestM=CurM2, BestS=CurS2
      ; I1 is I+1,
        lmr_loop(Pos, Color, Depth, Alpha2, Beta, Ms, I1, CurM2, CurS2, SE, BestM, BestS)
      )
    ).

% quiet_move: FAST version — just checks it's not a capture or promotion.
% No gives_check call (that was cloning the entire position and killing speed).
quiet_move(Pos, Color, M) :-
    \+ is_capture(Pos, Color, M, _),
    \+ is_promotion(M).

lmr_red(Depth, I, 2) :- Depth >= 6, I > 6, !.
lmr_red(Depth, I, 1) :- Depth >= 3, I > 3, !.
lmr_red(_,_,0).

% --- Null move pruning ---

null_move_prune(Pos, Color, Depth, Alpha, Beta, Beta) :-
    Depth >= 3,
    \+ movegen:in_check(Pos, Color),
    null_ok(Pos),
    R = 2,
    position:make_null_move(Pos, Undo),
    other_color(Color, Opp),
    D2 is Depth-1-R,
    A1 is -Beta, B1 is -(Beta-1),
    alphabeta(Pos, Opp, D2, A1, B1, _, S),
    position:unmake_null_move(Pos, Undo),
    Score is -S, Score >= Beta, Alpha < Beta.

null_ok(Pos) :-
    arg(2, Pos, pl(_WP,WN,WB,WR,WQ,_WK,_BP,BN,BB,BR,BQ,_BK)),
    length(WN,N1), length(WB,B1), length(WR,R1), length(WQ,Q1),
    length(BN,N2), length(BB,B2), length(BR,R2), length(BQ,Q2),
    NonPawn is N1+B1+R1+Q1+N2+B2+R2+Q2, NonPawn >= 3.

% --- Time ---
tick :- (retract(node_counter(N0))->true;N0=0), N is N0+1, asserta(node_counter(N)).

time_up :-
    (search_deadline(DL)->true;fail),
    (node_counter(N)->true;N=0),
    (0 is N mod 2048 -> get_time(Now), Now >= DL ; fail).

note_killer(Depth, M) :-
    (killer(Depth, M, _)->true ; killer(Depth, _, M)->true
    ; (retract(killer(Depth,K1,_))->assertz(killer(Depth,M,K1));assertz(killer(Depth,M,none)))).

note_history(M, Depth) :-
    move_key(M, K), Inc is Depth*Depth*50,
    (retract(hist(K, V0)) -> V is V0+Inc ; V = Inc), assertz(hist(K, V)).

% --- Move features ---
is_promotion(M) :- sub_string(M,_,1,0,C), member(C,["q","r","b","n","Q","R","B","N"]).

is_capture(Pos, Color, M, CapV) :-
    uci_to_toSq(M, ToSq), other_color(Color, Enemy),
    (position:piece(Pos, Enemy, T, ToSq) -> victim_value(T, CapV) ; CapV=0, fail).

victim_value(pawn,100). victim_value(knight,320). victim_value(bishop,330).
victim_value(rook,500). victim_value(queen,900). victim_value(king,0).

uci_to_toSq(Move, ToSq) :-
    sub_string(Move, 2, 2, _, ToStr), position:sq_index(ToStr, ToSq).

other_color(white, black).
other_color(black, white).