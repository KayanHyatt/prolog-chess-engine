:- module(perft, [
    perft/3,
    perft_from_fen/3,
    perft_suite/0
]).

:- use_module(position).
:- use_module(movegen).
:- use_module(fen).
:- use_module(library(lists)).

/*
Perft (performance test / move-count validation).

perft(+Pos, +Depth, -Nodes)
  Nodes is the number of leaf nodes reachable by making all legal moves to the given depth.
  Depth=0 => Nodes=1.

This is intended for correctness validation, not speed.
*/

perft(Pos0, Depth, Nodes) :-
    % clone once, then use make/unmake for speed
    position:clone_position(Pos0, Pos),
    perft_mut(Pos, Depth, Nodes).

perft_mut(_Pos, 0, 1) :- !.
perft_mut(Pos, Depth, Nodes) :-
    Depth > 0,
    position:side_to_move(Pos, STM),
    D1 is Depth - 1,
    findall(N,
        ( movegen:legal_move(Pos, STM, Move),
          position:make_move(Pos, Move, Undo),
          perft_mut(Pos, D1, N),
          position:unmake_move(Pos, Undo)
        ), Ns),
    sum_list(Ns, Nodes).

perft_from_fen(FenStr, Depth, Nodes) :-
    fen:fen_to_pos(FenStr, Pos),
    perft(Pos, Depth, Nodes).

% --------- quick sanity suite ---------

% Known perft counts (widely used).
% Start position:
%  d1=20, d2=400, d3=8902, d4=197281, d5=4865609
% Kiwipete (castling + pins, etc):
%  d1=48, d2=2039, d3=97862, d4=4085603, d5=193690690

perft_suite :-
    format("~n[perft] startpos~n", []),
    fen:startpos_fen(SF),
    run_case(SF, 1, 20),
    run_case(SF, 2, 400),
    run_case(SF, 3, 8902),
    run_case(SF, 4, 197281),
    run_case(SF, 5, 4865609),

    format("~n[perft] kiwipete~n", []),
    K = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    run_case(K, 1, 48),
    run_case(K, 2, 2039),
    run_case(K, 3, 97862),
    run_case(K, 4, 4085603),
    % depth 5 is large; keep it but you can comment it out if too slow.
    run_case(K, 5, 193690690),

    format("~n[perft] suite complete~n", []).

run_case(FenStr, Depth, Expected) :-
    perft_from_fen(FenStr, Depth, Nodes),
    ( Nodes =:= Expected ->
        format("  depth ~d: ~d  (ok)~n", [Depth, Nodes])
    ;
        format("  depth ~d: ~d  (EXPECTED ~d)  **MISMATCH**~n", [Depth, Nodes, Expected]),
        fail
    ).