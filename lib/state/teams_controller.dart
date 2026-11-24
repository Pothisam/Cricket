import 'package:flutter/foundation.dart';

import '../core/ids.dart';
import '../data/repositories/repositories.dart';
import '../models/player.dart';
import '../models/team.dart';

/// Thrown when a team cannot be created or made public because of the per-user limit.
class TeamLimitException implements Exception {
  TeamLimitException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown when a player cannot be added because the list is full (50 players).
class PlayerLimitException implements Exception {
  PlayerLimitException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TeamsController extends ChangeNotifier {
  TeamsController(this._teamRepo, this._playerRepo);

  final TeamRepository _teamRepo;
  final PlayerRepository _playerRepo;

  /// A user can own 3 teams: 1 public and 2 private (a duplicate counts as a team).
  /// A user's player list holds up to 50 players.
  static const maxPlayers = 50;

  static const playerLimitMessage =
      'You can add up to $maxPlayers players. Remove a player to add a new one.';

  int get playerCount => players.length;
  int get playersLeft => (maxPlayers - players.length).clamp(0, maxPlayers);
  bool get canAddPlayer => players.length < maxPlayers;

  static const maxTeams = 3;
  static const maxPublic = 1;
  static const maxPrivate = maxTeams - maxPublic;

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

  int get publicCount => teams.where((t) => t.isPublic).length;
  bool get canCreateTeam => teams.length < maxTeams;

  /// Shown when the limit is reached.
  static const limitMessage =
      'You can have up to $maxTeams teams ($maxPublic public and $maxPrivate private). '
      'Delete a team to create a new one.';

  /// Why a NEW team cannot be created (null = allowed).
  String? creationBlockedReason({required bool isPublic}) {
    if (teams.length >= maxTeams) return limitMessage;
    if (isPublic && publicCount >= maxPublic) {
      return 'Only $maxPublic team can be public. Make your other public team private first.';
    }
    if (!isPublic && teams.length - publicCount >= maxPrivate) {
      return 'You can have up to $maxPrivate private teams. Make a team public (only $maxPublic can be) or delete one.';
    }
    return null;
  }

  /// Why [t] cannot change its visibility (null = allowed). Teams that exist already are never touched.
  String? visibilityBlockedReason(Team t, bool wantsPublic) {
    if (wantsPublic == t.isPublic) return null;
    final others = teams.where((x) => x.id != t.id);
    if (wantsPublic && others.where((x) => x.isPublic).length >= maxPublic) {
      return 'Only $maxPublic team can be public. Make your other public team private first.';
    }
    if (!wantsPublic && others.where((x) => !x.isPublic).length >= maxPrivate) {
      return 'You can have up to $maxPrivate private teams. Delete one first.';
    }
    return null;
  }

  Future<Team> addTeam(
    String name,
    String shortName,
    int colorIndex, {
    bool isPublic = false,
  }) async {
    final blocked = creationBlockedReason(isPublic: isPublic);
    if (blocked != null) throw TeamLimitException(blocked);
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
    final blocked = creationBlockedReason(isPublic: false);
    if (blocked != null) throw TeamLimitException(blocked);
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
    if (!canAddPlayer) throw PlayerLimitException(playerLimitMessage);
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
      _clearRoles(t, p.id);
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
    _clearRoles(t, playerId);
    await _teamRepo.save(t);
    notifyListeners();
  }

  void _clearRoles(Team t, String playerId) {
    if (t.captainPlayerId == playerId) t.captainPlayerId = null;
    if (t.viceCaptainPlayerId == playerId) t.viceCaptainPlayerId = null;
  }

  /// Captain of this team. Pass null to take the role away. A player cannot be both.
  Future<void> setCaptain(Team t, String? playerId) async {
    if (playerId != null && t.viceCaptainPlayerId == playerId) {
      t.viceCaptainPlayerId = null;
    }
    t.captainPlayerId = playerId;
    await _teamRepo.save(t);
    notifyListeners();
  }

  Future<void> setViceCaptain(Team t, String? playerId) async {
    if (playerId != null && t.captainPlayerId == playerId) {
      t.captainPlayerId = null;
    }
    t.viceCaptainPlayerId = playerId;
    await _teamRepo.save(t);
    notifyListeners();
  }

  /// Moves a player in the batting order. Indexes are those of the shown squad list
  /// ([newIndex] is the position after the player was taken out, as ReorderableListView.onReorderItem gives it).
  Future<void> moveInSquad(Team t, int oldIndex, int newIndex) async {
    final ids = playersOf(t).map((p) => p.id).toList();
    if (oldIndex < 0 || oldIndex >= ids.length) return;
    ids.insert(newIndex.clamp(0, ids.length - 1), ids.removeAt(oldIndex));
    t.playerIds
      ..clear()
      ..addAll(ids);
    await _teamRepo.save(t);
    notifyListeners();
  }
}
