import 'package:cricket/data/api/api_models.dart';
import 'package:cricket/data/repositories/local_repositories.dart';
import 'package:cricket/data/sources/local_store.dart';
import 'package:cricket/models/player.dart';
import 'package:cricket/state/membership_controller.dart';
import 'package:cricket/state/team_membership.dart';
import 'package:cricket/state/teams_controller.dart';
import 'package:flutter_test/flutter_test.dart';

TeamsController newController() {
  final store = MemoryStore();
  return TeamsController(
    LocalTeamRepository(store),
    LocalPlayerRepository(store),
  );
}

JoinedTeam joined(String owner, String team, String name) =>
    JoinedTeam.fromJson({
      'ownerId': owner,
      'ownerName': 'Owner $owner',
      'teamId': team,
      'name': name,
      'shortName': name.substring(0, 2).toUpperCase(),
    });

ManagedTeam managed(String owner, String team, String name) =>
    ManagedTeam.fromJson({
      'ownerId': owner,
      'teamId': team,
      'name': name,
      'shortName': name.substring(0, 2).toUpperCase(),
    });

void main() {
  test('a player who is in no team, one team, several teams', () async {
    final tc = newController();
    final ms = MembershipController(null);
    final p = await tc.addPlayer(Player(id: 'p1', name: 'Ravi'));

    expect(TeamMembership.of(p, tc, ms).countLabel, 'Not in any team');
    expect(TeamMembership.of(p, tc, ms).total, 0);

    final a = await tc.addTeam('Kings', 'KIN', 0);
    await tc.addToTeam(a, 'p1');
    expect(TeamMembership.of(p, tc, ms).line, 'In 1 team: Kings');

    final b = await tc.addTeam('Stars', 'STA', 1, isPublic: true);
    await tc.addToTeam(b, 'p1');
    expect(TeamMembership.of(p, tc, ms).line, 'In 2 teams: Kings, Stars');
  });

  test('a long list of teams is shortened but the count stays exact', () async {
    // 3 teams is the limit per user, so build the list from the pieces directly
    final m = TeamMembership(mine: ['A', 'B', 'C'], others: ['D', 'E']);
    expect(m.total, 5);
    expect(m.line, 'In 5 teams: A, B, C +2');
    expect(m.breakdown, '3 yours · 2 added by others');
  });

  test('for me the teams of other scorers count too, and a team is never counted twice', () async {
    final tc = newController();
    final ms = MembershipController(null);
    final me = await tc.addPlayer(
      Player(id: 'me', name: 'Me', isSelf: true, linkedUserId: 'u1'),
    );
    final mine = await tc.addTeam('My Team', 'MY', 0);
    await tc.addToTeam(mine, 'me');

    ms.teams = [joined('o1', 't1', 'Alpha'), joined('o2', 't2', 'Beta')];
    // Beta was also handed over to me: still ONE team
    ms.managedTeams = [
      managed('o2', 't2', 'Beta'),
      managed('o3', 't3', 'Gamma'),
    ];

    final m = TeamMembership.of(me, tc, ms);
    expect(m.mine, ['My Team']);
    expect(m.others, ['Alpha', 'Beta', 'Gamma']);
    expect(m.total, 4);
    expect(m.countLabel, 'In 4 teams');
    expect(m.breakdown, '1 yours · 3 added by others');
  });

  test(
    'the teams of other scorers are never shown for somebody else\'s player',
    () async {
      final tc = newController();
      final ms = MembershipController(null)
        ..teams = [joined('o1', 't1', 'Alpha')];
      final p = await tc.addPlayer(Player(id: 'p1', name: 'Siva'));
      expect(TeamMembership.of(p, tc, ms).total, 0);
    },
  );

  test('summary: created, administered and added-by-others teams', () async {
    final tc = newController();
    await tc.addTeam('One', 'ONE', 0);
    await tc.addTeam('Two', 'TWO', 1);
    final ms = MembershipController(null)
      ..teams = [joined('o1', 't1', 'Alpha'), joined('o2', 't2', 'Beta')]
      ..managedTeams = [managed('o2', 't2', 'Beta')];

    final s = MyTeamsSummary(tc, ms);
    expect(s.created, 2);
    expect(s.admin, 1);
    expect(s.addedBy, 1); // Alpha only: Beta is counted as admin
    expect(s.total, 4);
  });
}
