import 'package:cricket/data/repositories/local_repositories.dart';
import 'package:cricket/data/sources/local_store.dart';
import 'package:cricket/models/player.dart';
import 'package:cricket/state/teams_controller.dart';
import 'package:cricket/ui/screens/players_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

TeamsController newController() {
  final store = MemoryStore();
  return TeamsController(
    LocalTeamRepository(store),
    LocalPlayerRepository(store),
  );
}

Future<void> fill(TeamsController tc, int n) async {
  for (var i = 0; i < n; i++) {
    await tc.addPlayer(Player(id: 'p$i', name: 'Player $i'));
  }
}

Widget counterHost(TeamsController tc) => ChangeNotifierProvider.value(
  value: tc,
  child: const MaterialApp(home: Scaffold(body: PlayerCounter())),
);

void main() {
  group('player limit: 50 players', () {
    test(
      '50 players can be added, the 51st is refused with a clear message',
      () async {
        final tc = newController();
        await fill(tc, 50);
        expect(tc.playerCount, 50);
        expect(tc.playersLeft, 0);
        expect(tc.canAddPlayer, isFalse);

        expect(
          () => tc.addPlayer(Player(id: 'extra', name: 'One too many')),
          throwsA(
            isA<PlayerLimitException>().having(
              (e) => e.message,
              'message',
              TeamsController.playerLimitMessage,
            ),
          ),
        );
        expect(tc.playerCount, 50);
      },
    );

    test('the counter tells how many are used and how many are left', () async {
      final tc = newController();
      await fill(tc, 12);
      expect(tc.playerCount, 12);
      expect(tc.playersLeft, 38);
      expect(tc.canAddPlayer, isTrue);
    });

    test('removing a player makes room again', () async {
      final tc = newController();
      await fill(tc, 50);
      await tc.deletePlayer(tc.players.first);
      expect(tc.playersLeft, 1);
      expect(tc.canAddPlayer, isTrue);
      await tc.addPlayer(Player(id: 'new', name: 'New'));
      expect(tc.playerCount, 50);
    });

    test(
      'a list that was already bigger is kept, only new players are blocked',
      () async {
        final store = MemoryStore();
        final repo = LocalPlayerRepository(store);
        for (var i = 0; i < 60; i++) {
          await repo.save(Player(id: 'o$i', name: 'Old $i'));
        }
        final tc = TeamsController(LocalTeamRepository(store), repo);
        await tc.load();
        expect(tc.playerCount, 60);
        expect(tc.playersLeft, 0); // never negative
        expect(tc.canAddPlayer, isFalse);
      },
    );
  });

  group('counter on the Players tab', () {
    testWidgets('shows "12 of 50 players" and "38 more can be added"', (
      tester,
    ) async {
      final tc = newController();
      await fill(tc, 12);
      await tester.pumpWidget(counterHost(tc));
      expect(find.text('12 of 50 players'), findsOneWidget);
      expect(find.text('38 more can be added'), findsOneWidget);
      expect(find.text(TeamsController.playerLimitMessage), findsNothing);
    });

    testWidgets('at 50 it says the list is full and why', (tester) async {
      final tc = newController();
      await fill(tc, 50);
      await tester.pumpWidget(counterHost(tc));
      expect(find.text('50 of 50 players'), findsOneWidget);
      expect(find.text('List is full'), findsOneWidget);
      expect(find.text(TeamsController.playerLimitMessage), findsOneWidget);
    });
  });
}
