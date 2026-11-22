enum PlayerRole {
  batter('Batter'),
  bowler('Bowler'),
  allRounder('All-rounder'),
  wicketKeeper('Wicket-keeper');

  const PlayerRole(this.label);
  final String label;
}

const battingStyles = ['Right-hand bat', 'Left-hand bat'];
const bowlingStyles = [
  'None',
  'Right-arm fast',
  'Right-arm medium',
  'Right-arm off spin',
  'Right-arm leg spin',
  'Left-arm fast',
  'Left-arm medium',
  'Left-arm orthodox',
  'Left-arm chinaman',
];

class Player {
  Player({
    required this.id,
    required this.name,
    this.role = PlayerRole.batter,
    this.battingStyle = 'Right-hand bat',
    this.bowlingStyle = 'None',
  });

  final String id;
  String name;
  PlayerRole role;
  String battingStyle;
  String bowlingStyle;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role.name,
        'battingStyle': battingStyle,
        'bowlingStyle': bowlingStyle,
      };

  factory Player.fromJson(Map<String, dynamic> j) => Player(
        id: j['id'] as String,
        name: j['name'] as String,
        role: PlayerRole.values.byName(j['role'] as String),
        battingStyle: j['battingStyle'] as String? ?? battingStyles.first,
        bowlingStyle: j['bowlingStyle'] as String? ?? 'None',
      );
}
