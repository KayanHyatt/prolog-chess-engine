:- use_module(engine_state).
:- use_module(movebook).
:- use_module(movegen).
:- use_module(position).
:- use_module(pgn).

main :-
    engine_state:reset_state,
    engine_state:get_position(StartPos),
    writeln("=== Prolog Chess Engine: Self-Play (CLI) ==="),
    MaxPlies = 200,
    loop(1, MaxPlies, [], MovesRev),
    reverse(MovesRev, Moves),
    pgn:write_game_pgn("game.pgn", StartPos, Moves, "PrologEngine", "PrologEngine"),
    writeln("Wrote game.pgn"),
    writeln("=== Done ===").

loop(Ply, MaxPlies, Acc, Acc) :-
    Ply > MaxPlies,
    format("Stopped: ply limit reached (~w).~n", [MaxPlies]),
    !.
loop(Ply, MaxPlies, Acc0, Acc) :-
    engine_state:side_to_move(Color),
    engine_state:get_position(Pos),
    choose_and_play(Pos, Color, Ply, MoveOpt, Result),
    ( Result = continue ->
        engine_state:toggle_side_to_move,
        Ply2 is Ply + 1,
        ( MoveOpt = none -> Acc1 = Acc0 ; Acc1 = [MoveOpt|Acc0] ),
        loop(Ply2, MaxPlies, Acc1, Acc)
    ; Result = stop(Reason) ->
        format("Stopped: ~w~n", [Reason]),
        Acc = Acc0
    ).

choose_and_play(Pos, Color, Ply, Move, Result) :-
    movebook:choose_move(Color, M0),
    ( M0 == resign ->
        format("~w. ~w resigns~n", [Ply, Color]),
        Move = none,
        Result = stop(resign)
    ; movegen:legal_move(Pos, Color, M0) ->
        format("~w. ~w: ~w~n", [Ply, Color, M0]),
        ( engine_state:apply_move(M0) ->
            Move = M0,
            Result = continue
        ;   Move = none,
            Result = stop(apply_failed(M0))
        )
    ;   % safety fallback
        findall(M, movegen:legal_move(Pos, Color, M), Ms),
        ( Ms == [] ->
            Move = none,
            Result = stop(no_legal_moves)
        ; Ms = [Fallback|_],
          format("~w. ~w: (fallback) ~w~n", [Ply, Color, Fallback]),
          ( engine_state:apply_move(Fallback) ->
              Move = Fallback,
              Result = continue
          ;   Move = none,
              Result = stop(apply_failed(Fallback))
          )
        )
    ).