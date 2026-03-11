:- module(movegen, [
    legal_move/3,
    in_check/2,
    insufficient_material/1
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
    legal_moves_list(Pos, Color, Legals),
    member(MoveStr, Legals).

% legal_moves_list(+Pos, +Color, -Moves)
% Deterministically collects all legal moves into a list.
% Pseudo-moves are collected first (no mutation), then each is tested
% with make_move/unmake_move in a deterministic loop (no backtracking
% interleaved with mutations, so setarg is safe).
legal_moves_list(Pos, Color, Legals) :-
    findall(M, pseudo_move(Pos, Color, M), PseudoMoves),
    filter_legal(Pos, Color, PseudoMoves, Legals).

filter_legal(_Pos, _Color, [], []).
filter_legal(Pos, Color, [M|Ms], Legals) :-
    ( position:make_move(Pos, M, Undo) ->
        ( \+ in_check(Pos, Color) ->
            Legals = [M|Rest]
        ;   Legals = Rest
        ),
        position:unmake_move(Pos, Undo)
    ;   Legals = Rest
    ),
    filter_legal(Pos, Color, Ms, Rest).

in_check(Pos, Color) :-
    king_square(Pos, Color, Ksq),
    other_color(Color, Enemy),
    attacks_square(Pos, Enemy, Ksq).

% Very small insufficient-material detector.
% True if neither side has material to force mate (K vs K, K+minor vs K).
insufficient_material(Pos) :-
    findall(T, position:piece(Pos, white, T, _), WTs),
    findall(T, position:piece(Pos, black, T, _), BTs),
    insufficient_side(WTs),
    insufficient_side(BTs).

insufficient_side(Ts0) :-
    exclude(=(king), Ts0, Ts),
    ( Ts == []
    ; Ts = [bishop]
    ; Ts = [knight]
    ).

% -------- Pseudo move generation (piece rules + occupancy) --------

pseudo_move(Pos, Color, MoveStr) :-
    position:piece(Pos, Color, Type, From),
    integer(From), From >= 0, From =< 63,   % <-- guard: required for arithmetic
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
    position:piece_at(Pos, Sq, _C, _T).

occupied_by(Pos, Color, Sq) :-
    position:piece_at(Pos, Sq, Color, _T).

enemy_at(Pos, Color, Sq) :-
    other_color(Color, Enemy),
    occupied_by(Pos, Enemy, Sq).

% Never allow capturing the enemy king (keeps positions and PGNs valid)
enemy_king_at(Pos, Color, Sq) :-
    other_color(Color, Enemy),
    position:piece_at(Pos, Sq, Enemy, king).

empty(Pos, Sq) :- \+ occupied(Pos, Sq).

file_of(Sq, F) :- F is (Sq mod 8) + 1.
rank_of(Sq, R) :- R is (Sq // 8) + 1.

on_board(Sq) :- integer(Sq), Sq >= 0, Sq =< 63.

% prevent wrap-around when stepping horizontally / diagonally
% Any single step (king/slider) must change file by at most 1.
% Vertical (±8) changes file by 0; horizontal (±1) and diagonal (±7,±9) by 1.
% A file change of 2+ means we wrapped around a board edge.
step_ok(From, To, _Delta) :-
    file_of(From, F1),
    file_of(To,   F2),
    Df is abs(F2 - F1),
    Df =< 1.

uci(From, To, MoveStr) :-
    position:index_sq(From, SFrom),
    position:index_sq(To,   STo),
    string_concat(SFrom, STo, MoveStr).

uci_promo(From, To, PromoChar, MoveStr) :-
    uci(From, To, Base),
    string_concat(Base, PromoChar, MoveStr).

% -------- Pawn moves (with en-passant + full promotions) --------

pawn_move(Pos, white, From, MoveStr) :-
    rank_of(From, R),
    file_of(From, _),

    % one step forward
    To1 is From + 8,
    on_board(To1),
    empty(Pos, To1),
    ( R =:= 7 ->
        promo_char(P),
        uci_promo(From, To1, P, MoveStr)
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
      \+ enemy_king_at(Pos, white, ToL),
      ( R =:= 7 -> promo_char(P), uci_promo(From, ToL, P, MoveStr) ; uci(From, ToL, MoveStr) )
    ; fail
    ).

pawn_move(Pos, white, From, MoveStr) :-
    file_of(From, F),
    rank_of(From, R),
    ( F < 8 -> ToR is From + 9, on_board(ToR), enemy_at(Pos, white, ToR),
      \+ enemy_king_at(Pos, white, ToR),
      ( R =:= 7 -> promo_char(P), uci_promo(From, ToR, P, MoveStr) ; uci(From, ToR, MoveStr) )
    ; fail
    ).

% En-passant capture for white
pawn_move(Pos, white, From, MoveStr) :-
    position:ep_square(Pos, EPSq),
    EPSq \= none,
    file_of(From, F),
    rank_of(From, 5),
    ( F > 1, ToL is From + 7, ToL =:= EPSq -> uci(From, ToL, MoveStr)
    ; F < 8, ToR is From + 9, ToR =:= EPSq -> uci(From, ToR, MoveStr)
    ).

pawn_move(Pos, black, From, MoveStr) :-
    rank_of(From, R),
    file_of(From, _F),

    % one step forward (towards rank 1)
    To1 is From - 8,
    on_board(To1),
    empty(Pos, To1),
    ( R =:= 2 ->
        promo_char(P),
        uci_promo(From, To1, P, MoveStr)
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
      \+ enemy_king_at(Pos, black, ToL),
      ( R =:= 2 -> promo_char(P), uci_promo(From, ToL, P, MoveStr) ; uci(From, ToL, MoveStr) )
    ; fail
    ).

pawn_move(Pos, black, From, MoveStr) :-
    file_of(From, F),
    rank_of(From, R),
    ( F < 8 -> ToR is From - 7, on_board(ToR), enemy_at(Pos, black, ToR),
      \+ enemy_king_at(Pos, black, ToR),
      ( R =:= 2 -> promo_char(P), uci_promo(From, ToR, P, MoveStr) ; uci(From, ToR, MoveStr) )
    ; fail
    ).

% En-passant capture for black
pawn_move(Pos, black, From, MoveStr) :-
    position:ep_square(Pos, EPSq),
    EPSq \= none,
    file_of(From, F),
    rank_of(From, 4),
    ( F > 1, ToL is From - 9, ToL =:= EPSq -> uci(From, ToL, MoveStr)
    ; F < 8, ToR is From - 7, ToR =:= EPSq -> uci(From, ToR, MoveStr)
    ).

promo_char("q").
promo_char("r").
promo_char("b").
promo_char("n").

% -------- Knight moves --------

knight_delta( 17). knight_delta( 15). knight_delta( 10). knight_delta(  6).
knight_delta(-17). knight_delta(-15). knight_delta(-10). knight_delta( -6).

knight_move(Pos, Color, From, MoveStr) :-
    knight_delta(D),
    To is From + D,
    on_board(To),
    knight_step_ok(From, To),
    ( empty(Pos, To)
    ; ( enemy_at(Pos, Color, To), \+ enemy_king_at(Pos, Color, To) )
    ),
    uci(From, To, MoveStr).

knight_step_ok(From, To) :-
    file_of(From, F1), rank_of(From, R1),
    file_of(To,   F2), rank_of(To,   R2),
    DF is abs(F2 - F1),
    DR is abs(R2 - R1),
    (DF =:= 1, DR =:= 2 ; DF =:= 2, DR =:= 1).

% -------- King moves (with castling) --------

king_delta( 9). king_delta( 8). king_delta( 7).
king_delta( 1). king_delta(-1).
king_delta(-7). king_delta(-8). king_delta(-9).

king_move(Pos, Color, From, MoveStr) :-
    king_delta(D),
    To is From + D,
    on_board(To),
    step_ok(From, To, D),
    \+ occupied_by(Pos, Color, To),
    \+ enemy_king_at(Pos, Color, To),
    uci(From, To, MoveStr).

% Castling pseudo-moves with full legality checks (no check, no through-check, squares empty, rights).
king_move(Pos, white, 4, MoveStr) :-
    position:castling_rights(Pos, cr(WK,WQ,_,_)),
    ( WK == true, castle_legal(Pos, white, kingside, MoveStr)
    ; WQ == true, castle_legal(Pos, white, queenside, MoveStr)
    ).

king_move(Pos, black, 60, MoveStr) :-
    position:castling_rights(Pos, cr(_,_,BK,BQ)),
    ( BK == true, castle_legal(Pos, black, kingside, MoveStr)
    ; BQ == true, castle_legal(Pos, black, queenside, MoveStr)
    ).

castle_legal(Pos, Color, kingside, MoveStr) :-
    \+ in_check(Pos, Color),
    ( Color == white -> KFrom=4, KTo=6, Pass=5, RFrom=7, EmptySq=[5,6]
    ; Color == black -> KFrom=60, KTo=62, Pass=61, RFrom=63, EmptySq=[61,62]
    ),
    % rook exists
    position:piece(Pos, Color, rook, RFrom),
    forall(member(S, EmptySq), empty(Pos, S)),
    other_color(Color, Enemy),
    \+ attacks_square(Pos, Enemy, Pass),
    \+ attacks_square(Pos, Enemy, KTo),
    uci(KFrom, KTo, MoveStr).

castle_legal(Pos, Color, queenside, MoveStr) :-
    \+ in_check(Pos, Color),
    ( Color == white -> KFrom=4, KTo=2, Pass=3, RFrom=0, EmptySq=[1,2,3]
    ; Color == black -> KFrom=60, KTo=58, Pass=59, RFrom=56, EmptySq=[57,58,59]
    ),
    position:piece(Pos, Color, rook, RFrom),
    forall(member(S, EmptySq), empty(Pos, S)),
    other_color(Color, Enemy),
    \+ attacks_square(Pos, Enemy, Pass),
    \+ attacks_square(Pos, Enemy, KTo),
    uci(KFrom, KTo, MoveStr).

% -------- Sliding pieces (bishop/rook/queen) --------

slider_move(Pos, Color, From, Deltas, MoveStr) :-
    member(D, Deltas),
    ray_step(Pos, Color, From, From, D, MoveStr).

% ray_step(+Pos,+Color,+OrigFrom,+CurSq,+Delta,-MoveStr)
% IMPORTANT: OrigFrom stays constant. CurSq advances along the ray.
ray_step(Pos, Color, OrigFrom, CurSq, D, MoveStr) :-
    To is CurSq + D,
    on_board(To),
    step_ok(CurSq, To, D),
    ( empty(Pos, To) ->
        uci(OrigFrom, To, MoveStr)
    ; enemy_at(Pos, Color, To),
      \+ enemy_king_at(Pos, Color, To) ->
        uci(OrigFrom, To, MoveStr)
    ).

ray_step(Pos, Color, OrigFrom, CurSq, D, MoveStr) :-
    To is CurSq + D,
    on_board(To),
    step_ok(CurSq, To, D),
    empty(Pos, To),
    ray_step(Pos, Color, OrigFrom, To, D, MoveStr).

% -------- Attack detection (for check) --------

king_square(Pos, Color, Sq) :-
    position:piece(Pos, Color, king, Sq), !.

attacks_square(Pos, Color, Sq) :-
    % Use pseudo attacks (fast): enough for check legality filtering
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