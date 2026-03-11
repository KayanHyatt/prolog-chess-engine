:- module(san, [
    uci_to_san/4,
    uci_to_san_checked/6
]).

:- use_module(library(lists)).
:- use_module(position).
:- use_module(movegen).

/*
uci_to_san(+Pos, +SideToMove, +UciMove, -SanString)

Supports:
- normal moves (e4, Nf3, Bb5)
- captures (exd5, Nxe5, Qxd7)
- check/checkmate (+/#)
- castling (O-O, O-O-O)
- promotions (e8=Q, exd8=Q+)
- disambiguation (Nbd2 / N1d2)

Assumes UCI is legal in given position (best results).
*/

uci_to_san(Pos, Side, Uci, San) :-
    % Backwards-compatible wrapper.
    % If SAN generation fails sanity checks, we return "??" rather than risking a wrong SAN.
    ( uci_to_san_checked(Pos, Side, Uci, San0, ok, _Dbg)
    -> San = San0
    ;  San = "??"
    ).

/*
uci_to_san_checked(+Pos, +SideToMove, +UciMove, -SanString, -Status, -Debug)

Status is:
  - ok
  - err(Reason)

Debug is:
  dbg(FromIdx, ToIdx, MovingType, PromoChar, IsCastle)

This predicate is designed for PGN writing / debugging: it refuses to emit a
potentially incorrect SAN. In particular it:
  - Determines the moving piece strictly from the From-square.
  - Validates that applying the UCI move results in the expected piece on To.
  - On any mismatch/failure it returns Status=err(...) and San="??".
*/
uci_to_san_checked(Pos, Side, UciIn, San, Status, Dbg) :-
    normalize_uci(UciIn, Uci),
    ( is_castle(Pos, Side, Uci, CastleSan) ->
        Dbg = dbg(none, none, king, none, true),
        ( position:apply_move(Pos, Uci, _Pos2)
        -> suffix_check(Pos, Side, Uci, CastleSan, San),
           Status = ok
        ;  San = "??",
           Status = err(apply_move_failed(castle)),
           !
        )
    ; parse_uci(Uci, From, To, PromoChar) ->
        ( moving_piece_checked(Pos, Side, From, Type) ->
            Dbg = dbg(From, To, Type, PromoChar, false),
            ( position:apply_move(Pos, Uci, Pos2) ->
                ( validate_resulting_piece(Pos2, Side, Type, To, PromoChar, Reason0) ->
                    capture_kind(Pos, Side, Type, From, To, Capture, EpCapture),
                    base_san(Pos, Side, Type, From, To, Capture, EpCapture, PromoChar, Base),
                    suffix_check(Pos, Side, Uci, Base, San),
                    Status = ok
                ;   San = "??",
                    Status = err(Reason0)
                )
            ;   San = "??",
                Status = err(apply_move_failed(Uci))
            )
        ;   San = "??",
            Dbg = dbg(From, To, none, PromoChar, false),
            Status = err(no_piece_on_from(From))
        )
    ;   San = "??",
        Status = err(bad_uci(Uci)),
        Dbg = dbg(none, none, none, none, false)
    ).

% -------- parsing helpers --------
normalize_uci(UciIn, Uci) :-
    ( string(UciIn) -> Uci = UciIn
    ; atom(UciIn)   -> atom_string(UciIn, Uci)
    ; term_string(UciIn, Uci)
    ).

parse_uci(Uci, From, To, PromoChar) :-
    normalize_uci(Uci, U),
    string_chars(U, Cs),
    Cs = [F1,R1,F2,R2|Rest],
    string_chars(SFrom, [F1,R1]),
    string_chars(STo,   [F2,R2]),
    position:sq_index(SFrom, From),
    position:sq_index(STo,   To),
    ( Rest = [P] -> PromoChar = P ; PromoChar = none ).

moving_piece(Pos, Side, From, Type) :-
    position:piece(Pos, Side, Type, From), !.

moving_piece_checked(Pos, Side, From, Type) :-
    integer(From), From >= 0, From =< 63,
    position:piece(Pos, Side, Type, From), !.

validate_resulting_piece(Pos2, Side, Type, To, PromoChar, Reason) :-
    expected_type(Type, PromoChar, ExpType),
    ( position:piece(Pos2, Side, ExpType, To) ->
        true
    ; findall(T, position:piece(Pos2, Side, T, To), Ts),
      ( Ts == [] -> Reason = post_move_missing_piece(To, ExpType)
      ; Reason = post_move_piece_mismatch(To, expected(ExpType), found(Ts))
      ),
      fail
    ).

expected_type(pawn, none, pawn) :- !.
expected_type(pawn, P, T2) :-
    P \= none,
    promo_piece_letter(P, L),
    promo_letter_type(L, T2), !.
expected_type(T, _P, T).

promo_letter_type("Q", queen).
promo_letter_type("R", rook).
promo_letter_type("B", bishop).
promo_letter_type("N", knight).

is_castle(Pos, Side, "e1g1", "O-O")   :- position:piece(Pos, Side, king, 4).
is_castle(Pos, Side, "e1c1", "O-O-O") :- position:piece(Pos, Side, king, 4).
is_castle(Pos, Side, "e8g8", "O-O")   :- position:piece(Pos, Side, king, 60).
is_castle(Pos, Side, "e8c8", "O-O-O") :- position:piece(Pos, Side, king, 60).

% capture detection, incl en passant
capture_kind(Pos, Side, pawn, From, To, Capture, EpCapture) :-
    ( position:piece(Pos, Enemy, _, To), Enemy \= Side ->
        Capture = true, EpCapture = false
    ; position:ep_square(Pos, EP), EP \= none, To =:= EP,
      file_of(From, FF), file_of(To, TF), abs(TF-FF) =:= 1 ->
        Capture = true, EpCapture = true
    ; Capture = false, EpCapture = false
    ).
capture_kind(Pos, Side, _Type, _From, To, Capture, false) :-
    ( position:piece(Pos, Enemy, _, To), Enemy \= Side -> Capture = true ; Capture = false ).

% -------- SAN building --------
base_san(_Pos, _Side, pawn, From, To, Capture, _EpCap, PromoChar, San) :-
    % pawn SAN: file if capture, then "x", then target
    to_sq(To, ToSq),
    file_of(From, FF),
    file_char(FF, FChar),
    ( Capture == true ->
        format(string(Stem0), "~w x~w", [FChar, ToSq]),
        strip_spaces(Stem0, Stem1)
    ; Stem1 = ToSq
    ),
    promo_suffix(PromoChar, PromoSuf),
    string_concat(Stem1, PromoSuf, San).

base_san(Pos, Side, Type, From, To, Capture, _EpCap, PromoChar, San) :-
    Type \= pawn,
    piece_letter(Type, Ltr),
    disambiguator(Pos, Side, Type, From, To, Dis),
    to_sq(To, ToSq),
    ( Capture == true -> Cap = "x" ; Cap = "" ),
    promo_suffix(PromoChar, PromoSuf),
    format(string(S0), "~w~w~w~w~w", [Ltr, Dis, Cap, ToSq, PromoSuf]),
    strip_spaces(S0, San).

piece_letter(knight, "N").
piece_letter(bishop, "B").
piece_letter(rook,   "R").
piece_letter(queen,  "Q").
piece_letter(king,   "K").

promo_suffix(none, "") :- !.
promo_suffix(P, S) :-
    promo_piece_letter(P, L),
    format(string(S), "=~w", [L]).

promo_piece_letter('q', "Q").
promo_piece_letter('r', "R").
promo_piece_letter('b', "B").
promo_piece_letter('n', "N").
promo_piece_letter('Q', "Q").
promo_piece_letter('R', "R").
promo_piece_letter('B', "B").
promo_piece_letter('N', "N").
promo_piece_letter(_, "Q").

% Convert square index to like "e4"
to_sq(Idx, SqStr) :- position:index_sq(Idx, SqStr).

% Disambiguation: if another same piece can also move to To, include file or rank or both
disambiguator(Pos, Side, Type, From, To, Dis) :-
    findall(F,
        ( position:piece(Pos, Side, Type, F),
          F \= From,
          can_reach(Pos, Side, Type, F, To)
        ),
        Others),
    ( Others == [] ->
        Dis = ""
    ; file_of(From, FF), rank_of(From, RF),
      ( member(F2, Others), file_of(F2, FF) -> SameFile = true ; SameFile = false ),
      ( member(F2, Others), rank_of(F2, RF) -> SameRank = true ; SameRank = false ),
      from_sq_file_rank(From, SF, SR),
      ( SameFile, SameRank -> format(string(Dis), "~w~w", [SF, SR])
      ; SameFile          -> Dis = SR
      ; SameRank          -> Dis = SF
      ; Dis = SF
      )
    ).

% A "can reach" test: checks legality list. This is slower but correct and easy.
can_reach(Pos, Side, _Type, From, To) :-
    % generate all legal moves and see if any matches From->To
    movegen:legal_move(Pos, Side, M),
    parse_uci(M, F, T, _P),
    F =:= From, T =:= To, !.

from_sq_file_rank(Idx, FileS, RankS) :-
    file_of(Idx, F), rank_of(Idx, R),
    file_char(F, FC),
    number_string(R, RankS),
    string_chars(FileS, [FC]).

file_of(Sq, F) :- F is (Sq mod 8) + 1.
rank_of(Sq, R) :- R is (Sq // 8) + 1.

file_char(N, C) :-
    nth1(N, ['a','b','c','d','e','f','g','h'], C).

strip_spaces(In, Out) :-
    split_string(In, " ", " ", Parts),
    atomic_list_concat(Parts, "", Out).

% -------- check / mate suffix --------
suffix_check(Pos, Side, Uci, Base, San) :-
    ( position:apply_move(Pos, Uci, Pos2) ->
        other_side(Side, Enemy),
        ( movegen:in_check(Pos2, Enemy) ->
            ( \+ movegen:legal_move(Pos2, Enemy, _) ->
                string_concat(Base, "#", San)
            ; string_concat(Base, "+", San)
            )
        ; San = Base
        )
    ; San = Base ).

other_side(white, black).
other_side(black, white).