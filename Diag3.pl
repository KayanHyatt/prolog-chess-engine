:- use_module(position).
:- use_module(movegen).
:- use_module(fen).

main :-
    fen:startpos_fen(SF),
    fen:fen_to_pos(SF, Pos0),
    position:clone_position(Pos0, Pos),

    Pos = pos(_B, PL, _STM, _CR, _EP, _HM, _FM, _K),

    format("=== Initial white pawn list ===~n"),
    arg(1, PL, WP0), format("  ~w~n", [WP0]),

    format("~n=== Make a2a3, unmake ===~n"),
    position:make_move(Pos, "a2a3", U1),
    arg(1, PL, WPa1), format("  after make a2a3: ~w~n", [WPa1]),
    position:unmake_move(Pos, U1),
    arg(1, PL, WPa2), format("  after unmake a2a3: ~w~n", [WPa2]),

    format("~n=== Make a2a4, unmake ===~n"),
    position:make_move(Pos, "a2a4", U2),
    arg(1, PL, WPb1), format("  after make a2a4: ~w~n", [WPb1]),
    position:unmake_move(Pos, U2),
    arg(1, PL, WPb2), format("  after unmake a2a4: ~w~n", [WPb2]),

    format("~n=== Make b2b3, unmake ===~n"),
    position:make_move(Pos, "b2b3", U3),
    arg(1, PL, WPc1), format("  after make b2b3: ~w~n", [WPc1]),
    position:unmake_move(Pos, U3),
    arg(1, PL, WPc2), format("  after unmake b2b3: ~w~n", [WPc2]),

    format("~n=== Now simulate what legal_move does ===~n"),
    format("~n--- legal_move style: make a2a3, unmake, then enumerate pseudo_move ---~n"),
    position:clone_position(Pos0, Pos2),
    Pos2 = pos(_B2, PL2, _STM2, _CR2, _EP2, _HM2, _FM2, _K2),
    arg(1, PL2, Before),
    format("  pawns before: ~w~n", [Before]),
    position:make_move(Pos2, "a2a3", Ua),
    position:unmake_move(Pos2, Ua),
    arg(1, PL2, After1),
    format("  pawns after make+unmake a2a3: ~w~n", [After1]),
    position:make_move(Pos2, "b2b3", Ub),
    position:unmake_move(Pos2, Ub),
    arg(1, PL2, After2),
    format("  pawns after make+unmake b2b3: ~w~n", [After2]),

    format("~n=== Test findall interaction ===~n"),
    position:clone_position(Pos0, Pos3),
    Pos3 = pos(_B3, PL3, _STM3, _CR3, _EP3, _HM3, _FM3, _K3),
    arg(1, PL3, Pre),
    format("  pawns before findall: ~w (len=~d)~n", [Pre, Len]),
    length(Pre, Len),
    findall(M,
        ( movegen:pseudo_move(Pos3, white, M),
          position:make_move(Pos3, M, Ux),
          position:unmake_move(Pos3, Ux)
        ), _AllMoves),
    arg(1, PL3, Post),
    length(Post, PostLen),
    format("  pawns after findall: ~w (len=~d)~n", [Post, PostLen]),

    format("~n=== Test: does findall + pseudo_move alone duplicate? ===~n"),
    position:clone_position(Pos0, Pos4),
    Pos4 = pos(_B4, PL4, _STM4, _CR4, _EP4, _HM4, _FM4, _K4),
    arg(1, PL4, Pre4),
    format("  pawns before: ~w~n", [Pre4]),
    findall(M, movegen:pseudo_move(Pos4, white, M), _PMs4),
    arg(1, PL4, Post4),
    format("  pawns after pseudo_move findall: ~w~n", [Post4]),

    format("~nDone.~n").