:- module(movegen, [
    legal_move/3,
    in_check/2
]).

:- use_module(position).

/*
  legal_move(+Pos, +Color, -MoveStr)
  Generates legal moves via backtracking.
  "Legal" here means: pseudo-legal move AND it does not leave your king in check.
*/

other_color(white, black).
other_color(black, white).

% -------- Public --------

legal_move(Pos, Color, MoveStr) :-
    pseudo_move(Pos, Color, MoveStr),
    position:apply_move(Pos, MoveStr, Pos2),
    \+ in_check(Pos2, Color).

in_check(Pos, Color) :-
    king_square(Pos, Color, Ksq),
    other_color(Color, Enemy),
    attacks_square(Pos, Enemy, Ksq).

% -------- Pseudo move generation (piece rules + occupancy) --------

pseudo_move(Pos, Color, MoveStr) :-
    position:piece(Pos, Color, Type, From),
    integer(From), From >= 0, From =< 63,   % guard: required for arithmetic
    piece_pseudo_move(Pos, Color, Type, From, MoveStr).


piece_pseudo_move(Pos, Color, pawn, From, MoveStr) :-
    pawn_move(Pos, Color, From, MoveStr).
piece_pseudo_move(Pos, Color, knight, From, MoveStr) :-
    knight_move(Pos, Color, From, MoveStr).
piece_pseudo_move(Pos, Color, bishop, From, MoveStr) :-
    slider_move(Pos, Color, From, [ 9, 7, -7, -9], MoveStr).
piece_pseudo_move(Pos, Color, rook, From, MoveStr) :-
    slider_move(Pos, Color, From, [ 8, -8, 1, -1], MoveStr).
piece_pseudo_move(Pos, Color, queen, From, MoveStr) :-
    slider_move(Pos, Color, From, [ 9, 7, -7, -9, 8, -8, 1, -1], MoveStr).
piece_pseudo_move(Pos, Color, king, From, MoveStr) :-
    king_move(Pos, Color, From, MoveStr).

% -------- Helpers: occupancy / bounds --------

occupied(Pos, Sq) :-
    position:piece(Pos, _, _, Sq).

occupied_by(Pos, Color, Sq) :-
    position:piece(Pos, Color, _, Sq).

enemy_at(Pos, Color, Sq) :-
    other_color(Color, Enemy),
    occupied_by(Pos, Enemy, Sq).

empty(Pos, Sq) :- \+ occupied(Pos, Sq).

file_of(Sq, F) :- F is (Sq mod 8) + 1.
rank_of(Sq, R) :- R is (Sq // 8) + 1.

on_board(Sq) :- integer(Sq), Sq >= 0, Sq =< 63.

% prevent wrap-around when stepping horizontally / diagonally
step_ok(From, To, Delta) :-
    file_of(From, F1),
    file_of(To,   F2),
    Df is abs(F2 - F1),
    ( Delta =:= 1  ; Delta =:= -1  -> Df =:= 1
    ; Delta =:= 9  ; Delta =:= -9  -> Df =:= 1
    ; Delta =:= 7  ; Delta =:= -7  -> Df =:= 1
    ; true  % vertical (±8) etc.
    ).

uci(From, To, MoveStr) :-
    position:index_sq(From, SFrom),
    position:index_sq(To,   STo),
    string_concat(SFrom, STo, MoveStr).

uci_promo(From, To, PromoChar, MoveStr) :-
    uci(From, To, Base),
    string_concat(Base, PromoChar, MoveStr).

% -------- Pawn moves (no en passant yet, basic promotion to queen) --------

pawn_move(Pos, white, From, MoveStr) :-
    rank_of(From, R),
    To1 is From + 8,
    on_board(To1),
    empty(Pos, To1),
    ( R =:= 7 ->
        uci_promo(From, To1, "q", MoveStr)
    ; uci(From, To1, MoveStr)
    ).

pawn_move(Pos, white, From, MoveStr) :-
    rank_of(From, 2),
    To1 is From + 8,
    To2 is From + 16,
    empty(Pos, To1),
    empty(Pos, To2),
    uci(From, To2, MoveStr).

pawn_move(Pos, white, From, MoveStr) :-
    file_of(From, F),
    rank_of(From, R),
    ( F > 1 -> ToL is From + 7, on_board(ToL), enemy_at(Pos, white, ToL),
      ( R =:= 7 -> uci_promo(From, ToL, "q", MoveStr) ; uci(From, ToL, MoveStr) )
    ; fail
    ).

pawn_move(Pos, white, From, MoveStr) :-
    file_of(From, F),
    rank_of(From, R),
    ( F < 8 -> ToR is From + 9, on_board(ToR), enemy_at(Pos, white, ToR),
      ( R =:= 7 -> uci_promo(From, ToR, "q", MoveStr) ; uci(From, ToR, MoveStr) )
    ; fail
    ).

pawn_move(Pos, black, From, MoveStr) :-
    rank_of(From, R),
    To1 is From - 8,
    on_board(To1),
    empty(Pos, To1),
    ( R =:= 2 ->
        uci_promo(From, To1, "q", MoveStr)
    ; uci(From, To1, MoveStr)
    ).

pawn_move(Pos, black, From, MoveStr) :-
    rank_of(From, 7),
    To1 is From - 8,
    To2 is From - 16,
    empty(Pos, To1),
    empty(Pos, To2),
    uci(From, To2, MoveStr).

pawn_move(Pos, black, From, MoveStr) :-
    file_of(From, F),
    rank_of(From, R),
    ( F > 1 -> ToL is From - 9, on_board(ToL), enemy_at(Pos, black, ToL),
      ( R =:= 2 -> uci_promo(From, ToL, "q", MoveStr) ; uci(From, ToL, MoveStr) )
    ; fail
    ).

pawn_move(Pos, black, From, MoveStr) :-
    file_of(From, F),
    rank_of(From, R),
    ( F < 8 -> ToR is From - 7, on_board(ToR), enemy_at(Pos, black, ToR),
      ( R =:= 2 -> uci_promo(From, ToR, "q", MoveStr) ; uci(From, ToR, MoveStr) )
    ; fail
    ).

% -------- Knight moves --------

knight_delta( 17). knight_delta( 15). knight_delta( 10). knight_delta(  6).
knight_delta(-17). knight_delta(-15). knight_delta(-10). knight_delta( -6).

knight_move(Pos, Color, From, MoveStr) :-
    knight_delta(D),
    To is From + D,
    on_board(To),
    knight_step_ok(From, To),
    ( empty(Pos, To) ; enemy_at(Pos, Color, To) ),
    uci(From, To, MoveStr).

knight_step_ok(From, To) :-
    file_of(From, F1), rank_of(From, R1),
    file_of(To,   F2), rank_of(To,   R2),
    DF is abs(F2 - F1),
    DR is abs(R2 - R1),
    (DF =:= 1, DR =:= 2 ; DF =:= 2, DR =:= 1).

% -------- King moves (no castling yet) --------

king_delta( 9). king_delta( 8). king_delta( 7).
king_delta( 1). king_delta(-1).
king_delta(-7). king_delta(-8). king_delta(-9).

king_move(Pos, Color, From, MoveStr) :-
    king_delta(D),
    To is From + D,
    on_board(To),
    step_ok(From, To, D),
    \+ occupied_by(Pos, Color, To),
    uci(From, To, MoveStr).

% -------- Sliding pieces (bishop/rook/queen) --------

slider_move(Pos, Color, From, Deltas, MoveStr) :-
    member(D, Deltas),
    ray_step(Pos, Color, From, D, MoveStr).

ray_step(Pos, Color, From, D, MoveStr) :-
    To is From + D,
    on_board(To),
    step_ok(From, To, D),
    ( empty(Pos, To) ->
        uci(From, To, MoveStr)
    ; enemy_at(Pos, Color, To) ->
        uci(From, To, MoveStr)
    ; fail
    ).
ray_step(Pos, Color, From, D, MoveStr) :-
    To is From + D,
    on_board(To),
    step_ok(From, To, D),
    empty(Pos, To),
    ray_step(Pos, Color, To, D, MoveStr).

% -------- Attack detection (for check) --------

king_square(Pos, Color, Sq) :-
    position:piece(Pos, Color, king, Sq), !.

attacks_square(Pos, Color, Sq) :-
    position:piece(Pos, Color, pawn, From),
    pawn_attacks(Color, From, Sq).
attacks_square(Pos, Color, Sq) :-
    position:piece(Pos, Color, knight, From),
    knight_attacks(From, Sq).
attacks_square(Pos, Color, Sq) :-
    position:piece(Pos, Color, bishop, From),
    slider_attacks(Pos, From, [9,7,-7,-9], Sq).
attacks_square(Pos, Color, Sq) :-
    position:piece(Pos, Color, rook, From),
    slider_attacks(Pos, From, [8,-8,1,-1], Sq).
attacks_square(Pos, Color, Sq) :-
    position:piece(Pos, Color, queen, From),
    slider_attacks(Pos, From, [9,7,-7,-9,8,-8,1,-1], Sq).
attacks_square(Pos, Color, Sq) :-
    position:piece(Pos, Color, king, From),
    king_attacks(From, Sq).

pawn_attacks(white, From, To) :-
    file_of(From, F),
    (F > 1 -> To is From + 7 ; fail),
    on_board(To).
pawn_attacks(white, From, To) :-
    file_of(From, F),
    (F < 8 -> To is From + 9 ; fail),
    on_board(To).

pawn_attacks(black, From, To) :-
    file_of(From, F),
    (F > 1 -> To is From - 9 ; fail),
    on_board(To).
pawn_attacks(black, From, To) :-
    file_of(From, F),
    (F < 8 -> To is From - 7 ; fail),
    on_board(To).

knight_attacks(From, To) :-
    knight_delta(D),
    To is From + D,
    on_board(To),
    knight_step_ok(From, To).

king_attacks(From, To) :-
    king_delta(D),
    To is From + D,
    on_board(To),
    step_ok(From, To, D).

slider_attacks(Pos, From, Deltas, Target) :-
    member(D, Deltas),
    slider_ray_attacks(Pos, From, D, Target).

slider_ray_attacks(Pos, From, D, Target) :-
    To is From + D,
    on_board(To),
    step_ok(From, To, D),
    ( To =:= Target ->
        true
    ; empty(Pos, To) ->
        slider_ray_attacks(Pos, To, D, Target)
    ; false
    ).
