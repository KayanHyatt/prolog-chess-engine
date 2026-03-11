:- module(movebook, [choose_move/2, choose_move/4]).

:- use_module(library(lists)).
:- use_module(library(random)).
:- use_module(engine_state).
:- use_module(position).
:- use_module(movegen).
:- use_module(eval).

:- ( catch(use_module(search), _, fail) -> true ; true ).

% -------- configuration --------
max_depth(10).        % allow deeper iterative deepening
time_ms(2000).        % 2 seconds per move
avoid_window(12).

choose_move(Color, Move) :-
    engine_state:get_position(Pos),
    time_ms(Tms),
    choose_move(Pos, Color, Tms, Move).

choose_move(Pos, Color, TimeMs, Move) :-
    findall(M, movegen:legal_move(Pos, Color, M), Ms0),
    sort(Ms0, Ms),
    ( Ms == [] -> Move = resign
    ; ( can_search ->
          choose_by_search(Pos, Color, Ms, TimeMs, Move)
      ;   choose_by_1ply(Pos, Color, Ms, Move)
      )
    ).

can_search :- functor(H, best_move, 5), predicate_property(search:H, _), !.

choose_by_search(Pos, Color, Ms, TimeMs, Move) :-
    max_depth(MaxD),
    search:reset_tables,
    ( ( predicate_property(search:best_move_timed(_,_,_,_,_,_), _) ->
          catch(search:best_move_timed(Pos, Color, MaxD, TimeMs, Best, _Score), _, fail)
      ;   catch(search:best_move(Pos, Color, MaxD, Best, _Score), _, fail)
      ),
      Best \= none,
      member(Best, Ms)
    -> Move = Best
    ;  choose_by_1ply(Pos, Color, Ms, Move)
    ).

choose_by_1ply(Pos, Color, Ms, Move) :-
    ( best_1ply(Pos, Color, Ms, Best) -> Move = Best
    ; random_member(Move, Ms)
    ).

best_1ply(Pos, Color, Moves, BestMove) :-
    findall(Score-M,
        ( member(M, Moves), score_after(Pos, Color, M, Score) ),
        Scored0),
    Scored0 \== [],
    keysort(Scored0, Asc),
    reverse(Asc, [_-BestMove|_]).

score_after(Pos, Color, MoveStr, Score) :-
    ( position:apply_move(Pos, MoveStr, Pos2)
    -> catch(eval:evaluate_for(Color, Pos2, Score), _, Score = 0)
    ; Score = 0 ).