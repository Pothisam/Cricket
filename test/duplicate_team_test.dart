import 'package:cricket/data/sources/local_store.dart';
import 'package:cricket/data/repositories/local_repositories.dart';
import 'package:cricket/state/teams_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('duplicating a team adds a private copy with the same players below the others', () async {
    final store = MemoryStore();
    final tc = TeamsController(LocalTeamRepository(store), LocalPlayerRepository(store));
    final a = await tc.addTeam('Blue Wing Team A', 'BWT', 2, isPublic: true);
    a.playerIds.addAll(['p1', 'p2', 'p3']);
    await tc.updateTeam(a);
    await tc.addTeam('Team B', 'TB', 1);

    final copy = await tc.duplicateTeam(a);

    expect(tc.teams.last.id, copy.id); // below the others
    expect(tc.teams.length, 3);
    expect(copy.id, isNot(a.id));
    expect(copy.name, 'Blue Wing Team A (copy)');
    expect(copy.shortName, 'BWT');
    expect(copy.colorIndex, 2);
    expect(copy.playerIds, ['p1', 'p2', 'p3']);
    expect(copy.isPublic, isFalse);
    // a later edit of the copy does not change the original
    copy.playerIds.add('p4');
    expect(a.playerIds.length, 3);
    // it was saved
    final saved = await LocalTeamRepository(store).getAll();
    expect(saved.map((t) => t.name), contains('Blue Wing Team A (copy)'));
  });

  test('a very long name still fits the 80 character limit', () async {
    final store = MemoryStore();
    final tc = TeamsController(LocalTeamRepository(store), LocalPlayerRepository(store));
    final t = await tc.addTeam('x' * 80, 'LNG', 0);
    final copy = await tc.duplicateTeam(t);
    expect(copy.name.length, lessThanOrEqualTo(80));
    expect(copy.name.endsWith(' (copy)'), isTrue);
  });
}
