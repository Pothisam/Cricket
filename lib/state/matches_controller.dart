import 'package:flutter/foundation.dart';

import '../data/repositories/repositories.dart';
import '../domain/stats_service.dart';
import '../models/cricket_match.dart';

class MatchesController extends ChangeNotifier {
  MatchesController(this._repo);

  final MatchRepository _repo;
  List<CricketMatch> matches = [];
  CricketStats? _stats;

  Future<void> load() async {
    matches = await _repo.getAll()
      ..sort((a, b) => b.date.compareTo(a.date));
    _stats = null;
    notifyListeners();
  }

  CricketStats get stats => _stats ??= CricketStats(matches);

  List<CricketMatch> get live => matches.where((m) => m.isLive).toList();
  List<CricketMatch> get finished => matches.where((m) => !m.isLive).toList();

  CricketMatch? byId(String id) {
    for (final m in matches) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> add(CricketMatch m) async {
    matches.insert(0, m);
    await save(m);
  }

  /// Persist after the match object was mutated in place.
  Future<void> save(CricketMatch m) async {
    _stats = null;
    notifyListeners();
    await _repo.save(m);
  }

  Future<void> delete(CricketMatch m) async {
    matches.remove(m);
    _stats = null;
    notifyListeners();
    await _repo.delete(m.id);
  }
}
