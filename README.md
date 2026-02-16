# Prolog Chess Engine (CLI Self-Play Harness)

This version runs **without WinBoard/XBoard**. It is meant for correctness + stability work.

## Requirements
- SWI-Prolog installed and on Windows typically at:
  `C:\Program Files\swipl\bin\swipl.exe`

## Run (Windows)
Double-click or run:

- `run_selfplay.bat`

## Run (any OS / terminal)
From the project folder:

```bash
swipl -q -f none -s selfplay.pl -g main -t halt
```

## What it does
- Initializes an internal position
- Repeatedly chooses a move for the side to move
- Applies it
- Prints a simple move list
- Stops on resign or after a move limit

## Files
- `engine_state.pl` - dynamic engine state + history + apply/undo
- `position.pl`      - board representation + UCI move application
- `movegen.pl`       - legal move generator + check detection
- `eval.pl`          - evaluation function (material + heuristics)
- `search.pl`        - alpha-beta search
- `movebook.pl`      - move selection (search fallback)
- `selfplay.pl`      - CLI harness (Option 2)
