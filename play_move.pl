:- use_module(position).
:- use_module(movegen).
:- use_module(fen).
:- use_module(eval).
:- use_module(search).

run :-
    current_prolog_flag(argv, Args),
    Args = [FenStr|_],
    atom_string(FenStr, Fen),
    fen:fen_to_pos(Fen, Pos0),
    position:clone_position(Pos0, Pos),
    position:side_to_move(Pos, STM),
    search:reset_tables,
    search:best_move_timed(Pos, STM, 20, 60000, Move, Score),
    format("Best move: ~w  (score: ~w)~n", [Move, Score]).