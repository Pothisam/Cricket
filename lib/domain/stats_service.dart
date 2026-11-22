import '../models/ball_event.dart';
import '../models/cricket_match.dart';
import 'innings_summary.dart';

class PlayerMatchRecord {
  PlayerMatchRecord(this.match);
  final CricketMatch match;
  int runs = 0, ballsFaced = 0, wickets = 0, runsConceded = 0, ballsBowled = 0;
  bool batted = false, out = false, bowled = false;
}

class PlayerCareer {
  PlayerCareer(this.id, this.name);
  final String id;
  String name;
  int matches = 0;
  int innings = 0, notOuts = 0, runs = 0, balls = 0, fours = 0, sixes = 0;
  int highScore = 0, fifties = 0, hundreds = 0, ducks = 0;
  bool highScoreNotOut = false;
  int bowlInnings = 0,
      ballsBowled = 0,
      runsConceded = 0,
      wickets = 0,
      maidens = 0;
  int bestWickets = 0, bestRuns = 0;
  int catches = 0, stumpings = 0, runOuts = 0;
  final List<PlayerMatchRecord> records = [];

  int get dismissals => innings - notOuts;
  double get average => dismissals == 0 ? runs.toDouble() : runs / dismissals;
  double get strikeRate => balls == 0 ? 0 : runs * 100 / balls;
  double get economy => ballsBowled == 0 ? 0 : runsConceded * 6 / ballsBowled;
  double get bowlingAverage => wickets == 0 ? 0 : runsConceded / wickets;
  String get oversBowled => oversText(ballsBowled);
  String get bestBowling => bowlInnings == 0 ? '-' : '$bestWickets/$bestRuns';
  String get highScoreText =>
      innings == 0 ? '-' : '$highScore${highScoreNotOut ? '*' : ''}';
}

class TeamRecord {
  TeamRecord(this.id, this.name, this.shortName);
  final String id;
  String name, shortName;
  int played = 0, won = 0, lost = 0, tied = 0;
  int highest = 0;
  int lowest = -1;
  int runsFor = 0, runsAgainst = 0;
  int get points => won * 2 + tied;
  String get lowestText => lowest < 0 ? '-' : '$lowest';
}

/// Aggregates career and team statistics from finished matches.
class CricketStats {
  CricketStats(List<CricketMatch> matches) {
    final done =
        matches.where((m) => m.status == MatchStatus.completed).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    for (final m in done) {
      _addMatch(m);
    }
  }

  final Map<String, PlayerCareer> players = {};
  final Map<String, TeamRecord> teams = {};
  int totalMatches = 0;
  int totalRuns = 0, totalWickets = 0, totalSixes = 0, totalFours = 0;
  int highestTeamTotal = 0;
  String highestTeamTotalBy = '';

  PlayerCareer? player(String id) => players[id];
  TeamRecord? team(String id) => teams[id];

  PlayerCareer _p(CricketMatch m, String id) {
    final c = players.putIfAbsent(id, () => PlayerCareer(id, m.playerName(id)));
    c.name = m.playerName(id);
    return c;
  }

  void _addMatch(CricketMatch m) {
    totalMatches++;
    final recs = <String, PlayerMatchRecord>{};
    PlayerMatchRecord rec(String id) =>
        recs.putIfAbsent(id, () => PlayerMatchRecord(m));

    for (final id in [...m.teamAPlayers, ...m.teamBPlayers]) {
      _p(m, id).matches++;
      rec(id);
    }

    for (final inn in m.innings) {
      final s = InningsSummary(m, inn);
      totalRuns += s.runs;
      totalWickets += s.wickets;
      if (s.runs > highestTeamTotal) {
        highestTeamTotal = s.runs;
        highestTeamTotalBy = m.teamName(inn.battingTeamId);
      }

      for (final b in s.batters) {
        final c = _p(m, b.id);
        if (b.balls == 0 && !b.out) continue; // never faced a ball
        c.innings++;
        if (!b.out) c.notOuts++;
        c.runs += b.runs;
        c.balls += b.balls;
        c.fours += b.fours;
        c.sixes += b.sixes;
        totalFours += b.fours;
        totalSixes += b.sixes;
        if (b.runs > c.highScore || (b.runs == c.highScore && !b.out)) {
          c.highScore = b.runs;
          c.highScoreNotOut = !b.out;
        }
        if (b.runs >= 100) {
          c.hundreds++;
        } else if (b.runs >= 50) {
          c.fifties++;
        }
        if (b.runs == 0 && b.out) c.ducks++;
        final r = rec(b.id);
        r.batted = true;
        r.out = b.out;
        r.runs = b.runs;
        r.ballsFaced = b.balls;
      }

      for (final bw in s.bowlers) {
        final c = _p(m, bw.id);
        c.bowlInnings++;
        c.ballsBowled += bw.balls;
        c.runsConceded += bw.runs;
        c.wickets += bw.wickets;
        c.maidens += bw.maidens;
        if (c.bowlInnings == 1 ||
            bw.wickets > c.bestWickets ||
            (bw.wickets == c.bestWickets && bw.runs < c.bestRuns)) {
          c.bestWickets = bw.wickets;
          c.bestRuns = bw.runs;
        }
        final r = rec(bw.id);
        r.bowled = true;
        r.wickets = bw.wickets;
        r.runsConceded = bw.runs;
        r.ballsBowled = bw.balls;
      }

      for (final b in inn.balls) {
        if (!b.isWicket || b.fielderId == null) continue;
        final f = _p(m, b.fielderId!);
        switch (b.wicket!) {
          case WicketType.caught:
            f.catches++;
          case WicketType.stumped:
            f.stumpings++;
          case WicketType.runOut:
            f.runOuts++;
          default:
        }
      }
    }

    recs.forEach((id, r) => players[id]!.records.add(r));
    _addTeams(m);
  }

  void _addTeams(CricketMatch m) {
    for (final id in [m.teamAId, m.teamBId]) {
      final t = teams.putIfAbsent(
        id,
        () => TeamRecord(id, m.teamName(id), m.teamShort(id)),
      );
      t.name = m.teamName(id);
      t.shortName = m.teamShort(id);
      t.played++;
      if (m.winnerId == null) {
        t.tied++;
      } else if (m.winnerId == id) {
        t.won++;
      } else {
        t.lost++;
      }
    }
    for (final inn in m.innings) {
      final bat = teams[inn.battingTeamId]!;
      final bowl = teams[inn.bowlingTeamId]!;
      bat.runsFor += inn.runs;
      bowl.runsAgainst += inn.runs;
      if (inn.runs > bat.highest) bat.highest = inn.runs;
      if (bat.lowest < 0 || inn.runs < bat.lowest) bat.lowest = inn.runs;
    }
  }

  List<PlayerCareer> topRunScorers([int n = 10]) =>
      (players.values.where((p) => p.runs > 0).toList()
            ..sort((a, b) => b.runs.compareTo(a.runs)))
          .take(n)
          .toList();

  List<PlayerCareer> topWicketTakers([int n = 10]) =>
      (players.values.where((p) => p.wickets > 0).toList()..sort((a, b) {
            final c = b.wickets.compareTo(a.wickets);
            return c != 0 ? c : a.economy.compareTo(b.economy);
          }))
          .take(n)
          .toList();

  List<TeamRecord> standings() => teams.values.toList()
    ..sort((a, b) {
      final c = b.points.compareTo(a.points);
      return c != 0 ? c : b.won.compareTo(a.won);
    });
}
