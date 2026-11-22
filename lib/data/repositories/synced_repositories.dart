import 'dart:async';

import '../../models/cricket_match.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../api/cricket_api.dart';
import '../api/sync_state.dart';
import 'repositories.dart';

/// Local-first repositories that also push every change to the API.
///
/// Writes always hit the local store first (the app works offline). The server
/// call is best-effort; a failure leaves the row marked dirty and the next
/// `SyncManager.syncAll()` pushes it through `POST /sync/push`.
class SyncedTeamRepository implements TeamRepository {
  SyncedTeamRepository(this._local, this._api, this._state);
  final TeamRepository _local;
  final CricketApi _api;
  final SyncState _state;

  @override
  Future<List<Team>> getAll() => _local.getAll();

  @override
  Future<void> save(Team team) async {
    await _local.save(team);
    await _state.markDirty(SyncState.teams, team.id);
    unawaited(_push(team));
  }

  Future<void> _push(Team t) async {
    if (!_api.sessionReady) return;
    try {
      await _api.putTeam(t);
      await _state.clearDirty(SyncState.teams, [t.id]);
    } catch (_) {}
  }

  @override
  Future<void> delete(String id) async {
    await _local.delete(id);
    await _state.markDeleted(SyncState.teams, id);
    if (!_api.sessionReady) return;
    unawaited(() async {
      try {
        await _api.deleteTeam(id);
        await _state.clearDeleted(SyncState.teams, [id]);
      } catch (_) {}
    }());
  }
}

class SyncedPlayerRepository implements PlayerRepository {
  SyncedPlayerRepository(this._local, this._api, this._state);
  final PlayerRepository _local;
  final CricketApi _api;
  final SyncState _state;

  @override
  Future<List<Player>> getAll() => _local.getAll();

  @override
  Future<void> save(Player player) async {
    await _local.save(player);
    await _state.markDirty(SyncState.players, player.id);
    unawaited(_push(player));
  }

  Future<void> _push(Player p) async {
    if (!_api.sessionReady) return;
    try {
      await _api.putPlayer(p);
      await _state.clearDirty(SyncState.players, [p.id]);
    } catch (_) {}
  }

  @override
  Future<void> delete(String id) async {
    await _local.delete(id);
    await _state.markDeleted(SyncState.players, id);
    if (!_api.sessionReady) return;
    unawaited(() async {
      try {
        await _api.deletePlayer(id);
        await _state.clearDeleted(SyncState.players, [id]);
      } catch (_) {}
    }());
  }
}

/// Matches: while a match is *live* the granular scoring endpoints
/// (`LiveScoringSync`) keep the server up to date, so a full `PUT` is only sent
/// the first time the server sees the match and once the match is no longer live.
class SyncedMatchRepository implements MatchRepository {
  SyncedMatchRepository(this._local, this._api, this._state);
  final MatchRepository _local;
  final CricketApi _api;
  final SyncState _state;

  @override
  Future<List<CricketMatch>> getAll() => _local.getAll();

  @override
  Future<void> save(CricketMatch match) async {
    await _local.save(match);
    await _state.markDirty(SyncState.matches, match.id);
    if (!match.isLive || !_state.serverHasMatch(match.id))
      unawaited(putNow(match));
  }

  /// Full upsert of one match; returns whether it succeeded.
  Future<bool> putNow(CricketMatch m) async {
    if (!_api.sessionReady) return false;
    try {
      await _api.putMatch(m);
      await _state.setServerHasMatch(m.id, true);
      if (!m.isLive) await _state.clearDirty(SyncState.matches, [m.id]);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> delete(String id) async {
    await _local.delete(id);
    await _state.markDeleted(SyncState.matches, id);
    await _state.setServerHasMatch(id, false);
    if (!_api.sessionReady) return;
    unawaited(() async {
      try {
        await _api.deleteMatch(id);
        await _state.clearDeleted(SyncState.matches, [id]);
      } catch (_) {}
    }());
  }
}
