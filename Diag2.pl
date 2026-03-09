:- use_module(position).
:- use_module(movegen).
:- use_module(fen).

main :-
    fen:startpos_fen(SF),
    fen:fen_to_pos(SF, Pos0),
    position:clone_position(Pos0, Pos),

    Pos = pos(_B, PL, _STM, _CR, _EP, _HM, _FM, _K),

    format("=== Initial white pawn list ===~n"),
    arg(1, PL, WP0),
    format("  ~w~n", [WP0]),

    format("~n=== Make a2a3 ===~n"),
    position:make_move(Pos, "a2a3", Undo1),
    arg(1, PL, WP1),
    format("  white pawns after make: ~w~n", [WP1]),

    format("~n=== Unmake a2a3 ===~n"),
    position:unmake_move(Pos, Undo1),
    arg(1, PL, WP2),
    format("  white pawns after unmake: ~w~n", [WP2]),
    length(WP2, Len2),
    format("  length: ~d~n", [Len2]),

    format("~n=== Make a2a3 again ===~n"),
    position:make_move(Pos, "a2a3", Undo2),
    arg(1, PL, WP3),
    format("  white pawns after 2nd make: ~w~n", [WP3]),

    format("~n=== Unmake a2a3 again ===~n"),
    position:unmake_move(Pos, Undo2),
    arg(1, PL, WP4),
    format("  white pawns after 2nd unmake: ~w~n", [WP4]),
    length(WP4, Len4),
    format("  length: ~d~n", [Len4]),

    format("~n=== Make a2a3 third time ===~n"),
    position:make_move(Pos, "a2a3", Undo3),
    arg(1, PL, WP5),
    format("  white pawns after 3rd make: ~w~n", [WP5]),

    format("~n=== Unmake a2a3 third time ===~n"),
    position:unmake_move(Pos, Undo3),
    arg(1, PL, WP6),
    format("  white pawns after 3rd unmake: ~w~n", [WP6]),
    length(WP6, Len6),
    format("  length: ~d~n", [Len6]),

    format("~nDone.~n").