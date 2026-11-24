class Team {
  Team({
    required this.id,
    required this.name,
    required this.shortName,
    this.colorIndex = 0,
    this.isPublic = false,
    this.captainPlayerId,
    this.viceCaptainPlayerId,
    List<String>? playerIds,
  }) : playerIds = playerIds ?? [];

  final String id;
  String name;
  String shortName;
  int colorIndex;

  /// Public: other scorers can find the team by name and challenge it. Private: only me.
  bool isPublic;

  /// Captain and vice-captain of THIS team (a player can lead one team and just play in another).
  String? captainPlayerId;
  String? viceCaptainPlayerId;
  final List<String> playerIds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'shortName': shortName,
    'colorIndex': colorIndex,
    'isPublic': isPublic,
    'captainPlayerId': captainPlayerId,
    'viceCaptainPlayerId': viceCaptainPlayerId,
    'playerIds': playerIds,
  };

  factory Team.fromJson(Map<String, dynamic> j) => Team(
    id: j['id'] as String,
    name: j['name'] as String,
    shortName: j['shortName'] as String,
    colorIndex: j['colorIndex'] as int? ?? 0,
    isPublic: j['isPublic'] as bool? ?? false,
    captainPlayerId: j['captainPlayerId'] as String?,
    viceCaptainPlayerId: j['viceCaptainPlayerId'] as String?,
    playerIds: List<String>.from(j['playerIds'] as List? ?? const []),
  );
}
