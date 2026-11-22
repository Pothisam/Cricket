import '../../models/ball_event.dart';
import '../../models/cricket_match.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import 'api_client.dart';
import 'api_models.dart';

typedef Json = Map<String, dynamic>;

/// One method per backend endpoint (see docs/BACKEND_API_SPEC.md).
/// All paths are relative to ApiConfig.baseUrl (/CricketAPI/api/v1).
class CricketApi {
  CricketApi(this.client);

  final ApiClient client;

  /// True once `POST /auth/session` succeeded for the current sign-in.
  /// Data endpoints answer 401 before that.
  bool sessionReady = false;

  static Json matchJson(CricketMatch m) =>
      m.toJson()..['date'] = m.date.toUtc().toIso8601String();

  static Json _map(dynamic v) => Map<String, dynamic>.from(v as Map);
  static List<Json> _items(dynamic v) =>
      [for (final e in (v['items'] as List? ?? const [])) _map(e)];

  // ---------------------------------------------------------------- misc
  Future<bool> health() async {
    final r = await client.get('/health', auth: false);
    return r is Map && r['status'] == 'ok';
  }

  Future<ServerConfig> config() async =>
      ServerConfig.fromJson(_map(await client.get('/config', auth: false)));

  Future<void> feedback(String message, {String? appVersion}) =>
      client.post('/feedback', body: {'message': message, 'appVersion': appVersion});

  // ---------------------------------------------------------------- auth
  Future<SessionResult> session(Json deviceInfo) async {
    final r = SessionResult.fromJson(_map(await client.post('/auth/session', body: deviceInfo)));
    sessionReady = true;
    return r;
  }

  Future<void> logout(String fcmToken) async {
    try {
      await client.post('/auth/logout', body: {'fcmToken': fcmToken});
    } finally {
      sessionReady = false;
    }
  }

  Future<ApiUser> me() async => ApiUser.fromJson(_map(await client.get('/me')));

  Future<ApiUser> updateMe({String? displayName, String? photoUrl}) async =>
      ApiUser.fromJson(_map(await client.patch('/me', body: {
        if (displayName != null) 'displayName': displayName,
        if (photoUrl != null) 'photoUrl': photoUrl,
      })));

  Future<void> deleteMe() async {
    await client.delete('/me');
    sessionReady = false;
  }

  // ------------------------------------------------------------- devices
  Future<void> registerToken(Json deviceInfo) => client.put('/devices/token', body: deviceInfo);

  Future<List<ApiDevice>> devices() async =>
      [for (final j in _items(await client.get('/devices'))) ApiDevice.fromJson(j)];

  Future<ApiDevice> updateDevice(int id, {required bool notificationsEnabled}) async =>
      ApiDevice.fromJson(_map(
          await client.patch('/devices/$id', body: {'notificationsEnabled': notificationsEnabled})));

  Future<void> deleteDevice(int id) => client.delete('/devices/$id');

  // --------------------------------------------------------------- teams
  Future<List<Team>> teams({DateTime? updatedSince}) async => [
        for (final j in _items(await client.get('/teams', query: {
          'limit': '200',
          'updatedSince': updatedSince?.toUtc().toIso8601String(),
        })))
          Team.fromJson(j)
      ];

  Future<Team> team(String id) async => Team.fromJson(_map(await client.get('/teams/$id')));

  Future<Team> putTeam(Team t) async =>
      Team.fromJson(_map(await client.put('/teams/${t.id}', body: t.toJson())));

  Future<void> deleteTeam(String id) => client.delete('/teams/$id');

  Future<TeamStats> teamStats(String id) async =>
      TeamStats.fromJson(_map(await client.get('/teams/$id/stats')));

  // ------------------------------------------------------------- players
  Future<List<Player>> players({DateTime? updatedSince}) async => [
        for (final j in _items(await client.get('/players', query: {
          'limit': '200',
          'updatedSince': updatedSince?.toUtc().toIso8601String(),
        })))
          Player.fromJson(j)
      ];

  Future<Player> player(String id) async => Player.fromJson(_map(await client.get('/players/$id')));

  Future<Player> putPlayer(Player p) async =>
      Player.fromJson(_map(await client.put('/players/${p.id}', body: p.toJson())));

  Future<void> deletePlayer(String id) => client.delete('/players/$id');

  Future<PlayerStats> playerStats(String id) async =>
      PlayerStats.fromJson(_map(await client.get('/players/$id/stats')));

  // ------------------------------------------------------------- matches
  Future<List<MatchSummary>> matchSummaries({String? status, DateTime? updatedSince}) async => [
        for (final j in _items(await client.get('/matches', query: {
          'status': status,
          'limit': '200',
          'updatedSince': updatedSince?.toUtc().toIso8601String(),
        })))
          MatchSummary.fromJson(j)
      ];

  Future<List<CricketMatch>> matchesFull({String? status}) async => [
        for (final j in _items(
            await client.get('/matches', query: {'full': 'true', 'status': status, 'limit': '200'})))
          CricketMatch.fromJson(j)
      ];

  Future<CricketMatch> match(String id) async =>
      CricketMatch.fromJson(_map(await client.get('/matches/$id')));

  Future<void> putMatch(CricketMatch m) => client.put('/matches/${m.id}', body: matchJson(m));

  Future<void> deleteMatch(String id) => client.delete('/matches/$id');

  // ----------------------------------------------------- live scoring
  Future<void> startInnings(String matchId,
          {required int inningsNo, required String battingTeamId, required String bowlingTeamId}) =>
      client.post('/matches/$matchId/innings', body: {
        'inningsNo': inningsNo,
        'battingTeamId': battingTeamId,
        'bowlingTeamId': bowlingTeamId,
      });

  Future<void> patchInnings(String matchId, int inningsNo,
          {String? striker, String? nonStriker, String? bowler, bool? completed}) =>
      client.patch('/matches/$matchId/innings/$inningsNo', body: {
        if (striker != null) 'striker': striker,
        if (nonStriker != null) 'nonStriker': nonStriker,
        if (bowler != null) 'bowler': bowler,
        if (completed != null) 'completed': completed,
      });

  /// [seq] is the 0-based position of the ball in the innings.
  Future<LiveInningsTotals> addBall(String matchId, int inningsNo, int seq, BallEvent b) async {
    final r = _map(await client.post('/matches/$matchId/innings/$inningsNo/balls',
        body: b.toJson()..['seq'] = seq));
    return LiveInningsTotals.fromJson(_map(r['innings']));
  }

  Future<LiveInningsTotals> undoLastBall(String matchId, int inningsNo) async {
    final r = _map(await client.delete('/matches/$matchId/innings/$inningsNo/balls/last'));
    return LiveInningsTotals.fromJson(_map(r['innings']));
  }

  Future<void> completeMatch(String matchId,
          {required MatchStatus status, String? winnerId, String? resultText}) =>
      client.post('/matches/$matchId/complete', body: {
        'status': status.name,
        'winnerId': winnerId,
        'resultText': resultText,
      });

  // ------------------------------------------------------ sharing / follow
  Future<ShareInfo> share(String matchId, {String visibility = 'link'}) async =>
      ShareInfo.fromJson(_map(await client.post('/matches/$matchId/share', body: {'visibility': visibility})));

  Future<void> unshare(String matchId) => client.delete('/matches/$matchId/share');

  Future<MatchSummary> follow(String shareCode) async =>
      MatchSummary.fromJson(_map(await client.post('/matches/follow', body: {'shareCode': shareCode})));

  Future<void> unfollow(String ownerId, String matchId) =>
      client.delete('/matches/$ownerId/$matchId/follow');

  Future<List<MatchSummary>> following() async =>
      [for (final j in _items(await client.get('/following'))) MatchSummary.fromJson(j)];

  /// Anonymous read-only view of a shared match.
  Future<CricketMatch> publicMatch(String shareCode) async =>
      CricketMatch.fromJson(_map(await client.get('/public/matches/$shareCode', auth: false)));

  // ----------------------------------------------------------------- sync
  Future<Json> syncPush({
    required List<Team> teams,
    required List<Player> players,
    required List<CricketMatch> matches,
    List<String> deletedTeams = const [],
    List<String> deletedPlayers = const [],
    List<String> deletedMatches = const [],
  }) async =>
      _map(await client.post('/sync/push', body: {
        'teams': [for (final t in teams) t.toJson()],
        'players': [for (final p in players) p.toJson()],
        'matches': [for (final m in matches) matchJson(m)],
        'deleted': {'teams': deletedTeams, 'players': deletedPlayers, 'matches': deletedMatches},
      }));

  Future<SyncPullResult> syncPull({String? since}) async {
    final r = _map(await client.get('/sync/pull', query: {'since': since}));
    final d = _map(r['deleted'] ?? const {});
    List<Json> list(String k) => [for (final e in (r[k] as List? ?? const [])) _map(e)];
    List<String> ids(String k) => [for (final e in (d[k] as List? ?? const [])) e as String];
    return SyncPullResult(
      teams: list('teams'),
      players: list('players'),
      matches: list('matches'),
      deletedTeams: ids('teams'),
      deletedPlayers: ids('players'),
      deletedMatches: ids('matches'),
      serverTime: r['serverTime'] as String,
    );
  }

  // --------------------------------------------------------- notifications
  Future<Inbox> inbox({bool unreadOnly = false, int limit = 50, String? cursor}) async {
    final r = _map(await client.get('/notifications', query: {
      'unreadOnly': unreadOnly ? 'true' : null,
      'limit': '$limit',
      'cursor': cursor,
    }));
    return Inbox(
      [for (final j in _items(r)) ApiNotification.fromJson(j)],
      r['unreadCount'] as int? ?? 0,
      r['nextCursor'] as String?,
    );
  }

  Future<void> markRead(int id) => client.post('/notifications/$id/read');
  Future<void> markAllRead() => client.post('/notifications/read-all');
  Future<void> deleteNotification(int id) => client.delete('/notifications/$id');

  Future<NotificationPrefs> preferences() async =>
      NotificationPrefs.fromJson(_map(await client.get('/notifications/preferences')));

  Future<NotificationPrefs> savePreferences(NotificationPrefs p) async =>
      NotificationPrefs.fromJson(_map(await client.put('/notifications/preferences', body: p.toJson())));

  /// Returns (sent, failed).
  Future<(int, int)> sendTest({String title = 'Test', String body = 'Hello from Cricket Scorer'}) async {
    final r = _map(await client.post('/notifications/test', body: {'title': title, 'body': body}));
    return (r['sent'] as int? ?? 0, r['failed'] as int? ?? 0);
  }

  /// Admin only (Firebase custom claim `admin: true`).
  Future<void> broadcast(String title, String body, {String topic = 'all'}) =>
      client.post('/admin/notifications/broadcast', body: {'title': title, 'body': body, 'topic': topic});
}
