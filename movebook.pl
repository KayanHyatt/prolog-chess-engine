:- module(movebook, [choose_move/2]).

:- use_module(library(lists)).
:- use_module(library(random)).
:- use_module(engine_state).
:- use_module(position).
:- use_module(movegen).
:- use_module(eval).

% If search.pl is present, we’ll use it.
:- ( catch(use_module(search), _, fail) -> true ; true ).

% choose_move(+Color, -Move)
% Move is UCI string (e2e4 / e7e8q) or the atom resign.
choose_move(Color, Move) :-
    engine_state:get_position(Pos),
    findall(M, movegen:legal_move(Pos, Color, M), Ms0),
    sort(Ms0, Ms),                % remove dups
    (   Ms == []
    ->  Move = resign
    ;   (   can_search
        ->  choose_by_search(Pos, Color, Ms, Move)
        ;   choose_by_1ply(Pos, Color, Ms, Move)
        )
    ).

can_search :-
    % search:best_move/5 exists and is callable
    functor(H, best_move, 5),
    predicate_property(search:H, _), !.

choose_by_search(Pos, Color, Ms, Move) :-
    % Depth 2 is a safe default. Bump later.
    (   catch(search:best_move(Pos, Color, 2, Best, _Score), _, fail),
        Best \= none,
        member(Best, Ms)
    ->  Move = Best
    ;   % If search fails for any reason, don’t crash—fallback.
        choose_by_1ply(Pos, Color, Ms, Move)
    ).

choose_by_1ply(Pos, Color, Ms, Move) :-
    (   best_by_1ply_eval(Pos, Color, Ms, Best)
    ->  Move = Best
    ;   random_member(Move, Ms)
    ).

best_by_1ply_eval(Pos, Color, Moves, BestMove) :-
    findall(Score-M,
        ( member(M, Moves),
          score_after(Pos, Color, M, Score)
        ),
        Scored0),
    Scored0 \== [],
    keysort(Scored0, Asc),
    reverse(Asc, [_-BestMove | _]).

score_after(Pos, Color, MoveStr, Score) :-
    (   position:apply_move(Pos, MoveStr, Pos2)
    ->  catch(eval:evaluate_for(Color, Pos2, Score), _, Score = 0)
    ;   Score = 0
    ).
