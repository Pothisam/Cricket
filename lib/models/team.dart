class Team {
  Team({
    required this.id,
    required this.name,
    required this.shortName,
    this.colorIndex = 0,
    this.isPublic = false,
    List<String>? playerIds,
  }) : playerIds = playerIds ?? [];

  final String id;
  String name;
  String shortName;
  int colorIndex;

  /// Public: other scorers can find the team by name and challenge it. Private: only me.
  bool isPublic;
  final List<String> playerIds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'shortName': shortName,
    'colorIndex': colorIndex,
    'isPublic': isPublic,
    'playerIds': playerIds,
  };

  factory Team.fromJson(Map<String, dynamic> j) => Team(
    id: j['id'] as String,
    name: j['name'] as String,
    shortName: j['shortName'] as String,
    colorIndex: j['colorIndex'] as int? ?? 0,
    isPublic: j['isPublic'] as bool? ?? false,
    playerIds: List<String>.from(j['playerIds'] as List? ?? const []),
  );
}
