/// Response models for endpoints that are not already covered by the app's own
/// Team / Player / CricketMatch models (those use their own toJson / fromJson).

DateTime? _dt(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

class ApiUser {
  ApiUser.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        email = j['email'] as String?,
        phoneNumber = j['phoneNumber'] as String?,
        displayName = j['displayName'] as String?,
        photoUrl = j['photoUrl'] as String?,
        authProvider = j['authProvider'] as String? ?? '',
        createdAt = _dt(j['createdAt']),
        lastLoginAt = _dt(j['lastLoginAt']);

  final String id;
  final String? email, phoneNumber, displayName, photoUrl;
  final String authProvider;
  final DateTime? createdAt, lastLoginAt;
}

class NotificationPrefs {
  NotificationPrefs({
    this.loginAlerts = true,
    this.matchStart = true,
    this.boundaries = true,
    this.wickets = true,
    this.milestones = true,
    this.inningsEnd = true,
    this.matchResult = true,
    this.quietHoursStart,
    this.quietHoursEnd,
  });

  bool loginAlerts, matchStart, boundaries, wickets, milestones, inningsEnd, matchResult;
  String? quietHoursStart, quietHoursEnd; // "HH:mm"

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) => NotificationPrefs(
        loginAlerts: j['loginAlerts'] as bool? ?? true,
        matchStart: j['matchStart'] as bool? ?? true,
        boundaries: j['boundaries'] as bool? ?? true,
        wickets: j['wickets'] as bool? ?? true,
        milestones: j['milestones'] as bool? ?? true,
        inningsEnd: j['inningsEnd'] as bool? ?? true,
        matchResult: j['matchResult'] as bool? ?? true,
        quietHoursStart: j['quietHoursStart'] as String?,
        quietHoursEnd: j['quietHoursEnd'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'loginAlerts': loginAlerts,
        'matchStart': matchStart,
        'boundaries': boundaries,
        'wickets': wickets,
        'milestones': milestones,
        'inningsEnd': inningsEnd,
        'matchResult': matchResult,
        'quietHoursStart': quietHoursStart,
        'quietHoursEnd': quietHoursEnd,
      };
}

class SessionResult {
  SessionResult.fromJson(Map<String, dynamic> j)
      : user = ApiUser.fromJson(j['user'] as Map<String, dynamic>),
        isNewUser = j['isNewUser'] as bool? ?? false,
        deviceId = (j['device'] as Map?)?['id'] as int?,
        preferences = NotificationPrefs.fromJson(
            Map<String, dynamic>.from(j['preferences'] as Map? ?? const {}));

  final ApiUser user;
  final bool isNewUser;
  final int? deviceId;
  final NotificationPrefs preferences;
}

class ApiDevice {
  ApiDevice.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        platform = j['platform'] as String? ?? '',
        deviceModel = j['deviceModel'] as String?,
        appVersion = j['appVersion'] as String?,
        notificationsEnabled = j['notificationsEnabled'] as bool? ?? true,
        isCurrent = j['isCurrent'] as bool? ?? false,
        lastSeenAt = _dt(j['lastSeenAt']);

  final int id;
  final String platform;
  final String? deviceModel, appVersion;
  final bool notificationsEnabled, isCurrent;
  final DateTime? lastSeenAt;
}

class ApiNotification {
  ApiNotification.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        type = j['type'] as String? ?? '',
        title = j['title'] as String? ?? '',
        body = j['body'] as String? ?? '',
        data = j['data'] == null ? null : Map<String, dynamic>.from(j['data'] as Map),
        readAt = _dt(j['readAt']),
        createdAt = _dt(j['createdAt']) ?? DateTime.now();

  final int id;
  final String type, title, body;
  final Map<String, dynamic>? data;
  DateTime? readAt;
  final DateTime createdAt;
  bool get unread => readAt == null;
}

class Inbox {
  Inbox(this.items, this.unreadCount, this.nextCursor);
  final List<ApiNotification> items;
  final int unreadCount;
  final String? nextCursor;
}

class InningsSummaryApi {
  InningsSummaryApi.fromJson(Map<String, dynamic> j)
      : inningsNo = j['inningsNo'] as int,
        battingTeamId = j['battingTeamId'] as String? ?? '',
        runs = j['runs'] as int? ?? 0,
        wickets = j['wickets'] as int? ?? 0,
        legalBalls = j['legalBalls'] as int? ?? 0,
        completed = j['completed'] as bool? ?? false;

  final int inningsNo, runs, wickets, legalBalls;
  final String battingTeamId;
  final bool completed;
  String get score => '$runs/$wickets (${legalBalls ~/ 6}.${legalBalls % 6})';
}

class MatchSummary {
  MatchSummary.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        ownerId = j['ownerId'] as String? ?? '',
        status = j['status'] as String? ?? 'live',
        date = _dt(j['date']) ?? DateTime.now(),
        venue = j['venue'] as String?,
        overs = j['overs'] as int? ?? 0,
        teamAName = (j['teamA'] as Map?)?['name'] as String? ?? '',
        teamBName = (j['teamB'] as Map?)?['name'] as String? ?? '',
        teamAShort = (j['teamA'] as Map?)?['short'] as String? ?? '',
        teamBShort = (j['teamB'] as Map?)?['short'] as String? ?? '',
        teamAId = (j['teamA'] as Map?)?['id'] as String? ?? '',
        tossText = j['tossText'] as String? ?? '',
        resultText = j['resultText'] as String?,
        innings = [
          for (final i in (j['innings'] as List? ?? const []))
            InningsSummaryApi.fromJson(Map<String, dynamic>.from(i as Map))
        ];

  final String id, ownerId, status, teamAName, teamBName, teamAShort, teamBShort, teamAId, tossText;
  final DateTime date;
  final String? venue, resultText;
  final int overs;
  final List<InningsSummaryApi> innings;
  bool get isLive => status == 'live';
}

class PlayerStats {
  PlayerStats.fromJson(Map<String, dynamic> j)
      : matches = j['matches'] as int? ?? 0,
        batting = Map<String, dynamic>.from(j['batting'] as Map? ?? const {}),
        bowling = Map<String, dynamic>.from(j['bowling'] as Map? ?? const {});

  final int matches;
  final Map<String, dynamic> batting, bowling;
}

class TeamStats {
  TeamStats.fromJson(Map<String, dynamic> j)
      : played = j['played'] as int? ?? 0,
        won = j['won'] as int? ?? 0,
        lost = j['lost'] as int? ?? 0,
        tied = j['tied'] as int? ?? 0,
        noResult = j['noResult'] as int? ?? 0;

  final int played, won, lost, tied, noResult;
}

class ShareInfo {
  ShareInfo.fromJson(Map<String, dynamic> j)
      : shareCode = j['shareCode'] as String,
        url = j['url'] as String? ?? '';
  final String shareCode, url;
}

class ServerConfig {
  ServerConfig.fromJson(Map<String, dynamic> j)
      : minAppVersion = j['minAppVersion'] as String? ?? '1.0.0',
        features = Map<String, bool>.from(j['features'] as Map? ?? const {});
  final String minAppVersion;
  final Map<String, bool> features;
}

class LiveInningsTotals {
  LiveInningsTotals.fromJson(Map<String, dynamic> j)
      : runs = j['runs'] as int? ?? 0,
        wickets = j['wickets'] as int? ?? 0,
        legalBalls = j['legalBalls'] as int? ?? 0;
  final int runs, wickets, legalBalls;
}

class SyncPullResult {
  SyncPullResult({
    required this.teams,
    required this.players,
    required this.matches,
    required this.deletedTeams,
    required this.deletedPlayers,
    required this.deletedMatches,
    required this.serverTime,
  });

  final List<Map<String, dynamic>> teams, players, matches;
  final List<String> deletedTeams, deletedPlayers, deletedMatches;
  final String serverTime;
}
