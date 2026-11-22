import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Small prefs-backed bookkeeping for cloud sync: which rows still need to be
/// pushed, which deletes are pending, last pull time and the account that owns
/// the data on this device.
class SyncState {
  SyncState(this._p);

  final SharedPreferences _p;

  static const teams = 'teams';
  static const players = 'players';
  static const matches = 'matches';

  Set<String> _set(String key) => (_p.getStringList(key) ?? const []).toSet();
  Future<void> _save(String key, Set<String> v) =>
      _p.setStringList(key, v.toList());

  Set<String> dirty(String kind) => _set('sync_dirty_$kind');
  Set<String> deleted(String kind) => _set('sync_deleted_$kind');

  Future<void> markDirty(String kind, String id) async {
    await _save('sync_dirty_$kind', dirty(kind)..add(id));
    await _save('sync_deleted_$kind', deleted(kind)..remove(id));
  }

  Future<void> clearDirty(String kind, Iterable<String> ids) =>
      _save('sync_dirty_$kind', dirty(kind)..removeAll(ids));

  Future<void> markDeleted(String kind, String id) async {
    await _save('sync_dirty_$kind', dirty(kind)..remove(id));
    await _save('sync_deleted_$kind', deleted(kind)..add(id));
  }

  Future<void> clearDeleted(String kind, Iterable<String> ids) =>
      _save('sync_deleted_$kind', deleted(kind)..removeAll(ids));

  /// Match ids the server already has (so live scoring can use the granular endpoints).
  bool serverHasMatch(String id) => _set('sync_server_matches').contains(id);
  Future<void> setServerHasMatch(String id, bool has) {
    final s = _set('sync_server_matches');
    has ? s.add(id) : s.remove(id);
    return _save('sync_server_matches', s);
  }

  String? get lastSync => _p.getString('sync_last');
  Future<void> setLastSync(String? v) =>
      v == null ? _p.remove('sync_last') : _p.setString('sync_last', v);

  String? get ownerUid => _p.getString('sync_owner');
  Future<void> setOwnerUid(String? v) =>
      v == null ? _p.remove('sync_owner') : _p.setString('sync_owner', v);

  bool get hasPending => [
    teams,
    players,
    matches,
  ].any((k) => dirty(k).isNotEmpty || deleted(k).isNotEmpty);

  /// Stable random id for this install (sent as `X-Device-Id` / `deviceId`).
  static String deviceIdOf(SharedPreferences p) {
    var id = p.getString('device_id');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(
        16,
        (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      p.setString('device_id', id);
    }
    return id;
  }

  /// Everything except the device id (used when a different account signs in).
  Future<void> resetForNewOwner() async {
    final id = _p.getString('device_id');
    await _p.clear();
    if (id != null) await _p.setString('device_id', id);
  }
}
