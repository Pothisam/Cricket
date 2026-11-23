import 'package:flutter/foundation.dart';

import '../core/ids.dart';
import '../data/repositories/repositories.dart';
import '../models/player.dart';
import '../models/team.dart';

class TeamsController extends ChangeNotifier {
  TeamsController(this._teamRepo, this._playerRepo);

  final TeamRepository _teamRepo;
  final PlayerRepository _playerRepo;

  List<Team> teams = [];
  List<Player> players = [];
  bool loaded = false;

  Future<void> load() async {
    teams = await _teamRepo.getAll();
    players = await _playerRepo.getAll();
    loaded = true;
    notifyListeners();
  }

  Team? teamById(String id) {
    for (final t in teams) {
      if (t.id == id) return t;
    }
    return null;
  }

  Player? playerById(String id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<Player> playersOf(Team t) => [
    for (final id in t.playerIds)
      if (playerById(id) != null) playerById(id)!,
  ];

  List<Team> teamsOfPlayer(String playerId) =>
      teams.where((t) => t.playerIds.contains(playerId)).toList();

  Future<Team> addTeam(
    String name,
    String shortName,
    int colorIndex, {
    bool isPublic = false,
  }) async {
    final t = Team(
      id: newId(),
      name: name.trim(),
      shortName: shortName.trim().toUpperCase(),
      colorIndex: colorIndex,
      isPublic: isPublic,
    );
    teams.add(t);
    await _teamRepo.save(t);
    notifyListeners();
    return t;
  }

  /// A copy of [t] (same short name, colour and players) that is added below the others.
  /// The copy is private, even if the original is public, and is named "<name> (copy)".
  Future<Team> duplicateTeam(Team t) async {
    const suffix = ' (copy)';
    final base = t.name.length + suffix.length > 80
        ? t.name.substring(0, 80 - suffix.length)
        : t.name;
    final copy = Team(
      id: newId(),
      name: '$base$suffix',
      shortName: t.shortName,
      colorIndex: t.colorIndex,
      playerIds: [...t.playerIds],
    );
    teams.add(copy);
    await _teamRepo.save(copy);
    notifyListeners();
    return copy;
  }

  Future<void> updateTeam(Team t) async {
    await _teamRepo.save(t);
    notifyListeners();
  }

  Future<void> deleteTeam(Team t) async {
    teams.remove(t);
    await _teamRepo.delete(t.id);
    notifyListeners();
  }

  /// Creates a player and optionally adds them to [team].
  Future<Player> addPlayer(Player p, {Team? team}) async {
    players.add(p);
    await _playerRepo.save(p);
    if (team != null) await addToTeam(team, p.id, notify: false);
    notifyListeners();
    return p;
  }

  Future<void> updatePlayer(Player p) async {
    await _playerRepo.save(p);
    notifyListeners();
  }

  Future<void> deletePlayer(Player p) async {
    players.remove(p);
    await _playerRepo.delete(p.id);
    for (final t in teams.where((t) => t.playerIds.remove(p.id))) {
      await _teamRepo.save(t);
    }
    notifyListeners();
  }

  Future<void> addToTeam(Team t, String playerId, {bool notify = true}) async {
    if (!t.playerIds.contains(playerId)) t.playerIds.add(playerId);
    await _teamRepo.save(t);
    if (notify) notifyListeners();
  }

  Future<void> removeFromTeam(Team t, String playerId) async {
    t.playerIds.remove(playerId);
    await _teamRepo.save(t);
    notifyListeners();
  }
}
