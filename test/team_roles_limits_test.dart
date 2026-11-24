import 'package:cricket/data/repositories/local_repositories.dart';
import 'package:cricket/data/sources/local_store.dart';
import 'package:cricket/models/player.dart';
import 'package:cricket/models/team.dart';
import 'package:cricket/state/teams_controller.dart';
import 'package:flutter_test/flutter_test.dart';

TeamsController newController() {
  final store = MemoryStore();
  return TeamsController(LocalTeamRepository(store), LocalPlayerRepository(store));
}

void main() {
  group('team limit: 3 teams, 1 public and 2 private', () {
    test('one public and two private teams can be created, a 4th cannot', () async {
      final tc = newController();
      await tc.addTeam('A', 'A', 0, isPublic: true);
      await tc.addTeam('B', 'B', 1);
      await tc.addTeam('C', 'C', 2);
      expect(tc.teams.length, 3);
      expect(tc.canCreateTeam, isFalse);

      expect(
        () => tc.addTeam('D', 'D', 3),
        throwsA(isA<TeamLimitException>().having((e) => e.message, 'message', TeamsController.limitMessage)),
      );
      expect(tc.teams.length, 3);
    });

    test('a second public team is refused with its own message', () async {
      final tc = newController();
      await tc.addTeam('A', 'A', 0, isPublic: true);
      expect(
        () => tc.addTeam('B', 'B', 1, isPublic: true),
        throwsA(isA<TeamLimitException>().having((e) => e.message, 'message', contains('Only 1 team can be public'))),
      );
    });

    test('a third private team is refused while only two are allowed', () async {
      final tc = newController();
      await tc.addTeam('A', 'A', 0);
      await tc.addTeam('B', 'B', 1);
      expect(
        () => tc.addTeam('C', 'C', 2),
        throwsA(isA<TeamLimitException>().having((e) => e.message, 'message', contains('2 private teams'))),
      );
    });

    test('a duplicate counts as a team and is refused at the limit', () async {
      final tc = newController();
      final a = await tc.addTeam('A', 'A', 0, isPublic: true);
      await tc.addTeam('B', 'B', 1);
      final copy = await tc.duplicateTeam(a); // 3rd team (private)
      expect(copy.isPublic, isFalse);
      expect(tc.canCreateTeam, isFalse);
      expect(() => tc.duplicateTeam(a), throwsA(isA<TeamLimitException>()));
    });

    test('changing visibility follows the same rule', () async {
      final tc = newController();
      final a = await tc.addTeam('A', 'A', 0, isPublic: true);
      final b = await tc.addTeam('B', 'B', 1);
      expect(tc.visibilityBlockedReason(b, true), contains('Only 1 team can be public'));
      expect(tc.visibilityBlockedReason(b, false), isNull); // no change
      expect(tc.visibilityBlockedReason(a, false), isNull); // public -> private is fine (1 private so far)
    });

    test('teams created before the rule are kept and can still be edited', () async {
      final store = MemoryStore();
      final repo = LocalTeamRepository(store);
      for (var i = 0; i < 5; i++) {
        await repo.save(Team(id: 't$i', name: 'Old $i', shortName: 'O$i', isPublic: true));
      }
      final tc = TeamsController(repo, LocalPlayerRepository(store));
      await tc.load();
      expect(tc.teams.length, 5);
      expect(tc.canCreateTeam, isFalse);
      // an edit that does not change the visibility is allowed
      expect(tc.visibilityBlockedReason(tc.teams.first, true), isNull);
    });
  });

  group('captain, vice-captain and order belong to the team', () {
    Future<(TeamsController, Team, List<Player>)> setup() async {
      final tc = newController();
      final team = await tc.addTeam('Kings', 'KIN', 0);
      final players = <Player>[];
      for (final n in ['Ravi', 'Arun', 'Sam', 'Dev']) {
        final p = await tc.addPlayer(Player(id: 'p$n', name: n), team: team);
        players.add(p);
      }
      return (tc, team, players);
    }

    test('captain and vice-captain are different people', () async {
      final (tc, team, _) = await setup();
      await tc.setCaptain(team, 'pRavi');
      await tc.setViceCaptain(team, 'pArun');
      expect(team.captainPlayerId, 'pRavi');
      expect(team.viceCaptainPlayerId, 'pArun');

      // making the vice-captain the captain frees the vice-captain role
      await tc.setCaptain(team, 'pArun');
      expect(team.captainPlayerId, 'pArun');
      expect(team.viceCaptainPlayerId, isNull);
    });

    test('a role can be taken away', () async {
      final (tc, team, _) = await setup();
      await tc.setCaptain(team, 'pRavi');
      await tc.setCaptain(team, null);
      expect(team.captainPlayerId, isNull);
    });

    test('removing a player from the team clears his role in that team', () async {
      final (tc, team, _) = await setup();
      await tc.setCaptain(team, 'pRavi');
      await tc.setViceCaptain(team, 'pArun');
      await tc.removeFromTeam(team, 'pRavi');
      expect(team.captainPlayerId, isNull);
      expect(team.viceCaptainPlayerId, 'pArun');
    });

    test('the same player is captain of one team and an ordinary player in another', () async {
      final (tc, team, _) = await setup();
      final other = await tc.addTeam('Stars', 'STA', 1);
      await tc.addToTeam(other, 'pRavi');
      await tc.setCaptain(team, 'pRavi');
      expect(team.captainPlayerId, 'pRavi');
      expect(other.captainPlayerId, isNull);
    });

    test('the batting order can be changed', () async {
      final (tc, team, _) = await setup();
      expect(team.playerIds, ['pRavi', 'pArun', 'pSam', 'pDev']);
      await tc.moveInSquad(team, 0, 2); // Ravi goes to the 3rd place
      expect(team.playerIds, ['pArun', 'pSam', 'pRavi', 'pDev']);
      await tc.moveInSquad(team, 3, 0); // Dev goes to the top
      expect(team.playerIds, ['pDev', 'pArun', 'pSam', 'pRavi']);
    });

    test('captain and order survive saving and loading', () async {
      final store = MemoryStore();
      final tc = TeamsController(LocalTeamRepository(store), LocalPlayerRepository(store));
      final team = await tc.addTeam('Kings', 'KIN', 0);
      await tc.addPlayer(Player(id: 'p1', name: 'A'), team: team);
      await tc.addPlayer(Player(id: 'p2', name: 'B'), team: team);
      await tc.setCaptain(team, 'p2');
      await tc.setViceCaptain(team, 'p1');

      final again = TeamsController(LocalTeamRepository(store), LocalPlayerRepository(store));
      await again.load();
      final loaded = again.teams.single;
      expect(loaded.captainPlayerId, 'p2');
      expect(loaded.viceCaptainPlayerId, 'p1');
    });
  });
}
