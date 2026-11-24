import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../data/api/live_scoring_sync.dart';
import '../domain/innings_summary.dart';
import '../domain/scoring_engine.dart';
import '../models/ball_event.dart';
import '../models/cricket_match.dart';
import '../models/innings.dart';
import 'matches_controller.dart';

/// Drives scoring for one match. All rules live in [ScoringEngine];
/// this class only sequences calls, persists and notifies.
class ScoringController extends ChangeNotifier {
  ScoringController(this.match, this._matches, {LiveScoringSync? live})
    : _live = live {
    if (match.innings.isEmpty) {
      ScoringEngine.startInnings(match, match.battingFirstId);
      _live?.startInnings(match, 1);
    }
  }

  final CricketMatch match;
  final MatchesController _matches;
  final LiveScoringSync? _live;

  int get _no => match.innings.length; // 1-based number of the current innings

  /// Pushes crease state / completion of the current innings to the server.
  void _syncCrease() => _live?.patchInnings(match, _no);

  Innings get innings => match.currentInnings!;
  InningsSummary get summary => InningsSummary(match, innings);
  bool get isSecondInnings => match.innings.length == 2;

  bool get needsBatter => ScoringEngine.needsBatter(match, innings);
  bool get needsBowler => ScoringEngine.needsBowler(innings);
  bool get canScore => ScoringEngine.canScore(match, innings);
  bool get inningsBreak =>
      match.isLive && innings.completed && match.innings.length == 1;

  /// Batters available to come in (not yet batted, not out, not at crease).
  List<String> get availableBatters {
    final s = summary;
    return s.yetToBat;
  }

  /// Bowlers from the fielding XI; excludes the bowler of the previous over.
  List<String> get availableBowlers {
    final all = match.squad(innings.bowlingTeamId);
    final last = innings.balls.isEmpty ? null : innings.balls.last.bowlerId;
    final justFinishedOver =
        innings.bowlerId == null && innings.balls.isNotEmpty;
    return all.where((id) => !(justFinishedOver && id == last)).toList();
  }

  Future<void> _commit() async {
    notifyListeners();
    await _matches.save(match);
  }

  Future<void> setOpeners(String striker, String nonStriker) {
    innings.strikerId = striker;
    innings.nonStrikerId = nonStriker;
    _syncCrease();
    return _commit();
  }

  Future<void> setNewBatter(String id) {
    if (innings.strikerId == null) {
      innings.strikerId = id;
    } else {
      innings.nonStrikerId = id;
    }
    _syncCrease();
    return _commit();
  }

  Future<void> setBowler(String id) {
    innings.bowlerId = id;
    _syncCrease();
    return _commit();
  }

  Future<void> swapStrike() {
    ScoringEngine.swapStrike(innings);
    _syncCrease();
    return _commit();
  }

  Future<void> recordBall({
    int runs = 0,
    ExtraType extra = ExtraType.none,
    int extraRuns = 0,
    WicketType? wicket,
    String? outPlayerId,
    String? fielderId,
    ShotDirection? shotDirection,
    List<Offset>? shotPath,
    ShotLoft? loft,
  }) {
    if (!canScore) return Future.value();
    final inn = innings;
    final ball = BallEvent(
      strikerId: inn.strikerId!,
      nonStrikerId: inn.nonStrikerId!,
      bowlerId: inn.bowlerId!,
      runs: runs,
      extra: extra,
      extraRuns: extra == ExtraType.wide || extra == ExtraType.noBall
          ? (extraRuns < 1 ? 1 : extraRuns)
          : extraRuns,
      wicket: wicket,
      outPlayerId: wicket == null ? null : (outPlayerId ?? inn.strikerId),
      fielderId: fielderId,
      shotDirection: shotDirection,
      shotPath: shotPath,
      loft: loft,
    );
    ScoringEngine.applyBall(inn, ball);
    _live?.addBall(match, _no);
    if (ScoringEngine.isInningsOver(match, inn)) {
      ScoringEngine.completeInnings(match, inn);
      _syncCrease(); // innings completed -> innings-end notification
      if (!match.isLive) _live?.complete(match); // match result notification
    } else {
      _syncCrease(); // new striker / bowler after the ball
    }
    return _commit();
  }

  Future<void> undo() {
    var inn = innings;
    var structural =
        false; // an innings was removed: no granular endpoint for that
    if (inn.balls.isEmpty && match.innings.length > 1) {
      match.innings.removeLast();
      inn = innings;
      structural = true;
    }
    var wasFinished = false;
    if (ScoringEngine.undo(inn)) {
      if (match.status != MatchStatus.live) {
        wasFinished = true;
        match.status = MatchStatus.live;
        match.winnerId = null;
        match.resultText = '';
      }
      if (structural || wasFinished) {
        _live?.resync(match);
      } else {
        _live?.undoLastBall(match, _no);
        _syncCrease();
      }
    }
    return _commit();
  }

  Future<void> startSecondInnings() {
    final first = match.innings.first;
    ScoringEngine.startInnings(match, first.bowlingTeamId);
    _live?.startInnings(match, _no);
    return _commit();
  }

  Future<void> endInningsEarly() {
    ScoringEngine.completeInnings(match, innings);
    _syncCrease();
    if (!match.isLive) _live?.complete(match);
    return _commit();
  }

  Future<void> endMatch() {
    ScoringEngine.endMatchNow(match);
    _live?.complete(match);
    return _commit();
  }

  // ===================================================== changes during the match

  /// Why [playerId] cannot be taken out of [teamId]'s playing XI (null = can be removed).
  /// A player who already batted, bowled, was dismissed or fielded stays: the scorecard needs him.
  String? removalBlockedReason(String teamId, String playerId) {
    final xi = match.squad(teamId);
    if (!xi.contains(playerId)) return 'Not in the playing XI';
    if (xi.length <= 2) return 'A team needs at least 2 players';
    for (final inn in match.innings) {
      if (inn.strikerId == playerId || inn.nonStrikerId == playerId) {
        return 'At the crease';
      }
      if (inn.bowlerId == playerId) return 'Bowling now';
      for (final b in inn.balls) {
        if (b.strikerId == playerId || b.nonStrikerId == playerId) {
          return 'Has already batted';
        }
        if (b.bowlerId == playerId) return 'Has already bowled';
        if (b.outPlayerId == playerId) return 'Was dismissed';
        if (b.fielderId == playerId) return 'Took part in a dismissal';
      }
    }
    // One player less is one wicket less: the batting side must not already be at that limit.
    final newMax = (xi.length - 2).clamp(1, 10);
    for (final inn in match.innings) {
      if (inn.battingTeamId == teamId && inn.wickets >= newMax) {
        return 'The innings would already be over';
      }
    }
    return null;
  }

  /// Players of [teamId] that are in the match squad but may not be removed are shown
  /// with [removalBlockedReason]. Returns false when nothing was changed.
  Future<bool> removeFromXi(String teamId, String playerId) async {
    if (!match.isLive || removalBlockedReason(teamId, playerId) != null) {
      return false;
    }
    match.squad(teamId).remove(playerId);
    match.playerNames.remove(playerId);
    _live?.resync(match);
    await _commit();
    return true;
  }

  /// Adds a player to [teamId]'s playing XI during the match. [name] is kept in the match
  /// so the scorecard stays readable. Returns false when the player is already playing.
  Future<bool> addToXi(String teamId, String playerId, String name) async {
    if (!match.isLive) return false;
    if (match.teamAPlayers.contains(playerId) ||
        match.teamBPlayers.contains(playerId)) {
      return false;
    }
    match.squad(teamId).add(playerId);
    match.playerNames[playerId] = name;
    _live?.resync(match);
    await _commit();
    return true;
  }

  /// The fewest overs the match can be changed to: the overs already bowled in any innings.
  int get minOvers {
    var bowled = 0;
    for (final inn in match.innings) {
      final o = (inn.legalBalls + 5) ~/ 6;
      if (o > bowled) bowled = o;
    }
    return bowled < 1 ? 1 : bowled;
  }

  /// Changes the number of overs of the match. Returns a short message about what happened, or null
  /// if the value is not allowed.
  ///
  /// * more overs: an innings that ended only because the old limit was reached is opened again
  /// * fewer overs: the innings (and the match, in the 2nd innings) ends if the new limit is reached
  Future<String?> changeOvers(int newOvers) async {
    if (!match.isLive || newOvers < minOvers || newOvers > 100) return null;
    final old = match.overs;
    if (newOvers == old) return 'The match is already $newOvers overs';
    match.overs = newOvers;

    var note = 'The match is now $newOvers overs';
    final inn = match.currentInnings;
    if (inn != null) {
      final endedByOldLimit = inn.completed && inn.legalBalls >= old * 6;
      if (endedByOldLimit && inn.legalBalls < newOvers * 6) {
        inn.completed = false;
        if (ScoringEngine.isInningsOver(match, inn)) {
          inn.completed =
              true; // still over for another reason (all out, target reached)
        } else {
          note = '$note. The innings carries on.';
        }
      } else if (!inn.completed && ScoringEngine.isInningsOver(match, inn)) {
        ScoringEngine.completeInnings(match, inn);
        note = match.isLive
            ? '$note. The innings is over.'
            : '$note. The match is over: ${match.resultText}';
      }
    }
    _live?.resync(match);
    if (!match.isLive) _live?.complete(match);
    await _commit();
    return note;
  }
}
