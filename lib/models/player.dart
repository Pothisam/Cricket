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

const genders = ['male', 'female', 'other'];

class Player {
  Player({
    required this.id,
    required this.name,
    this.role = PlayerRole.batter,
    this.battingStyle = 'Right-hand bat',
    this.bowlingStyle = 'None',
    this.email,
    this.phoneNumber,
    this.gender,
    this.dateOfBirth,
    this.heightCm,
    this.weightKg,
    this.jerseyNumber,
    this.city,
    this.photoUrl,
    this.linkedUserId,
    this.isSelf = false,
  });

  final String id;
  String name;
  PlayerRole role;
  String battingStyle;
  String bowlingStyle;

  /// Used to recognise the person: when it matches a registered user the
  /// server links this player to that user.
  String? email;
  String? phoneNumber;

  /// `male`, `female` or `other`.
  String? gender;

  /// `yyyy-MM-dd`.
  String? dateOfBirth;
  double? heightCm;
  double? weightKg;
  int? jerseyNumber;
  String? city;
  String? photoUrl;

  /// Set by the server: the signed-in user this player is.
  String? linkedUserId;

  /// Set by the server: this player is the account owner.
  bool isSelf;

  bool get isRegistered => linkedUserId != null;

  /// A registered user who is not me: only they can edit their own profile.
  /// (I can still add them to teams or remove them from my list.)
  bool get isReadOnly => isRegistered && !isSelf;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role.name,
        'battingStyle': battingStyle,
        'bowlingStyle': bowlingStyle,
        'email': email,
        'phoneNumber': phoneNumber,
        'gender': gender,
        'dateOfBirth': dateOfBirth,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'jerseyNumber': jerseyNumber,
        'city': city,
        'photoUrl': photoUrl,
        'linkedUserId': linkedUserId,
        'isSelf': isSelf,
      };

  factory Player.fromJson(Map<String, dynamic> j) => Player(
        id: j['id'] as String,
        name: j['name'] as String,
        role: PlayerRole.values.byName(j['role'] as String),
        battingStyle: j['battingStyle'] as String? ?? battingStyles.first,
        bowlingStyle: j['bowlingStyle'] as String? ?? 'None',
        email: j['email'] as String?,
        phoneNumber: j['phoneNumber'] as String?,
        gender: j['gender'] as String?,
        dateOfBirth: j['dateOfBirth'] as String?,
        heightCm: (j['heightCm'] as num?)?.toDouble(),
        weightKg: (j['weightKg'] as num?)?.toDouble(),
        jerseyNumber: (j['jerseyNumber'] as num?)?.toInt(),
        city: j['city'] as String?,
        photoUrl: j['photoUrl'] as String?,
        linkedUserId: j['linkedUserId'] as String?,
        isSelf: j['isSelf'] as bool? ?? false,
      );
}
