# Prolog Chess Engine (WinBoard/XBoard)

A chess engine written in SWI-Prolog that speaks the WinBoard/XBoard protocol.

## Run
Edit `run_engine.bat` to point to your SWI-Prolog install and project path, then run:
- `run_engine.bat`

## Protocol
Supports:
- `xboard`, `protover 2`
- `usermove ...`
- `ping/pong`
- `new`, `go`, `force`, `white`, `black`, `quit`

## Logging
Writes logs to:
%TEMP%\prolog_engine_logs\engine_<pid>.log

## Files
- `xboard.pl` protocol loop
- `engine_state.pl` dynamic engine state
- `position.pl` board representation + apply move
- `movegen.pl` legal move generation
- `eval.pl` evaluation
- `search.pl` alpha-beta
- `movebook.pl` move selection
