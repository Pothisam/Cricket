import 'dart:math' as math;

import '../../domain/shot_trajectory.dart';
import '../../models/ball_event.dart';
import 'scene3d.dart';

/// The batting clip chosen for a recorded delivery, with the details the replay
/// needs to line the bat up with the ball.
class BattingShot {
  const BattingShot({
    required this.clip,
    required this.duration,
    required this.contactTime,
    required this.contactPoint,
    required this.footwork,
  });

  final String clip;

  /// Length of the clip in seconds.
  final double duration;

  /// Seconds into the clip at which the bat meets the ball; null = no contact (a leave).
  final double? contactTime;

  /// Where the ball is when the bat meets it, in the batsman's own frame
  /// (metres; +Y up, bowler +Z, off side -X). Null when there is no contact.
  final V3? contactPoint;

  /// `front`, `back` or `none`.
  final String footwork;
}

/// Maps recorded scorecard data to the batting clips of the batsman model. The
/// mapping uses the clips' own metadata (shot direction, footwork, contact), so
/// adding a clip to the model makes it available automatically.
class BattingClips {
  BattingClips(Map<String, dynamic> meta)
    : _clips = Map<String, dynamic>.from(meta['clips'] as Map);

  final Map<String, dynamic> _clips;

  static const stance = 'Stance_Idle';

  bool has(String name) => _clips.containsKey(name);

  BattingShot shot(String name) {
    final m = Map<String, dynamic>.from(
      (_clips[name] ?? _clips['Defence_Forward']) as Map,
    );
    final contact = m['contact'] as Map?;
    final pt = contact == null
        ? null
        : (contact['point'] as List).map((e) => (e as num).toDouble()).toList();
    return BattingShot(
      clip: _clips.containsKey(name) ? name : 'Defence_Forward',
      duration: (m['duration'] as num).toDouble(),
      contactTime: (m['contactTime'] as num?)?.toDouble(),
      contactPoint: pt == null ? null : V3(pt[0], pt[1], pt[2]),
      footwork: (m['footwork'] as String?) ?? 'none',
    );
  }

  /// Azimuth of the recorded shot in the clips' convention: 0 straight, negative
  /// towards the off side (cover -50, point -95), positive towards the leg side.
  /// Taken from the way the drawn path leaves the bat, so a curved shot is played
  /// to where it started, not where it ended.
  static double azimuthOf(BallEvent b) {
    final path = b.shotPath;
    if (path != null && path.length >= 2) {
      final tr = ShotTrajectory(path, b.loft ?? ShotLoft.ground);
      final d = tr.pointAt(0.2) - tr.pointAt(0.0);
      if (d.distance > 1e-6) return -math.atan2(d.dx, d.dy) * 180 / math.pi;
    }
    return -(b.shotDirection?.angle ?? 0);
  }

  static double _angleGap(double a, double b) {
    var d = (a - b).abs() % 360;
    if (d > 180) d = 360 - d;
    return d;
  }

  /// Chooses the clip for [b]. Nothing here is random: the same ball always plays
  /// the same clip.
  BattingShot choose(BallEvent b) {
    switch (b.outcome) {
      case BallOutcome.wide:
      case BallOutcome.bye:
      case BallOutcome.legBye:
        return shot('Leave'); // the ball goes past without the bat
      case BallOutcome.wicket:
        switch (b.wicket!) {
          case WicketType.bowled:
          case WicketType.stumped:
            return shot('Drive_Straight'); // a full swing that misses
          case WicketType.lbw:
            return shot(
              'Defence_Forward',
            ); // beaten playing forward, hit on the pad
          case WicketType.hitWicket:
            return shot('Cut_Square');
          case WicketType.caught:
          case WicketType.runOut:
            return _byShot(b);
        }
      case BallOutcome.dot:
        return b.shotPath == null && b.shotDirection == null
            ? shot('Defence_Forward')
            : _byShot(b);
      case BallOutcome.runs:
      case BallOutcome.four:
      case BallOutcome.six:
      case BallOutcome.noBall:
        return _byShot(b);
    }
  }

  BattingShot _byShot(BallEvent b) {
    final az = azimuthOf(b);
    final airborne =
        b.loft == ShotLoft.aerial || b.loft == ShotLoft.lofted || b.runs == 6;
    if (airborne) {
      // Lofted shots: over cover, straight, or the leg side (pulled / hooked / flicked).
      if (az < -100 && has('Cut_Late')) return shot('Cut_Late');
      if (az < -20 && has('Loft_Cover')) return shot('Loft_Cover');
      if (az <= 22 && has('Loft_Straight')) return shot('Loft_Straight');
      if (az < 62 && has('Flick')) return shot('Flick');
      if (az < 105 && has('Pull')) return shot('Pull');
      if (has('Hook')) return shot('Hook');
    }
    // Ground shots: the clip whose recorded direction is closest.
    String? best;
    var bestGap = 1e9;
    _clips.forEach((name, raw) {
      final m = raw as Map;
      if (m['contact'] == null ||
          name.startsWith('Loft') ||
          name.startsWith('Defence'))
        return;
      final gap = _angleGap(az, (m['shotAzimuthDeg'] as num).toDouble());
      if (gap < bestGap) {
        bestGap = gap;
        best = name;
      }
    });
    if (b.runs == 0 &&
        b.outcome == BallOutcome.dot &&
        az.abs() < 30 &&
        has('Defence_Forward'))
      return shot('Defence_Forward');
    return shot(best ?? 'Drive_Straight');
  }
}
