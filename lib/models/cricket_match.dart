import 'innings.dart';

enum MatchStatus { live, completed, abandoned }

class CricketMatch {
  CricketMatch({
    required this.id,
    required this.teamAId,
    required this.teamBId,
    required this.teamAName,
    required this.teamBName,
    required this.teamAShort,
    required this.teamBShort,
    required this.overs,
    required this.tossWinnerId,
    required this.electedToBat,
    required this.teamAPlayers,
    required this.teamBPlayers,
    required this.playerNames,
    required this.date,
    this.venue = '',
    List<Innings>? innings,
    this.status = MatchStatus.live,
    this.winnerId,
    this.resultText = '',
    this.invitationId,
    this.opponentUserId,
  }) : innings = innings ?? [];

  final String id;
  final String teamAId, teamBId;
  final String teamAName, teamBName;
  final String teamAShort, teamBShort;
  final int overs;
  final String tossWinnerId;
  final bool electedToBat;

  /// Playing XI (player ids).
  final List<String> teamAPlayers, teamBPlayers;

  /// Name snapshot so a match stays readable if a player is later edited/removed.
  final Map<String, String> playerNames;
  final DateTime date;
  final String venue;
  final List<Innings> innings;
  MatchStatus status;
  String? winnerId;
  String resultText;

  /// Set when the match is against a team of another user (started from an accepted invitation).
  final String? invitationId;

  /// Owner of team B in such a match. Only the scorer (the owner of this match) can score it.
  final String? opponentUserId;

  bool get isLive => status == MatchStatus.live;

  String teamName(String id) => id == teamAId ? teamAName : teamBName;
  String teamShort(String id) => id == teamAId ? teamAShort : teamBShort;
  List<String> squad(String teamId) =>
      teamId == teamAId ? teamAPlayers : teamBPlayers;
  String playerName(String? id) => playerNames[id] ?? 'Unknown';
  String otherTeam(String id) => id == teamAId ? teamBId : teamAId;

  String get battingFirstId =>
      electedToBat ? tossWinnerId : otherTeam(tossWinnerId);

  Innings? get currentInnings => innings.isEmpty ? null : innings.last;

  /// Target for the chasing side (first innings total + 1), if applicable.
  int? get target => innings.length >= 2 ? innings.first.runs + 1 : null;

  String get tossText =>
      '${teamName(tossWinnerId)} won the toss and chose to ${electedToBat ? 'bat' : 'bowl'}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'teamAId': teamAId,
    'teamBId': teamBId,
    'teamAName': teamAName,
    'teamBName': teamBName,
    'teamAShort': teamAShort,
    'teamBShort': teamBShort,
    'overs': overs,
    'tossWinnerId': tossWinnerId,
    'electedToBat': electedToBat,
    'teamAPlayers': teamAPlayers,
    'teamBPlayers': teamBPlayers,
    'playerNames': playerNames,
    'date': date.toIso8601String(),
    'venue': venue,
    'innings': innings.map((i) => i.toJson()).toList(),
    'status': status.name,
    'winnerId': winnerId,
    'resultText': resultText,
    'invitationId': invitationId,
    'opponentUserId': opponentUserId,
  };

  factory CricketMatch.fromJson(Map<String, dynamic> j) => CricketMatch(
    id: j['id'] as String,
    teamAId: j['teamAId'] as String,
    teamBId: j['teamBId'] as String,
    teamAName: j['teamAName'] as String,
    teamBName: j['teamBName'] as String,
    teamAShort: j['teamAShort'] as String,
    teamBShort: j['teamBShort'] as String,
    overs: j['overs'] as int,
    tossWinnerId: j['tossWinnerId'] as String,
    electedToBat: j['electedToBat'] as bool,
    teamAPlayers: List<String>.from(j['teamAPlayers'] as List),
    teamBPlayers: List<String>.from(j['teamBPlayers'] as List),
    playerNames: Map<String, String>.from(j['playerNames'] as Map),
    date: DateTime.parse(j['date'] as String),
    venue: j['venue'] as String? ?? '',
    innings: (j['innings'] as List)
        .map((e) => Innings.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    status: MatchStatus.values.byName(j['status'] as String),
    winnerId: j['winnerId'] as String?,
    resultText: j['resultText'] as String? ?? '',
    invitationId: j['invitationId'] as String?,
    opponentUserId: j['opponentUserId'] as String?,
  );
}
