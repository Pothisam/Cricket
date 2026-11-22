import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Low-level local persistence. Repositories depend on this interface only.
abstract class LocalStore {
  Future<List<Map<String, dynamic>>> readList(String key);
  Future<void> writeList(String key, List<Map<String, dynamic>> items);
  Future<void> clear();
}

class SharedPrefsStore implements LocalStore {
  SharedPrefsStore(this._prefs);
  final SharedPreferences _prefs;

  @override
  Future<List<Map<String, dynamic>>> readList(String key) async {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  Future<void> writeList(String key, List<Map<String, dynamic>> items) =>
      _prefs.setString(key, jsonEncode(items));

  @override
  Future<void> clear() => _prefs.clear();
}

/// In-memory store, handy for tests.
class MemoryStore implements LocalStore {
  final Map<String, List<Map<String, dynamic>>> _data = {};

  @override
  Future<List<Map<String, dynamic>>> readList(String key) async =>
      (_data[key] ?? []).map((e) => Map<String, dynamic>.from(e)).toList();

  @override
  Future<void> writeList(String key, List<Map<String, dynamic>> items) async =>
      _data[key] = items;

  @override
  Future<void> clear() async => _data.clear();
}
