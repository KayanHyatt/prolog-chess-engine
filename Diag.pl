:- use_module(position).
:- use_module(movegen).
:- use_module(fen).

main :-
    fen:startpos_fen(SF),
    fen:fen_to_pos(SF, Pos0),

    format("=== Test 1: piece list contents ===~n"),
    position:clone_position(Pos0, P1),
    P1 = pos(_B1, PL1, _STM1, _CR1, _EP1, _HM1, _FM1, _K1),
    functor(PL1, F, A),
    format("PL functor: ~w/~w~n", [F, A]),
    forall(between(1, 12, I),
        ( arg(I, PL1, List),
          length(List, Len),
          format("  PL arg ~d: length=~d, contents=~w~n", [I, Len, List])
        )
    ),

    format("~n=== Test 2: pseudo_move count ===~n"),
    position:clone_position(Pos0, P2),
    findall(M, movegen:pseudo_move(P2, white, M), PMs),
    length(PMs, NP),
    format("Pseudo-legal moves for white: ~d~n", [NP]),
    sort(PMs, SPMs),
    length(SPMs, NSP),
    format("Unique pseudo-legal moves: ~d~n", [NSP]),
    forall(member(M, SPMs), format("  ~w~n", [M])),

    format("~n=== Test 3: legal_move count ===~n"),
    position:clone_position(Pos0, P3),
    findall(M, movegen:legal_move(P3, white, M), LMs),
    length(LMs, NL),
    format("Legal moves for white: ~d~n", [NL]),
    sort(LMs, SLMs),
    length(SLMs, NSL),
    format("Unique legal moves: ~d~n", [NSL]),
    forall(member(M, SLMs), format("  ~w~n", [M])),

    format("~n=== Test 4: position state after legal_move enumeration ===~n"),
    position:clone_position(Pos0, P4),
    P4 = pos(B4, _PL4, _STM4, _CR4, _EP4, _HM4, _FM4, _K4),
    format("Board[8] (a2) BEFORE: "),
    position:board_get(B4, 8, V8a),
    format("~w~n", [V8a]),
    findall(M, movegen:legal_move(P4, white, M), _LMs4),
    format("Board[8] (a2) AFTER: "),
    position:board_get(B4, 8, V8b),
    format("~w~n", [V8b]),
    position:side_to_move(P4, StmAfter),
    format("STM after: ~w~n", [StmAfter]),

    format("~n=== Test 5: perft depth 1 ===~n"),
    position:clone_position(Pos0, P5),
    position:side_to_move(P5, STM5),
    format("STM: ~w~n", [STM5]),
    findall(Move,
        ( movegen:legal_move(P5, STM5, Move),
          position:make_move(P5, Move, Undo),
          position:unmake_move(P5, Undo)
        ), Ms5),
    length(Ms5, NN5),
    format("Perft-style count: ~d~n", [NN5]),
    sort(Ms5, SMs5),
    length(SMs5, NUs5),
    format("Unique: ~d~n", [NUs5]),
    ( NN5 =\= NUs5 ->
        format("DUPLICATES FOUND:~n"),
        msort(Ms5, Sorted5),
        show_duplicates(Sorted5)
    ; true ),

    format("~nDone.~n").

show_duplicates([]).
show_duplicates([_]) :- !.
show_duplicates([A,A|Rest]) :- !,
    count_run(A, [A|Rest], N, Remaining),
    format("  ~w appears ~d times~n", [A, N]),
    show_duplicates(Remaining).
show_duplicates([_|Rest]) :-
    show_duplicates(Rest).

count_run(_, [], 0, []) :- !.
count_run(A, [A|Rest], N, Remaining) :- !,
    count_run(A, Rest, N1, Remaining),
    N is N1 + 1.
count_run(_, List, 0, List).