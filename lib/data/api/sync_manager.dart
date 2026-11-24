import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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
  }) : _teams = teams,
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

  /// A message the user has to read, for example a team the server refused because of the limit.
  String? notice;
  void clearNotice() {
    notice = null;
    notifyListeners();
  }

  DateTime? lastSyncedAt;
  String? lastError;
  bool get signedIn => api.sessionReady;

  // ------------------------------------------------------------ offline support
  // Every change is written to the device first and marked as "waiting" (see SyncState). This part sends
  // what is waiting as soon as the network is back: when the connection returns, when the app is opened
  // again, and every 15 seconds while something is waiting (with a growing pause after a failure).

  /// False while the device has no network.
  bool online = true;

  /// Changes (new / edited / deleted teams, players and matches) that are not on the server yet.
  int get pendingCount =>
      [SyncState.teams, SyncState.players, SyncState.matches]
          .map((k) => state.dirty(k).length + state.deleted(k).length)
          .fold(0, (a, b) => a + b);

  /// Pause before the next automatic attempt after [failures] failed attempts in a row: 30 s, 1 min, ... 5 min.
  static Duration backoff(int failures) =>
      Duration(seconds: math.min(300, 15 * (1 << math.min(failures, 5))));

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _timer;
  _ResumeObserver? _observer;
  String? _wantedUid; // the signed-in user whose session we keep alive
  int _failures = 0;
  DateTime? _nextAttempt;
  int _lastPending = -1;

  /// Start watching the network. Call once at app start.
  void startMonitoring() {
    if (_timer != null) return;
    _connectivity.checkConnectivity().then(_onConnectivity).catchError((_) {});
    _connSub = _connectivity.onConnectivityChanged.listen(_onConnectivity);
    _observer = _ResumeObserver(() {
      _failures = 0;
      _nextAttempt = null;
      unawaited(refreshDevice());
      unawaited(_kick());
    });
    WidgetsBinding.instance.addObserver(_observer!);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _timer?.cancel();
    if (_observer != null) WidgetsBinding.instance.removeObserver(_observer!);
    super.dispose();
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    final now =
        results.isNotEmpty &&
        !results.every((r) => r == ConnectivityResult.none);
    final was = online;
    online = now;
    api.online = now;
    notifyListeners();
    if (!was && now) {
      _failures = 0;
      _nextAttempt = null;
      unawaited(_kick()); // the network is back: send what is waiting
    }
  }

  void _tick() {
    final pending = pendingCount;
    if (pending != _lastPending) {
      _lastPending = pending;
      notifyListeners(); // keeps the "N changes waiting" counter fresh
    }
    final due = _nextAttempt == null || !DateTime.now().isBefore(_nextAttempt!);
    if (online &&
        due &&
        _wantedUid != null &&
        (pending > 0 || !api.sessionReady)) {
      unawaited(_kick());
    }
  }

  /// Tells the server about the current notification permission / token. The server only sends
  /// pushes to devices that said "notifications enabled", so this must follow the phone's settings.
  Future<void> refreshDevice({bool force = false}) async {
    final n = NotificationService.instance;
    final changed = await n.recheck();
    if ((!changed && !force) || !api.canSend) return;
    try {
      await api.registerToken(
        await devicePayload(
          deviceId: deviceId,
          fcmToken: n.token,
          notificationsEnabled: n.enabled,
        ),
      );
    } catch (_) {}
  }

  /// One automatic attempt: (re)start the session if it never started, otherwise sync.
  Future<void> _kick() async {
    final uid = _wantedUid;
    if (uid == null || !online || syncing) return;
    if (!api.sessionReady) {
      _uid = null; // allow startSession to run again
      await startSession(uid);
    } else {
      await syncAll();
    }
    if (lastError != null) {
      _failures++;
      _nextAttempt = DateTime.now().add(backoff(_failures));
    } else {
      _failures = 0;
      _nextAttempt = null;
    }
  }

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
    _wantedUid = uid;
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
      await api.session(
        await devicePayload(
          deviceId: deviceId,
          fcmToken: n.token,
          notificationsEnabled: n.enabled,
        ),
      );

      await _tokenSub?.cancel();
      _tokenSub = n.onTokenRefresh.listen((t) async {
        try {
          await api.registerToken(
            await devicePayload(
              deviceId: deviceId,
              fcmToken: t,
              notificationsEnabled: n.enabled,
            ),
          );
        } catch (_) {}
      });

      lastError = null;
      notifyListeners();
      await syncAll();
      await _reload(); // also loads the teams / matches I belong to
    } catch (e) {
      lastError = e is ApiException
          ? e.message
          : 'Could not start the session: $e';
      debugPrint('startSession failed: $e');
      _uid = null; // allow a retry on the next sign-in event / app start
      notifyListeners();
    }
  }

  /// Call before signing out of Firebase (needs the still-valid token).
  Future<void> endSession() async {
    final n = NotificationService.instance;
    final token =
        (await devicePayload(
              deviceId: deviceId,
              fcmToken: n.token,
              notificationsEnabled: n.enabled,
            ))['fcmToken']
            as String;
    await _tokenSub?.cancel();
    _tokenSub = null;
    try {
      await api.logout(token).timeout(const Duration(seconds: 8));
    } catch (_) {
      api.sessionReady = false;
    }
    _uid = null;
    _wantedUid = null;
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
    if ([
      dirtyTeams,
      dirtyPlayers,
      dirtyMatches,
      delTeams,
      delPlayers,
      delMatches,
    ].every((s) => s.isEmpty)) {
      return;
    }

    final teams = (await _teams.getAll())
        .where((t) => dirtyTeams.contains(t.id))
        .toList();
    final players = (await _players.getAll())
        .where((p) => dirtyPlayers.contains(p.id))
        .toList();
    final matches = (await _matches.getAll())
        .where((m) => dirtyMatches.contains(m.id))
        .toList();

    final res = await api.syncPush(
      teams: teams,
      players: players,
      matches: matches,
      deletedTeams: delTeams.toList(),
      deletedPlayers: delPlayers.toList(),
      deletedMatches: delMatches.toList(),
    );

    final rejected = <String, Set<String>>{};
    var needsReload = false;
    for (final r in (res['rejected'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(r as Map);
      final kind = switch (m['type']) {
        'team' => SyncState.teams,
        'player' => SyncState.players,
        _ => SyncState.matches,
      };
      if (m['reason'] == 'LIMIT_REACHED' &&
          (kind == SyncState.teams || kind == SyncState.players)) {
        // The server refused this item (3 teams, or 50 players). Make this device agree with it.
        final id = m['id'] as String;
        final isTeam = kind == SyncState.teams;
        try {
          // an existing item keeps the server's version
          if (isTeam) {
            await _teams.save(await api.team(id));
          } else {
            await _players.save(await api.player(id));
          }
        } catch (_) {
          // a new item that never made it
          if (isTeam) {
            await _teams.delete(id);
          } else {
            await _players.delete(id);
          }
        }
        notice =
            '${m['message'] ?? 'A limit was reached'} The ${isTeam ? 'team' : 'player'} was not saved.';
        needsReload = true;
        continue;
      }
      if (m['reason'] == 'FORBIDDEN' && kind == SyncState.players) {
        // e.g. a registered user's player edited on this device: the server's copy wins.
        try {
          await _players.save(await api.player(m['id'] as String));
        } catch (_) {}
        continue; // not "rejected": it is settled, so the dirty flag is cleared below
      }
      (rejected[kind] ??= {}).add(m['id'] as String);
    }
    Set<String> ok(String kind, Iterable<String> ids) =>
        ids.where((i) => !(rejected[kind]?.contains(i) ?? false)).toSet();

    await state.clearDirty(
      SyncState.teams,
      ok(SyncState.teams, teams.map((t) => t.id)),
    );
    await state.clearDirty(
      SyncState.players,
      ok(SyncState.players, players.map((p) => p.id)),
    );
    await state.clearDirty(
      SyncState.matches,
      ok(SyncState.matches, matches.map((m) => m.id)),
    );
    await state.clearDeleted(SyncState.teams, delTeams);
    await state.clearDeleted(SyncState.players, delPlayers);
    await state.clearDeleted(SyncState.matches, delMatches);
    for (final m in matches) {
      if (!(rejected[SyncState.matches]?.contains(m.id) ?? false)) {
        await state.setServerHasMatch(m.id, true);
      }
    }
    if (needsReload) await _reload();
  }

  Future<void> _pull() async {
    final r = await api.syncPull(since: state.lastSync);
    var changed = false;

    // Anything still waiting here is newer than the server's copy (it could not be sent, or it was
    // changed while syncing): keep the local version and send it next time.
    final waitingTeams = state.dirty(SyncState.teams);
    final waitingPlayers = state.dirty(SyncState.players);
    final waitingMatches = state.dirty(SyncState.matches);

    for (final j in r.teams) {
      final t = Team.fromJson(j);
      if (waitingTeams.contains(t.id)) continue;
      await _teams.save(t);
      changed = true;
    }
    for (final j in r.players) {
      final p = Player.fromJson(j);
      if (waitingPlayers.contains(p.id)) continue;
      await _players.save(p);
      changed = true;
    }
    for (final j in r.matches) {
      final m = CricketMatch.fromJson(j);
      if (waitingMatches.contains(m.id)) continue;
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
    _wantedUid = null;
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

/// Tells the SyncManager when the app comes back to the foreground.
class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this._onResume);
  final VoidCallback _onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResume();
  }
}
