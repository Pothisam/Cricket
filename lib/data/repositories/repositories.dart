import '../../models/cricket_match.dart';
import '../../models/player.dart';
import '../../models/team.dart';

/// Contracts used by state management. Local implementations live in
/// `local_repositories.dart`; an API-backed (or cache + API) implementation
/// can be dropped in later by changing only `AppDependencies`.
abstract class TeamRepository {
  Future<List<Team>> getAll();
  Future<void> save(Team team);
  Future<void> delete(String id);
}

abstract class PlayerRepository {
  Future<List<Player>> getAll();
  Future<void> save(Player player);
  Future<void> delete(String id);
}

abstract class MatchRepository {
  Future<List<CricketMatch>> getAll();
  Future<void> save(CricketMatch match);
  Future<void> delete(String id);
}

/// Wipes all data (used by "reset" in settings).
abstract class DataMaintenance {
  Future<void> clearAll();
}
