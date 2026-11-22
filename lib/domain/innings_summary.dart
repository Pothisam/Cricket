import '../models/ball_event.dart';
import '../models/cricket_match.dart';
import '../models/innings.dart';

String oversText(int legalBalls) => '${legalBalls ~/ 6}.${legalBalls % 6}';

class BatterLine {
  BatterLine(this.id, this.name);
  final String id;
  final String name;
  int runs = 0, balls = 0, fours = 0, sixes = 0;
  bool out = false;
  bool atCrease = false;
  String howOut = '';
  double get strikeRate => balls == 0 ? 0 : runs * 100 / balls;
}

class BowlerLine {
  BowlerLine(this.id, this.name);
  final String id;
  final String name;
  int balls = 0, runs = 0, wickets = 0, maidens = 0, wides = 0, noBalls = 0;
  String get overs => oversText(balls);
  double get economy => balls == 0 ? 0 : runs * 6 / balls;
}

class FallOfWicket {
  FallOfWicket(this.number, this.score, this.playerName, this.over);
  final int number, score;
  final String playerName, over;
}

class OverSummary {
  OverSummary(this.number, this.bowlerName);
  final int number;
  final String bowlerName;
  final List<BallEvent> balls = [];
  int get runs => balls.fold(0, (s, b) => s + b.totalRuns);
}

/// Everything a scorecard needs, derived purely from the ball list.
class InningsSummary {
  InningsSummary(this.match, this.innings) {
    _build();
  }

  final CricketMatch match;
  final Innings innings;

  int runs = 0, wickets = 0, legalBalls = 0;
  int wides = 0, noBalls = 0, byes = 0, legByes = 0;
  final Map<String, BatterLine> _batters = {};
  final Map<String, BowlerLine> _bowlers = {};
  final List<FallOfWicket> fow = [];
  final List<OverSummary> overs = [];

  List<BatterLine> get batters => _batters.values.toList();
  List<BowlerLine> get bowlers => _bowlers.values.toList();
  int get extras => wides + noBalls + byes + legByes;
  String get oversString => oversText(legalBalls);
  String get score => '$runs/$wickets';
  double get runRate => legalBalls == 0 ? 0 : runs * 6 / legalBalls;

  List<String> get yetToBat => match
      .squad(innings.battingTeamId)
      .where((id) => !_batters.containsKey(id))
      .toList();

  BatterLine? batter(String? id) => _batters[id];
  BowlerLine? bowler(String? id) => _bowlers[id];

  /// Balls of the over being bowled (or the one just finished).
  List<BallEvent> get currentOverBalls {
    if (legalBalls == 0 && innings.balls.isEmpty) return const [];
    final finished =
        legalBalls > 0 && legalBalls % 6 == 0 && innings.bowlerId == null;
    final idx = finished ? legalBalls ~/ 6 - 1 : legalBalls ~/ 6;
    return idx < overs.length ? overs[idx].balls : const [];
  }

  BatterLine _bat(String id) =>
      _batters.putIfAbsent(id, () => BatterLine(id, match.playerName(id)));
  BowlerLine _bowl(String id) =>
      _bowlers.putIfAbsent(id, () => BowlerLine(id, match.playerName(id)));

  String _howOut(BallEvent b) {
    final bowler = match.playerName(b.bowlerId);
    final f = b.fielderId == null ? null : match.playerName(b.fielderId);
    switch (b.wicket!) {
      case WicketType.bowled:
        return 'b $bowler';
      case WicketType.caught:
        return (f == null || b.fielderId == b.bowlerId)
            ? 'c & b $bowler'
            : 'c $f b $bowler';
      case WicketType.lbw:
        return 'lbw b $bowler';
      case WicketType.stumped:
        return 'st ${f ?? ''} b $bowler';
      case WicketType.hitWicket:
        return 'hit wicket b $bowler';
      case WicketType.runOut:
        return f == null ? 'run out' : 'run out ($f)';
    }
  }

  void _build() {
    final maiden = <String, ({int balls, int runs})>{};
    for (final b in innings.balls) {
      final overIdx = legalBalls ~/ 6;
      while (overs.length <= overIdx) {
        overs.add(OverSummary(overs.length + 1, match.playerName(b.bowlerId)));
      }
      overs[overIdx].balls.add(b);

      final bat = _bat(b.strikerId);
      _bat(b.nonStrikerId);
      final bowl = _bowl(b.bowlerId);

      runs += b.totalRuns;
      switch (b.extra) {
        case ExtraType.wide:
          wides += b.extraRuns;
          bowl.wides++;
        case ExtraType.noBall:
          noBalls += b.extraRuns;
          bowl.noBalls++;
        case ExtraType.bye:
          byes += b.extraRuns;
        case ExtraType.legBye:
          legByes += b.extraRuns;
        case ExtraType.none:
      }

      if (b.facedByBatter) bat.balls++;
      bat.runs += b.runs;
      if (b.runs == 4) bat.fours++;
      if (b.runs == 6) bat.sixes++;

      bowl.runs += b.bowlerRuns;
      if (b.isLegal) bowl.balls++;
      if (b.bowlerGetsWicket) bowl.wickets++;

      final key = '$overIdx|${b.bowlerId}';
      final prev = maiden[key] ?? (balls: 0, runs: 0);
      maiden[key] = (
        balls: prev.balls + (b.isLegal ? 1 : 0),
        runs: prev.runs + b.bowlerRuns,
      );

      if (b.isLegal) legalBalls++;

      if (b.isWicket) {
        wickets++;
        final outId = b.outPlayerId ?? b.strikerId;
        final line = _bat(outId);
        line.out = true;
        line.howOut = _howOut(b);
        fow.add(FallOfWicket(wickets, runs, line.name, oversText(legalBalls)));
      }
    }

    maiden.forEach((key, v) {
      if (v.balls == 6 && v.runs == 0) {
        _bowlers[key.split('|')[1]]!.maidens++;
      }
    });

    if (innings.strikerId != null) _bat(innings.strikerId!);
    if (innings.nonStrikerId != null) _bat(innings.nonStrikerId!);
    for (final l in _batters.values) {
      l.atCrease =
          !l.out && (l.id == innings.strikerId || l.id == innings.nonStrikerId);
    }
  }
}
