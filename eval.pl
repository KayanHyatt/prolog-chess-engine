:- module(eval, [evaluate_for/3, evaluate_lazy/5]).

:- use_module(library(aggregate)).
:- use_module(library(lists)).
:- use_module(position).

/*
Classical tapered evaluation — all 4 phases complete.

Phase 1: Fast mobility heuristic (no movegen calls)
Phase 2: (search improvements — in search.pl)
Phase 3: Knight outposts, connected passers, rook behind passer, king safety
Phase 4: Cached phase, lazy eval export

Additional: Development bonus, castling bonus, center control,
            aggressive PSQT weights favouring central pawn play.
*/

% evaluate_for(+MeColor, +Pos, -Score)
% Full evaluation. Positive => good for MeColor.
evaluate_for(Me, Pos, Score) :-
    other_color(Me, Them),
    game_phase(Pos, Phase),

    material(Pos, Me, Them, Phase, Mat),
    psqt(Pos, Me, Them, Phase, Psqt),
    tempo(Pos, Me, Tempo),

    pawn_structure(Pos, Me, Them, Phase, Pawns),
    bishop_pair(Pos, Me, Them, BP),
    rook_activity(Pos, Me, Them, Phase, RA),
    mobility_space(Pos, Me, Them, Phase, Mob),
    king_safety(Pos, Me, Them, Phase, KS),
    endgame_scaling(Pos, Me, Them, Phase, EG),
    knight_outposts(Pos, Me, Them, Phase, NO),
    development(Pos, Me, Them, Phase, Dev),

    Score is Mat + Psqt + Tempo + Pawns + BP + RA + Mob + KS + EG + NO + Dev.

% evaluate_lazy(+MeColor, +Pos, +Alpha, +Beta, -Score)
% Lazy eval: compute cheap terms first. If the cheap score is far outside
% the [Alpha-LazyMargin, Beta+LazyMargin] window, return early.
% Otherwise compute the full eval.
evaluate_lazy(Me, Pos, Alpha, Beta, Score) :-
    other_color(Me, Them),
    game_phase(Pos, Phase),
    material(Pos, Me, Them, Phase, Mat),
    psqt(Pos, Me, Them, Phase, Psqt),
    tempo(Pos, Me, Tempo),
    Cheap is Mat + Psqt + Tempo,
    LazyMargin = 250,
    ( Cheap > Beta + LazyMargin -> Score = Cheap
    ; Cheap < Alpha - LazyMargin -> Score = Cheap
    ; % Full eval needed
      pawn_structure(Pos, Me, Them, Phase, Pawns),
      bishop_pair(Pos, Me, Them, BP),
      rook_activity(Pos, Me, Them, Phase, RA),
      mobility_space(Pos, Me, Them, Phase, Mob),
      king_safety(Pos, Me, Them, Phase, KS),
      endgame_scaling(Pos, Me, Them, Phase, EG),
      knight_outposts(Pos, Me, Them, Phase, NO),
      development(Pos, Me, Them, Phase, Dev),
      Score is Cheap + Pawns + BP + RA + Mob + KS + EG + NO + Dev
    ).

other_color(white, black).
other_color(black, white).

% --- Game phase (computed once, passed through) ---
game_phase(Pos, Phase) :-
    aggregate_all(sum(W),
        ( position:piece(Pos, _C, T, _Sq), phase_weight(T, W) ),
        Phase0),
    ( Phase0 > 24 -> Phase = 24 ; Phase0 < 0 -> Phase = 0 ; Phase = Phase0 ).

phase_weight(pawn, 0). phase_weight(king, 0).
phase_weight(knight, 1). phase_weight(bishop, 1).
phase_weight(rook, 2). phase_weight(queen, 4).

blend(Phase, Mg, Eg, Out) :-
    Out is (Mg*Phase + Eg*(24-Phase)) // 24.

% --- Material ---
piece_value_mg(pawn,100). piece_value_mg(knight,320). piece_value_mg(bishop,330).
piece_value_mg(rook,500). piece_value_mg(queen,900). piece_value_mg(king,0).
piece_value_eg(pawn,120). piece_value_eg(knight,300). piece_value_eg(bishop,320).
piece_value_eg(rook,520). piece_value_eg(queen,900). piece_value_eg(king,0).

material(Pos, Me, Them, Phase, Score) :-
    mat_one(Pos, Me, Phase, S1), mat_one(Pos, Them, Phase, S2), Score is S1-S2.

mat_one(Pos, Color, Phase, Score) :-
    aggregate_all(sum(V),
        ( position:piece(Pos, Color, T, _),
          piece_value_mg(T, Mg), piece_value_eg(T, Eg), blend(Phase, Mg, Eg, V) ),
        Score).

% --- PSQT (strongly rewards central pawns) ---
psqt(Pos, Me, Them, Phase, Score) :-
    psqt_one(Pos, Me, Phase, S1), psqt_one(Pos, Them, Phase, S2), Score is S1-S2.

psqt_one(Pos, Color, Phase, Score) :-
    aggregate_all(sum(B),
        ( position:piece(Pos, Color, T, Sq), psqt_bonus(T, Color, Sq, Phase, B) ),
        Score).

psqt_bonus(T, Color, Sq, Phase, B) :-
    psqt_lookup(T, mg, Color, Sq, Mg),
    psqt_lookup(T, eg, Color, Sq, Eg),
    blend(Phase, Mg, Eg, B).

psqt_lookup(Type, Stage, white, Sq, V) :- psqt_table(Type, Stage, L), nth0(Sq, L, V), !.
psqt_lookup(Type, Stage, black, Sq, V) :- mirror_sq(Sq, MSq), psqt_table(Type, Stage, L), nth0(MSq, L, V), !.

mirror_sq(Sq, MSq) :- File is Sq mod 8, Rank is Sq // 8, MRank is 7-Rank, MSq is MRank*8+File.

% Pawn MG: STRONGLY rewards d4/e4 center control
psqt_table(pawn, mg,
[  0,  0,  0,  0,  0,  0,  0,  0,
  -8, -4,  0,  0,  0,  0, -4, -8,
  -8,  0,  5, 15, 15,  5,  0, -8,
 -10,  0, 10, 30, 30, 10,  0,-10,
  -5,  5, 15, 35, 35, 15,  5, -5,
   5, 10, 20, 30, 30, 20, 10,  5,
  15, 20, 25, 35, 35, 25, 20, 15,
   0,  0,  0,  0,  0,  0,  0,  0]).

psqt_table(pawn, eg,
[  0,  0,  0,  0,  0,  0,  0,  0,
  15, 15, 15, 15, 15, 15, 15, 15,
  10, 10, 12, 14, 14, 12, 10, 10,
   5,  5,  8, 10, 10,  8,  5,  5,
   0,  0,  3,  5,  5,  3,  0,  0,
  -5, -5,  0,  0,  0,  0, -5, -5,
 -10,-10, -5, -5, -5, -5,-10,-10,
   0,  0,  0,  0,  0,  0,  0,  0]).

% Knight: strongly rewards central squares
psqt_table(knight, mg,
[-50,-40,-30,-30,-30,-30,-40,-50,
 -40,-15,  0,  5,  5,  0,-15,-40,
 -30,  5, 15, 20, 20, 15,  5,-30,
 -30,  5, 20, 25, 25, 20,  5,-30,
 -30,  5, 20, 25, 25, 20,  5,-30,
 -30,  5, 15, 20, 20, 15,  5,-30,
 -40,-15,  0,  5,  5,  0,-15,-40,
 -50,-40,-30,-30,-30,-30,-40,-50]).

psqt_table(knight, eg,
[-40,-30,-20,-20,-20,-20,-30,-40,
 -30,-10,  0,  5,  5,  0,-10,-30,
 -20,  0, 10, 15, 15, 10,  0,-20,
 -20,  5, 15, 20, 20, 15,  5,-20,
 -20,  5, 15, 20, 20, 15,  5,-20,
 -20,  0, 10, 15, 15, 10,  0,-20,
 -30,-10,  0,  5,  5,  0,-10,-30,
 -40,-30,-20,-20,-20,-20,-30,-40]).

% Bishop: rewards diagonals and active squares
psqt_table(bishop, mg,
[-20,-10,-10,-10,-10,-10,-10,-20,
 -10,  5,  0,  0,  0,  0,  5,-10,
 -10, 10, 10, 10, 10, 10, 10,-10,
 -10,  0, 10, 15, 15, 10,  0,-10,
 -10,  5, 10, 15, 15, 10,  5,-10,
 -10,  0, 10, 10, 10, 10,  0,-10,
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
   0,  0,  0,  0,  0,  0,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0,
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

% King MG: strongly rewards castled positions (g1/c1 area)
psqt_table(king, mg,
[ 20, 35, 10,  0,  0, 10, 35, 20,
  25, 25,  5,  0,  0,  5, 25, 25,
 -10,-20,-20,-20,-20,-20,-20,-10,
 -20,-30,-30,-40,-40,-30,-30,-20,
 -30,-40,-40,-50,-50,-40,-40,-30,
 -30,-40,-40,-50,-50,-40,-40,-30,
 -30,-40,-40,-50,-50,-40,-40,-30,
 -30,-40,-40,-50,-50,-40,-40,-30]).

psqt_table(king, eg,
[-50,-30,-30,-30,-30,-30,-30,-50,
 -30,-10,  0,  5,  5,  0,-10,-30,
 -30,  5, 15, 20, 20, 15,  5,-30,
 -30,  5, 20, 25, 25, 20,  5,-30,
 -30,  5, 20, 25, 25, 20,  5,-30,
 -30,  5, 15, 20, 20, 15,  5,-30,
 -30,-10,  0,  5,  5,  0,-10,-30,
 -50,-30,-30,-30,-30,-30,-30,-50]).

% --- Development bonus ---
% Penalize undeveloped pieces (knights/bishops on back rank) in middlegame.
% Reward castled king.
development(Pos, Me, Them, Phase, Score) :-
    dev_one(Pos, Me, Phase, S1), dev_one(Pos, Them, Phase, S2), Score is S1-S2.

dev_one(Pos, Color, Phase, Score) :-
    undeveloped_penalty(Pos, Color, UPen),
    castled_bonus(Pos, Color, CB),
    center_control(Pos, Color, CC),
    Mg is -UPen + CB + CC,
    blend(Phase, Mg, 0, Score).

% Penalty for each minor piece still on its home square
undeveloped_penalty(Pos, white, Pen) :-
    aggregate_all(sum(12),
        ( member(Sq, [1, 6, 2, 5]),  % b1, g1, c1, f1
          position:piece_at(Pos, Sq, white, T),
          member(T, [knight, bishop])
        ), Pen).
undeveloped_penalty(Pos, black, Pen) :-
    aggregate_all(sum(12),
        ( member(Sq, [57, 62, 58, 61]),  % b8, g8, c8, f8
          position:piece_at(Pos, Sq, black, T),
          member(T, [knight, bishop])
        ), Pen).

% Bonus for having castled (king on g1/c1 for white, g8/c8 for black)
castled_bonus(Pos, white, Bonus) :-
    ( position:piece(Pos, white, king, Ksq),
      (Ksq =:= 6 ; Ksq =:= 2)  % g1 or c1
    -> Bonus = 30
    ; Bonus = 0 ).
castled_bonus(Pos, black, Bonus) :-
    ( position:piece(Pos, black, king, Ksq),
      (Ksq =:= 62 ; Ksq =:= 58)  % g8 or c8
    -> Bonus = 30
    ; Bonus = 0 ).

% Bonus for pawns controlling center squares (d4/d5/e4/e5)
center_control(Pos, Color, Score) :-
    center_squares(Color, Centers),
    aggregate_all(sum(8),
        ( member(CSq, Centers),
          position:piece(Pos, Color, pawn, CSq)
        ), Score).

center_squares(white, [27, 28, 35, 36]).  % d4, e4, d5, e5
center_squares(black, [27, 28, 35, 36]).  % same squares

% --- Pawn structure ---
pawn_structure(Pos, Me, Them, Phase, Score) :-
    pawn_terms(Pos, Me, Them, Phase, S1), pawn_terms(Pos, Them, Me, Phase, S2),
    Score is S1-S2.

pawn_terms(Pos, Color, Enemy, Phase, Score) :-
    doubled_pawns(Pos, Color, D),
    isolated_pawns(Pos, Color, I),
    passed_pawns(Pos, Color, Enemy, Phase, P),
    connected_passers(Pos, Color, Enemy, Phase, CP),
    Score is P + CP - 15*D - 12*I.

file_of(Sq, F) :- F is (Sq mod 8) + 1.
rank_of(Sq, R) :- R is (Sq // 8) + 1.

pawn_count_on_file(Pos, Color, File, N) :-
    aggregate_all(count, (position:piece(Pos, Color, pawn, Sq), file_of(Sq, File)), N).

doubled_pawns(Pos, Color, Count) :-
    aggregate_all(sum(K),
        (between(1,8,F), pawn_count_on_file(Pos,Color,F,N), (N>1->K is N-1;K=0)),
        Count).

isolated_pawns(Pos, Color, Count) :-
    aggregate_all(count,
        (between(1,8,F), pawn_count_on_file(Pos,Color,F,N), N>0,
         \+ pawn_on_adj(Pos,Color,F)),
        Count).

pawn_on_adj(Pos, Color, File) :-
    (Adj is File-1, Adj>=1, pawn_count_on_file(Pos,Color,Adj,N1), N1>0) ;
    (Adj is File+1, Adj=<8, pawn_count_on_file(Pos,Color,Adj,N2), N2>0).

passed_pawns(Pos, Color, Enemy, Phase, Score) :-
    aggregate_all(sum(B),
        (position:piece(Pos,Color,pawn,Sq), file_of(Sq,F), rank_of(Sq,MyR),
         is_passed(Pos,Enemy,Color,F,MyR), passed_bonus(Color,MyR,Phase,B)),
        Score).

is_passed(Pos, Enemy, Color, F, MyR) :-
    \+ epf(Pos,Enemy,Color,F,MyR),
    FL is F-1, \+ epf(Pos,Enemy,Color,FL,MyR),
    FR is F+1, \+ epf(Pos,Enemy,Color,FR,MyR).

epf(_,_,_,File,_) :- (File<1; File>8), !, fail.
epf(Pos, Enemy, MyColor, File, MyR) :-
    position:piece(Pos, Enemy, pawn, ESq), file_of(ESq, File), rank_of(ESq, ER),
    ahead_of(MyColor, ER, MyR).

ahead_of(white, ER, MyR) :- ER > MyR.
ahead_of(black, ER, MyR) :- ER < MyR.

passed_bonus(white, R, Phase, B) :- Mg is max(0,(R-2))*14, Eg is max(0,(R-2))*25, blend(Phase,Mg,Eg,B).
passed_bonus(black, R, Phase, B) :- Mg is max(0,(7-R))*14, Eg is max(0,(7-R))*25, blend(Phase,Mg,Eg,B).

connected_passers(Pos, Color, Enemy, Phase, Score) :-
    aggregate_all(sum(B),
        (position:piece(Pos,Color,pawn,Sq1), file_of(Sq1,F1), rank_of(Sq1,R1),
         is_passed(Pos,Enemy,Color,F1,R1),
         F2 is F1+1, position:piece(Pos,Color,pawn,Sq2), file_of(Sq2,F2), rank_of(Sq2,R2),
         is_passed(Pos,Enemy,Color,F2,R2), Sq2>Sq1,
         blend(Phase, 18, 35, B)),
        Score).

% --- Bishop pair ---
bishop_pair(Pos, Me, Them, Score) :-
    bp1(Pos,Me,S1), bp1(Pos,Them,S2), Score is S1-S2.
bp1(Pos, Color, Bonus) :-
    aggregate_all(count, position:piece(Pos, Color, bishop, _), N),
    (N >= 2 -> Bonus = 40 ; Bonus = 0).

% --- Rook activity ---
rook_activity(Pos, Me, Them, Phase, Score) :-
    ra1(Pos,Me,Them,Phase,S1), ra1(Pos,Them,Me,Phase,S2), Score is S1-S2.

ra1(Pos, Color, Enemy, Phase, Score) :-
    r7th(Pos,Color,R7), rfiles(Pos,Color,Enemy,RF),
    rbp(Pos,Color,Enemy,Phase,RBP),
    Score is R7+RF+RBP.

r7th(Pos, white, Score) :- aggregate_all(sum(18), (position:piece(Pos,white,rook,Sq),rank_of(Sq,7)), Score).
r7th(Pos, black, Score) :- aggregate_all(sum(18), (position:piece(Pos,black,rook,Sq),rank_of(Sq,2)), Score).

rfiles(Pos, Color, Enemy, Score) :-
    aggregate_all(sum(B),
        (position:piece(Pos,Color,rook,Sq), file_of(Sq,F),
         pawn_count_on_file(Pos,Color,F,MyP), pawn_count_on_file(Pos,Enemy,F,EnP),
         rfb(MyP,EnP,B)),
        Score).

rfb(0,0,20) :- !. rfb(0,_,12) :- !. rfb(_,_,0).

rbp(Pos, Color, Enemy, Phase, Score) :-
    aggregate_all(sum(B),
        (position:piece(Pos,Color,rook,RSq), file_of(RSq,RF), rank_of(RSq,RR),
         position:piece(Pos,Color,pawn,PSq), file_of(PSq,RF), rank_of(PSq,PR),
         behind(Color,RR,PR), is_passed(Pos,Enemy,Color,RF,PR),
         blend(Phase,12,28,B)),
        Score).

behind(white,RR,PR) :- RR < PR.
behind(black,RR,PR) :- RR > PR.

% --- Mobility (fast heuristic) ---
mobility_space(Pos, Me, Them, Phase, Score) :-
    mob(Pos,Me,M1), mob(Pos,Them,M2),
    sp(Pos,Me,Phase,S1), sp(Pos,Them,Phase,S2),
    Score is 3*(M1-M2) + (S1-S2).

mob(Pos, Color, Score) :-
    aggregate_all(sum(V), (position:piece(Pos,Color,T,_), mw(T,V)), Score).

mw(knight,4). mw(bishop,6). mw(rook,8). mw(queen,14). mw(pawn,1). mw(king,0).

sp(Pos, Color, Phase, Score) :-
    aggregate_all(sum(B), (position:piece(Pos,Color,T,Sq), sb(T,Color,Sq,Phase,B)), Score).

sb(pawn,white,Sq,Phase,B) :- rank_of(Sq,R), R>=4, !, blend(Phase,7,0,B).
sb(pawn,black,Sq,Phase,B) :- rank_of(Sq,R), R=<5, !, blend(Phase,7,0,B).
sb(knight,white,Sq,Phase,B) :- rank_of(Sq,R), R>=4, !, blend(Phase,5,0,B).
sb(knight,black,Sq,Phase,B) :- rank_of(Sq,R), R=<5, !, blend(Phase,5,0,B).
sb(bishop,white,Sq,Phase,B) :- rank_of(Sq,R), R>=4, !, blend(Phase,4,0,B).
sb(bishop,black,Sq,Phase,B) :- rank_of(Sq,R), R=<5, !, blend(Phase,4,0,B).
sb(_,_,_,_,0).

% --- Knight outposts ---
knight_outposts(Pos, Me, Them, Phase, Score) :-
    ko(Pos,Me,Them,Phase,S1), ko(Pos,Them,Me,Phase,S2), Score is S1-S2.

ko(Pos, Color, Enemy, Phase, Score) :-
    aggregate_all(sum(B),
        (position:piece(Pos,Color,knight,Sq), file_of(Sq,F), rank_of(Sq,R),
         is_outpost(Color,R), F>=3, F=<6,
         \+ can_pawn_attack(Pos,Enemy,Sq),
         blend(Phase,22,12,B)),
        Score).

is_outpost(white, R) :- R>=4, R=<6.
is_outpost(black, R) :- R>=3, R=<5.

can_pawn_attack(Pos, Enemy, Sq) :-
    file_of(Sq,F), rank_of(Sq,R),
    (FL is F-1, FL>=1, position:piece(Pos,Enemy,pawn,PSq), file_of(PSq,FL),
     rank_of(PSq,PR), pr(Enemy,PR,R)
    ;FR is F+1, FR=<8, position:piece(Pos,Enemy,pawn,PSq), file_of(PSq,FR),
     rank_of(PSq,PR), pr(Enemy,PR,R)
    ), !.

pr(white, PR, R) :- PR < R.
pr(black, PR, R) :- PR > R.

% --- King safety ---
king_safety(Pos, Me, Them, Phase, Score) :-
    ks(Pos,Me,Them,Phase,S1), ks(Pos,Them,Me,Phase,S2), Score is S1-S2.

ks(Pos, Color, Enemy, Phase, Score) :-
    (position:piece(Pos,Color,king,Ksq) ->
        pawn_shield(Pos,Color,Ksq,Shield),
        open_files_king(Pos,Color,Enemy,Ksq,OpenPen),
        enemy_press(Pos,Enemy,Ksq,Press),
        att_count(Pos,Enemy,Ksq,NumAtt),
        ScaledPress is Press * min(4,NumAtt) // 2,
        Mg is Shield - OpenPen - ScaledPress,
        blend(Phase, Mg, 0, Score)
    ; Score = 0).

pawn_shield(Pos, white, Ksq, Score) :-
    file_of(Ksq,F), rank_of(Ksq,R), R1 is R+1,
    sc(Pos,white,F,R1,C0), F1 is F-1, sc(Pos,white,F1,R1,C1), F2 is F+1, sc(Pos,white,F2,R1,C2),
    Missing is 3-(C0+C1+C2), Score is 22*(C0+C1+C2)-28*max(0,Missing).
pawn_shield(Pos, black, Ksq, Score) :-
    file_of(Ksq,F), rank_of(Ksq,R), R1 is R-1,
    sc(Pos,black,F,R1,C0), F1 is F-1, sc(Pos,black,F1,R1,C1), F2 is F+1, sc(Pos,black,F2,R1,C2),
    Missing is 3-(C0+C1+C2), Score is 22*(C0+C1+C2)-28*max(0,Missing).

sc(_,_,F,_,0) :- (F<1;F>8), !.
sc(_,_,_,R,0) :- (R<1;R>8), !.
sc(Pos,Color,F,R,C) :- Sq is (R-1)*8+(F-1), (position:piece(Pos,Color,pawn,Sq)->C=1;C=0).

open_files_king(Pos, Color, Enemy, Ksq, Penalty) :-
    file_of(Ksq,F),
    aggregate_all(sum(P),
        (member(DF,[-1,0,1]), KF is F+DF, KF>=1, KF=<8,
         pawn_count_on_file(Pos,Color,KF,MyP), pawn_count_on_file(Pos,Enemy,KF,EnP),
         (MyP=:=0,EnP=:=0->P=22 ; MyP=:=0->P=12 ; P=0)),
        Penalty).

enemy_press(Pos, Enemy, Ksq, Press) :-
    findall(W, (position:piece(Pos,Enemy,T,Sq), cheb_dist(Sq,Ksq,D), D=<2, pw(T,W)), Ws),
    sum_list(Ws, Press).

att_count(Pos, Enemy, Ksq, Count) :-
    aggregate_all(count,
        (position:piece(Pos,Enemy,T,Sq), T\=pawn, T\=king, cheb_dist(Sq,Ksq,D), D=<3),
        Count).

pw(pawn,2). pw(knight,7). pw(bishop,7). pw(rook,10). pw(queen,14). pw(king,0).

cheb_dist(A,B,D) :-
    file_of(A,FA), rank_of(A,RA), file_of(B,FB), rank_of(B,RB),
    DX is abs(FA-FB), DY is abs(RA-RB), D is max(DX,DY).

% --- Endgame scaling ---
endgame_scaling(Pos, Me, Them, Phase, Score) :-
    eg1(Pos,Me,EG1), eg1(Pos,Them,EG2), blend(Phase, 0, EG1-EG2, Score).

eg1(Pos, Color, Score) :-
    king_act(Pos,Color,KA), pawn_race(Pos,Color,PP), Score is KA+PP.

king_act(Pos, Color, Score) :-
    (position:piece(Pos,Color,king,Ksq) ->
        file_of(Ksq,F), rank_of(Ksq,R),
        CenterDist is abs(F-4)+abs(R-4), Score is 35-7*min(5,CenterDist)
    ; Score = 0).

pawn_race(Pos, Color, Score) :-
    aggregate_all(sum(25), (position:piece(Pos,Color,pawn,Sq), is_very_adv(Color,Sq)), Score).

is_very_adv(white, Sq) :- rank_of(Sq, R), R >= 6.
is_very_adv(black, Sq) :- rank_of(Sq, R), R =< 3.

% --- Tempo ---
tempo(Pos, Me, Score) :- (position:side_to_move(Pos, Me) -> Score = 14 ; Score = 0).