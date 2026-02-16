:- module(search, [
    best_move/5
]).

:- use_module(position).
:- use_module(movegen).
:- use_module(eval).

other_color(white, black).
other_color(black, white).

inf(1000000).

% best_move(+Pos, +Color, +Depth, -BestMove, -BestScore)
best_move(Pos, Color, Depth, BestMove, BestScore) :-
    inf(I),
    Alpha0 is -I,
    Beta0  is  I,
    alphabeta(Pos, Color, Depth, Alpha0, Beta0, BestMove, BestScore).

% alphabeta(+Pos,+Color,+Depth,+Alpha,+Beta,-Move,-Score)
alphabeta(Pos, Color, 0, _A, _B, none, Score) :-
    eval:evaluate_for(Color, Pos, Score), !.

alphabeta(Pos, Color, _Depth, _A, _B, none, Score) :-
    \+ movegen:legal_move(Pos, Color, _),
    terminal_score(Pos, Color, Score), !.

alphabeta(Pos, Color, Depth, Alpha, Beta, BestMove, BestScore) :-
    D1 is Depth - 1,
    inf(I),
    CurBestScore0 is -I,
    ordered_moves(Pos, Color, Moves),
    search_moves_list(Pos, Color, D1, Alpha, Beta, Moves, none, CurBestScore0, BestMove, BestScore).

terminal_score(Pos, Color, Score) :-
    ( movegen:in_check(Pos, Color) ->
        Score is -999999
    ; Score is 0
    ).

ordered_moves(Pos, Color, Moves) :-
    findall(M, movegen:legal_move(Pos, Color, M), Ms0),
    predsort(compare_moves(Pos, Color), Ms0, Moves).

compare_moves(Pos, Color, Delta, M1, M2) :-
    move_score(Pos, Color, M1, S1),
    move_score(Pos, Color, M2, S2),
    compare(Delta0, S2, S1),  % descending
    Delta = Delta0.

move_score(Pos, Color, Move, Score) :-
    ( sub_string(Move, _, 1, 0, "q") -> Promo = 10000 ; Promo = 0 ),
    ( uci_to_toSq(Move, ToSq),
      enemy_on_square(Pos, Color, ToSq) -> Cap = 5000 ; Cap = 0 ),
    Score is Promo + Cap.

uci_to_toSq(Move, ToSq) :-
    sub_string(Move, 2, 2, _, ToStr),
    position:sq_index(ToStr, ToSq).

enemy_on_square(Pos, Color, Sq) :-
    (Color = white -> Enemy = black ; Enemy = white),
    position:piece(Pos, Enemy, _, Sq).

search_moves_list(_Pos, _Color, _Depth, _Alpha, _Beta, [], CurM, CurS, CurM, CurS).
search_moves_list(Pos, Color, Depth, Alpha, Beta, [M|Ms], CurM, CurS, BestM, BestS) :-
    position:apply_move(Pos, M, Pos2),
    other_color(Color, Opp),
    A1 is -Beta, B1 is -Alpha,
    alphabeta(Pos2, Opp, Depth, A1, B1, _Reply, ReplyScore),
    Score is -ReplyScore,
    ( Score > CurS -> CurM2=M, CurS2=Score ; CurM2=CurM, CurS2=CurS ),
    Alpha2 is max(Alpha, Score),
    ( Alpha2 >= Beta ->
        BestM = CurM2, BestS = CurS2
    ; search_moves_list(Pos, Color, Depth, Alpha2, Beta, Ms, CurM2, CurS2, BestM, BestS)
    ).
