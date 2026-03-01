:- module(engine_state, [
    reset_state/0,

    set_mode/1, mode/1,
    set_my_color/1, my_color/1,
    set_side_to_move/1, side_to_move/1, toggle_side_to_move/0,

    note_played/2, played/2,
    clear_played/0,

    get_position/1, set_position/1,
    apply_move/1,           % apply_move(+MoveStr)  (fails if invalid)
    undo/0,                 % undo one half-move (if possible)
    remove/0,               % undo two half-moves (if possible)

    repetition_count/2      % repetition_count(+Pos, -Count)
]).

:- use_module(position).

:- dynamic mode/1.
:- dynamic my_color/1.
:- dynamic side_to_move/1.
:- dynamic played/2.
:- dynamic position/1.
:- dynamic history/1.

reset_state :-
    retractall(mode(_)),
    retractall(my_color(_)),
    retractall(side_to_move(_)),
    retractall(played(_,_)),
    retractall(position(_)),
    retractall(history(_)),
    % Default after "new": engine is Black; White to move.
    asserta(my_color(black)),
    asserta(side_to_move(white)),
    asserta(mode(play)),
    position:initial_position(P),
    asserta(position(P)),
    asserta(history([P])).

set_mode(M) :- retractall(mode(_)), asserta(mode(M)).
set_my_color(C) :- retractall(my_color(_)), asserta(my_color(C)).
set_side_to_move(S) :- retractall(side_to_move(_)), asserta(side_to_move(S)).

toggle_side_to_move :-
    ( retract(side_to_move(white)) -> asserta(side_to_move(black))
    ; retract(side_to_move(black)) -> asserta(side_to_move(white))
    ; asserta(side_to_move(white))
    ).

note_played(Color, Move) :- assertz(played(Color, Move)).
clear_played :- retractall(played(_,_)).

get_position(P) :- position(P), !.
get_position(P) :- position:initial_position(P).

% set_position(+Pos)
% Replaces the current position and resets the undo history.
set_position(P) :-
    retractall(position(_)),
    retractall(history(_)),
    asserta(position(P)),
    asserta(history([P])).

% apply_move(+MoveStr)
% Applies a UCI move string to the current position.
% Succeeds if the move could be applied; fails otherwise.
apply_move(MoveStr) :-
    get_position(P0),
    position:apply_move(P0, MoveStr, P1),
    push_position(P1).

push_position(P) :-
    retractall(position(_)),
    asserta(position(P)),
    ( retract(history(H)) -> true ; H = [] ),
    asserta(history([P|H])).

% undo/0
% Undo one half-move if possible. Also toggles side_to_move.
undo :-
    ( retract(history([_Cur, Prev | Rest]))
    -> set_position_keep_history(Prev, [Prev|Rest]),
       toggle_side_to_move
    ;  true ).

% remove/0
% Undo two half-moves if possible.
remove :-
    undo,
    undo.

set_position_keep_history(P, Hist) :-
    retractall(position(_)),
    retractall(history(_)),
    asserta(position(P)),
    asserta(history(Hist)).

% repetition_count(+Pos, -Count)
% Count is how many times Pos appears in the stored history.
repetition_count(Pos, Count) :-
    ( history(H) -> true ; H = [] ),
    include(=(Pos), H, Matches),
    length(Matches, Count).