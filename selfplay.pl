:- use_module(engine_state).
:- use_module(movebook).
:- use_module(movegen).
:- use_module(position).
:- use_module(library(format)).

% Entry point for: swipl ... -s selfplay.pl -g main -t halt
main :-
    engine_state:reset_state,
    writeln("=== Prolog Chess Engine: Self-Play (CLI) ==="),
    MaxPlies = 200,
    loop(1, MaxPlies),
    writeln("=== Done ===").

loop(Ply, MaxPlies) :-
    ( Ply > MaxPlies ->
        format("Stopped: ply limit reached (~w).~n", [MaxPlies])
    ; engine_state:side_to_move(Color),
      engine_state:get_position(Pos),
      choose_and_play(Pos, Color, Ply, Result),
      ( Result = continue ->
          engine_state:toggle_side_to_move,
          Ply2 is Ply + 1,
          loop(Ply2, MaxPlies)
      ; Result = stop(Reason) ->
          format("Stopped: ~w~n", [Reason])
      )
    ).

choose_and_play(Pos, Color, Ply, Result) :-
    movebook:choose_move(Color, Move),
    ( Move == resign ->
        format("~w. ~w resigns~n", [Ply, Color]),
        Result = stop(resign)
    ; movegen:legal_move(Pos, Color, Move) ->
        % print a simple ply log
        format("~w. ~w: ~w~n", [Ply, Color, Move]),
        ( engine_state:apply_move(Move) ->
            Result = continue
        ;   % should not happen if legal_move/3 + position:apply_move/3 agree
            Result = stop(apply_failed(Move))
        )
    ;   % safety: if movebook returns illegal, fallback to any legal move
        findall(M, movegen:legal_move(Pos, Color, M), Ms),
        ( Ms == [] ->
            Result = stop(no_legal_moves)
        ; Ms = [Fallback|_],
          format("~w. ~w: (fallback) ~w~n", [Ply, Color, Fallback]),
          ( engine_state:apply_move(Fallback) -> Result = continue
          ; Result = stop(apply_failed(Fallback))
          )
        )
    ).
