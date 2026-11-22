import '../models/ball_event.dart';
import '../models/cricket_match.dart';
import '../models/innings.dart';
import 'innings_summary.dart';

/// One recorded delivery positioned inside the match, plus the scorecard state
/// before and after it. Everything is derived from the recorded ball list, so
/// a replay is always identical to the scorecard.
class ReplayStep {
  ReplayStep({
    required this.inningsIndex,
    required this.innings,
    required this.ball,
    required this.over,
    required this.ballInOver,
    required this.before,
    required this.after,
    required this.isFirstOfInnings,
    required this.isLastOfInnings,
  });

  final int inningsIndex;
  final Innings innings;
  final BallEvent ball;

  /// 1-based over number and 1-based delivery number within that over
  /// (extras count as deliveries here, so a wide shows as its own ball).
  final int over, ballInOver;
  final InningsSummary before, after;
  final bool isFirstOfInnings, isLastOfInnings;

  String get overLabel => '$over.$ballInOver';
}

class ReplayEngine {
  ReplayEngine(this.match) {
    _build();
  }

  final CricketMatch match;
  final List<ReplayStep> steps = [];

  void _build() {
    for (var i = 0; i < match.innings.length; i++) {
      final inn = match.innings[i];
      var prev = _summaryOf(inn, 0);
      var legal = 0;
      var inOver = 0;
      for (var k = 0; k < inn.balls.length; k++) {
        final b = inn.balls[k];
        inOver++;
        final over = legal ~/ 6 + 1;
        final after = _summaryOf(inn, k + 1);
        steps.add(
          ReplayStep(
            inningsIndex: i,
            innings: inn,
            ball: b,
            over: over,
            ballInOver: inOver,
            before: prev,
            after: after,
            isFirstOfInnings: k == 0,
            isLastOfInnings: k == inn.balls.length - 1,
          ),
        );
        prev = after;
        if (b.isLegal) {
          legal++;
          if (legal % 6 == 0) inOver = 0;
        }
      }
    }
  }

  InningsSummary _summaryOf(Innings inn, int count) => InningsSummary(
    match,
    Innings(
      battingTeamId: inn.battingTeamId,
      bowlingTeamId: inn.bowlingTeamId,
      balls: inn.balls.sublist(0, count),
    ),
  );

  bool get isEmpty => steps.isEmpty;

  /// Index of the first delivery of innings [i], or null.
  int? firstStepOfInnings(int i) {
    final idx = steps.indexWhere((s) => s.inningsIndex == i);
    return idx < 0 ? null : idx;
  }
}
