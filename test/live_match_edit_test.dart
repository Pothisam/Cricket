import 'package:cricket/data/repositories/local_repositories.dart';
import 'package:cricket/data/sources/local_store.dart';
import 'package:cricket/models/ball_event.dart';
import 'package:cricket/models/cricket_match.dart';
import 'package:cricket/state/matches_controller.dart';
import 'package:cricket/state/scoring_controller.dart';
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
    playerNames: {
      for (final id in [...a, ...b]) id: id.toUpperCase(),
    },
    date: DateTime(2026, 1, 1),
  );
}

Future<ScoringController> started({int overs = 2}) async {
  final mc = MatchesController(LocalMatchRepository(MemoryStore()));
  final c = ScoringController(makeMatch(overs: overs), mc);
  await c.setOpeners('a1', 'a2');
  await c.setBowler('b1');
  return c;
}

void main() {
  group('add and remove players during the match', () {
    test(
      'a player can be added to the playing XI and is named in the scorecard',
      () async {
        final c = await started();
        expect(await c.addToXi('A', 'a4', 'New Batter'), isTrue);
        expect(c.match.teamAPlayers, ['a1', 'a2', 'a3', 'a4']);
        expect(c.match.playerName('a4'), 'New Batter');
        // he can now come in as a batter
        expect(c.availableBatters, contains('a4'));
      },
    );

    test('somebody who is already playing cannot be added twice', () async {
      final c = await started();
      expect(await c.addToXi('B', 'a1', 'A1'), isFalse); // already in team A
      expect(c.match.teamBPlayers.length, 3);
    });

    test(
      'players at the crease or bowling cannot be removed, others can',
      () async {
        final c = await started();
        expect(c.removalBlockedReason('A', 'a1'), 'At the crease');
        expect(c.removalBlockedReason('B', 'b1'), 'Bowling now');
        expect(c.removalBlockedReason('A', 'a3'), isNull);
        expect(c.removalBlockedReason('B', 'b2'), isNull);

        expect(await c.removeFromXi('A', 'a3'), isTrue);
        expect(c.match.teamAPlayers, ['a1', 'a2']);
        expect(c.match.playerNames.containsKey('a3'), isFalse);
      },
    );

    test(
      'a player who already batted, bowled or was dismissed has to stay',
      () async {
        final c = await started();
        await c.recordBall(runs: 1); // a1 and a2 batted, b1 bowled
        await c.recordBall(
          runs: 0,
          wicket: WicketType.bowled,
        ); // a2 (on strike) is out
        expect(c.removalBlockedReason('A', 'a1'), isNotNull);
        expect(c.removalBlockedReason('A', 'a2'), 'Has already batted');
        expect(c.removalBlockedReason('B', 'b1'), isNotNull);
      },
    );

    test('a team keeps at least 2 players', () async {
      final c = await started();
      await c.removeFromXi('B', 'b3');
      expect(c.match.teamBPlayers.length, 2);
      expect(
        c.removalBlockedReason('B', 'b2'),
        'A team needs at least 2 players',
      );
    });

    test('one player less must not end an innings that is already at the new wicket limit', () async {
      final c = await started(); // 3 players: 2 wickets
      await c.recordBall(runs: 0, wicket: WicketType.bowled); // 1 wicket down
      // removing a3 would leave 2 players = 1 wicket: the innings would be over already
      expect(
        c.removalBlockedReason('A', 'a3'),
        'The innings would already be over',
      );
    });

    test('nothing can be changed once the match is over', () async {
      final c = await started();
      await c.endMatch();
      expect(c.match.isLive, isFalse);
      expect(await c.addToXi('A', 'a9', 'Late'), isFalse);
      expect(await c.removeFromXi('A', 'a3'), isFalse);
    });
  });

  group('change the overs during the match', () {
    Future<void> bowlOver(ScoringController c) async {
      for (var i = 0; i < 6; i++) {
        await c.recordBall(runs: 0);
      }
    }

    test('the overs cannot go below the overs already bowled', () async {
      final c = await started(overs: 3);
      await bowlOver(c);
      expect(c.minOvers, 1);
      await c.setBowler('b2');
      await bowlOver(c);
      expect(c.minOvers, 2);
      expect(await c.changeOvers(1), isNull);
      expect(c.match.overs, 3);
      expect(await c.changeOvers(0), isNull);
      expect(await c.changeOvers(101), isNull);
    });

    test(
      'more overs open an innings that ended only because of the old limit',
      () async {
        final c = await started(overs: 1);
        await bowlOver(c);
        expect(c.innings.completed, isTrue); // 1 over limit reached
        final note = await c.changeOvers(2);
        expect(c.match.overs, 2);
        expect(c.innings.completed, isFalse);
        expect(note, contains('carries on'));
      },
    );

    test(
      'fewer overs end the innings when the new limit is already reached',
      () async {
        final c = await started(overs: 2);
        await bowlOver(c); // 1 over bowled, innings goes on
        expect(c.innings.completed, isFalse);
        final note = await c.changeOvers(1);
        expect(c.innings.completed, isTrue);
        expect(note, contains('innings is over'));
      },
    );

    test(
      'fewer overs in the 2nd innings finish the match with a result',
      () async {
        final c = await started(overs: 2);
        await c.endInningsEarly(); // 1st innings: 0 runs
        await c.startSecondInnings();
        await c.setOpeners('b1', 'b2');
        await c.setBowler('a1');
        await bowlOver(c);
        expect(c.match.isLive, isTrue);

        final note = await c.changeOvers(1);
        expect(c.match.isLive, isFalse);
        expect(c.match.resultText, isNotEmpty);
        expect(note, contains('match is over'));
      },
    );

    test(
      'an innings that was ended by hand stays ended when the overs change',
      () async {
        final c = await started(overs: 5);
        await c.endInningsEarly();
        await c.changeOvers(6);
        expect(c.innings.completed, isTrue);
      },
    );
  });
}
