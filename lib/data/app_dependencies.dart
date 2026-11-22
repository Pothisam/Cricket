import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'api/cricket_api.dart';
import 'api/live_scoring_sync.dart';
import 'api/sync_manager.dart';
import 'api/sync_state.dart';
import 'repositories/local_repositories.dart';
import 'repositories/repositories.dart';
import 'repositories/synced_repositories.dart';
import 'sources/local_store.dart';

/// Single composition root. UI and state classes only know the abstract
/// repositories; the synced ones keep the local store as the source of truth and
/// mirror every change to the API.
class AppDependencies {
  AppDependencies({
    required this.teams,
    required this.players,
    required this.matches,
    required this.maintenance,
    this.api,
    this.sync,
    this.live,
  });

  final TeamRepository teams;
  final PlayerRepository players;
  final MatchRepository matches;
  final DataMaintenance maintenance;

  /// Null in tests / local-only mode.
  final CricketApi? api;
  final SyncManager? sync;
  final LiveScoringSync? live;

  factory AppDependencies.local(LocalStore store) => AppDependencies(
        teams: LocalTeamRepository(store),
        players: LocalPlayerRepository(store),
        matches: LocalMatchRepository(store),
        maintenance: LocalDataMaintenance(store),
      );

  /// Local-first with cloud sync against the Cricket API.
  factory AppDependencies.synced(SharedPreferences prefs) {
    final store = SharedPrefsStore(prefs);
    final state = SyncState(prefs);
    final deviceId = SyncState.deviceIdOf(prefs);
    final api = CricketApi(ApiClient(deviceId: deviceId));

    final localTeams = LocalTeamRepository(store);
    final localPlayers = LocalPlayerRepository(store);
    final localMatches = LocalMatchRepository(store);
    final syncedMatches = SyncedMatchRepository(localMatches, api, state);

    return AppDependencies(
      teams: SyncedTeamRepository(localTeams, api, state),
      players: SyncedPlayerRepository(localPlayers, api, state),
      matches: syncedMatches,
      maintenance: LocalDataMaintenance(store),
      api: api,
      live: LiveScoringSync(api, state, syncedMatches),
      sync: SyncManager(
        api: api,
        state: state,
        deviceId: deviceId,
        teams: localTeams,
        players: localPlayers,
        matches: localMatches,
      ),
    );
  }
}
