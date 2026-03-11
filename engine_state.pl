:- module(engine_state, [
    reset_state/0,

    set_mode/1, mode/1,
    set_my_color/1, my_color/1,
    set_side_to_move/1, side_to_move/1,

    note_played/2, played/2,
    clear_played/0,

    get_position/1, set_position/1,
    apply_move/1,           % apply_move(+MoveStr)  (fails if invalid)
    undo/0,                 % undo one half-move (if possible)
    remove/0,               % undo two half-moves (if possible)

    repetition_count/2,
    recent_position/2      % repetition_count(+Pos, -Count)
]).

:- use_module(position).
:- use_module(fen).

:- dynamic mode/1.
:- dynamic my_color/1.
:- dynamic played/2.
:- dynamic position/1.
:- dynamic history/1.

reset_state :-
    retractall(mode(_)),
    retractall(my_color(_)),
    retractall(played(_,_)),
    retractall(position(_)),
    retractall(history(_)),
    % Default after "new": engine is Black; initial position is White to move.
    asserta(my_color(black)),
    asserta(mode(play)),
    % Use fen_to_pos instead of initial_position because setarg modifications
    % to the board term don't survive SWI-Prolog's assert/copy.
    % fen_to_pos builds the position identically but its result survives assert.
    fen:fen_to_pos("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", P),
    asserta(position(P)),
    asserta(history([P])).

set_mode(M) :- retractall(mode(_)), asserta(mode(M)).
set_my_color(C) :- retractall(my_color(_)), asserta(my_color(C)).
% side_to_move is stored in the position; these are compatibility helpers.
side_to_move(S) :-
    get_position(P),
    position:side_to_move(P, S).

set_side_to_move(S) :-
    get_position(P0),
    position:clone_position(P0, P2),
    setarg(3, P2, S),
    set_position(P2).

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
% Undo one half-move if possible.
undo :-
    ( retract(history([_Cur, Prev | Rest]))
    -> set_position_keep_history(Prev, [Prev|Rest]),
       true
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
    position:repetition_key(Pos, K),
    ( history(H) -> true ; H = [] ),
    findall(1,
        ( member(P, H),
          position:repetition_key(P, K2),
          K2 == K ),
        Ones),
    length(Ones, Count).

% recent_position(+Pos, +Window)
% True if Pos appears within the last Window positions (excluding current head).
recent_position(Pos, Window) :-
    position:repetition_key(Pos, K),
    ( history([_Cur|Rest]) -> true ; Rest = [] ),
    take(Rest, Window, Recent),
    member(P2, Recent),
    position:repetition_key(P2, K2),
    K2 == K.

take(_List, 0, []) :- !.
take([], _N, []).
take([X|Xs], N, [X|Ys]) :-
    N > 0, N1 is N-1, take(Xs, N1, Ys).