:- module(xboard, [run/0]).

:- use_module(library(readutil)).
:- use_module(engine_state).
:- use_module(movebook).

run :-
    set_prolog_flag(double_quotes, string),
    engine_state:reset_state,
    log_line(started),
    catch(loop, E, (log_line(fatal(E)), halt(1))).

loop :-
    read_line_to_string(user_input, Raw),
    ( Raw == end_of_file ->
        log_line(eof),
        true
    ; normalize_space(string(Line), Raw),
      log_line(in(Line)),
      catch(handle(Line), E, log_line(exception(handle(Line), E))),
      loop
    ).

% ---------- Logging to TEMP\prolog_engine_logs ----------
log_dir(Dir) :-
    ( getenv('TEMP', T) ; getenv('TMP', T) ; T = 'C:/Codding/prolog' ),
    format(string(Dir), "~w/prolog_engine_logs", [T]),
    catch(make_directory_path(Dir), _, true).

log_file(File) :-
    log_dir(Dir),
    current_prolog_flag(pid, PID),
    format(string(File), "~w/engine_~w.log", [Dir, PID]).

log_line(Term) :-
    catch(
        ( log_file(File),
          setup_call_cleanup(
              open(File, append, S, [encoding(utf8)]),
              ( format(S, "~q.~n", [Term]),
                flush_output(S)
              ),
              close(S)
          )
        ),
        _,
        true
    ).

% ---------- Command handling ----------
handle("") :- !.
handle("quit") :- !, log_line(quit), halt(0).
handle("xboard") :- !.

handle(Line) :-
    sub_string(Line, 0, _, _, "protover"), !,
    % Keep it simple and compatible
    writeln("feature usermove=1 ping=1 done=1"),
    flush_output.

handle(Line) :-
    sub_string(Line, 0, _, _, "ping "), !,
    sub_string(Line, 5, _, 0, N),
    format("pong ~w~n", [N]),
    flush_output.

handle("new") :- !,
    engine_state:reset_state,
    log_line(state(reset)).

handle("random") :- !.
handle("force")  :- !, engine_state:set_mode(force), log_line(mode(force)).
handle("easy")   :- !.
handle("hard")   :- !.
handle("post")   :- !.
handle("nopost") :- !.
handle("computer") :- !.

handle("go") :- !,
    engine_state:set_mode(play),
    log_line(mode(play)),
    maybe_play.

handle("white") :- !,
    engine_state:set_my_color(white),
    engine_state:set_mode(play),
    log_line(my_color(white)),
    maybe_play.

handle("black") :- !,
    engine_state:set_my_color(black),
    engine_state:set_mode(play),
    log_line(my_color(black)),
    maybe_play.

% moves: accept "e2e4", "usermove e2e4", "move e2e4"
handle(Line) :-
    parse_move_line(Line, Move), !,
    on_move_received(Move).

handle(_) :- !.

% ---------- Move parsing ----------
parse_move_line(Line, Move) :-
    ( sub_string(Line, 0, _, _, "usermove ") ->
        sub_string(Line, 9, _, 0, Move0),
        normalize_space(string(Move), Move0)
    ; sub_string(Line, 0, _, _, "move ") ->
        sub_string(Line, 5, _, 0, Move0),
        normalize_space(string(Move), Move0)
    ; Move = Line
    ),
    looks_like_move(Move).

looks_like_move(S) :-
    string_chars(S, Cs),
    ( Cs = [F1,R1,F2,R2]
    ; Cs = [F1,R1,F2,R2,_Promo]
    ),
    member(F1, ['a','b','c','d','e','f','g','h']),
    member(R1, ['1','2','3','4','5','6','7','8']),
    member(F2, ['a','b','c','d','e','f','g','h']),
    member(R2, ['1','2','3','4','5','6','7','8']).

% ---------- Game flow ----------
on_move_received(Move) :-
    engine_state:side_to_move(JustMoved),
    log_line(got_move(JustMoved, Move)),
    engine_state:note_played(JustMoved, Move),
    engine_state:apply_move(Move),
    engine_state:toggle_side_to_move,
    maybe_play.

maybe_play :-
    catch(maybe_play_core, E, log_line(exception(maybe_play, E))).

maybe_play_core :-
    engine_state:mode(play),
    engine_state:my_color(Me),
    engine_state:side_to_move(Me), !,
    movebook:choose_move(Me, Move),
    log_line(out(Me, Move)),
    ( Move == resign ->
        writeln("resign"),
        flush_output
    ; format("move ~w~n", [Move]),
      flush_output,
      engine_state:note_played(Me, Move),
      engine_state:apply_move(Move),
      engine_state:toggle_side_to_move
    ).
maybe_play_core.
