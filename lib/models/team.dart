class Team {
  Team({
    required this.id,
    required this.name,
    required this.shortName,
    this.colorIndex = 0,
    List<String>? playerIds,
  }) : playerIds = playerIds ?? [];

  final String id;
  String name;
  String shortName;
  int colorIndex;
  final List<String> playerIds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'shortName': shortName,
        'colorIndex': colorIndex,
        'playerIds': playerIds,
      };

  factory Team.fromJson(Map<String, dynamic> j) => Team(
        id: j['id'] as String,
        name: j['name'] as String,
        shortName: j['shortName'] as String,
        colorIndex: j['colorIndex'] as int? ?? 0,
        playerIds: List<String>.from(j['playerIds'] as List? ?? const []),
      );
}
