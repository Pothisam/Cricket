import 'dart:ui' as ui;

import 'package:cricket/domain/replay_engine.dart';
import 'package:cricket/domain/scoring_engine.dart';
import 'package:cricket/models/ball_event.dart';
import 'package:cricket/models/cricket_match.dart';
import 'package:cricket/ui/widgets/replay_scene.dart';
import 'package:flutter_test/flutter_test.dart';

CricketMatch _match() {
  final a = ['a1', 'a2', 'a3'], b = ['b1', 'b2', 'b3'];
  return CricketMatch(
    id: 'm',
    teamAId: 'A',
    teamBId: 'B',
    teamAName: 'A',
    teamBName: 'B',
    teamAShort: 'A',
    teamBShort: 'B',
    overs: 5,
    tossWinnerId: 'A',
    electedToBat: true,
    teamAPlayers: a,
    teamBPlayers: b,
    playerNames: {for (final i in [...a, ...b]) i: i},
    date: DateTime(2026),
  );
}

BallEvent _ball({int runs = 0, ExtraType extra = ExtraType.none, int extraRuns = 0, WicketType? wicket, ShotDirection? dir}) => BallEvent(
      strikerId: 'a1',
      nonStrikerId: 'a2',
      bowlerId: 'b1',
      runs: runs,
      extra: extra,
      extraRuns: extraRuns,
      wicket: wicket,
      outPlayerId: wicket == null ? null : 'a1',
      shotDirection: dir,
      fielderId: wicket == WicketType.caught ? 'b2' : null,
    );

void main() {
  test('the number of runs run and the clip length follow the scorecard', () {
    expect(replayRunsRun(_ball(runs: 1, dir: ShotDirection.cover)), 1);
    expect(replayRunsRun(_ball(runs: 2, dir: ShotDirection.cover)), 2);
    expect(replayRunsRun(_ball(runs: 3, dir: ShotDirection.cover)), 3);
    expect(replayRunsRun(_ball(runs: 4, dir: ShotDirection.cover)), 0); // a boundary is not run
    expect(replayRunsRun(_ball(extra: ExtraType.wide, extraRuns: 3)), 2); // 1 penalty + 2 run
    expect(replayRunsRun(_ball(extra: ExtraType.bye, extraRuns: 2)), 2);
    expect(replayRunsRun(_ball(wicket: WicketType.runOut, runs: 1)), 2); // one completed + the one he fell short of
    // More runs take longer, at the real pace of about 2.9 s per run.
    final one = replayClipSeconds(_ball(runs: 1, dir: ShotDirection.cover));
    final three = replayClipSeconds(_ball(runs: 3, dir: ShotDirection.cover));
    expect(three - one, closeTo(2 * 2.9, 0.01));
    expect(replayClipSeconds(_ball(wicket: WicketType.bowled)), greaterThan(replayClipSeconds(_ball())));
  });

  test('every outcome plays through its whole clip without errors', () {
    final m = _match();
    final inn = ScoringEngine.startInnings(m, 'A')
      ..strikerId = 'a1'
      ..nonStrikerId = 'a2'
      ..bowlerId = 'b1';
    final balls = [
      _ball(),
      _ball(runs: 1, dir: ShotDirection.midOn),
      _ball(runs: 2, dir: ShotDirection.cover),
      _ball(runs: 3, dir: ShotDirection.point),
      _ball(runs: 4, dir: ShotDirection.cover),
      _ball(runs: 6, dir: ShotDirection.midWicket),
      _ball(extra: ExtraType.wide, extraRuns: 1),
      _ball(extra: ExtraType.noBall, extraRuns: 1, runs: 2, dir: ShotDirection.straight),
      _ball(extra: ExtraType.bye, extraRuns: 1),
      _ball(extra: ExtraType.legBye, extraRuns: 4),
      _ball(wicket: WicketType.bowled),
      _ball(wicket: WicketType.lbw),
      _ball(wicket: WicketType.caught, dir: ShotDirection.midOff),
      _ball(wicket: WicketType.stumped),
      _ball(wicket: WicketType.runOut, runs: 1, dir: ShotDirection.point),
      _ball(wicket: WicketType.hitWicket),
    ];
    for (final b in balls) {
      inn.balls.add(b);
    }
    final engine = ReplayEngine(m);
    expect(engine.steps.length, balls.length);
    for (final step in engine.steps) {
      final clip = replayClipSeconds(step.ball);
      for (var i = 0; i <= 24; i++) {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        ReplayFieldPainter(
          step: step,
          t: i / 24,
          strikerName: 'S',
          nonStrikerName: 'N',
          bowlerName: 'B',
          fielderName: 'F',
          clipSeconds: clip,
        ).paint(canvas, const ui.Size(400, 300));
        recorder.endRecording().dispose();
      }
    }
  });
}
