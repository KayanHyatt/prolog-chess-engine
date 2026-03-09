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
Upgraded search:
- Alpha-beta with:
  - transposition table (TT)
  - move ordering (captures/promos/checks + killer + history)
  - quiescence search at depth 0 (captures/promos/checks)

BUG FIXES applied:
  1. gives_check/3 now always calls unmake_move (was corrupting position)
  2. aspiration_search uses fresh variables for widening calls
  3. Depth is pre-evaluated (D1 is Depth-1) before recursive calls so
     killers/history/TT store integer depths, not compound terms
  4. LMR else-branch uses fresh variable to avoid unification failure
  5. cap_tt_size counts once instead of O(n^2) findall loop
*/

:- dynamic tt/5.          % tt(Hash, Depth, Flag, Score, BestMove)
:- dynamic killer/3.      % killer(Depth, M1, M2)
:- dynamic hist/2.        % hist(Key, Value)

:- dynamic search_deadline/1.
:- dynamic node_counter/1.

inf(1000000).

reset_tables :-
    retractall(tt(_,_,_,_,_)),
    retractall(killer(_,_,_)),
    retractall(hist(_,_)).

% --------------------------
% Iterative deepening + time control
% --------------------------

% best_move_timed(+Pos,+Color,+MaxDepth,+TimeMs,-BestMove,-BestScore)
% Searches depth=1..MaxDepth until the time budget expires.
best_move_timed(Pos, Color, MaxDepth, TimeMs, BestMove, BestScore) :-
    get_time(Now),
    Deadline is Now + (TimeMs/1000.0),
    retractall(search_deadline(_)),
    asserta(search_deadline(Deadline)),
    retractall(node_counter(_)),
    asserta(node_counter(0)),
    inf(I),
    loop_depth(1, MaxDepth, Pos, Color, -I, I, none, 0, BestMove, BestScore).

loop_depth(D, MaxD, _Pos, _Color, _A, _B, CurM, CurS, CurM, CurS) :-
    D > MaxD, !.
loop_depth(D, MaxD, Pos, Color, Alpha0, Beta0, CurM, CurS, BestM, BestS) :-
    ( catch(aspiration_search(Pos, Color, D, CurS, Alpha0, Beta0, M, S), timeout, fail)
    -> CurM2=M, CurS2=S
    ;  CurM2=CurM, CurS2=CurS
    ),
    ( time_up -> BestM = CurM2, BestS = CurS2
    ; D1 is D+1,
      loop_depth(D1, MaxD, Pos, Color, Alpha0, Beta0, CurM2, CurS2, BestM, BestS)
    ).

% aspiration_search(+Pos,+Color,+Depth,+PrevScore,+A0,+B0,-Move,-Score)
% Uses a small window around the previous score; widens if it fails.
%
% FIX #2: Use fresh variables M0/S0 for initial search so widening calls
% don't fail from trying to rebind already-bound output variables.
aspiration_search(Pos, Color, Depth, Prev, A0, B0, BestMove, BestScore) :-
    Window is 50,
    ( Prev =:= 0 -> Alpha is A0, Beta is B0
    ; Alpha is max(A0, Prev-Window),
      Beta  is min(B0, Prev+Window)
    ),
    catch(alphabeta_root(Pos, Color, Depth, Alpha, Beta, M0, S0), timeout, throw(timeout)),
    ( S0 =< Alpha -> % fail-low: widen
        catch(alphabeta_root(Pos, Color, Depth, A0, Beta, BestMove, BestScore), timeout, throw(timeout))
    ; S0 >= Beta -> % fail-high: widen
        catch(alphabeta_root(Pos, Color, Depth, Alpha, B0, BestMove, BestScore), timeout, throw(timeout))
    ; BestMove = M0, BestScore = S0
    ).

% best_move(+Pos, +Color, +Depth, -BestMove, -BestScore)
best_move(Pos, Color, Depth, BestMove, BestScore) :-
    inf(I),
    Alpha0 is -I,
    Beta0  is  I,
    alphabeta_root(Pos, Color, Depth, Alpha0, Beta0, BestMove, BestScore).

alphabeta_root(Pos, Color, Depth, Alpha, Beta, BestMove, BestScore) :-
    ordered_moves(Pos, Color, Depth, Moves),
    search_root_moves(Pos, Color, Depth, Alpha, Beta, Moves, none, -1000000000, BestMove, BestScore).

% FIX #3: Pre-evaluate Depth-1 so recursive calls pass an integer.
search_root_moves(_Pos, _Color, _Depth, _A, _B, [], CurM, CurS, CurM, CurS).
search_root_moves(Pos, Color, Depth, Alpha, Beta, [M|Ms], CurM, CurS, BestM, BestS) :-
    position:make_move(Pos, M, Undo),
    other_color(Color, Opp),
    D1 is Depth - 1,
    A1 is -Beta, B1 is -Alpha,
    alphabeta(Pos, Opp, D1, A1, B1, _Reply, ReplyScore),
    position:unmake_move(Pos, Undo),
    Score is -ReplyScore,
    ( Score > CurS -> CurM2=M, CurS2=Score ; CurM2=CurM, CurS2=CurS ),
    Alpha2 is max(Alpha, Score),
    ( Alpha2 >= Beta ->
        BestM = CurM2, BestS = CurS2
    ; search_root_moves(Pos, Color, Depth, Alpha2, Beta, Ms, CurM2, CurS2, BestM, BestS)
    ).

% alphabeta(+Pos,+Color,+Depth,+Alpha,+Beta,-Move,-Score)
alphabeta(Pos, Color, Depth, Alpha, Beta, BestMove, BestScore) :-
    tick,
    ( time_up -> throw(timeout) ; true ),
    ( Depth =< 0 ->
        quiescence(Pos, Color, Alpha, Beta, BestMove, BestScore), !
    ; tt_probe(Pos, Color, Depth, Alpha, Beta, ProbeMove, ProbeScore, Hit),
      Hit == true ->
        BestMove = ProbeMove,
        BestScore = ProbeScore, !
    ; null_move_prune(Pos, Color, Depth, Alpha, Beta, CutScore) ->
        BestMove = none,
        BestScore = CutScore, !
    ; % terminal: no legal moves
      \+ movegen:legal_move(Pos, Color, _) ->
        terminal_score(Pos, Color, BestScore),
        BestMove = none, !
    ; ordered_moves(Pos, Color, Depth, Moves),
      search_moves_pvs(Pos, Color, Depth, Alpha, Beta, Moves, 1, none, -1000000000, BestMove, BestScore),
      tt_store(Pos, Color, Depth, Alpha, Beta, BestScore, BestMove)
    ).

terminal_score(Pos, Color, Score) :-
    ( movegen:in_check(Pos, Color) -> Score is -999999 ; Score is 0 ).

% --- TT ---
tt_key(Pos, Color, Hash) :-
    % Phase-2: use incremental zobrist key (already includes side-to-move).
    position:zobrist_key(Pos, K),
    % Keep Color in key for backward compatibility if callers pass mismatched Color.
    term_hash(K-Color, Hash).

tt_probe(Pos, Color, Depth, Alpha, Beta, BestMove, Score, Hit) :-
    tt_key(Pos, Color, H),
    ( tt(H, D0, Flag, S0, M0),
      D0 >= Depth ->
        ( Flag == exact ->
            BestMove = M0, Score = S0, Hit = true
        ; Flag == lower, S0 >= Beta ->
            BestMove = M0, Score = S0, Hit = true
        ; Flag == upper, S0 =< Alpha ->
            BestMove = M0, Score = S0, Hit = true
        ; Hit = false
        )
    ; Hit = false
    ).

% tt_bestmove(+Pos,+Color,-Move)
% Fetch a stored best move for ordering purposes even if it cannot be used
% as a cutoff for the current window.
tt_bestmove(Pos, Color, Move) :-
    tt_key(Pos, Color, H),
    tt(H, _D, _Flag, _S, Move),
    Move \== none, !.

tt_store(Pos, Color, Depth, Alpha, Beta, Score, BestMove) :-
    tt_key(Pos, Color, H),
    ( Score =< Alpha -> Flag = upper
    ; Score >= Beta  -> Flag = lower
    ; Flag = exact
    ),
    retractall(tt(H,_,_,_,_)),
    assertz(tt(H, Depth, Flag, Score, BestMove)),
    cap_tt_size(20000).

% FIX #5: Count TT entries once, then retract excess.
% Old code did findall+length inside a recursive loop = O(n^2).
cap_tt_size(Max) :-
    ( predicate_property(tt(_,_,_,_,_), number_of_clauses(N)) -> true ; N = 0 ),
    Excess is N - Max,
    ( Excess > 0 -> retract_n(Excess) ; true ).

retract_n(0) :- !.
retract_n(N) :-
    N > 0,
    ( retract(tt(_,_,_,_,_)) -> true ; true ),
    N1 is N - 1,
    retract_n(N1).

% --- Quiescence search ---
quiescence(Pos, Color, Alpha, Beta, none, Score) :-
    tick,
    ( time_up -> throw(timeout) ; true ),
    eval:evaluate_for(Color, Pos, Stand),
    ( Stand >= Beta -> Score = Stand, !
    ; Alpha1 is max(Alpha, Stand),
      tactical_moves(Pos, Color, TMs),
      q_search_moves(Pos, Color, Alpha1, Beta, TMs, Stand, Score)
    ).

q_search_moves(_Pos, _Color, _A, _B, [], Best, Best).
q_search_moves(Pos, Color, Alpha, Beta, [M|Ms], CurBest, BestScore) :-
    position:make_move(Pos, M, Undo),
    other_color(Color, Opp),
    A1 is -Beta, B1 is -Alpha,
    quiescence(Pos, Opp, A1, B1, _RM, ReplyScore),
    position:unmake_move(Pos, Undo),
    Score is -ReplyScore,
    CurBest2 is max(CurBest, Score),
    Alpha2 is max(Alpha, Score),
    ( Alpha2 >= Beta -> BestScore = CurBest2
    ; q_search_moves(Pos, Color, Alpha2, Beta, Ms, CurBest2, BestScore)
    ).

tactical_moves(Pos, Color, Moves) :-
    findall(S-M,
        ( movegen:legal_move(Pos, Color, M),
          tactical_score(Pos, Color, M, S),
          S > 0
        ),
        Pairs0),
    keysort(Pairs0, Pairs),
    reverse(Pairs, Rev),
    findall(M, member(_-M, Rev), Moves).

tactical_score(Pos, Color, M, S) :-
    ( is_promotion(M) -> Promo = 100000 ; Promo = 0 ),
    ( is_capture(Pos, Color, M, CapV) -> Cap = 50000 + CapV ; Cap = 0 ),
    % Avoid check-only moves in qsearch; they can explode the tree.
    S is Promo + Cap.

% --- Main move ordering ---
ordered_moves(Pos, Color, Depth, Moves) :-
    ( tt_bestmove(Pos, Color, TTMove) -> true ; TTMove = none ),
    findall(S-M,
        ( movegen:legal_move(Pos, Color, M),
          move_order_score(Pos, Color, Depth, M, S)
        ),
        Pairs0),
    keysort(Pairs0, Pairs),
    reverse(Pairs, Rev),
    findall(M, member(_-M, Rev), Ms0),
    ( TTMove \== none ->
        select(TTMove, Ms0, Rest) -> Moves = [TTMove|Rest] ; Moves = Ms0
    ; Moves = Ms0 ).

move_order_score(Pos, Color, Depth, M, Score) :-
    ( is_promotion(M) -> Promo = 100000 ; Promo = 0 ),
    ( is_capture(Pos, Color, M, CapV) -> Cap = 50000 + CapV ; Cap = 0 ),
    ( gives_check(Pos, Color, M) -> Chk = 12000 ; Chk = 0 ),
    killer_bonus(Depth, M, K),
    history_bonus(M, H),
    tt_bonus(Pos, Color, M, TTB),
    Score is Promo + Cap + Chk + K + H + TTB.

tt_bonus(Pos, Color, M, 200000) :-
    tt_bestmove(Pos, Color, M), !.
tt_bonus(_,_,_,0).

killer_bonus(Depth, M, 9000) :-
    killer(Depth, M, _), !.
killer_bonus(Depth, M, 8000) :-
    killer(Depth, _, M), !.
killer_bonus(_Depth, _M, 0).

history_bonus(M, H) :-
    move_key(M, K),
    ( hist(K, V) -> H is min(7000, V) ; H = 0 ).

move_key(M, K) :- K = M.

% --- Alpha-beta with PVS + LMR ---
% FIX #3: Pre-evaluate Depth-1 before recursive alphabeta calls.
search_moves_pvs(_Pos, _Color, _Depth, _A, _B, [], _I, CurM, CurS, CurM, CurS).
search_moves_pvs(Pos, Color, Depth, Alpha, Beta, [M|Ms], I, CurM, CurS, BestM, BestS) :-
    position:make_move(Pos, M, Undo),
    other_color(Color, Opp),
    D1 is Depth - 1,

    ( I =:= 1 ->
        % full window on first move
        A1 is -Beta, B1 is -Alpha,
        alphabeta(Pos, Opp, D1, A1, B1, _Reply, ReplyScore),
        Score is -ReplyScore
    ; % null-window search (PVS)
      A1 is -(Alpha+1), B1 is -Alpha,
      alphabeta(Pos, Opp, D1, A1, B1, _R1, R1Score),
      S1 is -R1Score,
      ( S1 > Alpha, S1 < Beta ->
          % re-search with full window
          A2 is -Beta, B2 is -Alpha,
          alphabeta(Pos, Opp, D1, A2, B2, _R2, R2Score),
          Score is -R2Score
      ; Score = S1 )
    ),

    position:unmake_move(Pos, Undo),

    ( Score > CurS -> CurM2 = M, CurS2 = Score ; CurM2 = CurM, CurS2 = CurS ),
    Alpha2 is max(Alpha, Score),

    ( Alpha2 >= Beta ->
        note_killer(Depth, M),
        note_history(M, Depth),
        BestM = CurM2, BestS = CurS2
    ; I1 is I+1,
      % LMR: reduce late quiet moves
      maybe_reorder_lmr(Pos, Color, Depth, Alpha2, Beta, Ms, I1, CurM2, CurS2, BestM, BestS)
    ).

maybe_reorder_lmr(Pos, Color, Depth, Alpha, Beta, Ms, I, CurM, CurS, BestM, BestS) :-
    search_moves_lmr(Pos, Color, Depth, Alpha, Beta, Ms, I, CurM, CurS, BestM, BestS).

% FIX #3 + FIX #4: Pre-evaluate depth; use fresh variable in else-branch.
search_moves_lmr(_Pos, _Color, _Depth, _A, _B, [], _I, CurM, CurS, CurM, CurS).
search_moves_lmr(Pos, Color, Depth, Alpha, Beta, [M|Ms], I, CurM, CurS, BestM, BestS) :-
    D1 is Depth - 1,
    ( Depth >= 3,
      I > 3,
      quiet_move(Pos, Color, M),
      lmr_reduction(Depth, I, Red),
      Red > 0
    ->
      % reduced-depth search
      position:make_move(Pos, M, Undo),
      other_color(Color, Opp),
      Dred is max(0, D1-Red),
      A1 is -(Alpha+1), B1 is -Alpha,
      alphabeta(Pos, Opp, Dred, A1, B1, _R1, R1Score),
      S1 is -R1Score,
      ( S1 > Alpha ->
          % verify at full depth/window
          A2 is -(Beta), B2 is -Alpha,
          alphabeta(Pos, Opp, D1, A2, B2, _R2, R2Score),
          Score is -R2Score
      ; Score = S1 ),
      position:unmake_move(Pos, Undo)
    ;
      % FIX #4: Use S1 for null-window result, Score for final result.
      % Old code bound Score twice causing unification failure on PVS re-search.
      position:make_move(Pos, M, Undo),
      other_color(Color, Opp),
      A1 is -(Alpha+1), B1 is -Alpha,
      alphabeta(Pos, Opp, D1, A1, B1, _R0, R0Score),
      S1 is -R0Score,
      ( S1 > Alpha, S1 < Beta ->
          A2 is -Beta, B2 is -Alpha,
          alphabeta(Pos, Opp, D1, A2, B2, _RR, RRScore),
          Score is -RRScore
      ; Score = S1 ),
      position:unmake_move(Pos, Undo)
    ),

    ( Score > CurS -> CurM2=M, CurS2=Score ; CurM2=CurM, CurS2=CurS ),
    Alpha2 is max(Alpha, Score),
    ( Alpha2 >= Beta ->
        note_killer(Depth, M),
        note_history(M, Depth),
        BestM=CurM2, BestS=CurS2
    ; I1 is I+1,
      search_moves_lmr(Pos, Color, Depth, Alpha2, Beta, Ms, I1, CurM2, CurS2, BestM, BestS)
    ).

quiet_move(Pos, Color, M) :-
    \+ is_capture(Pos, Color, M, _),
    \+ is_promotion(M),
    \+ gives_check(Pos, Color, M).

lmr_reduction(Depth, I, 2) :- Depth >= 6, I > 6, !.
lmr_reduction(Depth, I, 1) :- Depth >= 3, I > 3, !.
lmr_reduction(_,_,0).

% --------------------------
% Null move pruning
% --------------------------

null_move_prune(Pos, Color, Depth, Alpha, Beta, Beta) :-
    Depth >= 3,
    \+ movegen:in_check(Pos, Color),
    null_allowed(Pos),
    R = 2,
    position:make_null_move(Pos, Undo),
    other_color(Color, Opp),
    D2 is Depth-1-R,
    A1 is -Beta, B1 is -(Beta-1),
    alphabeta(Pos, Opp, D2, A1, B1, _M, S),
    position:unmake_null_move(Pos, Undo),
    Score is -S,
    Score >= Beta,
    % avoid returning lower than beta
    Alpha < Beta.

null_allowed(Pos) :-
    % crude zugzwang guard: avoid null move in very low-material endgames
    arg(2, Pos, pl(_WP,WN,WB,WR,WQ,_WK,_BP,BN,BB,BR,BQ,_BK)),
    length(WN, N1), length(WB, B1), length(WR, R1), length(WQ, Q1),
    length(BN, N2), length(BB, B2), length(BR, R2), length(BQ, Q2),
    NonPawn is N1+B1+R1+Q1+N2+B2+R2+Q2,
    NonPawn >= 3.

% --------------------------
% Time checks
% --------------------------

tick :-
    ( retract(node_counter(N0)) -> true ; N0 = 0 ),
    N is N0 + 1,
    asserta(node_counter(N)).

time_up :-
    ( search_deadline(DL) -> true ; fail ),
    ( node_counter(N) -> true ; N = 0 ),
    ( 0 is N mod 2048 ->
        get_time(Now), Now >= DL
    ; fail ).

note_killer(Depth, M) :-
    ( killer(Depth, M, _) -> true
    ; killer(Depth, _, M) -> true
    ; ( retract(killer(Depth, K1, _)) ->
          assertz(killer(Depth, M, K1))
      ; assertz(killer(Depth, M, none))
      )
    ).

note_history(M, Depth) :-
    move_key(M, K),
    Inc is Depth*Depth*50,
    ( retract(hist(K, V0)) -> V is V0 + Inc ; V = Inc ),
    assertz(hist(K, V)).

% --- Move features ---
is_promotion(M) :-
    sub_string(M, _, 1, 0, C),
    member(C, ["q","r","b","n","Q","R","B","N"]).

is_capture(Pos, Color, M, CapV) :-
    uci_to_toSq(M, ToSq),
    other_color(Color, Enemy),
    ( position:piece(Pos, Enemy, T, ToSq) ->
        victim_value(T, CapV)
    ; CapV = 0, fail ).

victim_value(pawn, 100).
victim_value(knight, 320).
victim_value(bishop, 330).
victim_value(rook, 500).
victim_value(queen, 900).
victim_value(king, 0).

% FIX #1: gives_check MUST always call unmake_move.
% Old code: ( in_check -> true ; false ) — when in_check fails, 'false' fails
% the clause, skipping unmake_move. Since make_move uses destructive setarg,
% the position is left permanently corrupted.
% Fix: capture the result in a flag, always unmake, then test the flag.
gives_check(Pos, Color, M) :-
    position:make_move(Pos, M, Undo),
    other_color(Color, Enemy),
    ( movegen:in_check(Pos, Enemy) -> Check = true ; Check = false ),
    position:unmake_move(Pos, Undo),
    Check == true.

uci_to_toSq(Move, ToSq) :-
    sub_string(Move, 2, 2, _, ToStr),
    position:sq_index(ToStr, ToSq).

other_color(white, black).
other_color(black, white).