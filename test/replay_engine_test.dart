import 'package:cricket/domain/replay_engine.dart';
import 'package:cricket/domain/scoring_engine.dart';
import 'package:cricket/domain/shot_trajectory.dart';
import 'package:cricket/models/ball_event.dart';
import 'package:cricket/models/cricket_match.dart';
import 'package:flutter_test/flutter_test.dart';

CricketMatch _match() {
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
    overs: 2,
    tossWinnerId: 'A',
    electedToBat: true,
    teamAPlayers: a,
    teamBPlayers: b,
    playerNames: {for (final id in [...a, ...b]) id: id.toUpperCase()},
    date: DateTime(2026, 1, 1),
  );
}

void main() {
  shotTrajectoryTests();
  test('replay steps mirror the recorded balls, scores and shot directions', () {
    final m = _match();
    final inn = ScoringEngine.startInnings(m, 'A')
      ..strikerId = 'a1'
      ..nonStrikerId = 'a2'
      ..bowlerId = 'b1';
    BallEvent mk({int runs = 0, ExtraType extra = ExtraType.none, int extraRuns = 0, ShotDirection? dir}) =>
        BallEvent(
          strikerId: inn.strikerId!,
          nonStrikerId: inn.nonStrikerId!,
          bowlerId: inn.bowlerId!,
          runs: runs,
          extra: extra,
          extraRuns: extraRuns,
          shotDirection: dir,
        );
    ScoringEngine.applyBall(inn, mk(runs: 4, dir: ShotDirection.cover));
    ScoringEngine.applyBall(inn, mk(extra: ExtraType.wide, extraRuns: 1));
    ScoringEngine.applyBall(inn, mk(runs: 6, dir: ShotDirection.midOn));

    final e = ReplayEngine(m);
    expect(e.steps.length, 3);
    expect(e.steps[0].ball.outcome, BallOutcome.four);
    expect(e.steps[0].ball.shotDirection, ShotDirection.cover);
    expect(e.steps[0].before.score, '0/0');
    expect(e.steps[0].after.score, '4/0');
    expect(e.steps[1].ball.outcome, BallOutcome.wide);
    expect(e.steps[1].overLabel, '1.2'); // the wide is its own delivery
    expect(e.steps[2].after.score, '11/0');
    expect(e.steps[2].overLabel, '1.3');
    expect(e.steps[2].isLastOfInnings, isTrue);
    // Replay score always equals the scorecard.
    expect(e.steps.last.after.runs, inn.runs);
  });

  test('shot direction survives JSON and old records without it still load', () {
    final b = BallEvent(
      strikerId: 'a',
      nonStrikerId: 'b',
      bowlerId: 'c',
      runs: 4,
      shotDirection: ShotDirection.fineLeg,
    );
    expect(BallEvent.fromJson(b.toJson()).shotDirection, ShotDirection.fineLeg);
    final old = b.toJson()..remove('shotDirection');
    expect(BallEvent.fromJson(old).shotDirection, isNull);
  });
}

void shotTrajectoryTests() {
  test('drawn shot path and loft survive JSON; old records still load', () {
    final b = BallEvent(
      strikerId: 'a',
      nonStrikerId: 'b',
      bowlerId: 'c',
      runs: 4,
      shotPath: const [Offset(0, -0.17), Offset(0.3, 0.2), Offset(0.8, 0.5)],
      loft: ShotLoft.lofted,
    );
    final back = BallEvent.fromJson(b.toJson());
    expect(back.shotPath, b.shotPath);
    expect(back.loft, ShotLoft.lofted);
    final old = b.toJson()..remove('shotPath')..remove('loft');
    expect(BallEvent.fromJson(old).shotPath, isNull);
  });

  test('trajectory follows the drawn curve, bounces and extends to the rope', () {
    final t = ShotTrajectory(const [Offset(0, -0.17), Offset(0.1, 0.1), Offset(0.4, 0.3)], ShotLoft.ground);
    expect(t.points.first, ShotTrajectory.origin);
    expect(t.direction, anyOf(ShotDirection.midOff, ShotDirection.cover, ShotDirection.straight));
    final lofted = ShotTrajectory(t.points, ShotLoft.lofted);
    expect(lofted.heightAt(0.3), greaterThan(1.0)); // in the air
    expect(lofted.heightAt(ShotTrajectory(t.points, ShotLoft.lofted).bounces.first), closeTo(0, 1e-6));
    final four = t.extendedTo(0.99);
    expect(four.end.distance, greaterThanOrEqualTo(0.99));
    final six = t.extendedTo(1.14, minLoft: ShotLoft.aerial);
    expect(six.loft, ShotLoft.aerial);
  });
}
