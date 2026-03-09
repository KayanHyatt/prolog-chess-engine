:- module(position, [
    % constructors
    initial_position/1,
    clone_position/2,

    % move application
    apply_move/3,
    make_move/3,
    unmake_move/2,

    % null-move helpers (used by search for pruning)
    make_null_move/2,
    unmake_null_move/2,

    % accessors
    piece/4,
    piece_at/4,
    side_to_move/2,
    castling_rights/2,
    ep_square/2,
    halfmove_clock/2,
    fullmove_number/2,
    zobrist_key/2,
    repetition_key/2,

    % low-level helpers (used by fen/perft/search)
    empty_board/1,
    empty_pl/1,
    board_get/3,
    board_set/4,
    pl_add/4,
    pl_remove/4,
    recompute_key/2,

    % square conversion
    sq_index/2,
    index_sq/2
]).

:- use_module(library(random)).

/*

Phase 2 position representation (speed foundations)

  pos(Board, PieceLists, SideToMove, CastlingRights, EpSquare,
      HalfmoveClock, FullmoveNumber, ZobristKey)

  Board      = board(A0,A1,...,A63) where each Ai is empty or pc(Color,Type)
  PieceLists = pl(WP,WN,WB,WR,WQ,WK,BP,BN,BB,BR,BQ,BK)
              each list contains square indexes for that piece type.

This gives:
  - O(1) piece_at via arg/3
  - Faster iteration via piece lists
  - Incremental zobrist hashing via make/unmake

NOTE:
  - make_move/3 and unmake_move/2 mutate the given position term in-place
    using setarg/3. This is intended for search/perft speed.
  - apply_move/3 remains a functional wrapper (clones then make_move/3).

*/

% --------------------------
% Zobrist tables (deterministic)
% --------------------------

:- dynamic(z_piece/4).
:- dynamic(z_side/1).
:- dynamic(z_castle/2).
:- dynamic(z_epfile/2).
:- dynamic(z_inited/0).

ensure_zobrist :- z_inited, !.
ensure_zobrist :-
    retractall(z_piece(_,_,_,_)),
    retractall(z_side(_)),
    retractall(z_castle(_,_)),
    retractall(z_epfile(_,_)),
    set_random(seed(13371337)),
    forall(member(C,[white,black]),
      forall(member(T,[pawn,knight,bishop,rook,queen,king]),
        forall(between(0,63,Sq),
          (rand64(R), assertz(z_piece(C,T,Sq,R)))
        ))),
    rand64(SR), assertz(z_side(SR)),
    % castling rights packed into 4-bit integer 0..15
    forall(between(0,15,Mask), (rand64(R), assertz(z_castle(Mask,R)))),
    forall(between(1,8,F), (rand64(R), assertz(z_epfile(F,R)))),
    assertz(z_inited).

% --------------------------
% Null move (toggle side to move, clear EP)
% --------------------------

% make_null_move(+Pos, -Undo)
% A "null move" is a pass: side-to-move toggles, EP target clears.
% Used only for search pruning (it is not a legal chess move).
make_null_move(Pos, undo_null(OldSide, OldEP, OldKey, OldFullmove, OldHalfmove)) :-
    ensure_zobrist,
    arg(3, Pos, OldSide),
    arg(5, Pos, OldEP),
    arg(8, Pos, OldKey),
    arg(6, Pos, OldHalfmove),
    arg(7, Pos, OldFullmove),
    % toggle side
    other_color(OldSide, NewSide),
    setarg(3, Pos, NewSide),
    % clear ep
    ( OldEP == none -> Key1 = OldKey
    ; OldEP = ep(File,_Rank), z_epfile(File, ZEP), Key1 is OldKey xor ZEP
    ),
    setarg(5, Pos, none),
    % toggle side key
    z_side(ZS),
    Key2 is Key1 xor ZS,
    setarg(8, Pos, Key2),
    % halfmove increments on null move; fullmove increments when black just moved
    HM2 is OldHalfmove + 1,
    setarg(6, Pos, HM2),
    ( OldSide == black -> FM2 is OldFullmove + 1 ; FM2 = OldFullmove ),
    setarg(7, Pos, FM2).

unmake_null_move(Pos, undo_null(OldSide, OldEP, OldKey, OldFullmove, OldHalfmove)) :-
    setarg(3, Pos, OldSide),
    setarg(5, Pos, OldEP),
    setarg(8, Pos, OldKey),
    setarg(6, Pos, OldHalfmove),
    setarg(7, Pos, OldFullmove).

rand64(R) :-
    random_between(0, 0xFFFFFFFF, A),
    random_between(0, 0xFFFFFFFF, B),
    R is (A<<32) xor B.

% --------------------------
% Square conversion
% --------------------------

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

% --------------------------
% Accessors
% --------------------------

side_to_move(pos(_B,_PL,STM,_CR,_EP,_HM,_FM,_K), STM).
castling_rights(pos(_B,_PL,_STM,CR,_EP,_HM,_FM,_K), CR).
ep_square(pos(_B,_PL,_STM,_CR,EP,_HM,_FM,_K), EP).
halfmove_clock(pos(_B,_PL,_STM,_CR,_EP,HM,_FM,_K), HM).
fullmove_number(pos(_B,_PL,_STM,_CR,_EP,_HM,FM,_K), FM).
zobrist_key(pos(_B,_PL,_STM,_CR,_EP,_HM,_FM,K), K).

% piece lists iterator
piece(Pos, C, T, Sq) :-
    Pos = pos(_B, PL, _STM, _CR, _EP, _HM, _FM, _K),
    pl_arg(C,T,Arg),
    arg(Arg, PL, L),
    member(Sq, L).

% O(1) board lookup
piece_at(pos(B,_PL,_STM,_CR,_EP,_HM,_FM,_K), Sq, C, T) :-
    board_get(B, Sq, Val),
    Val \= empty,
    Val = pc(C,T).

board_get(B, Sq, Val) :-
    A is Sq + 1,
    arg(A, B, Val).

board_set(B, Sq, Val, Old) :-
    A is Sq + 1,
    arg(A, B, Old),
    setarg(A, B, Val).

% repetition key ignores clocks
repetition_key(pos(_B,_PL,STM,CR,EP,_HM,_FM,K), Key) :-
    Key = rep(K,STM,CR,EP).

% --------------------------
% Initial position
% --------------------------

initial_position(Pos) :-
    ensure_zobrist,
    empty_board(B0),
    empty_pl(PL0),
    CR = cr(true,true,true,true),
    STM = white,
    EP = none,
    HM = 0,
    FM = 1,
    Key0 = 0,
    Pos0 = pos(B0,PL0,STM,CR,EP,HM,FM,Key0),
    place_initial(Pos0),
    recompute_key(Pos0, Key1),
    setarg(8, Pos0, Key1),
    Pos = Pos0.

empty_board(board(
    empty,empty,empty,empty,empty,empty,empty,empty,
    empty,empty,empty,empty,empty,empty,empty,empty,
    empty,empty,empty,empty,empty,empty,empty,empty,
    empty,empty,empty,empty,empty,empty,empty,empty,
    empty,empty,empty,empty,empty,empty,empty,empty,
    empty,empty,empty,empty,empty,empty,empty,empty,
    empty,empty,empty,empty,empty,empty,empty,empty,
    empty,empty,empty,empty,empty,empty,empty,empty
)).

empty_pl(pl([],[],[],[],[],[],[],[],[],[],[],[])).

place_initial(Pos) :-
    maplist(place_piece(Pos, white),
        [rook-0, knight-1, bishop-2, queen-3, king-4, bishop-5, knight-6, rook-7]),
    forall(between(8,15,Sq), place_piece(Pos, white, pawn-Sq)),
    forall(between(48,55,Sq), place_piece(Pos, black, pawn-Sq)),
    maplist(place_piece(Pos, black),
        [rook-56, knight-57, bishop-58, queen-59, king-60, bishop-61, knight-62, rook-63]).

place_piece(Pos, C, T-Sq) :-
    Pos = pos(B, PL, _STM, _CR, _EP, _HM, _FM, K0),
    board_set(B, Sq, pc(C,T), empty),
    pl_add(PL, C, T, Sq),
    z_piece(C,T,Sq,R),
    K1 is K0 xor R,
    setarg(8, Pos, K1).

% --------------------------
% Cloning (for functional apply_move)
% --------------------------

clone_position(pos(B,PL,STM,CR,EP,HM,FM,K), pos(B2,PL2,STM,CR,EP,HM,FM,K)) :-
    copy_term(B, B2),
    copy_term(PL, PL2).

% --------------------------
% Move parsing
% --------------------------

normalize_uci(MoveIn, MoveStr) :-
    ( string(MoveIn) -> MoveStr = MoveIn
    ; atom(MoveIn)   -> atom_string(MoveIn, MoveStr)
    ; is_list(MoveIn) -> string_chars(MoveStr, MoveIn)
    ; term_string(MoveIn, MoveStr)
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

other_color(white, black).
other_color(black, white).

% --------------------------
% Functional wrapper
% --------------------------

apply_move(Pos0, MoveIn, Pos1) :-
    clone_position(Pos0, Pos1),
    make_move(Pos1, MoveIn, _Undo).

% --------------------------
% Make / Unmake (mutating)
% --------------------------

make_move(Pos, MoveIn, undo(StateUndo, SquareUndos, PLUndos, EpXor)) :-
    ensure_zobrist,
    normalize_uci(MoveIn, MoveStr),
    parse_uci(MoveStr, From, To, Promo),

    % SAFETY: refuse moves that don't have a piece on From
    ( integer(From), integer(To) -> true ; !, fail ),
    ( position:piece_at(Pos, From, _C0, _T0) -> true ; !, fail ),

    Pos = pos(B, PL, STM0, CR0, EP0, HM0, FM0, K0),
    board_get(B, From, FromVal),
    FromVal = pc(STM0, T0),

    % snapshot state
    StateUndo = state(STM0,CR0,EP0,HM0,FM0,K0),
    
    % remove any existing EP xor from key (EP is stored via file-based zobrist)
    EpXor = ep_xor(EP0, EpOldX),
    ( EP0 == none -> K1=K0
    ; file_of(EP0,F0), z_epfile(F0,Re0), K1 is K0 xor Re0
    ),
    setarg(8, Pos, K1),
    setarg(5, Pos, none),

    ( is_castle_move(From, To, CastleSide),
      castle_side_color(CastleSide, STM0),
      castle_right_available(CR0, CastleSide),
      castle_path_empty(B, CastleSide)
    ->
      apply_castle_mut(Pos, CastleSide, SquareUndos, PLUndos),
      CaptureOrPawn = quiet
    ;
      apply_normal_mut(Pos, From, To, Promo, SquareUndos, PLUndos, CaptureOrPawn)
    ),

    update_castling_rights_mut(Pos, From, To, STM0, CR0),
    update_ep_square_mut(Pos, From, To, STM0, T0),
    update_halfmove_clock(HM0, T0, CaptureOrPawn, HM1),
    setarg(6, Pos, HM1),
    update_fullmove_number(FM0, STM0, FM1),
    setarg(7, Pos, FM1),

    other_color(STM0, STM1),
    setarg(3, Pos, STM1),
    z_side(SR),
    Pos = pos(_B,_PL2,_STM2,_CR2,_EP2,_HM2,_FM2,K2),
    K3 is K2 xor SR,
    setarg(8, Pos, K3).

unmake_move(Pos, undo(state(STM,CR,EP,HM,FM,K), SquareUndos, PLUndos, _EpXor)) :-
    restore_square_undos(Pos, SquareUndos),
    restore_pl_undos(Pos, PLUndos),
    setarg(3, Pos, STM),
    setarg(4, Pos, CR),
    setarg(5, Pos, EP),
    setarg(6, Pos, HM),
    setarg(7, Pos, FM),
    setarg(8, Pos, K).

restore_square_undos(_Pos, []) :- !.
restore_square_undos(Pos, [sq(Sq,Old)|Rest]) :-
    Pos = pos(B,_PL,_STM,_CR,_EP,_HM,_FM,_K),
    board_set(B, Sq, Old, _),
    restore_square_undos(Pos, Rest).

restore_pl_undos(_Pos, []) :- !.
restore_pl_undos(Pos, [plu(C,T,RemoveSq,AddSq)|Rest]) :-
    Pos = pos(_B,PL,_STM,_CR,_EP,_HM,_FM,_K),
    ( AddSq \= none -> pl_remove(PL,C,T,AddSq) ; true ),
    ( RemoveSq \= none -> pl_add(PL,C,T,RemoveSq) ; true ),
    restore_pl_undos(Pos, Rest).

% --------------------------
% Piece list helpers
% --------------------------

pl_arg(white,pawn,1).   pl_arg(white,knight,2). pl_arg(white,bishop,3).
pl_arg(white,rook,4).   pl_arg(white,queen,5).  pl_arg(white,king,6).
pl_arg(black,pawn,7).   pl_arg(black,knight,8). pl_arg(black,bishop,9).
pl_arg(black,rook,10).  pl_arg(black,queen,11). pl_arg(black,king,12).

pl_add(PL, C, T, Sq) :-
    pl_arg(C,T,A),
    arg(A, PL, L0),
    setarg(A, PL, [Sq|L0]).

pl_remove(PL, C, T, Sq) :-
    pl_arg(C,T,A),
    arg(A, PL, L0),
    select(Sq, L0, L1),
    setarg(A, PL, L1).

% --------------------------
% Castling
% --------------------------

is_castle_move(4,  6, white_kingside).
is_castle_move(4,  2, white_queenside).
is_castle_move(60, 62, black_kingside).
is_castle_move(60, 58, black_queenside).

castle_side_color(white_kingside, white).
castle_side_color(white_queenside, white).
castle_side_color(black_kingside, black).
castle_side_color(black_queenside, black).

castle_right_available(cr(WK,_WQ,_BK,_BQ), white_kingside) :- WK==true.
castle_right_available(cr(_WK,WQ,_BK,_BQ), white_queenside) :- WQ==true.
castle_right_available(cr(_WK,_WQ,BK,_BQ), black_kingside) :- BK==true.
castle_right_available(cr(_WK,_WQ,_BK,BQ), black_queenside) :- BQ==true.

castle_squares(white_kingside, 4, 6, 7, 5, [5,6]).
castle_squares(white_queenside,4, 2, 0, 3, [1,2,3]).
castle_squares(black_kingside, 60,62,63,61,[61,62]).
castle_squares(black_queenside,60,58,56,59,[57,58,59]).

castle_path_empty(B, Side) :-
    castle_squares(Side, _KF,_KT,_RF,_RT, Between),
    forall(member(Sq, Between), board_get(B,Sq,empty)).

apply_castle_mut(Pos, Side, SquareUndos, PLUndos) :-
    Pos = pos(B,PL,STM,_CR,_EP,_HM,_FM,K0),
    castle_squares(Side, KF, KT, RF, RT, _Between),
    board_get(B, KF, KOld),
    board_get(B, KT, ToOld),
    board_get(B, RF, ROld),
    board_get(B, RT, RToOld),
    SquareUndos = [sq(KF,KOld),sq(KT,ToOld),sq(RF,ROld),sq(RT,RToOld)],
    board_set(B, KF, empty, _),
    board_set(B, RF, empty, _),
    board_set(B, KT, pc(STM,king), _),
    board_set(B, RT, pc(STM,rook), _),
    pl_remove(PL,STM,king,KF), pl_add(PL,STM,king,KT),
    pl_remove(PL,STM,rook,RF), pl_add(PL,STM,rook,RT),
    PLUndos = [plu(STM,king,KF,KT), plu(STM,rook,RF,RT)],
    z_piece(STM,king,KF,RKf), z_piece(STM,king,KT,RKt),
    z_piece(STM,rook,RF,RRf), z_piece(STM,rook,RT,RRt),
    K1 is K0 xor RKf xor RKt xor RRf xor RRt,
    setarg(8, Pos, K1).

% --------------------------
% Normal moves
% --------------------------

apply_normal_mut(Pos, From, To, Promo, SquareUndos, PLUndos, CaptureOrPawn) :-
    Pos = pos(B,PL,STM,_CR,EP0,_HM,_FM,K0),
    board_get(B, From, pc(STM,T0)),
    board_get(B, To, ToVal0),
    ( T0==pawn, EP0 \= none, EP0=:=To, ToVal0==empty,
      pawn_ep_capture_square(STM, To, CapSq),
      board_get(B, CapSq, pc(Enemy,pawn)), Enemy \= STM
    ->
      board_get(B, CapSq, CapOld),
      SquareUndos = [sq(From,pc(STM,T0)), sq(To,ToVal0), sq(CapSq,CapOld)],
      board_set(B, From, empty, _),
      board_set(B, CapSq, empty, _),
      promoted_type(STM,T0,To,Promo,Tm),
      board_set(B, To, pc(STM,Tm), _),
      % PL
      pl_remove(PL,Enemy,pawn,CapSq),
      ( Tm==pawn ->
          pl_remove(PL,STM,pawn,From), pl_add(PL,STM,pawn,To),
          PLUndos = [plu(Enemy,pawn,CapSq,none), plu(STM,pawn,From,To)]
      ;
          pl_remove(PL,STM,pawn,From), pl_add(PL,STM,Tm,To),
          PLUndos = [plu(Enemy,pawn,CapSq,none), plu(STM,pawn,From,none), plu(STM,Tm,none,To)]
      ),
      % key
      z_piece(STM,pawn,From,RmF),
      z_piece(Enemy,pawn,CapSq,Rcap),
      z_piece(STM,Tm,To,RmT),
      K1 is K0 xor RmF xor Rcap xor RmT,
      setarg(8, Pos, K1),
      CaptureOrPawn = capture
    ;
      ( ToVal0 = pc(Enemy,CapT) -> (CapT==king -> fail ; true), CaptureOrPawn=capture
      ; Enemy=none, CapT=none, (T0==pawn -> CaptureOrPawn=pawnmove ; CaptureOrPawn=quiet)
      ),
      SquareUndos = [sq(From,pc(STM,T0)), sq(To,ToVal0)],
      board_set(B, From, empty, _),
      promoted_type(STM,T0,To,Promo,Tm),
      board_set(B, To, pc(STM,Tm), _),
      ( Enemy \= none -> pl_remove(PL,Enemy,CapT,To), PLUndosCap=[plu(Enemy,CapT,To,none)] ; PLUndosCap=[] ),
      ( Tm==T0 ->
          pl_remove(PL,STM,T0,From), pl_add(PL,STM,T0,To),
          PLUndosMove=[plu(STM,T0,From,To)]
      ;
          pl_remove(PL,STM,pawn,From), pl_add(PL,STM,Tm,To),
          PLUndosMove=[plu(STM,pawn,From,none),plu(STM,Tm,none,To)]
      ),
      append(PLUndosCap, PLUndosMove, PLUndos),
      z_piece(STM,T0,From,RmF),
      ( Enemy \= none -> z_piece(Enemy,CapT,To,Rcap) ; Rcap=0 ),
      z_piece(STM,Tm,To,RmT),
      K1 is K0 xor RmF xor Rcap xor RmT,
      setarg(8, Pos, K1)
    ).

promoted_type(C, pawn, To, Promo, Tm) :-
    rank_of(To, R),
    ( (C==white, R=:=8 ; C==black, R=:=1) ->
        ( Promo \= none -> Tm = Promo ; Tm = queen )
    ; Promo == none -> Tm = pawn
    ; fail
    ).
promoted_type(_C, T, _To, Promo, T) :- Promo == none.

pawn_ep_capture_square(white, EpTo, CapSq) :- CapSq is EpTo - 8.
pawn_ep_capture_square(black, EpTo, CapSq) :- CapSq is EpTo + 8.

rank_of(Sq, R) :- R is (Sq // 8) + 1.

% --------------------------
% Castling rights update
% --------------------------

update_castling_rights_mut(Pos, From, To, STM, CR0) :-
    ( From == 4,  STM==white -> drop_white_castle(CR0,CR1)
    ; From == 60, STM==black -> drop_black_castle(CR0,CR1)
    ; From == 0,  STM==white -> drop_wq(CR0,CR1)
    ; From == 7,  STM==white -> drop_wk(CR0,CR1)
    ; From == 56, STM==black -> drop_bq(CR0,CR1)
    ; From == 63, STM==black -> drop_bk(CR0,CR1)
    ; To == 0  -> drop_wq(CR0,CR1)
    ; To == 7  -> drop_wk(CR0,CR1)
    ; To == 56 -> drop_bq(CR0,CR1)
    ; To == 63 -> drop_bk(CR0,CR1)
    ; CR1 = CR0
    ),
    ( CR1 \= CR0 ->
        Pos = pos(_B,_PL,_STM,_CR,_EP,_HM,_FM,K0),
        castle_mask(CR0,M0), castle_mask(CR1,M1),
        z_castle(M0,R0), z_castle(M1,R1),
        K1 is K0 xor R0 xor R1,
        setarg(8, Pos, K1),
        setarg(4, Pos, CR1)
    ; true).

drop_white_castle(cr(_WK,_WQ,BK,BQ), cr(false,false,BK,BQ)).
drop_black_castle(cr(WK,WQ,_BK,_BQ), cr(WK,WQ,false,false)).
drop_wk(cr(_WK,WQ,BK,BQ), cr(false,WQ,BK,BQ)).
drop_wq(cr(WK,_WQ,BK,BQ), cr(WK,false,BK,BQ)).
drop_bk(cr(WK,WQ,_BK,BQ), cr(WK,WQ,false,BQ)).
drop_bq(cr(WK,WQ,BK,_BQ), cr(WK,WQ,BK,false)).

castle_mask(cr(WK,WQ,BK,BQ), Mask) :-
    ( WK==true -> B0=1 ; B0=0 ),
    ( WQ==true -> B1=2 ; B1=0 ),
    ( BK==true -> B2=4 ; B2=0 ),
    ( BQ==true -> B3=8 ; B3=0 ),
    Mask is B0+B1+B2+B3.

% --------------------------
% EP square update
% --------------------------

update_ep_square_mut(Pos, From, To, C, T) :-
    Pos = pos(_B,_PL,_STM,_CR,_EP,_HM,_FM,K0),
    ( T==pawn,
      ( C==white, From//8 =:= 1, To//8 =:= 3, To-From=:=16 -> EP is From+8
      ; C==black, From//8 =:= 6, To//8 =:= 4, From-To=:=16 -> EP is From-8
      )
    ->
      setarg(5, Pos, EP),
      file_of(EP,F), z_epfile(F,Re),
      K1 is K0 xor Re,
      setarg(8, Pos, K1)
    ; true).

file_of(Sq, F) :- F is (Sq mod 8) + 1.

% --------------------------
% Clocks
% --------------------------

update_halfmove_clock(HM0, T0, CaptureOrPawn, HM1) :-
    ( T0 == pawn -> HM1 = 0
    ; CaptureOrPawn == capture -> HM1 = 0
    ; HM1 is HM0 + 1
    ).

update_fullmove_number(FM0, STM0, FM1) :-
    ( STM0 == black -> FM1 is FM0 + 1 ; FM1 = FM0 ).

% --------------------------
% Key recomputation (debug / FEN)
% --------------------------

recompute_key(pos(B,_PL,STM,CR,EP,_HM,_FM,_K), Key) :-
    ensure_zobrist,
    findall(R,
      ( between(0,63,Sq),
        board_get(B,Sq,V),
        V = pc(C,T),
        z_piece(C,T,Sq,R)
      ), Rs),
    foldl(xor_, Rs, 0, Kp),
    ( STM == black -> z_side(SR), Ks is Kp xor SR ; Ks = Kp ),
    castle_mask(CR,M), z_castle(M,RC), Kc is Ks xor RC,
    ( EP == none -> Key = Kc
    ; file_of(EP,F), z_epfile(F,Re), Key is Kc xor Re
    ).

xor_(A,B,C) :- C is A xor B.
