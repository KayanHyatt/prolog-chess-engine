:- module(engine_state, [
    reset_state/0,

    set_mode/1, mode/1,
    set_my_color/1, my_color/1,
    set_side_to_move/1, side_to_move/1, toggle_side_to_move/0,

    note_played/2, played/2,

    get_position/1, set_position/1, apply_move/1
]).

:- use_module(position).

:- dynamic mode/1.
:- dynamic my_color/1.
:- dynamic side_to_move/1.
:- dynamic played/2.
:- dynamic position/1.

reset_state :-
    retractall(mode(_)),
    retractall(my_color(_)),
    retractall(side_to_move(_)),
    retractall(played(_,_)),
    retractall(position(_)),
    % Default after "new": engine is Black; White to move.
    asserta(my_color(black)),
    asserta(side_to_move(white)),
    asserta(mode(play)),
    position:initial_position(P),
    asserta(position(P)).

set_mode(M) :- retractall(mode(_)), asserta(mode(M)).
set_my_color(C) :- retractall(my_color(_)), asserta(my_color(C)).
set_side_to_move(S) :- retractall(side_to_move(_)), asserta(side_to_move(S)).

toggle_side_to_move :-
    ( retract(side_to_move(white)) -> asserta(side_to_move(black))
    ; retract(side_to_move(black)) -> asserta(side_to_move(white))
    ; asserta(side_to_move(white))
    ).

note_played(Color, Move) :- assertz(played(Color, Move)).

get_position(P) :- position(P), !.
get_position(P) :- position:initial_position(P).

set_position(P) :- retractall(position(_)), asserta(position(P)).

apply_move(MoveStr) :-
    get_position(P0),
    ( position:apply_move(P0, MoveStr, P1)
    -> set_position(P1)
    ;  true  % keep for now, but consider logging here
    ).

