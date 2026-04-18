:- use_module(position).
:- use_module(movegen).
:- use_module(fen).
:- use_module(eval).
:- use_module(search).
:- use_module(library(lists)).

run :-
    format("~n=== TACTICAL TEST SUITE ===~n~n"),
    tac("Back-rank mate (M1)",
        "6k1/5ppp/8/8/8/8/8/4R1K1 w - - 0 1",
        "e1e8", 10000, R1),
    tac("Q+K mate-in-1",
        "k7/8/1K6/8/8/8/8/1Q6 w - - 0 1",
        "b1a2", 10000, R2),
    tac("Rook mate-in-1",
        "1k6/8/1K6/8/8/8/8/R7 w - - 0 1",
        "a1a8", 5000, R3),
    tac("Promote pawn",
        "8/P7/8/8/8/8/8/4K2k w - - 0 1",
        "a7a8q", 5000, R4),
    tac("Capture hanging piece",
        "r1bqkbnr/pppppppp/2n5/4N3/8/8/PPPPPPPP/RNBQKB1R b KQkq - 0 2",
        "c6e5", 5000, R5),
    tac("Scholar's Qxf7#",
        "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR w KQkq - 2 3",
        "f3f7", 5000, R6),
    tac("Recapture knight",
        "rnbqkb1r/pppppppp/8/8/4n3/3B4/PPPPPPPP/RNBQK1NR w KQkq - 0 3",
        "d3e4", 5000, R7),
    tac("Queen captures undefended bishop",
        "rnb1kbnr/pppppppp/8/8/4q3/8/PPPPBPPP/RNBQK1NR b KQkq - 0 3",
        "e4e2", 5000, R8),
    tac("Smothered mate pattern",
        "r5rk/5Npp/8/8/8/8/8/4K2R w - - 0 1",
        "h1h7", 10000, R9),
    tac("King takes undefended rook",
        "8/8/8/8/8/8/r7/K7 w - - 0 1",
        "a1a2", 5000, R10),
    count_passes([R1,R2,R3,R4,R5,R6,R7,R8,R9,R10], P, T),
    format("~nResult: ~w / ~w passed~n~n", [P, T]).

tac(Label, FenStr, Expected, TimeMs, Result) :-
    fen:fen_to_pos(FenStr, Pos0),
    position:clone_position(Pos0, Pos),
    position:side_to_move(Pos, STM),
    search:reset_tables,
    ( catch(
        search:best_move_timed(Pos, STM, 20, TimeMs, Found, Score),
        _, (Found = none, Score = 0)
      )
    -> true
    ;  Found = none, Score = 0
    ),
    ( Found == Expected
    -> Result = pass,
       format("  PASS  ~w  (found ~w, score=~w)~n", [Label, Found, Score])
    ;  Result = fail,
       format("  FAIL  ~w  (expected ~w, got ~w, score=~w)~n",
           [Label, Expected, Found, Score])
    ).

count_passes([], 0, 0).
count_passes([pass|R], P, T) :- count_passes(R, P0, T0), P is P0+1, T is T0+1.
count_passes([fail|R], P, T) :- count_passes(R, P0, T0), P is P0, T is T0+1.