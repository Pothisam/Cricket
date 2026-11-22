import '../models/ball_event.dart';
import '../models/cricket_match.dart';
import '../models/innings.dart';

/// Pure cricket rules: strike rotation, over changes, innings / match end.
class ScoringEngine {
  static Innings startInnings(CricketMatch m, String battingTeamId) {
    final inn = Innings(
      battingTeamId: battingTeamId,
      bowlingTeamId: m.otherTeam(battingTeamId),
    );
    m.innings.add(inn);
    return inn;
  }

  static int maxWickets(CricketMatch m, Innings inn) =>
      (m.squad(inn.battingTeamId).length - 1).clamp(1, 10);

  /// True when openers / bowler / new batter must be chosen before scoring.
  static bool needsBatter(CricketMatch m, Innings inn) =>
      !inn.completed &&
      (inn.strikerId == null || inn.nonStrikerId == null) &&
      inn.wickets < maxWickets(m, inn);

  static bool needsBowler(Innings inn) =>
      !inn.completed && inn.bowlerId == null;

  static bool canScore(CricketMatch m, Innings inn) =>
      m.isLive && !inn.completed && !needsBatter(m, inn) && !needsBowler(inn);

  /// Records a delivery and updates strike / bowler state.
  static void applyBall(Innings inn, BallEvent b) {
    inn.balls.add(b);
    var s = inn.strikerId;
    var n = inn.nonStrikerId;
    if (b.runsRan.isOdd) {
      final t = s;
      s = n;
      n = t;
    }
    if (b.isWicket) {
      if (s == b.outPlayerId) {
        s = null;
      } else if (n == b.outPlayerId) {
        n = null;
      }
    }
    if (b.isLegal && inn.legalBalls % 6 == 0) {
      final t = s;
      s = n;
      n = t;
      inn.bowlerId = null;
    }
    inn.strikerId = s;
    inn.nonStrikerId = n;
  }

  /// Removes the last delivery and restores the crease state. Returns false if nothing to undo.
  static bool undo(Innings inn) {
    if (inn.balls.isEmpty) return false;
    final b = inn.balls.removeLast();
    inn.strikerId = b.strikerId;
    inn.nonStrikerId = b.nonStrikerId;
    inn.bowlerId = b.bowlerId;
    inn.completed = false;
    return true;
  }

  static void swapStrike(Innings inn) {
    final t = inn.strikerId;
    inn.strikerId = inn.nonStrikerId;
    inn.nonStrikerId = t;
  }

  static bool isInningsOver(CricketMatch m, Innings inn) {
    if (inn.legalBalls >= m.overs * 6) return true;
    if (inn.wickets >= maxWickets(m, inn)) return true;
    final isChase = m.innings.length >= 2 && identical(inn, m.innings[1]);
    return isChase && inn.runs >= m.target!;
  }

  /// Marks the innings (and the match, after the 2nd innings) as finished.
  static void completeInnings(CricketMatch m, Innings inn) {
    inn.completed = true;
    if (m.innings.length >= 2 && identical(inn, m.innings[1])) {
      _setResult(m);
    }
  }

  static void _setResult(CricketMatch m) {
    final first = m.innings[0];
    final second = m.innings[1];
    m.status = MatchStatus.completed;
    if (second.runs >= m.target!) {
      final left = maxWickets(m, second) - second.wickets;
      m.winnerId = second.battingTeamId;
      m.resultText =
          '${m.teamName(second.battingTeamId)} won by $left wicket${left == 1 ? '' : 's'}';
    } else if (second.runs == first.runs) {
      m.winnerId = null;
      m.resultText = 'Match tied';
    } else {
      final by = first.runs - second.runs;
      m.winnerId = first.battingTeamId;
      m.resultText =
          '${m.teamName(first.battingTeamId)} won by $by run${by == 1 ? '' : 's'}';
    }
  }

  /// Ends the match early using the current position (or abandons if nothing was played).
  static void endMatchNow(CricketMatch m) {
    for (final i in m.innings) {
      i.completed = true;
    }
    if (m.innings.length >= 2 && m.innings[1].balls.isNotEmpty) {
      _setResult(m);
    } else {
      m.status = MatchStatus.abandoned;
      m.winnerId = null;
      m.resultText = 'Match abandoned';
    }
  }
}
