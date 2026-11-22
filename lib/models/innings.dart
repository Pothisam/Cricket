import 'ball_event.dart';

class Innings {
  Innings({
    required this.battingTeamId,
    required this.bowlingTeamId,
    List<BallEvent>? balls,
    this.strikerId,
    this.nonStrikerId,
    this.bowlerId,
    this.completed = false,
  }) : balls = balls ?? [];

  final String battingTeamId;
  final String bowlingTeamId;
  final List<BallEvent> balls;

  /// Current state at the crease. `null` means "needs to be chosen".
  String? strikerId;
  String? nonStrikerId;
  String? bowlerId;
  bool completed;

  int get legalBalls => balls.where((b) => b.isLegal).length;
  int get runs => balls.fold(0, (s, b) => s + b.totalRuns);
  int get wickets => balls.where((b) => b.isWicket).length;

  Map<String, dynamic> toJson() => {
    'battingTeamId': battingTeamId,
    'bowlingTeamId': bowlingTeamId,
    'balls': balls.map((b) => b.toJson()).toList(),
    'striker': strikerId,
    'nonStriker': nonStrikerId,
    'bowler': bowlerId,
    'completed': completed,
  };

  factory Innings.fromJson(Map<String, dynamic> j) => Innings(
    battingTeamId: j['battingTeamId'] as String,
    bowlingTeamId: j['bowlingTeamId'] as String,
    balls: (j['balls'] as List)
        .map((e) => BallEvent.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    strikerId: j['striker'] as String?,
    nonStrikerId: j['nonStriker'] as String?,
    bowlerId: j['bowler'] as String?,
    completed: j['completed'] as bool? ?? false,
  );
}
