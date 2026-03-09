:- use_module(position).
:- use_module(movegen).
:- use_module(fen).

main :-
    fen:startpos_fen(SF),
    fen:fen_to_pos(SF, Pos0),

    format("=== Test A: findall with make+unmake inside ===~n"),
    position:clone_position(Pos0, PA),
    PA = pos(_BA, PLA, _STMA, _CRA, _EPA, _HMA, _FMA, _KA),
    arg(1, PLA, PreA),
    length(PreA, LenPreA),
    format("  pawns before findall: ~w (len=~d)~n", [PreA, LenPreA]),
    findall(M,
        ( movegen:pseudo_move(PA, white, M),
          position:make_move(PA, M, Ux),
          position:unmake_move(PA, Ux)
        ), AllMovesA),
    length(AllMovesA, NA),
    arg(1, PLA, PostA),
    length(PostA, LenPostA),
    format("  moves found: ~d~n", [NA]),
    format("  pawns after findall: ~w (len=~d)~n", [PostA, LenPostA]),

    format("~n=== Test B: findall with legal_move (has make+unmake inside) ===~n"),
    position:clone_position(Pos0, PB),
    PB = pos(_BB, PLB, _STMB, _CRB, _EPB, _HMB, _FMB, _KB),
    arg(1, PLB, PreB),
    length(PreB, LenPreB),
    format("  pawns before: ~w (len=~d)~n", [PreB, LenPreB]),
    findall(M, movegen:legal_move(PB, white, M), AllMovesB),
    length(AllMovesB, NB),
    arg(1, PLB, PostB),
    length(PostB, LenPostB),
    format("  legal moves found: ~d~n", [NB]),
    format("  pawns after: ~w (len=~d)~n", [PostB, LenPostB]),

    format("~n=== Test C: step through legal_move manually ===~n"),
    position:clone_position(Pos0, PC),
    PC = pos(_BC, PLC, _STMC, _CRC, _EPC, _HMC, _FMC, _KC),
    arg(1, PLC, PreC),
    format("  pawns before: ~w~n", [PreC]),
    
    % Manually do what legal_move does for first move
    format("~n  --- First call to legal_move internals ---~n"),
    movegen:pseudo_move(PC, white, M1),
    format("  pseudo_move returned: ~w~n", [M1]),
    arg(1, PLC, PLstate1),
    format("  pawns after pseudo_move: ~w~n", [PLstate1]),
    position:make_move(PC, M1, Undo1),
    arg(1, PLC, PLstate2),
    format("  pawns after make_move: ~w~n", [PLstate2]),
    ( \+ movegen:in_check(PC, white) -> Legal1 = true ; Legal1 = false ),
    arg(1, PLC, PLstate3),
    format("  pawns after in_check test: ~w~n", [PLstate3]),
    position:unmake_move(PC, Undo1),
    arg(1, PLC, PLstate4),
    format("  pawns after unmake_move: ~w~n", [PLstate4]),
    format("  legal=~w, move=~w~n", [Legal1, M1]),
    !,  % cut to stop after first move

    format("~n=== Test D: does in_check corrupt piece lists? ===~n"),
    position:clone_position(Pos0, PD),
    PD = pos(_BD, PLD, _STMD, _CRD, _EPD, _HMD, _FMD, _KD),
    arg(1, PLD, PreD),
    format("  pawns before: ~w~n", [PreD]),
    position:make_move(PD, "a2a3", UndoD),
    arg(1, PLD, MidD),
    format("  pawns after make a2a3: ~w~n", [MidD]),
    % Test in_check
    ( movegen:in_check(PD, white) -> format("  in check~n") ; format("  not in check~n") ),
    arg(1, PLD, MidD2),
    format("  pawns after in_check: ~w~n", [MidD2]),
    % Test with \+
    ( \+ movegen:in_check(PD, white) -> format("  \\+ in_check ok~n") ; format("  \\+ in_check fail~n") ),
    arg(1, PLD, MidD3),
    format("  pawns after \\+ in_check: ~w~n", [MidD3]),
    position:unmake_move(PD, UndoD),
    arg(1, PLD, PostD),
    format("  pawns after unmake: ~w~n", [PostD]),

    format("~nDone.~n").