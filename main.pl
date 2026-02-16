:- use_module(xboard).

:- initialization(start).

start :-
    % During compilation (swipl ... -c ...), do NOT start the engine loop.
    current_prolog_flag(os_argv, OsArgv),
    ( member('-c', OsArgv)
    -> true
    ; xboard:run
    ).
