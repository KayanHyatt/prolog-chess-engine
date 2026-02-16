:- module(position, [
    initial_position/1,
    apply_move/3,
    piece/4,
    sq_index/2,
    index_sq/2
]).

/*
Position representation:
  pos(Pieces)
  Pieces = [pc(Color,Type,SqIndex), ...]
SqIndex is 0..63 where 0=a1, 7=h1, 56=a8, 63=h8
*/

piece(pos(Ps), C, T, Sq) :- member(pc(C,T,Sq), Ps).

% --- square conversion ---
sq_index(SqStr, Idx) :-
    string(SqStr),
    string_chars(SqStr, [FileC, RankC]),
    file_num(FileC, F),
    rank_num(RankC, R),
    Idx is (R-1)*8 + (F-1).

index_sq(Idx, SqStr) :-
    F is (Idx mod 8) + 1,
    R is (Idx // 8) + 1,
    file_char(F, FileC),
    rank_char(R, RankC),
    string_chars(SqStr, [FileC, RankC]).

file_num(C, N) :- member(C-N, ['a'-1,'b'-2,'c'-3,'d'-4,'e'-5,'f'-6,'g'-7,'h'-8]).
rank_num(C, N) :- member(C-N, ['1'-1,'2'-2,'3'-3,'4'-4,'5'-5,'6'-6,'7'-7,'8'-8]).
file_char(N, C) :- member(C-N, ['a'-1,'b'-2,'c'-3,'d'-4,'e'-5,'f'-6,'g'-7,'h'-8]).
rank_char(N, C) :- member(C-N, ['1'-1,'2'-2,'3'-3,'4'-4,'5'-5,'6'-6,'7'-7,'8'-8]).

% --- initial position ---
initial_position(pos(Ps)) :-
    Ps = [
        % White pieces
        pc(white, rook,   0), pc(white, knight, 1), pc(white, bishop, 2), pc(white, queen, 3),
        pc(white, king,   4), pc(white, bishop, 5), pc(white, knight, 6), pc(white, rook, 7),
        pc(white, pawn,   8), pc(white, pawn,   9), pc(white, pawn,  10), pc(white, pawn,  11),
        pc(white, pawn,  12), pc(white, pawn,  13), pc(white, pawn,  14), pc(white, pawn,  15),

        % Black pieces
        pc(black, pawn,  48), pc(black, pawn,  49), pc(black, pawn,  50), pc(black, pawn,  51),
        pc(black, pawn,  52), pc(black, pawn,  53), pc(black, pawn,  54), pc(black, pawn,  55),
        pc(black, rook,  56), pc(black, knight,57), pc(black, bishop,58), pc(black, queen, 59),
        pc(black, king,  60), pc(black, bishop,61), pc(black, knight,62), pc(black, rook,  63)
    ].

% --- apply UCI move string like "e2e4" or "e7e8q" ---
apply_move(Pos0, MoveStr, Pos1) :-
    parse_uci(MoveStr, From, To, Promo),
    ( is_castle_move(From, To, Side) ->
        apply_castle(Pos0, Side, From, To, Pos1)
    ; apply_normal(Pos0, From, To, Promo, Pos1)
    ).

parse_uci(MoveStr, From, To, Promo) :-
    string_chars(MoveStr, Cs),
    ( Cs = [F1,R1,F2,R2|Rest]
    -> string_chars(SFrom, [F1,R1]),
       string_chars(STo,   [F2,R2]),
       sq_index(SFrom, From),
       sq_index(STo,   To),
       ( Rest = [P] -> promo_piece(P, Promo) ; Promo = none )
    ; fail
    ).

promo_piece('q', queen).
promo_piece('r', rook).
promo_piece('b', bishop).
promo_piece('n', knight).
promo_piece('Q', queen).
promo_piece('R', rook).
promo_piece('B', bishop).
promo_piece('N', knight).

% --- normal move: move piece, remove capture if any, handle promo ---
apply_normal(pos(Ps0), From, To, Promo, pos(Ps3)) :-
    select(pc(C,T,From), Ps0, Ps1),              % must have a piece at From (otherwise fail)
    ( select(pc(_,_,To), Ps1, Ps2) -> true       % capture if piece at To
    ; Ps2 = Ps1
    ),
    ( Promo \= none, T = pawn ->
        T2 = Promo
    ; T2 = T
    ),
    Ps3 = [pc(C,T2,To)|Ps2].

% --- simple castling support ---
is_castle_move(From, To, white_kingside) :- From =:= 4,  To =:= 6.
is_castle_move(From, To, white_queenside):- From =:= 4,  To =:= 2.
is_castle_move(From, To, black_kingside) :- From =:= 60, To =:= 62.
is_castle_move(From, To, black_queenside):- From =:= 60, To =:= 58.

apply_castle(pos(Ps0), Side, _From, _To, pos(Ps2)) :-
    castle_squares(Side, KingFrom, KingTo, RookFrom, RookTo),
    select(pc(Color, king, KingFrom), Ps0, PsA),
    select(pc(Color, rook, RookFrom), PsA, PsB),
    Ps2 = [pc(Color, king, KingTo), pc(Color, rook, RookTo) | PsB].

castle_squares(white_kingside, 4, 6, 7, 5)  :- Color = white, Color=Color.
castle_squares(white_queenside,4, 2, 0, 3)  :- Color = white, Color=Color.
castle_squares(black_kingside, 60,62,63,61) :- Color = black, Color=Color.
castle_squares(black_queenside,60,58,56,59) :- Color = black, Color=Color.
