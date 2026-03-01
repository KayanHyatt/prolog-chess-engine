:- use_module(engine_state).
:- use_module(movebook).
:- use_module(movegen).
:- use_module(position).
:- use_module(pgn).

% Config: write PGN every N plies (half-moves)
pgn_every_plies(10).

% swipl -q -f none -s selfplay.pl -g main -t halt
main :-
    engine_state:reset_state,
    engine_state:get_position(StartPos),
    writeln("=== Prolog Chess Engine: Self-Play (CLI) ==="),
    MaxPlies = 200,
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
              fail
            ))
    -> safe_replace_file(Tmp, "game.pgn"),
       writeln("Wrote game.pgn (final)")
    ;  true
    ).

maybe_write_pgn(Ply, StartPos, MovesRev) :-
    pgn_every_plies(N),
    ( N > 0,
      0 is Ply mod N
    -> reverse(MovesRev, Moves),
       Tmp = "game_tmp.pgn",
       ( catch(pgn:write_game_pgn(Tmp, StartPos, Moves, "PrologEngine", "PrologEngine"), E,
               ( print_message(error, E),
                 format("PGN checkpoint failed at ply ~w~n", [Ply]),
                 fail
               ))
         -> safe_replace_file(Tmp, "game.pgn"),
            format("Wrote game.pgn (checkpoint at ply ~w)~n", [Ply])
         ;  true
       )
    ;  true
    ).

safe_replace_file(Tmp, Final) :-
    catch(delete_file(Final), _, true),
    catch(rename_file(Tmp, Final), E,
          ( print_message(error, E),
            % if rename fails, keep tmp so you can inspect it
            true
          )).

loop(Ply, MaxPlies, StartPos, Acc0, Acc) :-
    ( Ply > MaxPlies ->
        format("Stopped: ply limit reached (~w).~n", [MaxPlies]),
        Acc = Acc0
    ; engine_state:get_position(Pos),

      % optional: if you still have this stop
      ( engine_state:repetition_count(Pos, C), C >= 3 ->
          format("Stopped: threefold repetition (count=~w).~n", [C]),
          Acc = Acc0
      ; engine_state:side_to_move(Color),
        choose_and_play(Pos, Color, Ply, MoveOpt, Result),

        % write checkpoint pgn every N plies (after making the move)
        ( Result = continue ->
            engine_state:toggle_side_to_move,
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