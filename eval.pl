:- module(eval, [evaluate_for/3]).

:- use_module(library(aggregate)).
:- use_module(position).
:- use_module(movegen).

% evaluate_for(+MeColor, +Pos, -Score)
% Positive => good for MeColor.
evaluate_for(Me, Pos, Score) :-
    other_color(Me, Them),

    material_psqt(Pos, Me, Them, S_mat),
    pawn_structure(Pos, Me, Them, S_pawns),
    mobility(Pos, Me, Them, S_mob),
    development(Pos, Me, Them, S_dev),

    % No side-to-move predicate assumed in your position, so tempo = 0
    S_tempo = 0,

    weight(material,     Wm),
    weight(pawns,        Wp),
    weight(mobility,     Wmo),
    weight(development,  Wd),
    weight(tempo,        Wt),

    Score is Wm*S_mat
          + Wp*S_pawns
          + Wmo*S_mob
          + Wd*S_dev
          + Wt*S_tempo.

other_color(white, black).
other_color(black, white).

% ---- weights (tune later) ----
weight(material,     1).
weight(pawns,        1).
weight(mobility,     2).
weight(development,  1).
weight(tempo,        1).

% ---- material ----
piece_value(pawn,   100).
piece_value(knight, 320).
piece_value(bishop, 330).
piece_value(rook,   500).
piece_value(queen,  900).
piece_value(king,     0).

material_psqt(Pos, Me, Them, Score) :-
    aggregate_all(sum(V),
        ( position:piece(Pos, Me, Type, Sq),
          piece_value(Type, M),
          psqt_bonus(Type, Me, Sq, P),
          V is M + P
        ),
        MySum),
    aggregate_all(sum(V),
        ( position:piece(Pos, Them, Type, Sq),
          piece_value(Type, M),
          psqt_bonus(Type, Them, Sq, P),
          V is M + P
        ),
        TheirSum),
    Score is MySum - TheirSum.

% ---- tiny “PSQT-like” formulas (safe; always bind P) ----
psqt_bonus(pawn, white, Sq, P) :-
    rank_of(Sq, R),
    P is (R-2)*5.
psqt_bonus(pawn, black, Sq, P) :-
    rank_of(Sq, R),
    P is (7-R)*5.

psqt_bonus(knight, _C, Sq, P) :-
    file_of(Sq, F), rank_of(Sq, R),
    dist_center(F, R, D),
    P is 30 - 10*D.

psqt_bonus(bishop, _C, Sq, P) :-
    file_of(Sq, F), rank_of(Sq, R),
    dist_center(F, R, D),
    P is 20 - 5*D.

psqt_bonus(rook, _C, Sq, P) :-
    rank_of(Sq, R),
    ( (R =:= 2 ; R =:= 7) -> P = 10 ; P = 0 ).

psqt_bonus(queen, _C, _Sq, 0).
psqt_bonus(king,  _C, _Sq, 0).

dist_center(F, R, D) :-
    DC is abs(F-4) + abs(R-4),
    (DC > 3 -> D = 3 ; D = DC).

% 0..63 indexing assumed (a1=0 .. h8=63)
file_of(Sq, F) :- F is (Sq mod 8) + 1.
rank_of(Sq, R) :- R is (Sq // 8) + 1.

% ---- mobility (legal move count difference) ----
mobility(Pos, Me, Them, Score) :-
    catch(aggregate_all(count, movegen:legal_move(Pos, Me, _), M1), _, M1 = 0),
    catch(aggregate_all(count, movegen:legal_move(Pos, Them, _), M2), _, M2 = 0),
    Score is M1 - M2.

% ---- development (tiny anti-shuffle heuristic) ----
development(Pos, Me, Them, Score) :-
    development_one(Pos, Me,  S1),
    development_one(Pos, Them, S2),
    Score is S1 - S2.

development_one(Pos, Color, Score) :-
    aggregate_all(sum(B),
        ( position:piece(Pos, Color, Type, Sq),
          dev_bonus(Type, Color, Sq, B)
        ),
        Score).

dev_bonus(knight, white, Sq, 10) :- Sq =\= 1, Sq =\= 6, !.
dev_bonus(knight, black, Sq, 10) :- Sq =\= 57, Sq =\= 62, !.
dev_bonus(bishop, white, Sq, 10) :- Sq =\= 2, Sq =\= 5, !.
dev_bonus(bishop, black, Sq, 10) :- Sq =\= 58, Sq =\= 61, !.
dev_bonus(_, _, _, 0).

% ---- pawn structure (doubled / isolated / passed) ----
pawn_structure(Pos, Me, Them, Score) :-
    doubled_pawns(Pos, Me, Dm),
    doubled_pawns(Pos, Them, Dt),
    isolated_pawns(Pos, Me, Im),
    isolated_pawns(Pos, Them, It),
    passed_pawns(Pos, Me, Pm),
    passed_pawns(Pos, Them, Pt),
    Score is (20*(Pm - Pt)) - (15*(Dm - Dt)) - (10*(Im - It)).

doubled_pawns(Pos, Color, Penalty) :-
    aggregate_all(sum(P),
        ( file(File),
          pawn_count_on_file(Pos, Color, File, N),
          N > 1,
          P is N - 1
        ),
        Penalty).

isolated_pawns(Pos, Color, Count) :-
    aggregate_all(count,
        ( file(File),
          pawn_count_on_file(Pos, Color, File, N), N > 0,
          \+ pawn_on_adjacent_file(Pos, Color, File)
        ),
        Count).

pawn_on_adjacent_file(Pos, Color, File) :-
    ( Adj is File-1, Adj >= 1, pawn_count_on_file(Pos, Color, Adj, N1), N1 > 0 )
    ;
    ( Adj is File+1, Adj =< 8, pawn_count_on_file(Pos, Color, Adj, N2), N2 > 0 ).

passed_pawns(Pos, Color, Count) :-
    other_color(Color, Enemy),
    aggregate_all(count,
        ( position:piece(Pos, Color, pawn, Sq),
          file_of(Sq, F),
          rank_of(Sq, MyR),
          \+ enemy_pawn_blocks(Pos, Enemy, Color, F,   MyR),
          \+ enemy_pawn_blocks(Pos, Enemy, Color, F-1, MyR),
          \+ enemy_pawn_blocks(Pos, Enemy, Color, F+1, MyR)
        ),
        Count).

enemy_pawn_blocks(_Pos, _Enemy, _MyColor, File, _MyR) :-
    (File < 1 ; File > 8), !, fail.
enemy_pawn_blocks(Pos, Enemy, MyColor, File, MyR) :-
    position:piece(Pos, Enemy, pawn, ESq),
    file_of(ESq, File),
    rank_of(ESq, ER),
    ahead_of(MyColor, ER, MyR).

ahead_of(white, ER, MyR) :- ER > MyR.
ahead_of(black, ER, MyR) :- ER < MyR.

pawn_count_on_file(Pos, Color, File, N) :-
    aggregate_all(count,
        ( position:piece(Pos, Color, pawn, Sq),
          file_of(Sq, File)
        ),
        N).

file(1). file(2). file(3). file(4). file(5). file(6). file(7). file(8).
