import 'dart:async';

import '../../models/cricket_match.dart';
import '../repositories/synced_repositories.dart';
import 'api_client.dart';
import 'cricket_api.dart';
import 'sync_state.dart';

/// Mirrors scoring actions to the granular live endpoints. These endpoints are
/// also what triggers the push notifications (match start, four, six, wicket,
/// milestone, innings end, match result).
///
/// Calls run strictly one after another. If one fails (offline, sequence gap)
/// the whole match is re-sent with `PUT /matches/{id}` so the server catches up.
class LiveScoringSync {
  LiveScoringSync(this._api, this._state, this._matches);

  final CricketApi _api;
  final SyncState _state;
  final SyncedMatchRepository _matches;

  Future<void> _tail = Future.value();

  void _enqueue(CricketMatch m, Future<void> Function() op) {
    _tail = _tail.then((_) async {
      if (!_api.sessionReady) return;
      try {
        if (!_state.serverHasMatch(m.id) && !await _matches.putNow(m)) return;
        await op();
      } on ApiException catch (e) {
        if (e.isUnauthenticated) return;
        await _matches.putNow(m); // resync everything; notifications for this step are skipped
      } catch (_) {}
    });
  }

  void startInnings(CricketMatch m, int inningsNo) {
    final inn = m.innings[inningsNo - 1];
    _enqueue(
      m,
      () => _api.startInnings(m.id,
          inningsNo: inningsNo, battingTeamId: inn.battingTeamId, bowlingTeamId: inn.bowlingTeamId),
    );
  }

  /// Current batters / bowler and the `completed` flag of an innings.
  void patchInnings(CricketMatch m, int inningsNo) {
    final inn = m.innings[inningsNo - 1];
    _enqueue(
      m,
      () => _api.patchInnings(m.id, inningsNo,
          striker: inn.strikerId,
          nonStriker: inn.nonStrikerId,
          bowler: inn.bowlerId,
          completed: inn.completed),
    );
  }

  void addBall(CricketMatch m, int inningsNo) {
    final inn = m.innings[inningsNo - 1];
    final seq = inn.balls.length - 1;
    final ball = inn.balls.last;
    _enqueue(m, () => _api.addBall(m.id, inningsNo, seq, ball).then((_) {}));
  }

  void undoLastBall(CricketMatch m, int inningsNo) =>
      _enqueue(m, () => _api.undoLastBall(m.id, inningsNo).then((_) {}));

  void complete(CricketMatch m) => _enqueue(
        m,
        () async {
          await _api.completeMatch(m.id,
              status: m.status, winnerId: m.winnerId, resultText: m.resultText);
          await _state.clearDirty(SyncState.matches, [m.id]);
        },
      );

  /// Full re-upload (used after structural changes that have no granular endpoint).
  void resync(CricketMatch m) => _enqueue(m, () => _matches.putNow(m).then((_) {}));
}
