import 'package:cricket/data/app_dependencies.dart';
import 'package:cricket/data/sample_data.dart';
import 'package:cricket/data/sources/local_store.dart';
import 'package:cricket/state/matches_controller.dart';
import 'package:cricket/state/teams_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sample data loads, completes matches and produces stats', () async {
    final deps = AppDependencies.local(MemoryStore());
    final tc = TeamsController(deps.teams, deps.players);
    final mc = MatchesController(deps.matches);
    await SampleData.load(tc, mc);

    expect(tc.teams.length, 3);
    expect(mc.matches.length, 3);
    expect(mc.matches.every((m) => m.resultText.isNotEmpty), isTrue);
    expect(mc.stats.topRunScorers(), isNotEmpty);
    expect(mc.stats.standings().length, 3);

    // Reloading from the repository gives the same matches.
    final fresh = MatchesController(deps.matches);
    await fresh.load();
    expect(fresh.matches.length, 3);
  });
}
