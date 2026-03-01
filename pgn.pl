:- module(pgn, [write_game_pgn/5]).

:- use_module(library(lists)).
:- use_module(san).
:- use_module(position).
:- use_module(movegen).

/*
write_game_pgn(+File, +StartPos, +MovesUci, +WhiteName, +BlackName)
- Writes a PGN with SAN move text.
- Result is inferred:
    - "1-0" if black checkmated
    - "0-1" if white checkmated
    - "1/2-1/2" if stalemate (no legal moves, not in check)
    - "*" otherwise (unknown / stopped early)
*/
write_game_pgn(File, StartPos, MovesUci, WhiteName, BlackName) :-
    setup_call_cleanup(
        open(File, write, S, [encoding(utf8)]),
        write_pgn_stream(S, StartPos, MovesUci, WhiteName, BlackName),
        close(S)
    ).

write_pgn_stream(S, StartPos, MovesUci, WhiteName, BlackName) :-
    result_from_final_position(StartPos, MovesUci, Result),
    get_time(Now),
    format_time(string(Date), "%Y.%m.%d", Now),

    format(S, "[Event \"Selfplay\"]~n", []),
    format(S, "[Site \"Local\"]~n", []),
    format(S, "[Date \"~w\"]~n", [Date]),
    format(S, "[Round \"-\"]~n", []),
    format(S, "[White \"~w\"]~n", [WhiteName]),
    format(S, "[Black \"~w\"]~n", [BlackName]),
    format(S, "[Result \"~w\"]~n~n", [Result]),

    moves_to_san_lines(StartPos, MovesUci, Sans),
    write_moves_wrapped(S, Sans, 1),
    format(S, " ~w~n", [Result]).

% ---- Determine result by replaying moves ----
result_from_final_position(StartPos, MovesUci, Result) :-
    replay_moves(StartPos, MovesUci, FinalPos, SideToMove),
    ( \+ movegen:legal_move(FinalPos, SideToMove, _) ->
        ( movegen:in_check(FinalPos, SideToMove) ->
            ( SideToMove == white -> Result = "0-1" ; Result = "1-0" )
        ; Result = "1/2-1/2"
        )
    ; Result = "*"
    ).

replay_moves(Pos0, MovesUci, PosF, SideToMove) :-
    replay_moves_(Pos0, white, MovesUci, PosF, SideToMove).

replay_moves_(Pos, Side, [], Pos, Side).
replay_moves_(Pos0, Side0, [M|Ms], PosF, SideF) :-
    ( position:apply_move(Pos0, M, Pos1) ->
        other_side(Side0, Side1),
        replay_moves_(Pos1, Side1, Ms, PosF, SideF)
    ;   % If something went wrong, stop and mark unknown
        PosF = Pos0,
        SideF = Side0
    ).

other_side(white, black).
other_side(black, white).

% ---- Convert UCI moves to SAN ----
moves_to_san_lines(StartPos, MovesUci, Sans) :-
    moves_to_san_(StartPos, white, MovesUci, Sans).

moves_to_san_(_Pos, _Side, [], []).
moves_to_san_(Pos0, Side0, [Uci|Rest], [San|Sans]) :-
    san:uci_to_san(Pos0, Side0, Uci, San),
    ( position:apply_move(Pos0, Uci, Pos1) -> true ; Pos1 = Pos0 ),
    other_side(Side0, Side1),
    moves_to_san_(Pos1, Side1, Rest, Sans).

% ---- PGN move text wrapping ----
write_moves_wrapped(S, Sans, MoveNo) :-
    write_moves_wrapped_(S, Sans, MoveNo, 0).

write_moves_wrapped_(_S, [], _MoveNo, _Col).
write_moves_wrapped_(S, [W|Rest], MoveNo, Col0) :-
    format(string(Token), "~w. ~w", [MoveNo, W]),
    emit_token(S, Token, Col0, Col1),
    ( Rest = [B|Rest2] ->
        emit_token(S, B, Col1, Col2),
        MoveNo2 is MoveNo + 1,
        write_moves_wrapped_(S, Rest2, MoveNo2, Col2)
    ; nl(S)
    ).

emit_token(S, Token, Col0, ColN) :-
    string_length(Token, L),
    ( Col0 =:= 0 ->
        format(S, "~w", [Token]),
        ColN is L
    ; Col0 + 1 + L > 78 ->
        format(S, "~n~w", [Token]),
        ColN is L
    ; format(S, " ~w", [Token]),
      ColN is Col0 + 1 + L
    ).