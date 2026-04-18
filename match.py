"""
Automated match: Prolog Chess Engine vs GNU Chess
Plays N games, alternating colours, and reports results.

Usage:
    python match.py --gnuchess "C:\path\to\gnuchess.exe" --prolog "C:\path\to\project" --games 6 --time 10

Requirements: Python 3.7+, SWI-Prolog and GNU Chess installed.
"""

import subprocess
import sys
import time
import argparse
import re
import os


def start_gnuchess(gnuchess_path):
    """Start GNU Chess in UCI mode."""
    proc = subprocess.Popen(
        [gnuchess_path, "--uci"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1
    )
    # Send 'uci' and wait for 'uciok'
    proc.stdin.write("uci\n")
    proc.stdin.flush()
    while True:
        line = proc.stdout.readline().strip()
        if line == "uciok":
            break
    proc.stdin.write("isready\n")
    proc.stdin.flush()
    while True:
        line = proc.stdout.readline().strip()
        if line == "readyok":
            break
    return proc


def gnuchess_move(proc, moves_uci, time_ms):
    """Get a move from GNU Chess given the move history."""
    if moves_uci:
        pos_cmd = f"position startpos moves {' '.join(moves_uci)}\n"
    else:
        pos_cmd = "position startpos\n"
    proc.stdin.write(pos_cmd)
    proc.stdin.flush()
    proc.stdin.write(f"go movetime {time_ms}\n")
    proc.stdin.flush()

    best_move = None
    while True:
        line = proc.stdout.readline().strip()
        if line.startswith("bestmove"):
            best_move = line.split()[1]
            break
    return best_move


def gnuchess_newgame(proc):
    """Reset GNU Chess for a new game."""
    proc.stdin.write("ucinewgame\n")
    proc.stdin.flush()
    proc.stdin.write("isready\n")
    proc.stdin.flush()
    while True:
        line = proc.stdout.readline().strip()
        if line == "readyok":
            break


def prolog_move(prolog_dir, moves_uci, time_ms):
    """Get a move from the Prolog engine by constructing FEN from move list."""
    # We'll use a helper that applies moves from startpos and searches
    helper = os.path.join(prolog_dir, "_match_helper.pl")

    # Build the move list as a Prolog list
    if moves_uci:
        move_list = "[" + ",".join(f'"{m}"' for m in moves_uci) + "]"
    else:
        move_list = "[]"

    # Write a temporary helper script each time
    helper_code = f""":- use_module(position).
:- use_module(movegen).
:- use_module(fen).
:- use_module(eval).
:- use_module(search).
:- use_module(engine_state).

run :-
    engine_state:reset_state,
    Moves = {move_list},
    apply_moves(Moves),
    engine_state:get_position(Pos),
    position:side_to_move(Pos, STM),
    position:clone_position(Pos, PosC),
    search:reset_tables,
    TimeMs = {time_ms},
    ( catch(
        search:best_move_timed(PosC, STM, 20, TimeMs, Move, Score),
        _, (Move = none, Score = 0)
      )
    -> true
    ;  Move = none, Score = 0
    ),
    format("BESTMOVE ~w SCORE ~w~n", [Move, Score]).

apply_moves([]).
apply_moves([M|Rest]) :-
    engine_state:apply_move(M),
    apply_moves(Rest).
"""
    with open(helper, "w") as f:
        f.write(helper_code)

    try:
        result = subprocess.run(
            ["swipl", "-q", "-f", "none", "--stack_limit=2G",
             "-s", "_match_helper.pl", "-g", "run", "-t", "halt"],
            capture_output=True, text=True, timeout=time_ms // 1000 + 30,
            cwd=prolog_dir
        )
        output = result.stdout
        # Parse BESTMOVE from output
        for line in output.split("\n"):
            if line.startswith("BESTMOVE"):
                parts = line.split()
                move = parts[1]
                score = int(parts[3]) if len(parts) > 3 else 0
                return move, score
        # If we get here, something went wrong
        print(f"  [PROLOG ERROR] stdout: {output[:200]}")
        print(f"  [PROLOG ERROR] stderr: {result.stderr[:200]}")
        return None, 0
    except subprocess.TimeoutExpired:
        print("  [PROLOG TIMEOUT]")
        return None, 0
    finally:
        if os.path.exists(helper):
            os.remove(helper)


def is_game_over(moves_uci, gnuchess_proc):
    """Check if game is over by asking GNU Chess to search — if bestmove is (none), game is over."""
    # We can't easily detect this without a full rules engine.
    # Instead, we'll cap at 200 plies and check for obvious conditions.
    if len(moves_uci) >= 200:
        return True, "max moves"
    return False, ""


def play_game(gnuchess_path, prolog_dir, game_num, prolog_is_white, time_ms):
    """Play one game. Returns (result_for_prolog, num_moves, pgn_moves)."""
    print(f"\n--- Game {game_num}: Prolog={'White' if prolog_is_white else 'Black'} ---")

    gnuchess_proc = start_gnuchess(gnuchess_path)
    gnuchess_newgame(gnuchess_proc)

    moves_uci = []
    pgn_moves = []
    move_num = 1
    ply = 0
    max_ply = 200

    try:
        while ply < max_ply:
            is_white_turn = (ply % 2 == 0)
            is_prolog_turn = (is_white_turn == prolog_is_white)
            color_name = "White" if is_white_turn else "Black"
            engine_name = "Prolog" if is_prolog_turn else "GNUChess"

            if is_prolog_turn:
                move, score = prolog_move(prolog_dir, moves_uci, time_ms)
                if move is None or move == "none":
                    # Prolog couldn't find a move — likely checkmate or stalemate
                    if score <= -900000:
                        result = "gnuchess_wins"
                    else:
                        result = "draw"
                    print(f"  {engine_name} ({color_name}) has no move. Result: {result}")
                    break
                extra = f" (score={score})"
            else:
                move = gnuchess_move(gnuchess_proc, moves_uci, time_ms)
                if move is None or move == "(none)":
                    result = "prolog_wins"
                    print(f"  GNUChess ({color_name}) has no move. Prolog wins!")
                    break
                score = None
                extra = ""

            # Check for mate scores
            if score is not None and abs(score) >= 999000:
                pass  # let the game continue, mate will be found next ply

            moves_uci.append(move)

            if is_white_turn:
                print(f"  {move_num}. {move}{extra}", end="")
                pgn_moves.append(f"{move_num}. {move}")
            else:
                print(f" {move}{extra}")
                pgn_moves.append(move)
                move_num += 1

            ply += 1

            # Simple draw detection: if last 12 moves repeat
            if len(moves_uci) >= 12:
                last4 = moves_uci[-4:]
                prev4 = moves_uci[-8:-4]
                prev8 = moves_uci[-12:-8]
                if last4 == prev4 == prev8:
                    result = "draw"
                    print(f"\n  Draw by repetition detected.")
                    break
        else:
            result = "draw"
            print(f"\n  Draw: max ply reached.")

    except Exception as e:
        print(f"\n  Error: {e}")
        result = "draw"
    finally:
        gnuchess_proc.stdin.write("quit\n")
        gnuchess_proc.stdin.flush()
        gnuchess_proc.terminate()

    return result, ply, pgn_moves


def main():
    parser = argparse.ArgumentParser(description="Prolog Engine vs GNU Chess match")
    parser.add_argument("--gnuchess", required=True, help="Path to gnuchess.exe")
    parser.add_argument("--prolog", required=True, help="Path to prolog chess engine directory")
    parser.add_argument("--games", type=int, default=6, help="Number of games (default: 6)")
    parser.add_argument("--time", type=int, default=10, help="Seconds per move (default: 10)")
    args = parser.parse_args()

    time_ms = args.time * 1000
    results = {"prolog_wins": 0, "gnuchess_wins": 0, "draw": 0}

    print(f"=== PROLOG ENGINE vs GNU CHESS ===")
    print(f"Games: {args.games}, Time/move: {args.time}s")
    print(f"GNU Chess: {args.gnuchess}")
    print(f"Prolog dir: {args.prolog}")

    for i in range(1, args.games + 1):
        prolog_is_white = (i % 2 == 1)  # alternate colours
        result, ply, pgn = play_game(
            args.gnuchess, args.prolog, i, prolog_is_white, time_ms
        )

        if result not in results:
            result = "draw"
        results[result] += 1

        result_str = {"prolog_wins": "1-0" if prolog_is_white else "0-1",
                      "gnuchess_wins": "0-1" if prolog_is_white else "1-0",
                      "draw": "1/2-1/2"}[result]
        print(f"  Result: {result_str} ({result}) in {ply} plies\n")

    print(f"\n=== MATCH RESULT ===")
    print(f"Prolog wins: {results['prolog_wins']}")
    print(f"GNU Chess wins: {results['gnuchess_wins']}")
    print(f"Draws: {results['draw']}")
    total = args.games
    prolog_score = results['prolog_wins'] + results['draw'] * 0.5
    gnu_score = results['gnuchess_wins'] + results['draw'] * 0.5
    print(f"Score: Prolog {prolog_score} - {gnu_score} GNU Chess")


if __name__ == "__main__":
    main()