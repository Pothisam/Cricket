import 'dart:ui' show Offset;

enum ExtraType { none, wide, noBall, bye, legBye }

enum WicketType {
  bowled('Bowled'),
  caught('Caught'),
  lbw('LBW'),
  runOut('Run out'),
  stumped('Stumped'),
  hitWicket('Hit wicket');

  const WicketType(this.label);
  final String label;
}

/// Where the ball was hit, relative to a right-handed batter facing the bowler.
/// [angle] is in degrees clockwise from straight down the ground (0 = towards
/// the bowler, positive = off side / screen right in the top-down view).
enum ShotDirection {
  straight('Straight', 0),
  midOff('Mid-off', 25),
  cover('Cover', 55),
  point('Point', 90),
  thirdMan('Third man', 140),
  fineLeg('Fine leg', -140),
  squareLeg('Square leg', -90),
  midWicket('Mid-wicket', -55),
  midOn('Mid-on', -25);

  const ShotDirection(this.label, this.angle);
  final String label;
  final double angle;
}

/// How the shot travelled: along the turf (with small skips), in the air with a
/// bounce, or fully airborne (sixes / catches).
enum ShotLoft {
  ground('Ground'),
  lofted('Lofted'),
  aerial('Aerial');

  const ShotLoft(this.label);
  final String label;
}

/// Coarse classification of a delivery, used by the replay and the future API.
enum BallOutcome { dot, runs, four, six, wide, noBall, bye, legBye, wicket }

/// One delivery. Carries a snapshot of who was on the field so that
/// undo and scorecards can be rebuilt purely from the ball list.
class BallEvent {
  BallEvent({
    required this.strikerId,
    required this.nonStrikerId,
    required this.bowlerId,
    this.runs = 0,
    this.extra = ExtraType.none,
    this.extraRuns = 0,
    this.wicket,
    this.outPlayerId,
    this.fielderId,
    this.shotDirection,
    this.shotPath,
    this.loft,
  });

  final String strikerId;
  final String nonStrikerId;
  final String bowlerId;

  /// Runs scored off the bat.
  final int runs;
  final ExtraType extra;

  /// Extra runs, including the 1-run penalty for wides / no balls.
  final int extraRuns;
  final WicketType? wicket;
  final String? outPlayerId;
  final String? fielderId;

  /// Where the ball went off the bat; `null` when not recorded / not hit.
  final ShotDirection? shotDirection;

  /// Drawn path of the ball off the bat, in ground coordinates (radius 1,
  /// +y towards the bowler). `null` when only a direction was recorded.
  final List<Offset>? shotPath;
  final ShotLoft? loft;

  BallOutcome get outcome {
    if (isWicket) return BallOutcome.wicket;
    switch (extra) {
      case ExtraType.wide:
        return BallOutcome.wide;
      case ExtraType.noBall:
        return BallOutcome.noBall;
      case ExtraType.bye:
        return BallOutcome.bye;
      case ExtraType.legBye:
        return BallOutcome.legBye;
      case ExtraType.none:
        return runs == 6
            ? BallOutcome.six
            : runs == 4
            ? BallOutcome.four
            : runs == 0
            ? BallOutcome.dot
            : BallOutcome.runs;
    }
  }

  bool get isLegal => extra != ExtraType.wide && extra != ExtraType.noBall;
  bool get isWicket => wicket != null;
  int get totalRuns => runs + extraRuns;

  /// Runs charged to the bowler (byes / leg byes are not).
  int get bowlerRuns => runs + (isLegal ? 0 : extraRuns);
  bool get bowlerGetsWicket => wicket != null && wicket != WicketType.runOut;

  /// Runs physically run by the batters; odd => strike changes.
  int get runsRan {
    switch (extra) {
      case ExtraType.none:
      case ExtraType.noBall:
        return runs;
      case ExtraType.wide:
        return extraRuns - 1;
      case ExtraType.bye:
      case ExtraType.legBye:
        return extraRuns;
    }
  }

  bool get facedByBatter => extra != ExtraType.wide;

  String get label {
    if (isWicket) return runs > 0 ? 'W+$runs' : 'W';
    switch (extra) {
      case ExtraType.wide:
        return extraRuns > 1 ? 'Wd+${extraRuns - 1}' : 'Wd';
      case ExtraType.noBall:
        return runs > 0 ? 'Nb+$runs' : 'Nb';
      case ExtraType.bye:
        return '${extraRuns}b';
      case ExtraType.legBye:
        return '${extraRuns}lb';
      case ExtraType.none:
        return '$runs';
    }
  }

  Map<String, dynamic> toJson() => {
    'striker': strikerId,
    'nonStriker': nonStrikerId,
    'bowler': bowlerId,
    'runs': runs,
    'extra': extra.name,
    'extraRuns': extraRuns,
    'wicket': wicket?.name,
    'out': outPlayerId,
    'fielder': fielderId,
    'shotDirection': shotDirection?.name,
    'shotPath': shotPath == null
        ? null
        : [
            for (final p in shotPath!) [p.dx, p.dy],
          ],
    'loft': loft?.name,
  };

  factory BallEvent.fromJson(Map<String, dynamic> j) => BallEvent(
    strikerId: j['striker'] as String,
    nonStrikerId: j['nonStriker'] as String,
    bowlerId: j['bowler'] as String,
    runs: j['runs'] as int,
    extra: ExtraType.values.byName(j['extra'] as String),
    extraRuns: j['extraRuns'] as int,
    wicket: j['wicket'] == null
        ? null
        : WicketType.values.byName(j['wicket'] as String),
    outPlayerId: j['out'] as String?,
    fielderId: j['fielder'] as String?,
    shotDirection: j['shotDirection'] == null
        ? null
        : ShotDirection.values.byName(j['shotDirection'] as String),
    shotPath: j['shotPath'] == null
        ? null
        : [
            for (final p in j['shotPath'] as List)
              Offset(
                ((p as List)[0] as num).toDouble(),
                (p[1] as num).toDouble(),
              ),
          ],
    loft: j['loft'] == null
        ? null
        : ShotLoft.values.byName(j['loft'] as String),
  );
}
