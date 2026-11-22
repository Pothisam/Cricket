import 'package:flutter/material.dart';

import '../../domain/replay_engine.dart';
import '../../models/ball_event.dart';

/// Headline shown over the field once the recorded outcome is known.
class ReplayBanner {
  const ReplayBanner(this.text, this.color, {this.detail});
  final String text;
  final Color color;
  final String? detail;
}

ReplayBanner? bannerFor(ReplayStep s) {
  final b = s.ball;
  switch (b.outcome) {
    case BallOutcome.dot:
      return null;
    case BallOutcome.runs:
      return ReplayBanner('${b.runs} RUN${b.runs == 1 ? '' : 'S'}', Colors.teal.shade600);
    case BallOutcome.four:
      return ReplayBanner('FOUR!', Colors.blue.shade600);
    case BallOutcome.six:
      return ReplayBanner('SIX!', Colors.purple.shade600);
    case BallOutcome.wide:
      return ReplayBanner('WIDE', Colors.orange.shade700,
          detail: b.extraRuns > 1 ? '+${b.extraRuns - 1} run' : null);
    case BallOutcome.noBall:
      return ReplayBanner('NO BALL', Colors.orange.shade700,
          detail: b.runs > 0 ? '+${b.runs} off the bat' : null);
    case BallOutcome.bye:
      return ReplayBanner('${b.extraRuns} BYE${b.extraRuns == 1 ? '' : 'S'}', Colors.orange.shade700);
    case BallOutcome.legBye:
      return ReplayBanner('${b.extraRuns} LEG BYE${b.extraRuns == 1 ? '' : 'S'}', Colors.orange.shade700);
    case BallOutcome.wicket:
      final outId = b.outPlayerId ?? b.strikerId;
      final line = s.after.batter(outId);
      return ReplayBanner('WICKET! ${b.wicket!.label}', Colors.red.shade600,
          detail: line == null ? null : '${line.name} ${line.howOut}');
  }
}
