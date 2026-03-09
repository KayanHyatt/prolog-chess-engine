:- use_module(engine_state).
:- use_module(movebook).
:- use_module(movegen).
:- use_module(position).
:- use_module(pgn).

pgn_every_plies(10).

main :-
    engine_state:reset_state,
    engine_state:get_position(StartPos),
    writeln("=== Prolog Chess Engine: Self-Play (CLI) ==="),
    MaxPlies = 400,
    setup_call_cleanup(
        true,
        loop(1, MaxPlies, StartPos, [], MovesRev),
        finalize_pgn(StartPos, MovesRev)
    ),
    writeln("=== Done ===").

finalize_pgn(StartPos, MovesRev) :-
    reverse(MovesRev, Moves),
    Tmp = "game_tmp.pgn",
    ( catch(pgn:write_game_pgn(Tmp, StartPos, Moves, "PrologEngine", "PrologEngine"), E,
            ( print_message(error, E),
              writeln("Failed to write final PGN"),
              fail ))
    -> safe_replace_file(Tmp, "game.pgn"),
       writeln("Wrote game.pgn (final)")
    ;  true ).

maybe_write_pgn(Ply, StartPos, MovesRev) :-
    pgn_every_plies(N),
    ( N > 0, 0 is Ply mod N ->
        reverse(MovesRev, Moves),
        Tmp = "game_tmp.pgn",
        ( catch(pgn:write_game_pgn(Tmp, StartPos, Moves, "PrologEngine", "PrologEngine"), E,
                ( print_message(error, E),
                  format("PGN checkpoint failed at ply ~w~n", [Ply]),
                  fail ))
        -> safe_replace_file(Tmp, "game.pgn"),
           format("Wrote game.pgn (checkpoint at ply ~w)~n", [Ply])
        ;  true )
    ; true ).

safe_replace_file(Tmp, Final) :-
    catch(delete_file(Final), _, true),
    catch(rename_file(Tmp, Final), E,
          ( print_message(error, E),
            true )).

loop(Ply, MaxPlies, _StartPos, Acc, Acc) :-
    Ply > MaxPlies,
    format("Stopped: ply limit reached (~w).~n", [MaxPlies]),
    !.

loop(Ply, MaxPlies, StartPos, Acc0, Acc) :-
    engine_state:get_position(Pos),
    engine_state:side_to_move(Color),

    % Draw rules (50-move, threefold repetition, insufficient material)
    ( position:halfmove_clock(Pos, HM), HM >= 100 ->
        format("Stopped: draw by 50-move rule (halfmove=~w).~n", [HM]),
        Acc = Acc0
    ; engine_state:repetition_count(Pos, Rep), Rep >= 3 ->
        format("Stopped: draw by threefold repetition (count=~w).~n", [Rep]),
        Acc = Acc0
    ; movegen:insufficient_material(Pos) ->
        writeln("Stopped: draw by insufficient material."),
        Acc = Acc0
    ;

    % Game end detection: checkmate / stalemate
      ( \+ movegen:legal_move(Pos, Color, _) ->
        ( movegen:in_check(Pos, Color) ->
            format("Stopped: checkmate (~w to move).~n", [Color])
        ;   format("Stopped: stalemate (~w to move).~n", [Color])
        ),
        Acc = Acc0
    ;   choose_and_play(Pos, Color, Ply, MoveOpt, Result),
        ( Result = continue ->
            ( MoveOpt = none -> Acc1 = Acc0 ; Acc1 = [MoveOpt|Acc0] ),
            maybe_write_pgn(Ply, StartPos, Acc1),
            Ply2 is Ply + 1,
            loop(Ply2, MaxPlies, StartPos, Acc1, Acc)
        ; Result = stop(Reason) ->
            format("Stopped: ~w~n", [Reason]),
            Acc = Acc0
        )
      )
    ).

choose_and_play(Pos, Color, Ply, Move, Result) :-
    movebook:choose_move(Color, M0),
    ( M0 == resign ->
        format("~w. ~w resigns~n", [Ply, Color]),
        Move = none,
        Result = stop(resign)
    ; movegen:legal_move(Pos, Color, M0) ->
        format("~w. ~w: ~w~n", [Ply, Color, M0]),
        engine_state:note_played(Color, M0),
        ( engine_state:apply_move(M0) ->
            Move = M0,
            Result = continue
        ;   Move = none,
            Result = stop(apply_failed(M0))
        )
    ;   findall(M, movegen:legal_move(Pos, Color, M), Ms),
        ( Ms == [] ->
            Move = none,
            Result = stop(no_legal_moves)
        ; random_member(Fallback, Ms),
          format("~w. ~w: (fallback) ~w~n", [Ply, Color, Fallback]),
          engine_state:note_played(Color, Fallback),
          ( engine_state:apply_move(Fallback) ->
              Move = Fallback,
              Result = continue
          ;   Move = none,
              Result = stop(apply_failed(Fallback))
          )
        )
    ).