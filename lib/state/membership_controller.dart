import 'package:flutter/foundation.dart';

import '../data/api/api_models.dart';
import '../data/api/cricket_api.dart';

/// Teams I was added to and matches I played in, created by other scorers.
/// Read only and fetched from the server (`/me/joined-teams`, `/me/matches`).
class MembershipController extends ChangeNotifier {
  MembershipController(this._api);

  final CricketApi? _api;

  List<JoinedTeam> teams = [];
  List<MatchSummary> matches = [];
  bool loading = false;
  String? error;

  Future<void> load() async {
    final api = _api;
    if (api == null) return;
    if (!api.sessionReady) {
      // signed out (or not connected yet): do not show another account's data
      if (teams.isNotEmpty || matches.isNotEmpty) clear();
      return;
    }
    loading = true;
    notifyListeners();
    try {
      final t = await api.joinedTeams();
      final m = await api.myMatches();
      teams = t;
      matches = m;
      error = null;
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Matches of one joined team (same scorer and team).
  List<MatchSummary> matchesOf(JoinedTeam t) =>
      matches.where((m) => m.ownerId == t.ownerId && (m.teamAId == t.teamId || m.teamBId == t.teamId)).toList();

  void clear() {
    teams = [];
    matches = [];
    notifyListeners();
  }
}
