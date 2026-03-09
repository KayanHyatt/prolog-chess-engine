:- module(eval, [evaluate_for/3]).

:- use_module(library(aggregate)).
:- use_module(library(lists)).
:- use_module(position).
:- use_module(movegen).

% evaluate_for(+MeColor, +Pos, -Score)
% Positive => good for MeColor.
% Classical tapered eval (middlegame/endgame blend).

evaluate_for(Me, Pos, Score) :-
    other_color(Me, Them),

    game_phase(Pos, Phase),  % 0..24

    material(Pos, Me, Them, Mat),
    psqt(Pos, Me, Them, Phase, Psqt),

    pawn_structure(Pos, Me, Them, Phase, Pawns),
    bishop_pair(Pos, Me, Them, BP),
    rook_activity(Pos, Me, Them, RA),
    mobility_space(Pos, Me, Them, Phase, Mob),
    king_safety(Pos, Me, Them, Phase, KS),
    endgame_scaling(Pos, Me, Them, Phase, EG),

    tempo(Pos, Me, Tempo),

    Score is Mat + Psqt + Pawns + BP + RA + Mob + KS + EG + Tempo.

other_color(white, black).
other_color(black, white).

% ------------------------
% Game phase (taper factor)
% ------------------------
% Common phase weights: N=1 B=1 R=2 Q=4, total 24.

game_phase(Pos, Phase) :-
    phase_weight(knight, 1),
    phase_weight(bishop, 1),
    phase_weight(rook,   2),
    phase_weight(queen,  4),
    aggregate_all(sum(W),
        ( position:piece(Pos, _C, T, _Sq),
          phase_weight(T, W)
        ),
        Phase0),
    ( Phase0 > 24 -> Phase = 24
    ; Phase0 < 0  -> Phase = 0
    ; Phase = Phase0
    ).

phase_weight(pawn,   0).
phase_weight(king,   0).
phase_weight(knight, 1).
phase_weight(bishop, 1).
phase_weight(rook,   2).
phase_weight(queen,  4).

blend(Phase, Mg, Eg, Out) :-
    % Phase=24 => pure MG, Phase=0 => pure EG
    Out is (Mg*Phase + Eg*(24-Phase)) // 24.

% ------------------------
% Material
% ------------------------

piece_value_mg(pawn,   100).
piece_value_mg(knight, 320).
piece_value_mg(bishop, 330).
piece_value_mg(rook,   500).
piece_value_mg(queen,  900).
piece_value_mg(king,     0).

piece_value_eg(pawn,   120).  % pawns slightly more valuable in EG
piece_value_eg(knight, 300).
piece_value_eg(bishop, 320).
piece_value_eg(rook,   520).
piece_value_eg(queen,  900).
piece_value_eg(king,     0).

material(Pos, Me, Them, Score) :-
    game_phase(Pos, Phase),
    material_one(Pos, Me,  Phase, S1),
    material_one(Pos, Them, Phase, S2),
    Score is S1 - S2.

material_one(Pos, Color, Phase, Score) :-
    aggregate_all(sum(V),
        ( position:piece(Pos, Color, T, _Sq),
          piece_value_mg(T, Mg),
          piece_value_eg(T, Eg),
          blend(Phase, Mg, Eg, V)
        ),
        Score).

% ------------------------
% PSQT (tapered)
% ------------------------

psqt(Pos, Me, Them, Phase, Score) :-
    psqt_one(Pos, Me,  Phase, S1),
    psqt_one(Pos, Them, Phase, S2),
    Score is S1 - S2.

psqt_one(Pos, Color, Phase, Score) :-
    aggregate_all(sum(B),
        ( position:piece(Pos, Color, T, Sq),
          psqt_bonus(T, Color, Sq, Phase, B)
        ),
        Score).

psqt_bonus(king, Color, Sq, Phase, B) :-
    psqt_lookup(king, mg, Color, Sq, Mg),
    psqt_lookup(king, eg, Color, Sq, Eg),
    blend(Phase, Mg, Eg, B).
psqt_bonus(T, Color, Sq, Phase, B) :-
    T \= king,
    psqt_lookup(T, mg, Color, Sq, Mg),
    psqt_lookup(T, eg, Color, Sq, Eg),
    blend(Phase, Mg, Eg, B).

psqt_lookup(Type, Stage, white, Sq, V) :-
    psqt_table(Type, Stage, L),
    nth0(Sq, L, V), !.
psqt_lookup(Type, Stage, black, Sq, V) :-
    mirror_sq(Sq, MSq),
    psqt_table(Type, Stage, L),
    nth0(MSq, L, V), !.

mirror_sq(Sq, MSq) :-
    File is Sq mod 8,
    Rank is Sq // 8,
    MRank is 7 - Rank,
    MSq is MRank*8 + File.

% NOTE: These are compact classical-style tables (not tuned);
% they are stage-aware and provide stable play.

psqt_table(pawn, mg,
[-10,-10,-10,-10,-10,-10,-10,-10,
  -5,  0,  0,  5,  5,  0,  0, -5,
  -5,  0, 10, 15, 15, 10,  0, -5,
  -5,  5, 10, 20, 20, 10,  5, -5,
   0,  5, 10, 25, 25, 10,  5,  0,
   5, 10, 15, 25, 25, 15, 10,  5,
  10, 15, 20, 30, 30, 20, 15, 10,
   0,  0,  0,  0,  0,  0,  0,  0]).

psqt_table(pawn, eg,
[  0,  0,  0,  0,  0,  0,  0,  0,
  10, 10, 10, 10, 10, 10, 10, 10,
   5,  5,  7,  8,  8,  7,  5,  5,
   0,  0,  3,  5,  5,  3,  0,  0,
  -5, -5,  0,  2,  2,  0, -5, -5,
 -10,-10, -5,  0,  0, -5,-10,-10,
 -15,-15,-10, -5, -5,-10,-15,-15,
 -20,-20,-15,-10,-10,-15,-20,-20]).

psqt_table(knight, mg,
[-50,-40,-30,-30,-30,-30,-40,-50,
 -40,-20,  0,  0,  0,  0,-20,-40,
 -30,  0, 10, 15, 15, 10,  0,-30,
 -30,  5, 15, 20, 20, 15,  5,-30,
 -30,  0, 15, 20, 20, 15,  0,-30,
 -30,  5, 10, 15, 15, 10,  5,-30,
 -40,-20,  0,  5,  5,  0,-20,-40,
 -50,-40,-30,-30,-30,-30,-40,-50]).

psqt_table(knight, eg,
[-40,-30,-20,-20,-20,-20,-30,-40,
 -30,-10,  0,  0,  0,  0,-10,-30,
 -20,  0, 10, 12, 12, 10,  0,-20,
 -20,  0, 12, 15, 15, 12,  0,-20,
 -20,  0, 12, 15, 15, 12,  0,-20,
 -20,  0, 10, 12, 12, 10,  0,-20,
 -30,-10,  0,  0,  0,  0,-10,-30,
 -40,-30,-20,-20,-20,-20,-30,-40]).

psqt_table(bishop, mg,
[-20,-10,-10,-10,-10,-10,-10,-20,
 -10,  0,  0,  0,  0,  0,  0,-10,
 -10,  0,  5, 10, 10,  5,  0,-10,
 -10,  5,  5, 10, 10,  5,  5,-10,
 -10,  0, 10, 10, 10, 10,  0,-10,
 -10, 10, 10, 10, 10, 10, 10,-10,
 -10,  5,  0,  0,  0,  0,  5,-10,
 -20,-10,-10,-10,-10,-10,-10,-20]).

psqt_table(bishop, eg,
[-10, -5, -5, -5, -5, -5, -5,-10,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  5,  7,  7,  5,  0, -5,
  -5,  5,  7, 10, 10,  7,  5, -5,
  -5,  0,  7, 10, 10,  7,  0, -5,
  -5,  5,  5,  7,  7,  5,  5, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
 -10, -5, -5, -5, -5, -5, -5,-10]).

psqt_table(rook, mg,
[  0,  0,  0,  5,  5,  0,  0,  0,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
   5, 10, 10, 10, 10, 10, 10,  5,
   0,  0,  0,  0,  0,  0,  0,  0]).

psqt_table(rook, eg,
[  5,  5,  5,  5,  5,  5,  5,  5,
   0,  0,  0,  0,  0,  0,  0,  0,
  -5, -5, -5, -5, -5, -5, -5, -5,
  -5, -5, -5, -5, -5, -5, -5, -5,
  -5, -5, -5, -5, -5, -5, -5, -5,
  -5, -5, -5, -5, -5, -5, -5, -5,
   0,  0,  0,  0,  0,  0,  0,  0,
   5,  5,  5,  5,  5,  5,  5,  5]).

psqt_table(queen, mg,
[-20,-10,-10, -5, -5,-10,-10,-20,
 -10,  0,  0,  0,  0,  0,  0,-10,
 -10,  0,  5,  5,  5,  5,  0,-10,
  -5,  0,  5,  5,  5,  5,  0, -5,
   0,  0,  5,  5,  5,  5,  0, -5,
 -10,  5,  5,  5,  5,  5,  0,-10,
 -10,  0,  5,  0,  0,  0,  0,-10,
 -20,-10,-10, -5, -5,-10,-10,-20]).

psqt_table(queen, eg,
[-10, -5, -5, -5, -5, -5, -5,-10,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  5,  5,  5,  5,  0, -5,
  -5,  0,  5, 10, 10,  5,  0, -5,
  -5,  0,  5, 10, 10,  5,  0, -5,
  -5,  0,  5,  5,  5,  5,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
 -10, -5, -5, -5, -5, -5, -5,-10]).

psqt_table(king, mg,
[ 20, 30, 10,  0,  0, 10, 30, 20,
  20, 20,  0,  0,  0,  0, 20, 20,
 -10,-20,-20,-20,-20,-20,-20,-10,
 -20,-30,-30,-40,-40,-30,-30,-20,
 -30,-40,-40,-50,-50,-40,-40,-30,
 -30,-40,-40,-50,-50,-40,-40,-30,
 -30,-40,-40,-50,-50,-40,-40,-30,
 -30,-40,-40,-50,-50,-40,-40,-30]).

psqt_table(king, eg,
[-50,-30,-30,-30,-30,-30,-30,-50,
 -30,-10,  0,  0,  0,  0,-10,-30,
 -30,  0, 10, 15, 15, 10,  0,-30,
 -30,  0, 15, 20, 20, 15,  0,-30,
 -30,  0, 15, 20, 20, 15,  0,-30,
 -30,  0, 10, 15, 15, 10,  0,-30,
 -30,-10,  0,  0,  0,  0,-10,-30,
 -50,-30,-30,-30,-30,-30,-30,-50]).

% ------------------------
% Pawn structure
% ------------------------

pawn_structure(Pos, Me, Them, Phase, Score) :-
    pawn_terms(Pos, Me,  Phase, S1),
    pawn_terms(Pos, Them, Phase, S2),
    Score is S1 - S2.

pawn_terms(Pos, Color, Phase, Score) :-
    doubled_pawns(Pos, Color, D),
    isolated_pawns(Pos, Color, I),
    backward_pawns(Pos, Color, B),
    passed_pawns(Pos, Color, Phase, P),
    % penalties positive for weakness
    Score is P - 12*D - 10*I - 8*B.

file_of(Sq, F) :- F is (Sq mod 8) + 1.
rank_of(Sq, R) :- R is (Sq // 8) + 1.

file(1). file(2). file(3). file(4). file(5). file(6). file(7). file(8).

pawn_count_on_file(Pos, Color, File, N) :-
    aggregate_all(count,
        ( position:piece(Pos, Color, pawn, Sq),
          file_of(Sq, File)
        ),
        N).

doubled_pawns(Pos, Color, Count) :-
    aggregate_all(sum(K),
        ( file(F),
          pawn_count_on_file(Pos, Color, F, N),
          ( N > 1 -> K is N-1 ; K = 0 )
        ),
        Count).

isolated_pawns(Pos, Color, Count) :-
    aggregate_all(count,
        ( file(F),
          pawn_count_on_file(Pos, Color, F, N), N > 0,
          \+ pawn_on_adjacent_file(Pos, Color, F)
        ),
        Count).

pawn_on_adjacent_file(Pos, Color, File) :-
    ( Adj is File-1, Adj >= 1, pawn_count_on_file(Pos, Color, Adj, N1), N1 > 0 )
    ;
    ( Adj is File+1, Adj =< 8, pawn_count_on_file(Pos, Color, Adj, N2), N2 > 0 ).

% Backward pawn (approx): pawn with no friendly pawn on adjacent files that can support it,
% and whose advance square is either blocked or controlled by enemy pawn.
backward_pawns(Pos, Color, Count) :-
    other_color(Color, Enemy),
    aggregate_all(count,
        ( position:piece(Pos, Color, pawn, Sq),
          file_of(Sq, F),
          rank_of(Sq, R),
          \+ friendly_pawn_ahead_adj(Pos, Color, F, R),
          forward_sq(Color, Sq, Fwd),
          ( occupied_sq(Pos, Fwd)
          ; enemy_pawn_attacks_square(Pos, Enemy, Fwd)
          )
        ),
        Count).

occupied_sq(Pos, Sq) :- position:piece_at(Pos, Sq, _C, _T).

friendly_pawn_ahead_adj(Pos, Color, File, Rank) :-
    ( Adj is File-1, Adj >= 1, position:piece(Pos, Color, pawn, Sq1), file_of(Sq1, Adj), rank_of(Sq1, R1), can_support(Color, R1, Rank) )
    ;
    ( Adj is File+1, Adj =< 8, position:piece(Pos, Color, pawn, Sq2), file_of(Sq2, Adj), rank_of(Sq2, R2), can_support(Color, R2, Rank) ).

can_support(white, Rp, R) :- Rp >= R.
can_support(black, Rp, R) :- Rp =< R.

forward_sq(white, Sq, Fwd) :- Fwd is Sq + 8.
forward_sq(black, Sq, Fwd) :- Fwd is Sq - 8.

enemy_pawn_attacks_square(Pos, Enemy, Target) :-
    position:piece(Pos, Enemy, pawn, Sq),
    pawn_attacks(Enemy, Sq, A),
    member(Target, A), !.

pawn_attacks(white, Sq, Attacks) :-
    file_of(Sq, F), rank_of(Sq, R),
    R1 is R+1,
    findall(T,
        ( member(DF, [-1,1]),
          F2 is F+DF, between(1,8,F2), between(1,8,R1),
          T is (R1-1)*8 + (F2-1)
        ),
        Attacks).

pawn_attacks(black, Sq, Attacks) :-
    file_of(Sq, F), rank_of(Sq, R),
    R1 is R-1,
    findall(T,
        ( member(DF, [-1,1]),
          F2 is F+DF, between(1,8,F2), between(1,8,R1),
          T is (R1-1)*8 + (F2-1)
        ),
        Attacks).

passed_pawns(Pos, Color, Phase, Score) :-
    other_color(Color, Enemy),
    aggregate_all(sum(B),
        ( position:piece(Pos, Color, pawn, Sq),
          file_of(Sq, F),
          rank_of(Sq, MyR),
          \+ enemy_pawn_in_front(Pos, Enemy, Color, F,   MyR),
          \+ enemy_pawn_in_front(Pos, Enemy, Color, F-1, MyR),
          \+ enemy_pawn_in_front(Pos, Enemy, Color, F+1, MyR),
          passed_bonus(Color, MyR, Phase, B)
        ),
        Score).

enemy_pawn_in_front(_Pos, _Enemy, _MyColor, File, _MyR) :-
    (File < 1 ; File > 8), !, fail.
enemy_pawn_in_front(Pos, Enemy, MyColor, File, MyR) :-
    position:piece(Pos, Enemy, pawn, ESq),
    file_of(ESq, File),
    rank_of(ESq, ER),
    ahead_of(MyColor, ER, MyR).

ahead_of(white, ER, MyR) :- ER > MyR.
ahead_of(black, ER, MyR) :- ER < MyR.

passed_bonus(white, R, Phase, B) :-
    Mg is max(0, (R-2))*10,
    Eg is max(0, (R-2))*18,
    blend(Phase, Mg, Eg, B).
passed_bonus(black, R, Phase, B) :-
    Mg is max(0, (7-R))*10,
    Eg is max(0, (7-R))*18,
    blend(Phase, Mg, Eg, B).

% ------------------------
% Bishop pair
% ------------------------

bishop_pair(Pos, Me, Them, Score) :-
    bishop_pair_one(Pos, Me,  S1),
    bishop_pair_one(Pos, Them, S2),
    Score is S1 - S2.

bishop_pair_one(Pos, Color, Bonus) :-
    aggregate_all(count, position:piece(Pos, Color, bishop, _), N),
    ( N >= 2 -> Bonus = 30 ; Bonus = 0 ).

% ------------------------
% Rook activity
% ------------------------

rook_activity(Pos, Me, Them, Score) :-
    rook_activity_one(Pos, Me,  S1),
    rook_activity_one(Pos, Them, S2),
    Score is S1 - S2.

rook_activity_one(Pos, Color, Score) :-
    rook_on_7th(Pos, Color, R7),
    rook_files(Pos, Color, RF),
    Score is R7 + RF.

rook_on_7th(Pos, white, Score) :-
    aggregate_all(sum(12),
        ( position:piece(Pos, white, rook, Sq), rank_of(Sq, 7) ),
        Score).
rook_on_7th(Pos, black, Score) :-
    aggregate_all(sum(12),
        ( position:piece(Pos, black, rook, Sq), rank_of(Sq, 2) ),
        Score).

rook_files(Pos, Color, Score) :-
    other_color(Color, Enemy),
    aggregate_all(sum(B),
        ( position:piece(Pos, Color, rook, Sq),
          file_of(Sq, F),
          pawn_count_on_file(Pos, Color, F, MyP),
          pawn_count_on_file(Pos, Enemy, F, EnP),
          rook_file_bonus(MyP, EnP, B)
        ),
        Score).

rook_file_bonus(0, 0, 14) :- !.  % open
rook_file_bonus(0, _ ,  7) :- !.  % semi-open
rook_file_bonus(_, _ ,  0).

% ------------------------
% Mobility + space
% ------------------------
% Keep it cheap-ish: count pseudo-legal moves (not legality filtered).
% If pseudo movegen is not exported, we fall back to legal count.

mobility_space(Pos, Me, Them, Phase, Score) :-
    mobility_one(Pos, Me,  M1),
    mobility_one(Pos, Them, M2),
    space_one(Pos, Me,  Phase, S1),
    space_one(Pos, Them, Phase, S2),
    Score is 2*(M1 - M2) + (S1 - S2).

mobility_one(Pos, Color, Count) :-
    ( current_predicate(movegen:pseudo_move/3) ->
        aggregate_all(count, movegen:pseudo_move(Pos, Color, _), Count)
    ;
        aggregate_all(count, movegen:legal_move(Pos, Color, _), Count)
    ).

% Space: bonus for pawns and minor pieces advanced into enemy half (mostly MG).
space_one(Pos, Color, Phase, Score) :-
    aggregate_all(sum(B),
        ( position:piece(Pos, Color, T, Sq),
          space_bonus(T, Color, Sq, Phase, B)
        ),
        Score).

space_bonus(pawn, white, Sq, Phase, B) :- rank_of(Sq, R), R >= 4, blend(Phase, 6, 0, B).
space_bonus(pawn, black, Sq, Phase, B) :- rank_of(Sq, R), R =< 5, blend(Phase, 6, 0, B).
space_bonus(knight, white, Sq, Phase, B) :- rank_of(Sq, R), R >= 4, blend(Phase, 4, 0, B).
space_bonus(knight, black, Sq, Phase, B) :- rank_of(Sq, R), R =< 5, blend(Phase, 4, 0, B).
space_bonus(bishop, white, Sq, Phase, B) :- rank_of(Sq, R), R >= 4, blend(Phase, 3, 0, B).
space_bonus(bishop, black, Sq, Phase, B) :- rank_of(Sq, R), R =< 5, blend(Phase, 3, 0, B).
space_bonus(_, _, _, _, 0).

% ------------------------
% King safety
% ------------------------
% Mostly MG. Includes pawn shield + open file penalty near king + nearby enemy pieces.

king_safety(Pos, Me, Them, Phase, Score) :-
    king_safety_one(Pos, Me,  Phase, S1),
    king_safety_one(Pos, Them, Phase, S2),
    Score is S1 - S2.

king_safety_one(Pos, Color, Phase, Score) :-
    ( position:piece(Pos, Color, king, Ksq) ->
        pawn_shield(Pos, Color, Ksq, Shield),
        open_file_near_king(Pos, Color, Ksq, OpenPenalty),
        enemy_pressure_near_king(Pos, Color, Ksq, Press),
        Mg is Shield - OpenPenalty - Press,
        blend(Phase, Mg, 0, Score)
    ; Score = 0 ).

pawn_shield(Pos, white, Ksq, Score) :-
    file_of(Ksq, F), rank_of(Ksq, R),
    R1 is R+1,
    shield_count(Pos, white, F, R1, C0),
    F1 is F-1, shield_count(Pos, white, F1, R1, C1),
    F2 is F+1, shield_count(Pos, white, F2, R1, C2),
    Missing is 3 - (C0 + C1 + C2),
    Score is 18*(C0+C1+C2) - 20*max(0, Missing).

pawn_shield(Pos, black, Ksq, Score) :-
    file_of(Ksq, F), rank_of(Ksq, R),
    R1 is R-1,
    shield_count(Pos, black, F, R1, C0),
    F1 is F-1, shield_count(Pos, black, F1, R1, C1),
    F2 is F+1, shield_count(Pos, black, F2, R1, C2),
    Missing is 3 - (C0 + C1 + C2),
    Score is 18*(C0+C1+C2) - 20*max(0, Missing).

shield_count(_Pos, _Color, F, _R, 0) :- (F < 1 ; F > 8), !.
shield_count(_Pos, _Color, _F, R, 0) :- (R < 1 ; R > 8), !.
shield_count(Pos, Color, F, R, C) :-
    Sq is (R-1)*8 + (F-1),
    ( position:piece(Pos, Color, pawn, Sq) -> C = 1 ; C = 0 ).

open_file_near_king(Pos, Color, Ksq, Penalty) :-
    other_color(Color, Enemy),
    file_of(Ksq, F),
    pawn_count_on_file(Pos, Color, F, MyP),
    pawn_count_on_file(Pos, Enemy, F, EnP),
    ( MyP =:= 0, EnP =:= 0 -> Penalty = 25
    ; MyP =:= 0             -> Penalty = 12
    ; Penalty = 0
    ).

enemy_pressure_near_king(Pos, Color, Ksq, Press) :-
    other_color(Color, Enemy),
    findall(W,
        ( position:piece(Pos, Enemy, T, Sq),
          cheb_dist(Sq, Ksq, D), D =< 2,
          pressure_weight(T, W)
        ),
        Ws),
    sum_list(Ws, Sum),
    Press is Sum.

pressure_weight(pawn,   2).
pressure_weight(knight, 6).
pressure_weight(bishop, 6).
pressure_weight(rook,   8).
pressure_weight(queen,  10).
pressure_weight(king,   0).

cheb_dist(A, B, D) :-
    file_of(A, FA), rank_of(A, RA),
    file_of(B, FB), rank_of(B, RB),
    DX is abs(FA-FB), DY is abs(RA-RB),
    D is max(DX, DY).

% ------------------------
% Endgame scaling
% ------------------------

endgame_scaling(Pos, Me, Them, Phase, Score) :-
    % only matters in EG, so MG component is 0
    endgame_one(Pos, Me,  EG1),
    endgame_one(Pos, Them, EG2),
    blend(Phase, 0, EG1-EG2, Score).

endgame_one(Pos, Color, Score) :-
    king_activity(Pos, Color, KA),
    passed_pawn_race_hint(Pos, Color, PP),
    Score is KA + PP.

king_activity(Pos, Color, Score) :-
    ( position:piece(Pos, Color, king, Ksq) ->
        file_of(Ksq, F), rank_of(Ksq, R),
        Dist is abs(F-4) + abs(R-4),
        Score is 25 - 5*min(5, Dist)
    ; Score = 0 ).

passed_pawn_race_hint(Pos, Color, Score) :-
    % Extra EG bonus for advanced passers already handled, but add a small kicker
    % for very advanced pawns.
    aggregate_all(sum(B),
        ( position:piece(Pos, Color, pawn, Sq),
          is_very_advanced(Color, Sq),
          B = 15
        ),
        Score).

is_very_advanced(white, Sq) :- rank_of(Sq, R), R >= 6.
is_very_advanced(black, Sq) :- rank_of(Sq, R), R =< 3.

% ------------------------
% Tempo
% ------------------------

tempo(Pos, Me, Score) :-
    ( position:side_to_move(Pos, Me) -> Score = 10 ; Score = 0 ).
