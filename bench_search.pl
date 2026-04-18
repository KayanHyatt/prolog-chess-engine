:- use_module(position).
:- use_module(movegen).
:- use_module(fen).
:- use_module(eval).
:- use_module(search).
:- use_module(library(lists)).

run :-
    format("~n=== SEARCH DEPTH-TIME PROFILE ===~n~n"),
    format("Starting position:~n"),
    fen:startpos_fen(SF),
    do_search(SF, 500),
    do_search(SF, 1000),
    do_search(SF, 2000),
    do_search(SF, 5000),
    do_search(SF, 10000),
    do_search(SF, 30000),
    format("~nKiwipete:~n"),
    K = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    do_search(K, 500),
    do_search(K, 1000),
    do_search(K, 2000),
    do_search(K, 5000),
    do_search(K, 10000),
    do_search(K, 30000).

do_search(FenStr, TimeMs) :-
    fen:fen_to_pos(FenStr, Pos0),
    position:clone_position(Pos0, Pos),
    position:side_to_move(Pos, STM),
    search:reset_tables,
    get_time(T0),
    ( catch(
        search:best_move_timed(Pos, STM, 20, TimeMs, Move, Score),
        _, (Move = timeout, Score = 0)
      )
    -> true
    ;  Move = none, Score = 0
    ),
    get_time(T1),
    Dt is T1 - T0,
    ( catch(search:node_counter(NC), _, fail) -> Nodes = NC ; Nodes = unknown ),
    ( number(Nodes), Dt > 0.001 -> NPS is round(Nodes / Dt) ; NPS = '-' ),
    TimeSec is TimeMs / 1000.0,
    format("  ~1fs: move=~w score=~wcp nodes=~w NPS=~w wall=~3fs~n",
        [TimeSec, Move, Score, Nodes, NPS, Dt]).