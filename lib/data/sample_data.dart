import 'dart:math';

import '../core/ids.dart';
import '../domain/scoring_engine.dart';
import '../models/ball_event.dart';
import '../models/cricket_match.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../state/matches_controller.dart';
import '../state/teams_controller.dart';

/// Builds demo teams and a few simulated matches so every screen has content.
class SampleData {
  static const _names = {
    'Royal Strikers': [
      'Arjun Rao',
      'Vikram Shah',
      'Rohan Mehta',
      'Karan Iyer',
      'Sameer Khan',
      'Dev Patel',
      'Nikhil Joshi',
      'Imran Ali',
      'Pranav Nair',
      'Tarun Das',
      'Yash Verma',
    ],
    'Thunder Kings': [
      'Aditya Menon',
      'Rahul Sharma',
      'Kabir Singh',
      'Manav Gill',
      'Zaid Ahmed',
      'Harsh Vora',
      'Ishaan Roy',
      'Neel Desai',
      'Omkar Pawar',
      'Sujay Bose',
      'Varun Kapoor',
    ],
    'City Warriors': [
      'Ankit Yadav',
      'Bhavesh Jain',
      'Chirag Bhatt',
      'Dhruv Saxena',
      'Eshan Malik',
      'Farhan Qureshi',
      'Gaurav Tiwari',
      'Hemant Rana',
      'Irfan Sheikh',
      'Jatin Arora',
      'Kunal Sethi',
    ],
  };

  static Future<void> load(TeamsController tc, MatchesController mc) async {
    final rnd = Random(7);
    final teams = <Team>[];
    var color = 0;
    for (final e in _names.entries) {
      final short = e.key.split(' ').map((w) => w[0]).join();
      // 1 public + 2 private teams, within the per-user team limit
      final t = await tc.addTeam(
        e.key,
        short,
        color++ % 8,
        isPublic: color == 1,
      );
      for (var i = 0; i < e.value.length; i++) {
        await tc.addPlayer(
          Player(
            id: newId(),
            name: e.value[i],
            role: i == 5
                ? PlayerRole.wicketKeeper
                : i < 4
                ? PlayerRole.batter
                : i < 7
                ? PlayerRole.allRounder
                : PlayerRole.bowler,
            battingStyle: i.isEven ? 'Right-hand bat' : 'Left-hand bat',
            bowlingStyle: i >= 4 ? 'Right-arm medium' : 'None',
          ),
          team: t,
        );
      }
      teams.add(t);
    }
    await mc.add(
      _simulate(
        tc,
        teams[0],
        teams[1],
        rnd,
        10,
        DateTime.now().subtract(const Duration(days: 6)),
      ),
    );
    await mc.add(
      _simulate(
        tc,
        teams[1],
        teams[2],
        rnd,
        10,
        DateTime.now().subtract(const Duration(days: 3)),
      ),
    );
    await mc.add(
      _simulate(
        tc,
        teams[2],
        teams[0],
        rnd,
        10,
        DateTime.now().subtract(const Duration(days: 1)),
      ),
    );
  }

  static CricketMatch _simulate(
    TeamsController tc,
    Team a,
    Team b,
    Random rnd,
    int overs,
    DateTime date,
  ) {
    final names = <String, String>{};
    for (final t in [a, b]) {
      for (final p in tc.playersOf(t)) {
        names[p.id] = p.name;
      }
    }
    final m = CricketMatch(
      id: newId(),
      teamAId: a.id,
      teamBId: b.id,
      teamAName: a.name,
      teamBName: b.name,
      teamAShort: a.shortName,
      teamBShort: b.shortName,
      overs: overs,
      tossWinnerId: rnd.nextBool() ? a.id : b.id,
      electedToBat: rnd.nextBool(),
      teamAPlayers: List.of(a.playerIds),
      teamBPlayers: List.of(b.playerIds),
      playerNames: names,
      date: date,
      venue: 'Community Ground',
    );

    var battingId = m.battingFirstId;
    for (var k = 0; k < 2; k++) {
      final inn = ScoringEngine.startInnings(m, battingId);
      final order = m.squad(battingId);
      final attack = m.squad(inn.bowlingTeamId).sublist(4);
      var next = 2;
      var over = 0;
      inn.strikerId = order[0];
      inn.nonStrikerId = order[1];
      while (!ScoringEngine.isInningsOver(m, inn)) {
        if (ScoringEngine.needsBatter(m, inn)) {
          final id = order[next++];
          if (inn.strikerId == null) {
            inn.strikerId = id;
          } else {
            inn.nonStrikerId = id;
          }
        }
        inn.bowlerId ??= attack[over++ % attack.length];
        final r = rnd.nextDouble();
        final fielders = m.squad(inn.bowlingTeamId);
        var runs = 0;
        var extra = ExtraType.none;
        var extraRuns = 0;
        WicketType? wk;
        String? fielder;
        if (r < 0.05 + k * 0.01) {
          wk = [
            WicketType.bowled,
            WicketType.caught,
            WicketType.lbw,
            WicketType.caught,
            WicketType.stumped,
          ][rnd.nextInt(5)];
          if (wk == WicketType.caught || wk == WicketType.stumped) {
            fielder = fielders[rnd.nextInt(fielders.length)];
          }
        } else if (r < 0.10) {
          extra = ExtraType.wide;
          extraRuns = 1;
        } else if (r < 0.12) {
          extra = ExtraType.noBall;
          extraRuns = 1;
          runs = rnd.nextBool() ? 0 : 4;
        } else if (r < 0.14) {
          extra = rnd.nextBool() ? ExtraType.bye : ExtraType.legBye;
          extraRuns = 1;
        } else {
          runs = const [0, 0, 0, 1, 1, 1, 1, 2, 3, 4, 4, 6][rnd.nextInt(12)];
        }
        ScoringEngine.applyBall(
          inn,
          BallEvent(
            strikerId: inn.strikerId!,
            nonStrikerId: inn.nonStrikerId!,
            bowlerId: inn.bowlerId!,
            runs: runs,
            extra: extra,
            extraRuns: extraRuns,
            wicket: wk,
            outPlayerId: wk == null ? null : inn.strikerId,
            fielderId: fielder,
            shotDirection: (runs > 0 || wk == WicketType.caught)
                ? ShotDirection.values[rnd.nextInt(ShotDirection.values.length)]
                : null,
          ),
        );
      }
      ScoringEngine.completeInnings(m, inn);
      battingId = inn.bowlingTeamId;
    }
    return m;
  }
}
