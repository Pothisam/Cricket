/// Response models for endpoints that are not already covered by the app's own
/// Team / Player / CricketMatch models (those use their own toJson / fromJson).

DateTime? _dt(Object? v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

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

  bool loginAlerts,
      matchStart,
      boundaries,
      wickets,
      milestones,
      inningsEnd,
      matchResult;
  String? quietHoursStart, quietHoursEnd; // "HH:mm"

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) =>
      NotificationPrefs(
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
        Map<String, dynamic>.from(j['preferences'] as Map? ?? const {}),
      );

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
      data = j['data'] == null
          ? null
          : Map<String, dynamic>.from(j['data'] as Map),
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
      teamBId = (j['teamB'] as Map?)?['id'] as String? ?? '',
      tossText = j['tossText'] as String? ?? '',
      resultText = j['resultText'] as String?,
      innings = [
        for (final i in (j['innings'] as List? ?? const []))
          InningsSummaryApi.fromJson(Map<String, dynamic>.from(i as Map)),
      ];

  final String id,
      ownerId,
      status,
      teamAName,
      teamBName,
      teamAShort,
      teamBShort,
      teamAId,
      teamBId,
      tossText;
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

/// The signed-in user's cricket profile (`GET/PUT /me/profile`).
class PlayerProfile {
  PlayerProfile({
    this.userId = '',
    this.playerId = '',
    this.email,
    this.phoneNumber,
    this.photoUrl,
    this.displayName = '',
    this.gender,
    this.dateOfBirth,
    this.city,
    this.isDiscoverable = true,
    this.role = 'batter',
    this.battingStyle = 'Right-hand bat',
    this.bowlingStyle = 'None',
    this.heightCm,
    this.weightKg,
    this.jerseyNumber,
  });

  String userId, playerId;
  String? email, phoneNumber, photoUrl, gender, dateOfBirth, city;
  String displayName;
  bool isDiscoverable;
  String role, battingStyle, bowlingStyle;
  double? heightCm, weightKg;
  int? jerseyNumber;

  factory PlayerProfile.fromJson(Map<String, dynamic> j) => PlayerProfile(
    userId: j['userId'] as String? ?? '',
    playerId: j['playerId'] as String? ?? '',
    email: j['email'] as String?,
    phoneNumber: j['phoneNumber'] as String?,
    photoUrl: j['photoUrl'] as String?,
    displayName: j['displayName'] as String? ?? '',
    gender: j['gender'] as String?,
    dateOfBirth: j['dateOfBirth'] as String?,
    city: j['city'] as String?,
    isDiscoverable: j['isDiscoverable'] as bool? ?? true,
    role: j['role'] as String? ?? 'batter',
    battingStyle: j['battingStyle'] as String? ?? 'Right-hand bat',
    bowlingStyle: j['bowlingStyle'] as String? ?? 'None',
    heightCm: (j['heightCm'] as num?)?.toDouble(),
    weightKg: (j['weightKg'] as num?)?.toDouble(),
    jerseyNumber: (j['jerseyNumber'] as num?)?.toInt(),
  );

  /// Body of `PUT /me/profile` (the profile is replaced).
  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'gender': gender,
    'dateOfBirth': dateOfBirth,
    'city': city,
    'phoneNumber': phoneNumber,
    'photoUrl': photoUrl,
    'isDiscoverable': isDiscoverable,
    'role': role,
    'battingStyle': battingStyle,
    'bowlingStyle': bowlingStyle,
    'heightCm': heightCm,
    'weightKg': weightKg,
    'jerseyNumber': jerseyNumber,
  };
}

/// One hit of `GET /players/search`.
class PlayerSearchItem {
  PlayerSearchItem.fromJson(Map<String, dynamic> j)
    : source = j['source'] as String? ?? 'mine',
      playerId = j['playerId'] as String?,
      userId = j['userId'] as String?,
      name = j['name'] as String? ?? '',
      email = j['email'] as String?,
      photoUrl = j['photoUrl'] as String?,
      role = j['role'] as String? ?? 'batter',
      battingStyle = j['battingStyle'] as String? ?? '',
      bowlingStyle = j['bowlingStyle'] as String? ?? '',
      city = j['city'] as String?,
      isRegistered = j['isRegistered'] as bool? ?? false,
      isSelf = j['isSelf'] as bool? ?? false;

  /// `mine` = already in my player list, `user` = a registered user I can add.
  final String source;
  final String? playerId, userId, email, photoUrl, city;
  final String name, role, battingStyle, bowlingStyle;
  final bool isRegistered, isSelf;
  bool get isMine => source == 'mine';
}

/// A team created by someone else in which I am a member (`GET /me/joined-teams`).
class JoinedTeam {
  JoinedTeam.fromJson(Map<String, dynamic> j)
    : ownerId = j['ownerId'] as String,
      ownerName = j['ownerName'] as String?,
      teamId = j['teamId'] as String,
      name = j['name'] as String? ?? '',
      shortName = j['shortName'] as String? ?? '',
      colorIndex = (j['colorIndex'] as num?)?.toInt() ?? 0,
      playerCount = (j['playerCount'] as num?)?.toInt() ?? 0,
      squad = [
        for (final m in (j['squad'] as List? ?? const []))
          SquadMember.fromJson(Map<String, dynamic>.from(m as Map)),
      ];

  final String ownerId, teamId, name, shortName;
  final String? ownerName;
  final int colorIndex, playerCount;

  /// Only filled by `GET /me/joined-teams/{ownerId}/{teamId}`.
  final List<SquadMember> squad;
}

class SquadMember {
  SquadMember.fromJson(Map<String, dynamic> j)
    : name = j['name'] as String? ?? '',
      role = j['role'] as String? ?? 'batter',
      battingStyle = j['battingStyle'] as String? ?? '',
      bowlingStyle = j['bowlingStyle'] as String? ?? '',
      photoUrl = j['photoUrl'] as String?,
      isRegistered = j['isRegistered'] as bool? ?? false,
      isMe = j['isMe'] as bool? ?? false,
      isCaptain = j['isCaptain'] as bool? ?? false,
      isViceCaptain = j['isViceCaptain'] as bool? ?? false,
      isOwner = j['isOwner'] as bool? ?? false,
      playerId = j['playerId'] as String? ?? '';

  /// Id in the squad owner's player list.
  final String playerId;
  final String name, role, battingStyle, bowlingStyle;
  final String? photoUrl;
  final bool isRegistered, isMe;

  /// Roles in this team.
  final bool isCaptain, isViceCaptain, isOwner;
}

/// A team of another user found by name (`GET /teams/search`).
class TeamSearchItem {
  TeamSearchItem.fromJson(Map<String, dynamic> j)
    : ownerId = j['ownerId'] as String,
      ownerName = j['ownerName'] as String?,
      teamId = j['teamId'] as String,
      name = j['name'] as String? ?? '',
      shortName = j['shortName'] as String? ?? '',
      colorIndex = (j['colorIndex'] as num?)?.toInt() ?? 0,
      playerCount = (j['playerCount'] as num?)?.toInt() ?? 0;

  final String ownerId, teamId, name, shortName;
  final String? ownerName;
  final int colorIndex, playerCount;
}

/// A match challenge between two teams of different users (`/match-invitations`).
/// Once accepted it is the scheduled match, visible to both owners.
class MatchInvitation {
  MatchInvitation.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      outgoing = j['direction'] == 'outgoing',
      status = j['status'] as String? ?? 'pending',
      fromUserId = j['fromUserId'] as String? ?? '',
      fromUserName = j['fromUserName'] as String?,
      fromTeamId = (j['fromTeam'] as Map?)?['id'] as String? ?? '',
      fromTeamName = (j['fromTeam'] as Map?)?['name'] as String? ?? '',
      fromTeamShort = (j['fromTeam'] as Map?)?['short'] as String? ?? '',
      toUserId = j['toUserId'] as String? ?? '',
      toUserName = j['toUserName'] as String?,
      toTeamId = (j['toTeam'] as Map?)?['id'] as String? ?? '',
      toTeamName = (j['toTeam'] as Map?)?['name'] as String? ?? '',
      toTeamShort = (j['toTeam'] as Map?)?['short'] as String? ?? '',
      overs = (j['overs'] as num?)?.toInt() ?? 20,
      scheduledAt = _dt(j['scheduledAt']),
      venue = j['venue'] as String?,
      message = j['message'] as String?,
      matchId = j['matchId'] as String?,
      createdAt = _dt(j['createdAt']) ?? DateTime.now();

  final String id, status, fromUserId, fromTeamId, fromTeamName, fromTeamShort;
  final String toUserId, toTeamId, toTeamName, toTeamShort;
  final String? fromUserName, toUserName, venue, message, matchId;

  /// I sent it: I am the scorer and I start the match.
  final bool outgoing;
  final int overs;
  final DateTime? scheduledAt;
  final DateTime createdAt;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isStarted => status == 'started';

  /// The other side.
  String get otherTeamName => outgoing ? toTeamName : fromTeamName;
  String? get otherOwnerName => outgoing ? toUserName : fromUserName;
  String get title => '$fromTeamShort vs $toTeamShort';
}

/// Result of `POST /notifications/test`: how many devices got the push, and why not when none did.
class TestPushResult {
  TestPushResult(this.sent, this.failed, this.reason);
  final int sent, failed;

  /// push_disabled | no_target_devices | quiet_hours | an FCM error code.
  final String? reason;

  /// Plain-language explanation for the user.
  String get message {
    if (sent > 0)
      return 'Sent to $sent device${sent == 1 ? '' : 's'}. It should appear in the notification bar.';
    return switch (reason) {
      'push_disabled' =>
        'The server cannot send push messages: it has no Firebase service-account key. '
            'The backend developer must set FirebaseConfig:CredentialsPath on the server '
            '(Firebase Console > Project settings > Service accounts > Generate new private key).',
      'no_target_devices' =>
        'The server has no device of yours that accepts notifications. '
            'Allow notifications for this app in the phone settings, then reopen the app.',
      'quiet_hours' => 'Quiet hours are on, so nothing was sent.',
      'Unregistered' || 'InvalidArgument' => 'This phone\'s notification token is no longer valid. Close and reopen the app to register it again.',
      'SenderIdMismatch' || 'ThirdPartyAuthError' => 'The server\'s Firebase key belongs to a different Firebase project than the app (cricket-run-notification).',
      final r? => 'The push could not be delivered ($r).',
      null => 'The push could not be delivered.',
    };
  }
}

/// A user a team was handed over to (`GET /teams/{id}/managers`).
class TeamManagerInfo {
  TeamManagerInfo.fromJson(Map<String, dynamic> j)
    : userId = j['userId'] as String,
      name = j['name'] as String?,
      photoUrl = j['photoUrl'] as String?,
      email = j['email'] as String?;
  final String userId;
  final String? name, photoUrl, email;
}

class ManagedMember {
  ManagedMember.fromJson(Map<String, dynamic> j)
    : playerId = j['playerId'] as String,
      name = j['name'] as String? ?? '',
      role = j['role'] as String? ?? 'batter',
      battingStyle = j['battingStyle'] as String? ?? '',
      bowlingStyle = j['bowlingStyle'] as String? ?? '',
      photoUrl = j['photoUrl'] as String?,
      isRegistered = j['isRegistered'] as bool? ?? false,
      isOwner = j['isOwner'] as bool? ?? false,
      isAdmin = j['isAdmin'] as bool? ?? false,
      isMe = j['isMe'] as bool? ?? false;
  final String playerId, name, role, battingStyle, bowlingStyle;
  final String? photoUrl;
  final bool isRegistered;

  /// The creator of the team: a manager cannot remove them.
  final bool isOwner;

  /// An admin of the team (a registered player the team was handed over to).
  final bool isAdmin;

  /// This player is me.
  final bool isMe;
}

/// A team handed over to me (`/me/managed-teams`): I can run it, only the creator can delete it.
class ManagedTeam {
  ManagedTeam.fromJson(Map<String, dynamic> j)
    : ownerId = j['ownerId'] as String,
      ownerName = j['ownerName'] as String?,
      teamId = j['teamId'] as String,
      name = j['name'] as String? ?? '',
      shortName = j['shortName'] as String? ?? '',
      colorIndex = (j['colorIndex'] as num?)?.toInt() ?? 0,
      isPublic = j['isPublic'] as bool? ?? false,
      captainPlayerId = j['captainPlayerId'] as String?,
      viceCaptainPlayerId = j['viceCaptainPlayerId'] as String?,
      playerCount = (j['playerCount'] as num?)?.toInt() ?? 0,
      squad = [
        for (final m in (j['squad'] as List? ?? const []))
          ManagedMember.fromJson(Map<String, dynamic>.from(m as Map)),
      ],
      roster = [
        for (final m in (j['roster'] as List? ?? const []))
          ManagedMember.fromJson(Map<String, dynamic>.from(m as Map)),
      ];
  final String ownerId, teamId, name, shortName;
  final String? ownerName, captainPlayerId, viceCaptainPlayerId;
  final int colorIndex, playerCount;
  final bool isPublic;

  /// Filled by the detail call only.
  final List<ManagedMember> squad, roster;
}
