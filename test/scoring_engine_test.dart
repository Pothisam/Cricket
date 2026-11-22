import 'package:cricket/data/repositories/local_repositories.dart';
import 'package:cricket/data/sources/local_store.dart';
import 'package:cricket/domain/innings_summary.dart';
import 'package:cricket/domain/scoring_engine.dart';
import 'package:cricket/domain/stats_service.dart';
import 'package:cricket/models/ball_event.dart';
import 'package:cricket/models/cricket_match.dart';
import 'package:cricket/models/innings.dart';
import 'package:flutter_test/flutter_test.dart';

CricketMatch makeMatch({int overs = 2}) {
  final a = ['a1', 'a2', 'a3'];
  final b = ['b1', 'b2', 'b3'];
  return CricketMatch(
    id: 'm1',
    teamAId: 'A',
    teamBId: 'B',
    teamAName: 'Alpha',
    teamBName: 'Bravo',
    teamAShort: 'ALP',
    teamBShort: 'BRV',
    overs: overs,
    tossWinnerId: 'A',
    electedToBat: true,
    teamAPlayers: a,
    teamBPlayers: b,
    playerNames: {for (final id in [...a, ...b]) id: id.toUpperCase()},
    date: DateTime(2026, 1, 1),
  );
}

BallEvent ball(Innings inn, {int runs = 0, ExtraType extra = ExtraType.none, int extraRuns = 0, WicketType? wicket}) =>
    BallEvent(
      strikerId: inn.strikerId!,
      nonStrikerId: inn.nonStrikerId!,
      bowlerId: inn.bowlerId!,
      runs: runs,
      extra: extra,
      extraRuns: extraRuns,
      wicket: wicket,
      outPlayerId: wicket == null ? null : inn.strikerId,
    );

void main() {
  test('odd runs rotate strike, over end swaps and clears bowler', () {
    final m = makeMatch();
    final inn = ScoringEngine.startInnings(m, 'A')
      ..strikerId = 'a1'
      ..nonStrikerId = 'a2'
      ..bowlerId = 'b1';
    ScoringEngine.applyBall(inn, ball(inn, runs: 1));
    expect(inn.strikerId, 'a2');
    for (var i = 0; i < 5; i++) {
      ScoringEngine.applyBall(inn, ball(inn));
    }
    expect(inn.legalBalls, 6);
    expect(inn.bowlerId, isNull);
    expect(inn.strikerId, 'a1'); // swapped at over end
    expect(InningsSummary(m, inn).bowler('b1')!.maidens, 0);
  });

  test('wide does not count as a legal ball; penalty and extras tallied', () {
    final m = makeMatch();
    final inn = ScoringEngine.startInnings(m, 'A')
      ..strikerId = 'a1'
      ..nonStrikerId = 'a2'
      ..bowlerId = 'b1';
    ScoringEngine.applyBall(inn, ball(inn, extra: ExtraType.wide, extraRuns: 2));
    final s = InningsSummary(m, inn);
    expect(s.legalBalls, 0);
    expect(s.runs, 2);
    expect(s.wides, 2);
    expect(s.batter('a1')!.balls, 0);
    expect(inn.strikerId, 'a2'); // 1 run ran on the wide
  });

  test('wicket clears the slot and undo restores state', () {
    final m = makeMatch();
    final inn = ScoringEngine.startInnings(m, 'A')
      ..strikerId = 'a1'
      ..nonStrikerId = 'a2'
      ..bowlerId = 'b1';
    ScoringEngine.applyBall(inn, ball(inn, wicket: WicketType.bowled));
    expect(inn.strikerId, isNull);
    expect(ScoringEngine.needsBatter(m, inn), isTrue);
    ScoringEngine.undo(inn);
    expect(inn.strikerId, 'a1');
    expect(inn.balls, isEmpty);
  });

  test('maiden over and full match result', () {
    final m = makeMatch(overs: 1);
    final i1 = ScoringEngine.startInnings(m, 'A')
      ..strikerId = 'a1'
      ..nonStrikerId = 'a2'
      ..bowlerId = 'b1';
    for (var i = 0; i < 6; i++) {
      ScoringEngine.applyBall(i1, ball(i1, runs: i == 5 ? 6 : 0));
    }
    expect(ScoringEngine.isInningsOver(m, i1), isTrue);
    ScoringEngine.completeInnings(m, i1);

    final i2 = ScoringEngine.startInnings(m, 'B')
      ..strikerId = 'b1'
      ..nonStrikerId = 'b2'
      ..bowlerId = 'a1';
    expect(m.target, 7);
    ScoringEngine.applyBall(i2, ball(i2, runs: 6));
    expect(ScoringEngine.isInningsOver(m, i2), isFalse);
    ScoringEngine.applyBall(i2, ball(i2, runs: 1));
    expect(ScoringEngine.isInningsOver(m, i2), isTrue);
    ScoringEngine.completeInnings(m, i2);
    expect(m.status, MatchStatus.completed);
    expect(m.resultText, 'Bravo won by 2 wickets');

    final stats = CricketStats([m]);
    expect(stats.player('a1')!.runs, 6);
    expect(stats.team('B')!.won, 1);
  });

  test('match survives a JSON round trip via the local repository', () async {
    final m = makeMatch();
    final inn = ScoringEngine.startInnings(m, 'A')
      ..strikerId = 'a1'
      ..nonStrikerId = 'a2'
      ..bowlerId = 'b1';
    ScoringEngine.applyBall(inn, ball(inn, runs: 4));
    final repo = LocalMatchRepository(MemoryStore());
    await repo.save(m);
    final loaded = (await repo.getAll()).single;
    expect(loaded.innings.single.runs, 4);
    expect(loaded.playerName('a1'), 'A1');
  });
}
