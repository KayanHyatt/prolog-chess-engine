:- module(fen, [
    fen_to_pos/2,
    pos_to_fen/2,
    startpos_fen/1
]).

:- use_module(position).

/*
FEN support for Phase-2 position representation.

FEN: <board> <stm> <castling> <ep> <halfmove> <fullmove>
*/

startpos_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1").

fen_to_pos(FenIn, Pos) :-
    normalize_fen(FenIn, Fen),
    split_string(Fen, " ", " ", [BoardS, StmS, CastleS, EpS, HMStr, FMStr]),
    stm_from(StmS, STM),
    castling_from(CastleS, CR),
    ep_from(EpS, EP),
    number_string(HM, HMStr),
    number_string(FM, FMStr),
    position:empty_board(B),
    position:empty_pl(PL),
    Pos0 = pos(B,PL,STM,CR,EP,HM,FM,0),
    board_to_position(BoardS, Pos0),
    position:recompute_key(Pos0, K),
    setarg(8, Pos0, K),
    Pos = Pos0.

pos_to_fen(Pos, Fen) :-
    Pos = pos(B,_PL, STM, CR, EP, HM, FM, _K),
    board_string(B, BoardS),
    stm_to(STM, StmS),
    castling_to(CR, CastleS),
    ep_to(EP, EpS),
    number_string(HM, HMStr),
    number_string(FM, FMStr),
    atomic_list_concat([BoardS, StmS, CastleS, EpS, HMStr, FMStr], ' ', Fen).

normalize_fen(FenIn, Fen) :-
    ( string(FenIn) -> Fen = FenIn
    ; atom(FenIn) -> atom_string(FenIn, Fen)
    ; term_string(FenIn, Fen)
    ).

% ---- STM ----
stm_from("w", white).
stm_from("b", black).
stm_to(white, "w").
stm_to(black, "b").

% ---- Castling ----
castling_from("-", cr(false,false,false,false)) :- !.
castling_from(S, cr(WK,WQ,BK,BQ)) :-
    string_chars(S, Cs),
    ( memberchk('K', Cs) -> WK=true ; WK=false ),
    ( memberchk('Q', Cs) -> WQ=true ; WQ=false ),
    ( memberchk('k', Cs) -> BK=true ; BK=false ),
    ( memberchk('q', Cs) -> BQ=true ; BQ=false ).

castling_to(cr(false,false,false,false), "-") :- !.
castling_to(cr(WK,WQ,BK,BQ), S) :-
    findall(C,
        ( (WK==true, C='K')
        ; (WQ==true, C='Q')
        ; (BK==true, C='k')
        ; (BQ==true, C='q')
        ), Cs),
    string_chars(S, Cs).

% ---- EP ----
ep_from("-", none) :- !.
ep_from(SqS, Idx) :- position:sq_index(SqS, Idx).
ep_to(none, "-") :- !.
ep_to(Idx, SqS) :- position:index_sq(Idx, SqS).

% ---- Board parse ----

board_to_position(BoardS, Pos) :-
    split_string(BoardS, "/", "/", [R8,R7,R6,R5,R4,R3,R2,R1]),
    rank_fill(Pos, 8, R8),
    rank_fill(Pos, 7, R7),
    rank_fill(Pos, 6, R6),
    rank_fill(Pos, 5, R5),
    rank_fill(Pos, 4, R4),
    rank_fill(Pos, 3, R3),
    rank_fill(Pos, 2, R2),
    rank_fill(Pos, 1, R1).

rank_fill(Pos, Rank, Str) :-
    string_chars(Str, Cs),
    rank_fill_(Pos, Rank, 1, Cs).

rank_fill_(_Pos, _Rank, 9, []) :- !.
rank_fill_(Pos, Rank, File, [C|Rest]) :-
    char_type(C, digit),
    atom_number(C, N),
    File2 is File + N,
    rank_fill_(Pos, Rank, File2, Rest).
rank_fill_(Pos, Rank, File, [C|Rest]) :-
    piece_char(C, Color, Type),
    Sq is (Rank-1)*8 + (File-1),
    Pos = pos(B,PL,_STM,_CR,_EP,_HM,_FM,_K),
    position:board_set(B, Sq, pc(Color,Type), _),
    position:pl_add(PL, Color, Type, Sq),
    File2 is File + 1,
    rank_fill_(Pos, Rank, File2, Rest).

piece_char('P', white, pawn).
piece_char('N', white, knight).
piece_char('B', white, bishop).
piece_char('R', white, rook).
piece_char('Q', white, queen).
piece_char('K', white, king).
piece_char('p', black, pawn).
piece_char('n', black, knight).
piece_char('b', black, bishop).
piece_char('r', black, rook).
piece_char('q', black, queen).
piece_char('k', black, king).

% ---- Board emit ----

board_string(B, BoardS) :-
    findall(Str, (between(8,1,R), rank_string(B,R,Str)), Rev),
    reverse(Rev, RankStrs),
    atomic_list_concat(RankStrs, '/', BoardS).

between(Hi,Lo,Hi) :- Hi>=Lo.
between(Hi,Lo,X) :- Hi>Lo, Hi1 is Hi-1, between(Hi1,Lo,X).

rank_string(B, Rank, Str) :-
    Base is (Rank-1)*8,
    findall(V, (between(0,7,Off), Sq is Base+Off, position:board_get(B,Sq,V)), Vs),
    compress(Vs, Cs),
    string_chars(Str, Cs).

compress([], []) :- !.
compress(Vs, Cs) :-
    take_empties(Vs, N, Rest),
    ( N>0 ->
        number_chars(N, Digits),
        append(Digits, Cs2, Cs),
        compress(Rest, Cs2)
    ; Vs = [pc(C,T)|Rest2],
      piece_char(P, C, T),
      Cs = [P|Cs2],
      compress(Rest2, Cs2)
    ).

take_empties([empty|Rest], N, Rest2) :-
    take_empties(Rest, N1, Rest2),
    N is N1 + 1.
take_empties(Vs, 0, Vs).