import '../../models/cricket_match.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../sources/local_store.dart';
import 'repositories.dart';

/// Generic "list of JSON docs keyed by id" helper over [LocalStore].
class _Collection<T> {
  _Collection(this._store, this._key, this._from, this._to, this._id);

  final LocalStore _store;
  final String _key;
  final T Function(Map<String, dynamic>) _from;
  final Map<String, dynamic> Function(T) _to;
  final String Function(T) _id;

  Future<List<T>> getAll() async => (await _store.readList(_key)).map(_from).toList();

  Future<void> save(T item) async {
    final all = await getAll();
    final i = all.indexWhere((e) => _id(e) == _id(item));
    if (i >= 0) {
      all[i] = item;
    } else {
      all.add(item);
    }
    await _store.writeList(_key, all.map(_to).toList());
  }

  Future<void> delete(String id) async {
    final all = await getAll()
      ..removeWhere((e) => _id(e) == id);
    await _store.writeList(_key, all.map(_to).toList());
  }
}

class LocalTeamRepository implements TeamRepository {
  LocalTeamRepository(LocalStore s)
      : _c = _Collection(s, 'teams', Team.fromJson, (t) => t.toJson(), (t) => t.id);
  final _Collection<Team> _c;

  @override
  Future<List<Team>> getAll() => _c.getAll();
  @override
  Future<void> save(Team team) => _c.save(team);
  @override
  Future<void> delete(String id) => _c.delete(id);
}

class LocalPlayerRepository implements PlayerRepository {
  LocalPlayerRepository(LocalStore s)
      : _c = _Collection(s, 'players', Player.fromJson, (p) => p.toJson(), (p) => p.id);
  final _Collection<Player> _c;

  @override
  Future<List<Player>> getAll() => _c.getAll();
  @override
  Future<void> save(Player player) => _c.save(player);
  @override
  Future<void> delete(String id) => _c.delete(id);
}

class LocalMatchRepository implements MatchRepository {
  LocalMatchRepository(LocalStore s)
      : _c = _Collection(
            s, 'matches', CricketMatch.fromJson, (m) => m.toJson(), (m) => m.id);
  final _Collection<CricketMatch> _c;

  @override
  Future<List<CricketMatch>> getAll() => _c.getAll();
  @override
  Future<void> save(CricketMatch match) => _c.save(match);
  @override
  Future<void> delete(String id) => _c.delete(id);
}

class LocalDataMaintenance implements DataMaintenance {
  LocalDataMaintenance(this._store);
  final LocalStore _store;

  @override
  Future<void> clearAll() => _store.clear();
}
