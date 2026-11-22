import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/cricket_match.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../services/notification_service.dart';
import '../repositories/repositories.dart';
import 'api_client.dart';
import 'cricket_api.dart';
import 'device_info.dart';
import 'sync_state.dart';

/// Owns the server session (login hook, FCM token registration, logout) and the
/// two-way data sync (`POST /sync/push` then `GET /sync/pull`).
class SyncManager extends ChangeNotifier {
  SyncManager({
    required this.api,
    required this.state,
    required this.deviceId,
    required TeamRepository teams,
    required PlayerRepository players,
    required MatchRepository matches,
  })  : _teams = teams,
        _players = players,
        _matches = matches;

  final CricketApi api;
  final SyncState state;
  final String deviceId;
  final TeamRepository _teams; // local repositories (no API side effects)
  final PlayerRepository _players;
  final MatchRepository _matches;

  final List<Future<void> Function()> _reloaders = [];
  StreamSubscription<String>? _tokenSub;
  String? _uid;

  bool syncing = false;
  DateTime? lastSyncedAt;
  String? lastError;
  bool get signedIn => api.sessionReady;

  /// Controllers register here so they refresh after a pull.
  void addReloader(Future<void> Function() reload) => _reloaders.add(reload);

  Future<void> _reload() async {
    for (final r in _reloaders) {
      await r();
    }
  }

  // ------------------------------------------------------------ session
  /// Call after every Firebase sign-in (and on app start when already signed in).
  Future<void> startSession(String uid) async {
    if (_uid == uid) return; // already started / in progress
    _uid = uid;
    try {
      // Different account than the one that owns the data on this device.
      final owner = state.ownerUid;
      if (owner != null && owner != uid) {
        await state.resetForNewOwner();
        await _reload();
      }
      await state.setOwnerUid(uid);

      final n = NotificationService.instance;
      await api.session(await devicePayload(
        deviceId: deviceId,
        fcmToken: n.token,
        notificationsEnabled: n.enabled,
      ));

      await _tokenSub?.cancel();
      _tokenSub = n.onTokenRefresh.listen((t) async {
        try {
          await api.registerToken(await devicePayload(
              deviceId: deviceId, fcmToken: t, notificationsEnabled: n.enabled));
        } catch (_) {}
      });

      lastError = null;
      notifyListeners();
      await syncAll();
    } on ApiException catch (e) {
      lastError = e.message;
      _uid = null; // allow a retry on the next sign-in event / app start
      notifyListeners();
    }
  }

  /// Call before signing out of Firebase (needs the still-valid token).
  Future<void> endSession() async {
    final n = NotificationService.instance;
    final token = (await devicePayload(
        deviceId: deviceId, fcmToken: n.token, notificationsEnabled: n.enabled))['fcmToken'] as String;
    await _tokenSub?.cancel();
    _tokenSub = null;
    try {
      await api.logout(token).timeout(const Duration(seconds: 8));
    } catch (_) {
      api.sessionReady = false;
    }
    _uid = null;
    notifyListeners();
  }

  // --------------------------------------------------------------- sync
  Future<void> syncAll() async {
    if (syncing || !api.sessionReady) return;
    syncing = true;
    lastError = null;
    notifyListeners();
    try {
      await _push();
      await _pull();
      lastSyncedAt = DateTime.now();
    } on ApiException catch (e) {
      lastError = e.message;
    } catch (e) {
      lastError = '$e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> _push() async {
    final dirtyTeams = state.dirty(SyncState.teams);
    final dirtyPlayers = state.dirty(SyncState.players);
    final dirtyMatches = state.dirty(SyncState.matches);
    final delTeams = state.deleted(SyncState.teams);
    final delPlayers = state.deleted(SyncState.players);
    final delMatches = state.deleted(SyncState.matches);
    if ([dirtyTeams, dirtyPlayers, dirtyMatches, delTeams, delPlayers, delMatches]
        .every((s) => s.isEmpty)) {
      return;
    }

    final teams = (await _teams.getAll()).where((t) => dirtyTeams.contains(t.id)).toList();
    final players = (await _players.getAll()).where((p) => dirtyPlayers.contains(p.id)).toList();
    final matches = (await _matches.getAll()).where((m) => dirtyMatches.contains(m.id)).toList();

    final res = await api.syncPush(
      teams: teams,
      players: players,
      matches: matches,
      deletedTeams: delTeams.toList(),
      deletedPlayers: delPlayers.toList(),
      deletedMatches: delMatches.toList(),
    );

    final rejected = <String, Set<String>>{};
    for (final r in (res['rejected'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(r as Map);
      final kind = switch (m['type']) {
        'team' => SyncState.teams,
        'player' => SyncState.players,
        _ => SyncState.matches,
      };
      (rejected[kind] ??= {}).add(m['id'] as String);
    }
    Set<String> ok(String kind, Iterable<String> ids) =>
        ids.where((i) => !(rejected[kind]?.contains(i) ?? false)).toSet();

    await state.clearDirty(SyncState.teams, ok(SyncState.teams, teams.map((t) => t.id)));
    await state.clearDirty(SyncState.players, ok(SyncState.players, players.map((p) => p.id)));
    await state.clearDirty(SyncState.matches, ok(SyncState.matches, matches.map((m) => m.id)));
    await state.clearDeleted(SyncState.teams, delTeams);
    await state.clearDeleted(SyncState.players, delPlayers);
    await state.clearDeleted(SyncState.matches, delMatches);
    for (final m in matches) {
      if (!(rejected[SyncState.matches]?.contains(m.id) ?? false)) {
        await state.setServerHasMatch(m.id, true);
      }
    }
  }

  Future<void> _pull() async {
    final r = await api.syncPull(since: state.lastSync);
    var changed = false;

    for (final j in r.teams) {
      await _teams.save(Team.fromJson(j));
      changed = true;
    }
    for (final j in r.players) {
      await _players.save(Player.fromJson(j));
      changed = true;
    }
    for (final j in r.matches) {
      final m = CricketMatch.fromJson(j);
      await _matches.save(m);
      await state.setServerHasMatch(m.id, true);
      changed = true;
    }
    for (final id in r.deletedTeams) {
      await _teams.delete(id);
      changed = true;
    }
    for (final id in r.deletedPlayers) {
      await _players.delete(id);
      changed = true;
    }
    for (final id in r.deletedMatches) {
      await _matches.delete(id);
      await state.setServerHasMatch(id, false);
      changed = true;
    }

    await state.setLastSync(r.serverTime);
    if (changed) await _reload();
  }

  /// Clears this device after the account was deleted.
  Future<void> wipeLocal() async {
    await _tokenSub?.cancel();
    await state.resetForNewOwner();
    _uid = null;
    api.sessionReady = false;
    await _reload();
    notifyListeners();
  }

  /// "Erase all data": removes everything on the server (one `sync/push` with
  /// every id in `deleted`) and on this device.
  Future<void> eraseEverything() async {
    if (api.sessionReady) {
      final teams = await _teams.getAll();
      final players = await _players.getAll();
      final matches = await _matches.getAll();
      await api.syncPush(
        teams: const [],
        players: const [],
        matches: const [],
        deletedTeams: [for (final t in teams) t.id],
        deletedPlayers: [for (final p in players) p.id],
        deletedMatches: [for (final m in matches) m.id],
      );
    }
    await state.resetForNewOwner();
    if (_uid != null) await state.setOwnerUid(_uid);
    await _reload();
    notifyListeners();
  }
}
