:- module(movebook, [choose_move/2]).

:- use_module(library(lists)).
:- use_module(library(random)).
:- use_module(engine_state).
:- use_module(position).
:- use_module(movegen).
:- use_module(eval).

% search is optional; if present we use it
:- ( catch(use_module(search), _, fail) -> true ; true ).

% -------- configuration --------
max_depth(4).   % increase cautiously

% choose_move(+Color, -Move)
% Move is UCI string (e2e4 / e7e8q) or the atom resign.
choose_move(Color, Move) :-
    engine_state:get_position(Pos),
    findall(M, movegen:legal_move(Pos, Color, M), Ms0),
    sort(Ms0, MsA),

    % 1) kill immediate A->B then B->A backtracks
    filter_backtracks(MsA, MsB),

    % 2) repetition avoidance: prefer moves leading to least-repeated positions
    prefer_least_repeated(Pos, MsB, Ms),

    (   Ms == []
    ->  Move = resign
    ;   (   can_search
        ->  choose_by_search(Pos, Color, Ms, Move)
        ;   choose_by_1ply(Pos, Color, Ms, Move)
        )
    ).

% ---------------------------
% Search / eval selection
% ---------------------------

can_search :-
    functor(H, best_move, 5),
    predicate_property(search:H, _), !.

choose_by_search(Pos, Color, Ms, Move) :-
    max_depth(MaxD),
    (   iterative_deepening(Pos, Color, MaxD, Best),
        Best \= none,
        member(Best, Ms)
    ->  Move = Best
    ;   choose_by_1ply(Pos, Color, Ms, Move)
    ).

iterative_deepening(Pos, Color, MaxD, BestMove) :-
    iterative_deepening_(1, MaxD, Pos, Color, none, BestMove).

iterative_deepening_(D, MaxD, _Pos, _Color, CurBest, CurBest) :-
    D > MaxD, !.
iterative_deepening_(D, MaxD, Pos, Color, CurBest, BestMove) :-
    ( catch(search:best_move(Pos, Color, D, M, _Score), _, fail),
      M \= none
    -> NextBest = M
    ;  NextBest = CurBest
    ),
    D2 is D + 1,
    iterative_deepening_(D2, MaxD, Pos, Color, NextBest, BestMove).

choose_by_1ply(Pos, Color, Ms, Move) :-
    (   best_by_1ply_eval(Pos, Color, Ms, Best)
    ->  Move = Best
    ;   random_member(Move, Ms)
    ).

best_by_1ply_eval(Pos, Color, Moves, BestMove) :-
    findall(Score-M,
        ( member(M, Moves),
          score_after(Pos, Color, M, Score)
        ),
        Scored0),
    Scored0 \== [],
    keysort(Scored0, Asc),
    reverse(Asc, [_-BestMove | _]).

score_after(Pos, Color, MoveStr, Score) :-
    (   position:apply_move(Pos, MoveStr, Pos2)
    ->  catch(eval:evaluate_for(Color, Pos2, Score), _, Score = 0)
    ;   Score = 0
    ).

% ---------------------------
% Repetition avoidance
% ---------------------------

% prefer_least_repeated(+Pos, +MovesIn, -MovesOut)
% Keeps only moves that lead to positions with the smallest repetition count in history.
% If anything fails, falls back safely to MovesIn.
prefer_least_repeated(Pos, MovesIn, MovesOut) :-
    (   MovesIn == []
    ->  MovesOut = []
    ;   findall(Cnt-M,
            ( member(M, MovesIn),
              repetition_cost(Pos, M, Cnt)
            ),
            Pairs),
        ( Pairs == [] ->
            MovesOut = MovesIn
        ; keysort(Pairs, Sorted),
          Sorted = [BestCnt-_|_],
          findall(M,
              member(BestCnt-M, Sorted),
              BestMoves),
          ( BestMoves == [] -> MovesOut = MovesIn ; MovesOut = BestMoves )
        )
    ).

% repetition_cost(+Pos, +Move, -Count)
% Count is how often the resulting position already occurred.
% Lower is better. Unknown -> treat as high.
repetition_cost(Pos, Move, Count) :-
    (   position:apply_move(Pos, Move, Pos2)
    ->  ( catch(engine_state:repetition_count(Pos2, C), _, fail)
        -> Count = C
        ;  Count = 999
        )
    ;   Count = 999
    ).

% ---------------------------
% Anti-backtrack: avoid immediate A->B then B->A
% ---------------------------

filter_backtracks(Moves, Filtered) :-
    (   catch(last_move_uci(Last), _, fail)
    ->  exclude(is_backtrack(Last), Moves, Moves2),
        ( Moves2 == [] -> Filtered = Moves ; Filtered = Moves2 )
    ;   Filtered = Moves
    ).

is_backtrack(Last, M) :-
    inverse_uci(Last, M).

last_move_uci(Last) :-
    findall(M, engine_state:played(_, M), Ms),
    Ms \= [],
    last(Ms, Last).

inverse_uci(M1, M2) :-
    uci_from_to(M1, F1, T1),
    uci_from_to(M2, F2, T2),
    F1 =:= T2,
    T1 =:= F2.

uci_from_to(Uci, From, To) :-
    string_chars(Uci, [F1,R1,F2,R2|_]),
    string_chars(SFrom, [F1,R1]),
    string_chars(STo,   [F2,R2]),
    position:sq_index(SFrom, From),
    position:sq_index(STo,   To).