import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/replay_engine.dart';
import '../../domain/shot_trajectory.dart';
import '../../models/ball_event.dart';
import 'attached_mesh.dart';
import 'batting_clips.dart';
import 'glb_model.dart';
import 'hero_assets.dart';
import 'mesh3d.dart';
import 'scene3d.dart';
import 'stadium3d.dart';
import 'stadium_model.dart';

// ---------------------------------------------------------------------------
// World space: ground radius = 1, +y runs from the batter towards the bowler
// ("straight"), +x is the off side seen from behind a right-handed batter.
// The camera sits high behind the batter, so far things are smaller (2.5D).
// ---------------------------------------------------------------------------

const _tRelease = 0.30; // ball leaves the bowler's hand
const _tContact = 0.55; // ball reaches the bat

// Real dimensions: 1 world unit = 65 m (boundary radius). The pitch is 20.12 m
// between the stumps, a player is 1.8 m, stumps are 71 cm and the ball 7 cm.
const _metre = 1 / 65;

/// Height of one "z unit" used by the ball tracks (1.3 m).
const _zUnit = 1.3 * _metre;
const _playerHeight = 1.8 * _metre;

const _batStumps = Offset(0, -10.06 * _metre);
const _bowlStumps = Offset(0, 10.06 * _metre);
const _strikerHome = Offset(-0.6 * _metre, -9.6 * _metre);
const _strikerFar = Offset(-0.6 * _metre, 9.6 * _metre);
const _nonHome = Offset(0.9 * _metre, 9.8 * _metre);
const _nonFar = Offset(0.9 * _metre, -9.8 * _metre);
const _keeperHome = Offset(0, -23 * _metre);
const _hitPoint = ShotTrajectory.origin;
const _umpireHome = Offset(1.6 * _metre, 12.5 * _metre);

Offset _dirVec(double angleDeg) {
  final a = angleDeg * math.pi / 180;
  return Offset(math.sin(a), math.cos(a));
}

Offset _fielderHome(ShotDirection d) => fielderHome(d);

class _K {
  const _K(this.t, this.p, {this.z = 0, this.arc = 0, this.curve = Curves.linear});
  final double t;
  final Offset p;
  final double z;

  /// Extra height in the middle of the segment ending at this key (bounce / loft).
  final double arc;
  final Curve curve;
}

class _Track {
  _Track(this.keys, [this.tPerSec = 0.18]);
  final List<_K> keys;

  /// Clip units per second, so speeds can be measured in metres per second.
  final double tPerSec;

  int _seg(double t) {
    var i = 0;
    while (i < keys.length - 2 && t >= keys[i + 1].t) {
      i++;
    }
    return i;
  }

  Offset pos(double t) {
    if (keys.length == 1 || t <= keys.first.t) return keys.first.p;
    if (t >= keys.last.t) return keys.last.p;
    final i = _seg(t);
    final p = ((t - keys[i].t) / (keys[i + 1].t - keys[i].t)).clamp(0.0, 1.0);
    return Offset.lerp(keys[i].p, keys[i + 1].p, keys[i + 1].curve.transform(p))!;
  }

  double z(double t) {
    if (keys.length == 1 || t <= keys.first.t) return keys.first.z;
    if (t >= keys.last.t) return keys.last.z;
    final i = _seg(t);
    final p = ((t - keys[i].t) / (keys[i + 1].t - keys[i].t)).clamp(0.0, 1.0);
    final e = keys[i + 1].curve.transform(p);
    return keys[i].z + (keys[i + 1].z - keys[i].z) * e + keys[i + 1].arc * math.sin(math.pi * p);
  }

  /// 0..1 how fast the actor is moving (1 = a 6.5 m/s sprint), for the run cycle.
  double speed(double t) {
    if (t <= keys.first.t || t >= keys.last.t) return 0;
    final a = pos(t), b = pos(t + 0.01);
    return ((b - a).distance / 0.01 * 65 * tPerSec / 6.5).clamp(0.0, 1.0);
  }
}

class _Pose {
  const _Pose({
    this.run = 0,
    this.armL = -0.15,
    this.armR = 0.15,
    this.crouch = 0,
    this.lean = 0,
    this.plane = 0,
    this.cadence = -1,
    this.twist = 0,
    this.lift = 0,
    this.shift = 0,
    this.finger = false,
    this.headBow = 0,
    this.batSide = 0,
    this.bat,
    this.glove = false,
  });
  final double run; // 0..1 run-cycle amplitude
  final double armL, armR; // 0 = hanging down, pi = straight up, + = towards screen right
  final double crouch, lean;

  /// Arm swing plane: 0 = sideways, pi/2 = forwards / backwards.
  final double plane;

  /// Leg-cycle rate multiplier; negative = derived from the run speed.
  final double cadence;

  /// Upper-body turn relative to the legs (radians), jump height and a
  /// forward step, in body heights.
  final double twist, lift, shift;

  /// Raised index finger (the umpire's out signal).
  final bool finger;
  final bool glove;

  /// How far the head is bowed, 0..1 (smooth version of [headDown]).
  final double headBow;

  /// 0..1: the bat is carried in one hand at the side instead of held in front.
  final double batSide;
  final double? bat; // bat angle, same convention as arms
}

class _Actor {
  _Actor(this.world, this.yaw, this.shirt, this.pose,
      {this.helmet = false, this.label, this.umpire = false, this.variant = 0, this.hero = false, this.kit = KitLook.fielding, this.animTime, this.animBlend = 1.0, this.clip});
  final Offset world;

  /// Heading in radians: 0 faces down the pitch (+y), clockwise positive.
  final double yaw;
  final bool umpire;

  /// Drawn with the textured rigged model (when it has loaded).
  final bool hero;
  final KitLook kit;

  /// Seconds into the retargeted motion-capture batting clip (striker only).
  final double? animTime;

  /// Name of the batting clip (batsman model); [animTime] is then seconds into it.
  final String? clip;

  /// 1 = pose fully from the motion-capture clip, 0 = fully from the choreography.
  final double animBlend;

  /// Picks skin and hair so people don't all look the same.
  final int variant;
  V3 get base => V3(world.dx, world.dy, 0);
  final Color shirt;
  final _Pose pose;
  final bool helmet;
  final String? label;
}

// ---------------------------------------------------------------------------
// Timeline and physics helpers
// ---------------------------------------------------------------------------

/// Seconds the batters take for one run (20 m at about 7 m/s, plus the turn).
const _runSecs = 2.9;

/// The dismissed batter walks this way (behind the batting end, towards the pavilion).
const _walkHeading = Offset(-0.623, -0.782);

/// How many runs the batters physically run on this ball (0 if none).
int replayRunsRun(BallEvent b) {
  switch (b.outcome) {
    case BallOutcome.runs:
      return b.runs;
    case BallOutcome.noBall:
      return (b.runs >= 1 && b.runs <= 3) ? b.runs : 0;
    case BallOutcome.wide:
      return b.runsRan;
    case BallOutcome.bye:
    case BallOutcome.legBye:
      return b.extraRuns < 4 ? b.extraRuns : 0;
    case BallOutcome.wicket:
      return b.wicket == WicketType.runOut ? b.runs + 1 : 0;
    case BallOutcome.dot:
    case BallOutcome.four:
    case BallOutcome.six:
      return 0;
  }
}

/// Real-time length of this ball's clip at 1x. Run balls last long enough for
/// the batters to really run, and wickets have room for the walk off.
double replayClipSeconds(BallEvent b) {
  final n = replayRunsRun(b);
  switch (b.outcome) {
    case BallOutcome.wicket:
      return b.wicket == WicketType.runOut ? (3.4 + n * _runSecs + 1.0) / 0.46 : 13.0;
    case BallOutcome.six:
    case BallOutcome.four:
      return 8.2;
    case BallOutcome.runs:
      return 3.4 + n * _runSecs + 1.4;
    case BallOutcome.wide:
    case BallOutcome.noBall:
    case BallOutcome.bye:
    case BallOutcome.legBye:
      return 8.2 + n * _runSecs;
    case BallOutcome.dot:
      return 5.6;
  }
}

/// Slow motion around the moment the ball hits the stumps / pad.
double _slowMo(double x) {
  const pts = [(0.0, 0.0), (0.45, 0.47), (0.85, 0.64), (1.0, 1.0)];
  for (var i = 1; i < pts.length; i++) {
    if (x <= pts[i].$1) {
      final f = (x - pts[i - 1].$1) / (pts[i].$1 - pts[i - 1].$1);
      return pts[i - 1].$2 + (pts[i].$2 - pts[i - 1].$2) * f;
    }
  }
  return 1.0;
}

const _g = 9.81;

({double tanA, double cosA, double v, double seconds}) _ballisticSolve(double dMetres, double z0, double zT, double speed) {
  final dz = zT - z0;
  var v = speed;
  // The lowest speed that can reach the target; a longer throw needs more.
  final vMin = math.sqrt(_g * (dz + math.sqrt(dz * dz + dMetres * dMetres))) * 1.05;
  if (v < vMin) v = vMin;
  final disc = v * v * v * v - _g * (_g * dMetres * dMetres + 2 * dz * v * v);
  final tanA = (v * v - math.sqrt(math.max(0.0, disc))) / (_g * math.max(dMetres, 0.01)); // the flatter arc
  final cosA = 1 / math.sqrt(1 + tanA * tanA);
  return (tanA: tanA, cosA: cosA, v: v, seconds: dMetres / (v * cosA));
}

/// Flight time (seconds) of a throw from [from] (at [z0] m) to [to] (at [zT] m).
double _ballisticSeconds(Offset from, double z0, Offset to, double zT, double speed) =>
    _ballisticSolve((to - from).distance * 65, z0, zT, speed).seconds;

/// Adds keys for a ballistic flight: gravity, with the release angle solved from
/// the distance, the height difference and the speed. Longer throws arc higher.
/// Heights are in metres; returns the time (in clip units) the ball arrives.
double _ballistic(List<_K> keys, Offset from, double z0, Offset to, double zT, double t0, double tPerSec, {double speed = 26}) {
  final d = (to - from).distance * 65;
  if (d < 0.05) {
    keys.add(_K(t0, to, z: zT / 1.3));
    return t0;
  }
  final s = _ballisticSolve(d, z0, zT, speed);
  const n = 18;
  for (var i = 1; i <= n; i++) {
    final f = i / n;
    final x = d * f;
    final z = z0 + x * s.tanA - _g * x * x / (2 * s.v * s.v * s.cosA * s.cosA);
    keys.add(_K(t0 + s.seconds * f * tPerSec, Offset.lerp(from, to, f)!, z: math.max(0.0, z) / 1.3));
  }
  return t0 + s.seconds * tPerSec;
}

/// A physically simulated delivery: leaves the hand at 2.2 m, pitches, loses speed
/// and height in the bounce and reaches the bat at [zEnd] metres. Returns samples
/// of (time fraction, distance fraction, height in metres).
List<(double, double, double)> _deliveryProfile(double dist, double zEnd) {
  const z0 = 2.2, vx = 34.0, e = 0.62, loss = 0.85;
  double endHeight(double lb) {
    final tb = lb / vx;
    final vz0 = (0.5 * _g * tb * tb - z0) / tb;
    final vzb = vz0 - _g * tb;
    final vz1 = -e * vzb;
    final tr = (dist - lb) / (vx * loss);
    return vz1 * tr - 0.5 * _g * tr * tr;
  }

  var lb = dist * 0.7;
  var err = 1e9;
  for (var i = 0; i <= 80; i++) {
    final c = dist * 0.45 + (dist - 1.0 - dist * 0.45) * i / 80;
    final er = (endHeight(c) - zEnd).abs();
    if (er < err) {
      err = er;
      lb = c;
    }
  }
  final tb = lb / vx;
  final vz0 = (0.5 * _g * tb * tb - z0) / tb;
  final vzb = vz0 - _g * tb;
  final vz1 = -e * vzb;
  final tr = (dist - lb) / (vx * loss);
  final total = tb + tr;
  final out = <(double, double, double)>[];
  const n = 28;
  for (var k = 0; k <= n; k++) {
    final s = total * k / n;
    if (s <= tb) {
      out.add((s / total, vx * s / dist, math.max(0.0, z0 + vz0 * s - 0.5 * _g * s * s)));
    } else {
      final u = s - tb;
      out.add((s / total, (lb + vx * loss * u) / dist, math.max(0.0, vz1 * u - 0.5 * _g * u * u)));
    }
  }
  return out;
}

/// 2.5D animated delivery. The picture is a pure function of the recorded
/// ball and [t] (0..1), so the same scorecard always replays the same way.
class ReplayFieldPainter extends CustomPainter {
  ReplayFieldPainter({
    required this.step,
    required this.t,
    required this.strikerName,
    required this.nonStrikerName,
    required this.bowlerName,
    this.fielderName,
    this.assets,
    this.clipSeconds = 5.6,
    this.debugCamera,
  });

  final ReplayStep step;
  final double t;
  final String strikerName, nonStrikerName, bowlerName;
  final String? fielderName;
  final HeroAssets? assets;

  /// Real-time length of this clip at 1x (drives run timing and walking pace).
  final double clipSeconds;

  /// Test hook: (eye, target, fov) overrides the cinematic camera.
  final (double, double, double, double, double, double, double)? debugCamera;

  static const _batting = Color(0xFF1E66D0);
  static const _fielding = Color(0xFFD64545);
  static const _keeperColor = Color(0xFFF2A516);
  static const _umpireColor = Color(0xFF263238);

  late Cam3 _cam;
  late MeshBuilder _mb;
  late MeshBuilder _mbTop;
  final List<_HeroJob> _heroJobs = [];
  final List<(String, Offset)> _labels = [];

  @override
  void paint(Canvas canvas, Size size) {

    final b = step.ball;
    final out = b.outcome;
    final secs = clipSeconds;
    final realT = this.t;
    final signalKind0 = _signalFor(b);
    final isWicket = out == BallOutcome.wicket;
    final stumpHit = isWicket && (b.wicket == WicketType.bowled || b.wicket == WicketType.lbw);
    final nRuns = replayRunsRun(b);

    // Phases of the clip. Signals: action, then the umpire cutaway. Wickets: action,
    // umpire, then the dismissed batter walks off.
    const wicketAction = 0.46, wicketCut = 0.60;
    const signalCut = 0.72;
    const preSecs = 3.4; // delivery up to the shot
    final cutBeg = isWicket ? wicketAction : signalCut;
    final cutEnd = isWicket ? wicketCut : 1.0;
    final hasCut = isWicket || signalKind0 != _Umpire.none;
    final inCut = hasCut && realT >= cutBeg && realT < cutEnd;
    final walking = isWicket && realT >= wicketCut;
    final walkSec = walking ? (realT - wicketCut) * secs : 0.0;
    final actionFrac = isWicket ? wicketAction : (signalKind0 != _Umpire.none ? signalCut : 1.0);
    final actionSecs = secs * actionFrac;
    final x = hasCut ? (realT / cutBeg).clamp(0.0, 1.0) : realT;
    // Clip time t: 0..1 over the action. Run balls play the delivery in real time,
    // then give each run its real duration.
    final p0 = preSecs / actionSecs;
    final double t = nRuns > 0
        ? (x < p0 ? x / p0 * 0.58 : 0.58 + (x - p0) / (1 - p0) * 0.42)
        : (stumpHit ? _slowMo(x) : x);
    final tPerSecPost = nRuns > 0 ? 0.42 / (actionSecs - preSecs) : 1 / actionSecs;
    final tPerSec = tPerSecPost;
    final tPerSecPre = nRuns > 0 ? 0.58 / preSecs : tPerSec;
    // The batting clip comes from the recorded shot (never random). The clip's own
    // contact point also tells us how high the ball meets the bat and where the
    // batsman has to stand for the bat to meet it.
    final batClips = assets?.battingClips;
    final shotPlan = batClips?.choose(b);
    final hasContactShot = shotPlan?.contactPoint != null &&
        (out == BallOutcome.runs ||
            out == BallOutcome.four ||
            out == BallOutcome.six ||
            out == BallOutcome.dot ||
            (out == BallOutcome.noBall && b.runs > 0) ||
            (out == BallOutcome.wicket && (b.wicket == WicketType.caught || b.wicket == WicketType.runOut)));
    final contactZ = ((shotPlan?.contactPoint?.y ?? 0.65).clamp(0.15, 1.5)) / 1.3;
    final stumpIdx = (step.over + step.ballInOver) % 3 - 1; // which stump the ball hits
    // The drawn path (if any) is the source of truth for where the ball went;
    // otherwise fall back to the recorded direction (unrecorded => straight).
    final recorded = b.shotPath != null && b.shotPath!.length >= 2;
    final recordedPlan = recorded ? ShotTrajectory(b.shotPath!, b.loft ?? ShotLoft.ground) : null;
    final dir = recordedPlan?.direction ?? b.shotDirection ?? ShotDirection.straight;
    final dirAngle = recordedPlan?.endAngle ?? b.shotDirection?.angle ?? 0;

    ShotTrajectory planFor(double frac, ShotLoft fallback, {double? reach, ShotLoft? minLoft}) {
      var tr = recordedPlan != null
          ? ShotTrajectory(recordedPlan.points, b.loft ?? fallback)
          : ShotTrajectory.fromDirection(dir, frac, fallback);
      if (reach != null) {
        tr = tr.extendedTo(reach, minLoft: minLoft);
      } else if (minLoft != null && tr.loft.index < minLoft.index) {
        tr = ShotTrajectory(tr.points, minLoft);
      }
      return tr;
    }


    // ---- choreography ---------------------------------------------------
    final ball = <_K>[];
    var ballVisible = true;
    final runKeysStriker = <_K>[const _K(0, _strikerHome)];
    final runKeysNon = <_K>[const _K(0, _nonHome)];
    final fielder = <_K>[_K(0, _fielderHome(dir))];
    final keeper = <_K>[const _K(0, _keeperHome)];
    final extraFielders = <ShotDirection, Offset>{}; // neighbours stepping in
    double? breakAt; // stumps at the batter's end
    double? bowlEndBreak; // stumps at the bowler's end
    double? swingAt; // bat meets ball
    var swingKind = _Swing.none;
    var runStart = 0.6;
    final runDur = _runSecs * tPerSecPost;
    double? catchAt, throwAt, pickupAt;
    double? celebrateAt; // bowler's side celebrates
    var batterOut = false;
    var outIsStriker = true;
    var umpire = _Umpire.none;
    double umpireAt = 0.6;
    double? boundaryAt;
    var chosenActive = false;
    var strikerStepOut = false;
    var keeperChase = false;
    Offset? caughtBallAt;

    const bowlerRelease = Offset(0.4 * _metre, 8.8 * _metre);
    ball.add(const _K(0, bowlerRelease, z: 1.7));
    ball.add(const _K(_tRelease, bowlerRelease, z: 1.7));

    // The delivery is simulated: it leaves the hand at 2.2 m, pitches, loses speed
    // and height in the bounce and arrives at [z] (units of 1.3 m) at the bat.
    void deliver(Offset to, {double z = 0.5, double end = _tContact}) {
      final dist = (to - bowlerRelease).distance * 65;
      final prof = _deliveryProfile(dist, z * 1.3);
      for (final p in prof.skip(1)) {
        final pos = Offset.lerp(bowlerRelease, to, p.$2)! + Offset(0.25 * _metre * math.sin(math.pi * p.$2), 0);
        ball.add(_K(_tRelease + (end - _tRelease) * p.$1, pos, z: p.$3 / 1.3));
      }
    }

    /// The ball leaves the bat and follows the recorded path, skipping /
    /// bouncing / flying according to its loft.
    void batShot({required double end, required ShotTrajectory plan, bool chase = true}) {
      deliver(_hitPoint, z: contactZ);
      const n = 36;
      for (var i = 1; i <= n; i++) {
        final tau = i / n;
        final sp = plan.progress(tau);
        ball.add(_K(_tContact + (end - _tContact) * tau, plan.pointAt(sp), z: plan.heightAt(sp)));
      }
      swingAt = _tContact;
      chosenActive = chase;
    }

    void ran(int n) {
      var from = _strikerHome, toP = _strikerFar;
      var nFrom = _nonHome, nTo = _nonFar;
      for (var i = 0; i < n; i++) {
        final t0 = runStart + i * runDur;
        // Run to the opposite crease (about 80% of the time), then turn and go back.
        final tRun = t0 + runDur * 0.78;
        runKeysStriker
          ..add(_K(t0, from))
          ..add(_K(tRun, toP, curve: Curves.easeInOut));
        runKeysNon
          ..add(_K(t0, nFrom))
          ..add(_K(tRun, nTo, curve: Curves.easeInOut));
        final a = from;
        from = toP;
        toP = a;
        final c = nFrom;
        nFrom = nTo;
        nTo = c;
      }
    }

    /// The fielder collects the ball, waits for the batters to finish the runs, then
    /// throws with a ballistic arc. Returns the time the ball arrives.
    double fieldAndThrow(Offset ballEnd, double arrive) {
      fielder.add(_K(_tContact + 0.03, _fielderHome(dir)));
      fielder.add(_K(arrive, ballEnd, curve: Curves.easeInOut));
      pickupAt = arrive;
      final to = _keeperHome + const Offset(0, 0.6 * _metre);
      final flightT = _ballisticSeconds(ballEnd, 1.6, to, 1.0, 27) * tPerSecPost;
      final throwStart = math.max(arrive + 0.02, runStart + nRuns * runDur - flightT - 0.03);
      throwAt = throwStart;
      ball.add(_K(throwStart, ballEnd, z: 1.6 / 1.3));
      final t1 = _ballistic(ball, ballEnd, 1.6, to, 1.0, throwStart, tPerSecPost, speed: 27);
      keeper.add(_K(arrive, _keeperHome));
      keeper.add(_K(t1, _keeperHome));
      catchAt = t1;
      return t1;
    }

    switch (out) {
      case BallOutcome.dot:
        final hasDir = recorded || b.shotDirection != null;
        final plan = hasDir
            ? planFor(0.14, ShotLoft.ground)
            : ShotTrajectory([ShotTrajectory.origin, ShotTrajectory.origin + const Offset(0, -0.012)], ShotLoft.ground);
        batShot(end: 0.66, plan: plan, chase: hasDir);
        swingKind = _Swing.defend;
        if (hasDir) fielder.add(_K(0.8, Offset.lerp(_fielderHome(dir), plan.end, 0.5)!, curve: Curves.easeOut));
      case BallOutcome.runs:
        final plan = planFor(0.18 + 0.14 * b.runs, ShotLoft.ground);
        batShot(end: 0.8, plan: plan);
        swingKind = _Swing.drive;
        ran(b.runs);
        fieldAndThrow(plan.end, 0.8);
      case BallOutcome.four:
        final plan = planFor(0.98, ShotLoft.ground, reach: 0.98);
        batShot(end: 0.86, plan: plan);
        swingKind = _Swing.drive;
        fielder.add(_K(0.58, _fielderHome(dir)));
        fielder.add(_K(0.8, Offset.lerp(_fielderHome(dir), plan.end, 0.4)!, curve: Curves.easeOut));
        boundaryAt = 0.86;
      case BallOutcome.six:
        final plan = planFor(1.14, ShotLoft.aerial, reach: 1.14, minLoft: ShotLoft.aerial);
        batShot(end: 0.9, plan: plan);
        swingKind = _Swing.lofted;
        fielder.add(_K(0.58, _fielderHome(dir)));
        fielder.add(_K(0.82, Offset.lerp(_fielderHome(dir), plan.end, 0.5)!, curve: Curves.easeOut));
        boundaryAt = 0.9;
      case BallOutcome.noBall:
        umpire = _Umpire.noBall;
        umpireAt = _tRelease;
        final r = b.runs;
        if (r == 6) {
          batShot(end: 0.9, plan: planFor(1.14, ShotLoft.aerial, reach: 1.14, minLoft: ShotLoft.aerial));
          swingKind = _Swing.lofted;
          boundaryAt = 0.9;
        } else if (r == 4) {
          batShot(end: 0.86, plan: planFor(0.98, ShotLoft.ground, reach: 0.98));
          swingKind = _Swing.drive;
          boundaryAt = 0.86;
        } else if (r == 0) {
          batShot(end: 0.66, plan: ShotTrajectory.fromDirection(ShotDirection.straight, 0.1, ShotLoft.ground), chase: false);
          swingKind = _Swing.defend;
        } else {
          final plan = planFor(0.18 + 0.14 * r, ShotLoft.ground);
          batShot(end: 0.8, plan: plan);
          swingKind = _Swing.drive;
          ran(r);
          fieldAndThrow(plan.end, 0.8);
        }
        if (r == 4 || r == 6) {
          fielder.add(_K(0.58, _fielderHome(dir)));
          fielder.add(_K(0.8, Offset.lerp(_fielderHome(dir), ball.last.p, 0.4)!, curve: Curves.easeOut));
        }
      case BallOutcome.wide:
        umpire = _Umpire.wide;
        deliver(const Offset(2.0 * _metre, -9.6 * _metre), z: 0.6);
        ball.add(const _K(0.66, Offset(1.0 * _metre, -23 * _metre), z: 0.7, arc: 0.1, curve: Curves.easeOut));
        keeper.add(const _K(_tContact - 0.05, _keeperHome));
        keeper.add(const _K(0.62, Offset(1.0 * _metre, -23 * _metre), curve: Curves.easeOut));
        catchAt = 0.66;
        swingKind = _Swing.leave;
        runStart = 0.66;
        ran(b.runsRan);
      case BallOutcome.bye:
      case BallOutcome.legBye:
        umpire = out == BallOutcome.bye ? _Umpire.bye : _Umpire.legBye;
        final leg = out == BallOutcome.legBye;
        deliver(leg ? _hitPoint : const Offset(0, -10 * _metre), z: 0.5);
        swingKind = leg ? _Swing.defend : _Swing.miss;
        swingAt = _tContact;
        if (b.extraRuns >= 4) {
          ball.add(_K(0.86, Offset(leg ? -0.3 : 0, -1.0), z: 0, curve: Curves.easeOut));
          keeper.add(const _K(0.58, _keeperHome));
          keeper.add(_K(0.8, Offset(leg ? -0.2 : 0, -0.65), curve: Curves.easeOut));
          keeperChase = true;
          boundaryAt = 0.86;
        } else {
          ball.add(_K(0.66, leg ? const Offset(-1.5 * _metre, -22 * _metre) : _keeperHome + const Offset(0, 0.4 * _metre), z: 0.5, arc: 0.1, curve: Curves.easeOut));
          catchAt = 0.66;
          runStart = 0.62;
          ran(b.extraRuns);
        }
      case BallOutcome.wicket:
        celebrateAt = 0.62;
        umpire = _Umpire.out;
        batterOut = true;
        switch (b.wicket!) {
          case WicketType.bowled:
            deliver(Offset(stumpIdx * 0.114 * _metre, _batStumps.dy), z: 0.27, end: _tContact);
            // After the impact the ball drops behind the stumps and rolls on towards the keeper.
            final tDrop = _ballistic(ball, Offset(stumpIdx * 0.114 * _metre, _batStumps.dy), 0.35, Offset(0, -14 * _metre), 0.0, _tContact, tPerSec, speed: 7);
            ball.add(_K(tDrop + 0.05, _keeperHome + const Offset(0, 2 * _metre), curve: Curves.easeOut));
            breakAt = _tContact;
            swingKind = _Swing.miss;
            swingAt = _tContact - 0.04;
            umpireAt = 0.72;
          case WicketType.hitWicket:
            deliver(_hitPoint, z: 0.45);
            _ballistic(ball, _hitPoint, 0.5, Offset(0.6 * _metre, -17 * _metre), 0.0, _tContact, tPerSec, speed: 6);
            breakAt = 0.6;
            swingKind = _Swing.drive;
            swingAt = _tContact;
            umpireAt = 0.74;
          case WicketType.lbw:
            deliver(_hitPoint, z: 0.38);
            _ballistic(ball, _hitPoint, 0.5, Offset(-0.5 * _metre, -8.0 * _metre), 0.0, _tContact, tPerSec, speed: 4);
            swingKind = _Swing.miss;
            swingAt = _tContact;
            umpireAt = 0.8;
            celebrateAt = 0.6;
          case WicketType.caught:
            final home = _fielderHome(dir);
            final plan = planFor(fielderRadius[dir]! - 0.08, ShotLoft.lofted, minLoft: ShotLoft.lofted);
            final landing = plan.end;
            batShot(end: 0.78, plan: plan, chase: false);
            swingKind = _Swing.lofted;
            fielder
              ..clear()
              ..add(_K(0, home))
              ..add(_K(0.58, home))
              ..add(_K(0.78, landing, curve: Curves.easeOut));
            catchAt = 0.78;
            caughtBallAt = landing;
            ball.add(_K(1.0, landing, z: 0.7));
            chosenActive = true;
            celebrateAt = 0.8;
            umpireAt = 0.86;
          case WicketType.stumped:
            deliver(_hitPoint + const Offset(0, -0.4 * _metre), z: 0.4);
            ball.add(const _K(0.64, Offset(0, -22 * _metre), z: 0.55, curve: Curves.easeOut));
            keeper.add(const _K(0.6, _keeperHome));
            catchAt = 0.64;
            breakAt = 0.7;
            swingKind = _Swing.miss;
            swingAt = _tContact - 0.03;
            strikerStepOut = true;
            umpireAt = 0.82;
            celebrateAt = 0.74;
          case WicketType.runOut:
            outIsStriker = b.outPlayerId == null || b.outPlayerId == b.strikerId;
            final done = b.runs;
            final plan = planFor(0.32, ShotLoft.ground);
            final end = plan.end;
            batShot(end: 0.7, plan: plan);
            swingKind = _Swing.drive;
            // Complete `done` runs, then a final one that falls short.
            ran(done);
            final lastT = runStart + done * runDur;
            final fromStriker = runKeysStriker.last.p;
            final fromNon = runKeysNon.last.p;
            final partialEnd = lastT + runDur * 0.7;
            runKeysStriker.add(_K(lastT, fromStriker));
            runKeysStriker.add(_K(partialEnd, Offset.lerp(fromStriker, fromStriker == _strikerHome ? _strikerFar : _strikerHome, 0.8)!, curve: Curves.easeOut));
            runKeysNon.add(_K(lastT, fromNon));
            runKeysNon.add(_K(partialEnd, Offset.lerp(fromNon, fromNon == _nonHome ? _nonFar : _nonHome, 0.8)!, curve: Curves.easeOut));
            // Throw at the stumps the out batter is running to.
            final cur = outIsStriker ? fromStriker : fromNon;
            final stumpsTarget = cur.dy < 0 ? _bowlStumps : _batStumps;
            final flightT = _ballisticSeconds(end, 1.6, stumpsTarget, 0.5, 28) * tPerSec;
            final arriveT = math.max(partialEnd - 0.01, _tContact + 0.2 + flightT);
            final throwStart = arriveT - flightT;
            fielder
              ..clear()
              ..add(_K(0, _fielderHome(dir)))
              ..add(_K(_tContact + 0.03, _fielderHome(dir)))
              ..add(_K(throwStart - 0.02, end, curve: Curves.easeInOut));
            pickupAt = throwStart - 0.02;
            throwAt = throwStart;
            ball.add(_K(throwStart, end, z: 1.6 / 1.3));
            _ballistic(ball, end, 1.6, stumpsTarget, 0.5, throwStart, tPerSec, speed: 28);
            if (stumpsTarget == _bowlStumps) {
              bowlEndBreak = arriveT;
            } else {
              breakAt = arriveT;
            }
            celebrateAt = arriveT + 0.02;
            umpireAt = arriveT + 0.04;
        }
    }

    // Idle neighbours step towards the ball when it has been hit.
    if (chosenActive || out == BallOutcome.four || out == BallOutcome.six) {
      final end = ball.last.p;
      for (final d in ShotDirection.values) {
        if (d == dir) continue;
        var diff = (d.angle - dirAngle).abs();
        if (diff > 180) diff = 360 - diff;
        if (diff <= 70) {
          extraFielders[d] = Offset.lerp(_fielderHome(d), end, 0.22)!;
        }
      }
    }

    final ballTrack = _Track(ball);
    final strikerTrack = _Track(runKeysStriker, tPerSecPost);
    final nonTrack = _Track(runKeysNon, tPerSecPost);
    final fielderTrack = _Track(fielder, tPerSecPost);
    final keeperTrack = _Track(keeper, tPerSecPost);

    final catchAtF = catchAt;
    final throwAtF = throwAt;
    final pickupAtF = pickupAt;
    final swingAtF = swingAt;
    final breakAtF = breakAt;
    final bowlEndBreakF = bowlEndBreak;
    final celebrateAtF = celebrateAt;
    final boundaryAtF = boundaryAt;

    // ---- bowler ---------------------------------------------------------
    final bowlerTrack = _Track([
      const _K(0, Offset(-0.03, 0.4)),
      const _K(0.27, Offset(0.008, 0.138), curve: Curves.easeIn),
      const _K(0.5, Offset(0.0, 0.07), curve: Curves.easeOut),
    ], tPerSecPre);

    double yawTo(Offset from, Offset to) => math.atan2(to.dx - from.dx, to.dy - from.dy);
    double moveYaw(_Track tr, double fallback) {
      final a = tr.pos(t);
      var b2 = tr.pos(t + 0.01);
      if ((b2 - a).distance < 1e-5) b2 = tr.pos(t + 0.05); // waiting at the crease: face the next leg
      if ((b2 - a).distance < 1e-5) return fallback;
      return yawTo(a, b2);
    }

    final ballNow = ballTrack.pos(t);
    final actors = <_Actor>[];
    final phase = this.t * clipSeconds * 9.0;

    // Bowler.
    {
      final p = bowlerTrack.pos(t);
      final run = bowlerTrack.speed(t);
      final arm = ((t - 0.2) / 0.14).clamp(0.0, 1.0);
      final celebrating = celebrateAtF != null && t >= celebrateAtF;
      double aR, aL;
      var plane = math.pi / 2;
      if (celebrating) {
        aR = math.pi - 0.3;
        aL = -(math.pi - 0.3);
        plane = 0;
      } else if (t >= 0.2 && t <= 0.36) {
        aR = -arm * 2 * math.pi; // overarm circle, back-up-over-forward
        aL = 2.5 * math.sin(math.pi * arm); // front arm reaches up and across
      } else {
        aR = 0.7 * math.sin(phase + math.pi) * run;
        aL = 0.7 * math.sin(phase) * run;
      }
      final bound = ((t - 0.2) / 0.12).clamp(0.0, 1.0);
      final windUp = ((t - 0.2) / 0.1).clamp(0.0, 1.0);
      final through = ((t - 0.3) / 0.12).clamp(0.0, 1.0);
      final twist = t < 0.2 ? 0.0 : -0.8 * windUp + 1.6 * through * (t < 0.3 ? 0 : 1);
      final lean = t < 0.3
          ? 0.08
          : 0.08 + 0.32 * ((t - 0.3) / 0.15).clamp(0.0, 1.0) * (1 - ((t - 0.5) / 0.3).clamp(0.0, 1.0));
      actors.add(_Actor(
          p,
          math.pi,
          _fielding,
          _Pose(
            run: run,
            armL: aL,
            armR: aR,
            plane: plane,
            lean: lean,
            twist: celebrating ? 0 : twist.clamp(-0.8, 0.8),
            lift: 0.1 * math.sin(math.pi * bound),
            crouch: t > 0.3 && t < 0.42 ? 0.5 : 0,
          ),
          label: bowlerName,
          hero: true,
          variant: 4,
          kit: KitLook.fielding));
    }

    // Umpire.
    {
      var aR = 0.12, aL = -0.12;
      var finger = false;
      var yawU = math.pi + 0.5;
      var crouchU = 0.0;
      if (inCut) {
        // Cutaway: he turns to the camera and gives the signal.
        yawU = 0.12;
        final u = ((realT - cutBeg) / (cutEnd - cutBeg)).clamp(0.0, 1.0);
        final rise = Curves.easeOut.transform((u / 0.22).clamp(0.0, 1.0));
        double up(double to) => 0.3 + (to - 0.3) * rise;
        switch (signalKind0) {
          case _Umpire.four:
            aR = up(1.0) + 0.6 * math.sin(u * 24) * rise; // arm waved across the body
          case _Umpire.six:
            aR = up(math.pi - 0.15);
            aL = -aR;
          case _Umpire.out:
            aR = up(math.pi - 0.1);
            finger = rise > 0.8;
          case _Umpire.wide:
            aR = up(math.pi / 2);
            aL = -aR;
          case _Umpire.noBall:
            aR = up(math.pi / 2);
          case _Umpire.bye:
            aR = up(math.pi - 0.25);
          case _Umpire.legBye:
            aR = 0.35;
            crouchU = 0.2;
          case _Umpire.none:
        }
      } else if (umpire != _Umpire.none && t >= umpireAt && !walking) {
        switch (umpire) {
          case _Umpire.out:
            aR = math.pi - 0.1;
          case _Umpire.wide:
            aR = math.pi / 2;
            aL = -math.pi / 2;
          case _Umpire.noBall:
            aR = math.pi / 2;
          case _Umpire.bye:
            aR = math.pi - 0.2;
          case _Umpire.legBye:
            aR = 0.5;
          case _Umpire.four:
          case _Umpire.six:
          case _Umpire.none:
        }
      }
      actors.add(_Actor(_umpireHome, yawU, _umpireColor, _Pose(armL: aL, armR: aR, finger: finger, crouch: crouchU), umpire: true, variant: 7, hero: true, kit: KitLook.umpire));
    }

    // Keeper.
    {
      final p = keeperTrack.pos(t);
      final catching = catchAtF != null && t >= catchAtF - 0.06;
      final breaking = breakAtF != null && t >= breakAtF - 0.04 && b.wicket == WicketType.stumped;
      final reach = catching || breaking;
      actors.add(_Actor(
          p,
          keeperChase ? moveYaw(keeperTrack, math.pi) : 0,
          _keeperColor,
          _Pose(
            run: keeperChase ? keeperTrack.speed(t) : 0,
            armL: reach ? 0.62 * math.pi : 0.5,
            armR: reach ? 0.62 * math.pi : 0.5,
            plane: reach ? math.pi / 2 : 0.6,
            crouch: 0.7,
            glove: true,
          ),
          hero: true,
          variant: 6,
          kit: KitLook.keeper));
    }

    // Fielders.
    for (final d in ShotDirection.values) {
      var p = _fielderHome(d);
      var yaw = yawTo(p, _batStumps);
      var pose = const _Pose(crouch: 0.3, armL: 0.5, armR: 0.5, plane: 0.5);
      String? label;
      final chosen = d == dir &&
          (chosenActive || out == BallOutcome.four || out == BallOutcome.six || out == BallOutcome.runs);
      if (chosen) {
        p = fielderTrack.pos(t);
        final speed = fielderTrack.speed(t);
        final caught = out == BallOutcome.wicket && b.wicket == WicketType.caught;
        yaw = t > 0.56 ? (speed > 0.05 ? moveYaw(fielderTrack, yaw) : yawTo(p, ballNow)) : yaw;
        if (caught && catchAtF != null && t >= catchAtF - 0.05) {
          pose = _Pose(armL: -(math.pi - 0.35), armR: math.pi - 0.35, glove: true);
          if (celebrateAtF != null && t >= celebrateAtF) {
            pose = _Pose(armL: -(math.pi - 0.3), armR: math.pi - 0.3);
          }
          if (t >= catchAtF) label = fielderName;
        } else if (pickupAtF != null && t >= pickupAtF && t < (throwAtF ?? pickupAtF)) {
          pose = const _Pose(crouch: 0.9, armL: 0.7, armR: 0.7, plane: math.pi / 2, lean: 0.14);
        } else if (throwAtF != null && t >= throwAtF && t < throwAtF + 0.06) {
          pose = _Pose(armR: math.pi * (1 - (t - throwAtF) / 0.06), armL: -0.6, plane: math.pi / 2);
        } else if (out == BallOutcome.six && t > 0.6) {
          pose = const _Pose(armL: -0.4, armR: 0.4, lean: -0.05); // watches it sail over
        } else {
          pose = _Pose(
              run: speed,
              armL: 0.8 * math.sin(phase) * speed,
              armR: 0.8 * math.sin(phase + math.pi) * speed,
              plane: math.pi / 2,
              crouch: speed > 0.05 ? 0 : 0.3);
        }
      } else if (extraFielders.containsKey(d)) {
        final p0 = _fielderHome(d);
        final k = ((t - 0.58) / 0.15).clamp(0.0, 1.0);
        p = Offset.lerp(p0, extraFielders[d]!, Curves.easeOut.transform(k))!;
        final sp = k > 0 && k < 1 ? 1.0 : 0.0;
        yaw = k > 0 ? yawTo(p0, extraFielders[d]!) : yaw;
        pose = _Pose(
            run: sp,
            armL: 0.7 * math.sin(phase) * sp,
            armR: 0.7 * math.sin(phase + math.pi) * sp,
            plane: sp > 0 ? math.pi / 2 : 0.5,
            crouch: sp > 0 ? 0 : 0.3);
      }
      actors.add(_Actor(p, yaw, _fielding, pose, label: label, variant: d.index + 2, hero: true, kit: KitLook.fielding));
    }

    // Batters.
    Offset? outBatterPos;
    {
      final sp = strikerTrack.pos(t);
      final np = nonTrack.pos(t);
      final sRun = strikerTrack.speed(t);
      final nRun = nonTrack.speed(t);
      var sPos = sp;
      if (strikerStepOut && t > 0.45) {
        sPos = Offset.lerp(_strikerHome, _strikerHome + const Offset(0.3 * _metre, 3.0 * _metre),
            Curves.easeOut.transform(((t - 0.45) / 0.12).clamp(0.0, 1.0)))!;
      }
      var sYaw = 0.0;

      // The dismissed batter reacts (head drops, shoulders sag), turns on the spot with a
      // little shuffle of the feet, then eases into an ordinary walk (1.5 m/s) to the pavilion.
      ({Offset pos, double yaw, double speed, double turn, double sign}) walkOff(Offset start, double yaw0) {
        const reactS = 1.4, turnS = 1.4, ramp = 0.9, pace = 1.5;
        final heading = yawTo(Offset.zero, _walkHeading);
        final turnP = ((walkSec - reactS) / turnS).clamp(0.0, 1.0);
        final turn = Curves.easeInOut.transform(turnP);
        final s = math.max(0.0, walkSec - reactS - turnS * 0.6);
        final dist = pace * (s < ramp ? s * s / (2 * ramp) : ramp / 2 + (s - ramp));
        var d = heading - yaw0;
        while (d > math.pi) {
          d -= 2 * math.pi;
        }
        while (d < -math.pi) {
          d += 2 * math.pi;
        }
        return (pos: start + _walkHeading * (dist / 65), yaw: yaw0 + d * turn, speed: (s / ramp).clamp(0.0, 1.0), turn: turnP, sign: d >= 0 ? 1.0 : -1.0);
      }

      final strikerEndPos = strikerStepOut ? _strikerHome + const Offset(0.3 * _metre, 3.0 * _metre) : strikerTrack.pos(1.0);
      final endLook = strikerTrack.pos(0.97);
      final strikerEndYaw = (strikerEndPos - endLook).distance > 1e-5 ? yawTo(endLook, strikerEndPos) : 0.0;
      var walkBlend = 0.0; // 0 = still in the action pose, 1 = fully in the walking pose
      var walkSpeed = 0.0;
      var turnShuffle = 0.0;
      var turnTwist = 0.0;
      if (walking && outIsStriker) {
        final w = walkOff(strikerEndPos, strikerEndYaw);
        sPos = w.pos;
        sYaw = w.yaw;
        walkSpeed = w.speed;
        walkBlend = Curves.easeInOut.transform((walkSec / 1.0).clamp(0.0, 1.0));
        turnShuffle = math.sin(math.pi * w.turn);
        turnTwist = 0.4 * turnShuffle * w.sign;
        outBatterPos = sPos;
      }

      final running = sRun > 0.05;
      if (running) sYaw = moveYaw(strikerTrack, 0);
      final swinging = swingAtF != null && !running;
      final swingP = swingAtF == null ? 0.0 : ((t - (swingAtF - 0.07)) / 0.16).clamp(0.0, 1.0);
      final sBat = _batAngle(swingKind, swingP, dirAngle, t);
      final walkRun = 0.32 * walkSpeed + 0.22 * turnShuffle; // shuffles while turning, then walks
      final sRunEff = sRun * (1 - walkBlend) + walkRun * walkBlend;
      // The batting clip plays so the bat meets the ball at t = 0.55 (its contact time is
      // 1.0 s into the clip). It is blended away when the batter sets off, celebrates or
      // walks off, and the stance clip blends back in when he is again at the batting end.
      double? mocapT;
      String? clipName;
      var animBlend = 1.0;
      final stepping = strikerStepOut && t > 0.45;
      if (!stepping) {
        if (batClips != null && shotPlan != null) {
          clipName = shotPlan.clip;
          final tc = shotPlan.contactTime ?? 1.0;
          const pace = 0.75; // clip seconds per real second: unhurried against a 1.4 s delivery
          final perSec = t < _tContact ? tPerSecPre : tPerSecPost;
          mocapT = (tc + (t - _tContact) / perSec * pace).clamp(0.0, shotPlan.duration);
        } else {
          // Fallback when the batsman model is missing: the retargeted captured clip.
          final hits = swingKind != _Swing.none && swingKind != _Swing.leave;
          if (t < 0.25) {
            mocapT = 0;
          } else if (t < 0.5) {
            mocapT = (t - 0.25) / 0.25 * 1.0;
          } else if (!hits) {
            mocapT = 1.0;
          } else if (t < 0.55) {
            mocapT = 1.0 + (t - 0.5) / 0.05 * 0.25;
          } else {
            mocapT = 1.25 + Curves.easeOut.transform(((t - 0.55) / 0.22).clamp(0.0, 1.0)) * 0.95;
          }
        }
        final tLeave = nRuns > 0 ? runStart - 0.02 : (boundaryAtF != null ? boundaryAtF - 0.04 : null);
        if (tLeave != null) animBlend = 1 - Curves.easeInOut.transform(((t - tLeave) / 0.1).clamp(0.0, 1.0));
        // After an even number of runs he is back at the batting end: settle into the stance.
        if (batClips != null && nRuns > 0 && nRuns.isEven && !isWicket) {
          final tBack = runStart + (nRuns - 1) * runDur + runDur * 0.78;
          if (t > tBack) {
            clipName = BattingClips.stance;
            mocapT = ((t - tBack) / tPerSecPost * 0.75) % 2.0;
            animBlend = Curves.easeInOut.transform(((t - tBack) / 0.08).clamp(0.0, 1.0));
          }
        }
        if (walkBlend > 0) animBlend = math.min(animBlend, 1 - walkBlend);
        if (animBlend <= 0.001) mocapT = null;
      } else {
        animBlend = 0;
      }
      // Shuffle into line so the bat meets the ball where the ball actually is (at most
      // 0.35 m), easing in over the trigger and holding after contact.
      final sc = shotPlan?.contactPoint;
      if (hasContactShot && sc != null) {
        final want = _hitPoint - Offset(-sc.x * _metre, sc.z * _metre) - _strikerHome;
        final maxLen = 0.35 * _metre;
        final shuffle = want.distance > maxLen ? want / want.distance * maxLen : want;
        final tcs = shotPlan?.contactTime ?? 1.0;
        final u = (((t < _tContact ? tcs + (t - _tContact) / tPerSecPre * 0.75 : tcs + 1.0) - 0.2) / (tcs - 0.2)).clamp(0.0, 1.0);
        sPos = sPos + shuffle * (u * u * (3 - 2 * u));
      }
      final side = dirAngle > 8 ? 1.0 : (dirAngle < -8 ? -1.0 : 0.0);
      final swingEase = swinging ? Curves.easeInOut.transform(swingP) : 0.0;
      final lean = (swinging && swingP > 0 && swingP < 1) ? 0.08 : 0.0;
      final headBow = batterOut && outIsStriker ? math.max(Curves.easeInOut.transform(((t - (_tContact + 0.06)) / 0.12).clamp(0.0, 1.0)), walkBlend) : 0.0;
      final celebrate = boundaryAtF != null &&
          t > boundaryAtF - 0.04 &&
          b.outcome != BallOutcome.bye &&
          b.outcome != BallOutcome.legBye;
      actors.add(_Actor(
        sPos,
        sYaw,
        _batting,
        _Pose(
          run: sRunEff,
          armL: 0.8 * math.sin(phase) * sRunEff,
          armR: 0.8 * math.sin(phase + math.pi) * sRunEff,
          cadence: walkBlend > 0 ? 0.55 : -1,
          plane: math.pi / 2,
          bat: (running && walkBlend == 0) ? null : (celebrate ? math.pi - 0.5 : sBat * (1 - walkBlend) + 0.3 * walkBlend),
          lean: (lean + (running ? 0.18 : 0)) * (1 - walkBlend) + 0.06 * walkBlend,
          crouch: (running || celebrate ? 0.0 : 0.3 - 0.15 * swingEase) * (1 - walkBlend) + 0.1 * walkBlend,
          headBow: headBow,
          batSide: walkBlend,
          twist: (swinging ? (side == 0 ? 0.25 : side * 0.9) * swingEase : 0.0) * (1 - walkBlend) + turnTwist,
          shift: (swinging ? 0.14 * swingEase : 0.0) * (1 - walkBlend),
        ),
        helmet: true,
        label: strikerName,
        hero: true,
        kit: KitLook.batting,
        animTime: mocapT,
        animBlend: animBlend,
        clip: clipName,
        variant: 3,
      ));
      final nonOut = batterOut && !outIsStriker;
      var nPos = np;
      var nYaw = math.pi;
      var nWalk = 0.0;
      var nBlend = 0.0;
      var nShuffle = 0.0;
      var nTwist = 0.0;
      if (nonOut && walking) {
        final nEnd = nonTrack.pos(1.0);
        final nLook = nonTrack.pos(0.97);
        final w = walkOff(nEnd, (nEnd - nLook).distance > 1e-5 ? yawTo(nLook, nEnd) : math.pi);
        nPos = w.pos;
        nYaw = w.yaw;
        nWalk = w.speed;
        nBlend = Curves.easeInOut.transform((walkSec / 1.0).clamp(0.0, 1.0));
        nShuffle = math.sin(math.pi * w.turn);
        nTwist = 0.4 * nShuffle * w.sign;
        outBatterPos = nPos;
      }
      if (nRun > 0.05) nYaw = moveYaw(nonTrack, 0);
      // After an odd number of runs the non-striker has arrived at the batting end: stance.
      String? nClip;
      double? nClipTime;
      var nAnimBlend = 0.0;
      if (batClips != null && nRuns.isOdd && !isWicket) {
        final tBack = runStart + (nRuns - 1) * runDur + runDur * 0.78;
        if (t > tBack) {
          nClip = BattingClips.stance;
          nClipTime = ((t - tBack) / tPerSecPost * 0.75) % 2.0;
          nAnimBlend = Curves.easeInOut.transform(((t - tBack) / 0.08).clamp(0.0, 1.0));
        }
      }
      actors.add(_Actor(
        nPos,
        nYaw,
        _batting,
        _Pose(
          run: nRun * (1 - nBlend) + (0.32 * nWalk + 0.22 * nShuffle) * nBlend,
          armL: 0.8 * math.sin(phase) * (nRun * (1 - nBlend) + (0.32 * nWalk + 0.22 * nShuffle) * nBlend),
          armR: 0.8 * math.sin(phase + math.pi) * (nRun * (1 - nBlend) + (0.32 * nWalk + 0.22 * nShuffle) * nBlend),
          cadence: nBlend > 0 ? 0.55 : -1,
          plane: math.pi / 2,
          bat: nRun > 0.05 && nBlend == 0 ? null : 0.3,
          headBow: nonOut ? math.max(Curves.easeInOut.transform(((t - 0.84) / 0.12).clamp(0.0, 1.0)), nBlend) : 0.0,
          batSide: nBlend,
          twist: nTwist,
        ),
        helmet: true,
        hero: true,
        kit: KitLook.batting,
        animTime: nClipTime,
        animBlend: nAnimBlend,
        clip: nClip,
        variant: 5,
      ));
    }

    // ---- camera: over the bowler's shoulder, then chasing the ball -----------
    final hit0 = ballTrack.pos(_tContact + 0.02);
    final hit1 = ballTrack.pos(_tContact + 0.12);
    final travels = (ballTrack.pos(0.72) - _hitPoint).distance > 0.2;
    final hv = hit1 - hit0;
    final hdir = hv.distance < 1e-4 ? const Offset(0, 1) : hv / hv.distance;

    // 1) Start just behind the bowler's end, like the TV / game view, pushing in
    //    slowly as he runs past and delivers.
    final push = Curves.easeInOut.transform((t / 0.32).clamp(0.0, 1.0));
    var eye1 = V3.lerp(const V3(-0.006, 0.292, 0.056), const V3(-0.004, 0.258, 0.05), push);
    const look1 = V3(0, -0.12, 0.012);
    // 2) After the shot, the camera swings round behind the ball and follows it.
    final lag = ballTrack.pos(math.max(_tContact, t - 0.06));
    final bz = ballTrack.z(t) * _zUnit;
    final eye3 = V3(lag.dx - hdir.dx * 0.17, lag.dy - hdir.dy * 0.17, 0.05 + 0.04 * (1 - ((t - 0.55) / 0.2).clamp(0.0, 1.0)) + bz * 0.35);
    final look3 = V3(ballNow.dx + hdir.dx * 0.06, ballNow.dy + hdir.dy * 0.06, 0.004 + bz * 0.6);
    final k = (travels ? 1.0 : 0.0) * Curves.easeInOut.transform(((t - 0.54) / 0.14).clamp(0.0, 1.0));
    var camEye = V3.lerp(eye1, eye3, k);
    var camTarget = V3.lerp(look1, look3, k);
    var camFov = 27 + 16 * k;
    // Bowled / LBW: zoom in on the stumps and the batter for the impact, then ease back.
    var zoomIn = 0.0;
    if (stumpHit && !inCut && !walking) {
      zoomIn = Curves.easeInOut.transform(((t - 0.3) / 0.22).clamp(0.0, 1.0)) * (1 - Curves.easeInOut.transform(((t - 0.82) / 0.18).clamp(0.0, 1.0)));
    }
    if (zoomIn > 0) {
      camEye = V3.lerp(camEye, const V3(0.058, 0.07, 0.026), zoomIn);
      camTarget = V3.lerp(camTarget, const V3(0, -0.152, 0.012), zoomIn);
      camFov -= 14 * zoomIn;
    }
    // While the batters run, pull back to a wide view of the pitch so both are seen
    // setting off, crossing and turning.
    if (nRuns > 0 && !inCut && !walking) {
      final kRun = Curves.easeInOut.transform(((t - 0.66) / 0.1).clamp(0.0, 1.0));
      camEye = V3.lerp(camEye, const V3(0.0, -0.5, 0.2), kRun);
      camTarget = V3.lerp(camTarget, const V3(0, 0.0, 0.01), kRun);
      camFov = camFov + (40 - camFov) * kRun;
    }
    // After the umpire: follow the dismissed batter as he walks back.
    final walker = outBatterPos;
    if (walking && walker != null) {
      camEye = V3(walker.dx - _walkHeading.dx * 0.075 + 0.02, walker.dy - _walkHeading.dy * 0.075, 0.05);
      camTarget = V3(walker.dx + _walkHeading.dx * 0.02, walker.dy + _walkHeading.dy * 0.02, 0.012);
      camFov = 30;
    }
    if (inCut) {
      // 3) Cutaway: a close shot of the umpire giving the signal.
      final u = ((realT - cutBeg) / (cutEnd - cutBeg)).clamp(0.0, 1.0);
      final zoom = Curves.easeOut.transform((u / 0.5).clamp(0.0, 1.0));
      camEye = V3(_umpireHome.dx + 0.5 * _metre, _umpireHome.dy + (6.6 - 1.4 * zoom) * _metre, 1.45 * _metre);
      camTarget = V3(_umpireHome.dx, _umpireHome.dy, 1.12 * _metre);
      camFov = 34;
    }
    final dbg = debugCamera;
    if (dbg != null) {
      camEye = V3(dbg.$1, dbg.$2, dbg.$3);
      camTarget = V3(dbg.$4, dbg.$5, dbg.$6);
      camFov = dbg.$7;
    }
    _cam = Cam3(camEye, camTarget, size, camFov, centerY: 0.5);
    _mb = MeshBuilder(_cam);
    _mbTop = MeshBuilder(_cam);
    _heroJobs.clear();
    _ballDot = null;

    // ---- paint ----------------------------------------------------------
    paintBackdrop(canvas, _cam);
    paintGround(canvas, _cam);
    final stadiumModel = assets?.stadium;
    if (stadiumModel != null) drawStadiumModel(canvas, _cam, stadiumModel);
    addStadium(_mb, stands: stadiumModel == null);

    if (!inCut && boundaryAtF != null && t >= boundaryAtF - 0.02) {
      final bye = out == BallOutcome.bye || out == BallOutcome.legBye;
      _drawBoundaryFlash(canvas, bye ? (out == BallOutcome.legBye ? 200 : 180) : dirAngle, t - boundaryAtF, out);
    }

    _labels.clear();
    final strongHit = b.wicket == WicketType.bowled || b.wicket == WicketType.hitWicket;
    _addStumps(_bowlStumps, bowlEndBreakF == null ? -1 : (t - bowlEndBreakF) * 3.0, -1, hit: 0, power: 0.35);
    _addStumps(_batStumps, breakAtF == null ? -1 : (t - breakAtF) * 3.0, 1, hit: stumpIdx, power: strongHit ? 1.0 : 0.35);
    final heroes = assets;
    for (final a in actors) {
      if (a.hero && heroes != null) {
        _buildHero(canvas, a, heroes);
      } else {
        _buildFigure(canvas, a);
      }
    }

    // The ball: a real sphere, with a shadow on the ground.
    if (inCut) {
      // The ball is out of the picture during the umpire's cutaway.
    } else if (t >= _tRelease && ballVisible) {
      final hideAfter = out == BallOutcome.six ? 0.95 : 2.0;
      if (t <= hideAfter) {
        var bp = ballNow;
        var bz2 = ballTrack.z(t);
        if (caughtBallAt != null && catchAtF != null && t >= catchAtF) {
          bp = caughtBallAt;
          bz2 = 0.75;
        }
        final shrink = out == BallOutcome.six ? ((1 - (t - 0.84) / 0.11).clamp(0.2, 1.0)) : 1.0;
        _addBall(canvas, bp, bz2, shrink);
      }
    } else if (t < _tRelease) {
      _addBall(canvas, bowlerTrack.pos(t), 1.0, 1.0);
    }

    _mb.flush(canvas);
    // The rigged characters, far to near, each followed by its kit (helmet, pads, bat, hat).
    _heroJobs.sort((x, y) => y.depth.compareTo(x.depth));
    for (final j in _heroJobs) {
      j.draw(canvas);
    }
    _mbTop.flush(canvas);
    final dot = _ballDot;
    if (dot != null && !inCut) {
      canvas.drawCircle(dot, 2.4, Paint()..color = const Color(0xFFD32F2F));
      canvas.drawCircle(
        dot,
        2.4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.white,
      );
    }

    // Comet trail so the curve and the bounces are easy to follow.
    if (!inCut && t >= _tRelease && ballVisible && (out != BallOutcome.six || t <= 0.95)) {
      for (var g = 16; g >= 1; g--) {
        final tg = t - g * 0.007;
        if (tg >= _tRelease) {
          final w = ballTrack.pos(tg);
          final pt = _cam.project(V3(w.dx, w.dy, ballTrack.z(tg) * _zUnit + 0.0016));
          canvas.drawCircle(pt.pt, math.max(1.1, 0.0006 * pt.scale), Paint()..color = Colors.white.withValues(alpha: 0.035 * (17 - g)));
        }
      }
    }
    if (isWicket && realT > 0.9) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: ((realT - 0.9) / 0.1).clamp(0.0, 1.0)));
    }
    if (!inCut) {
      for (final l in _labels) {
        _label(canvas, l.$1, l.$2, Colors.white, 10);
      }
    }
  }

  double _batAngle(_Swing kind, double p, double dirAngle, double t) {
    final side = dirAngle > 8 ? 1.0 : (dirAngle < -8 ? -1.0 : 0.0);
    final stance = side == 0 ? -2.9 : -2.5 * side;
    // Before the swing the bat rises from the crease to the backlift.
    if (p <= 0 && kind != _Swing.none && kind != _Swing.leave) {
      return _lerp(0.35, stance, Curves.easeInOut.transform(((t - 0.25) / 0.2).clamp(0.0, 1.0)));
    }
    switch (kind) {
      case _Swing.none:
      case _Swing.leave:
        return 0.35;
      case _Swing.defend:
        return _lerp(stance * 0.5, 0.15 * (side == 0 ? 1 : side), p);
      case _Swing.drive:
        final fwd = side == 0 ? 2.9 : 2.2 * side;
        return _lerp(stance, fwd, Curves.easeInOut.transform(p));
      case _Swing.lofted:
        final fwd = side == 0 ? 3.1 : 2.5 * side;
        return _lerp(stance, fwd, Curves.easeInOut.transform(p));
      case _Swing.miss:
        final fwd = side == 0 ? 2.4 : 2.0 * side;
        return _lerp(stance, fwd, Curves.easeInOut.transform(p));
    }
  }

  double _lerp(double a, double b, double p) => a + (b - a) * p;

  // -------------------------------------------------------------------------
  // 3D drawing helpers
  // -------------------------------------------------------------------------

  void _drawBoundaryFlash(Canvas canvas, double angle, double since, BallOutcome out) {
    final k = (since / 0.1).clamp(0.0, 1.0);
    final path = Path();
    var started = false;
    for (var a = angle - 16; a <= angle + 16; a += 2) {
      final d = _dirVec(a);
      final p = _cam.project(V3(d.dx, d.dy, 0.002)).pt;
      if (!started) {
        path.moveTo(p.dx, p.dy);
        started = true;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    final blink = 0.5 + 0.5 * math.sin(since * 80);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Colors.amber.withValues(alpha: (0.5 + 0.5 * blink) * k),
    );
    // Standing sign board at the rope.
    final d = _dirVec(angle) * 1.04;
    final c = _cam.project(V3(d.dx, d.dy, 0.012));
    final w = 0.035 * c.scale * k, h = 0.022 * c.scale * k;
    final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: c.pt, width: w, height: h), const Radius.circular(5));
    canvas.drawRRect(rect, Paint()..color = out == BallOutcome.six ? Colors.purple.shade600 : Colors.blue.shade600);
    if (k > 0.5) _label(canvas, out == BallOutcome.six ? '6' : '4', rect.center, Colors.white, h * 0.7, bold: true);
  }

  /// Stumps and bails. [since] is the time in seconds since the impact (negative
  /// = still standing). The stump that is hit pivots about its base and falls
  /// away from the bowler; the others follow a moment later. The bails are
  /// projectiles: they leave upwards and backwards and drop under gravity.
  void _addStumps(Offset w, double since, double toward, {int hit = 0, double power = 1}) {
    const h = 0.71 * _metre, sp = 0.114 * _metre;
    const cream = Color(0xFFF5E6B0);
    for (var i = -1; i <= 1; i++) {
      final base = V3(w.dx + i * sp, w.dy, 0);
      var th = 0.0;
      if (since > 0) {
        final alpha = (i == hit ? 24.0 : 8.0) * power; // rad/s^2
        final delay = i == hit ? 0.0 : 0.05;
        final ss = math.max(0.0, since - delay);
        th = math.min(1.4, 0.5 * alpha * ss * ss);
      }
      final top = V3(base.x + (th > 0 ? (i - hit) * 0.08 * _metre * th : 0), base.y - toward * math.sin(th) * h, math.cos(th) * h);
      _mb.limb(base, top, 0.021 * _metre, 0.019 * _metre, cream, sides: 5);
    }
    if (since <= 0) {
      _mb.limb(V3(w.dx - sp, w.dy, h + 0.01 * _metre), V3(w.dx + sp, w.dy, h + 0.01 * _metre), 0.012 * _metre, 0.012 * _metre, Colors.white, sides: 4);
    } else {
      for (final side in [-1.0, 1.0]) {
        // Initial velocity (m/s): backwards along the ball's direction, up, and a little sideways.
        final vy = -toward * (2.8 + 1.2 * side.abs()) * power;
        final vx = side * (0.9 + 0.5 * power);
        final vz = 2.0 * power + 0.3;
        final px = w.dx + (side * sp * 0.5 + vx * since * _metre);
        final py = w.dy + vy * since * _metre;
        final zRaw = h + 0.01 * _metre + (vz * since - 0.5 * _g * since * since) * _metre;
        final pz = math.max(0.012 * _metre, zRaw);
        final spin = since * (9 + 4 * side);
        final c = V3(px, py, pz);
        final d = V3(math.cos(spin), math.sin(spin), 0) * (0.056 * _metre);
        _mb.limb(c - d, c + d, 0.012 * _metre, 0.012 * _metre, Colors.white, sides: 4);
      }
    }
  }

  /// The ball at its real size (about 7 cm across). When that is less than a couple
  /// of pixels, a small dot is also drawn so it can still be followed.
  void _addBall(Canvas canvas, Offset world, double z, double scale) {
    const r = 0.00058;
    final height = z * _zUnit;
    final g = _cam.project(V3(world.dx, world.dy, 0));
    canvas.drawOval(
      Rect.fromCenter(center: g.pt, width: r * 2.8 * g.scale, height: r * 1.0 * g.scale),
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );
    _mbTop.sphere(V3(world.dx, world.dy, height + r), r * scale, const Color(0xFFD32F2F), lat: 5, lon: 9);
    _mbTop.limb(V3(world.dx - r * 0.7 * scale, world.dy, height + r), V3(world.dx + r * 0.7 * scale, world.dy, height + r), r * 0.1, r * 0.1, Colors.white, sides: 4);
    final c = _cam.project(V3(world.dx, world.dy, height + r));
    if (r * scale * c.scale < 2.2) {
      _ballDot = c.pt;
    }
  }

  Offset? _ballDot;

  /// The textured, rigged model for every player. The skeleton is posed either
  /// from the retargeted motion-capture batting clip (the striker's stance and
  /// shot) or from the choreography's joint targets with two-bone IK (hands reach
  /// the signal, feet stay planted). Distant players use cheaper geometry.
  void _buildHero(Canvas canvas, _Actor a, HeroAssets assets) {
    final ground = a.base;
    final cp = _cam.project(ground);
    if (cp.depth < 0.02) return;
    final batsmanModel = a.helmet ? assets.batsman : null;
    final model = batsmanModel ?? assets.players[a.variant % assets.players.length];
    const H = _playerHeight;
    const modelHeight = 1.87; // metres, head top of the glTF in its bind pose
    final p = a.pose;
    const up = V3(0, 0, 1);
    final lod = cp.depth < 0.22 ? 0 : (cp.depth < 0.5 ? 1 : 2);

    final lowYaw = a.yaw;
    final upYaw = a.yaw + p.twist;
    final fwd = V3(math.sin(lowYaw), math.cos(lowYaw), 0);
    final right = V3(math.cos(lowYaw), -math.sin(lowYaw), 0);
    final fwdS = V3(math.sin(upYaw), math.cos(upYaw), 0);
    final rightS = V3(math.cos(upYaw), -math.sin(upYaw), 0);
    final body = ground + fwd * (p.shift * H);
    V3 lo(double lat, double fw, double h) => body + right * (lat * H) + fwd * (fw * H) + up * (h * H);
    V3 hi(double lat, double fw, double h) => body + rightS * (lat * H) + fwdS * (fw * H) + up * (h * H);

    final crouchK = 1 - 0.2 * p.crouch;
    final lean = p.lean + 0.1 * p.crouch;
    final hipZ = 0.5 * crouchK + p.lift;
    final shZ = 0.8 * crouchK + p.lift;
    final hipC = lo(0, 0, hipZ);
    final chest = hi(0, lean, shZ);
    final shL = hi(-0.135, lean, shZ - 0.015);
    final shR = hi(0.135, lean, shZ - 0.015);
    final neck = hi(0, lean * 1.1, shZ + 0.03);
    final bow = p.headBow;
    final headC = hi(0, lean * 1.3 + 0.06 * bow, shZ + 0.135 - 0.035 * bow);

    // Foot targets with the run cycle.
    final ph = t * clipSeconds * 9.0 * (p.cadence > 0 ? p.cadence : 0.5 + 0.5 * p.run);
    final stride = 0.3 * p.run;
    final feetW = <V3>[];
    for (final side in [-1.0, 1.0]) {
      final cyc = ph + (side > 0 ? math.pi : 0);
      final s = math.sin(cyc);
      final lift = math.max(0.0, math.cos(cyc)) * 0.16 * p.run;
      feetW.add(lo(side * 0.08, s * stride, lift + 0.035));
    }

    // Hands (bat grip or free arms).
    final cph = math.cos(p.plane), sph = math.sin(p.plane);
    V3 armDir(double ang) => rightS * (math.sin(ang) * cph) + fwdS * (math.sin(ang) * sph) + up * (-math.cos(ang));
    final batAngle = p.bat;
    V3 handL, handR;
    V3? batDir;
    if (batAngle != null) {
      final inFront = chest +
          rightS * (0.17 * H * math.sin(batAngle * 0.5)) +
          fwdS * (0.2 * H) -
          up * (0.22 * H * math.max(0.2, math.cos(batAngle * 0.5)));
      // Carried: one hand holds the handle at the hip, the other arm swings free. With
      // the batsman model the bat is attached to the left (top) hand, so that hand carries it.
      final leftHolds = a.helmet && assets.batsman != null;
      final atSide = hipC + rightS * ((leftHolds ? -0.17 : 0.17) * H) + up * (0.05 * H) + fwdS * (0.02 * H);
      final grip = V3.lerp(inFront, atSide, p.batSide);
      if (leftHolds) {
        handL = grip - rightS * (0.02 * H);
        handR = V3.lerp(grip + rightS * (0.02 * H), shR + armDir(p.armR) * (0.4 * H), p.batSide);
      } else {
        handR = grip + rightS * (0.02 * H);
        handL = V3.lerp(grip - rightS * (0.02 * H), shL + armDir(p.armL) * (0.4 * H), p.batSide);
      }
      final held = (rightS * math.sin(batAngle) + fwdS * 0.15 + up * (-math.cos(batAngle))).unit;
      batDir = V3.lerp(held, (up * -0.95 + fwdS * 0.12).unit, p.batSide).unit;
    } else {
      handL = shL + armDir(p.armL) * (0.4 * H);
      handR = shR + armDir(p.armR) * (0.4 * H);
    }

    // ---- pose the skeleton ----------------------------------------------------
    final tf = HeroTransform(base: body, right: right, fwd: fwd, scale: H / modelHeight);
    final bn = _HeroBones.of(model);
    final motion = assets.motion;
    final animT = a.animTime;
    final clipAnim = (batsmanModel != null && a.clip != null) ? model.animByName(a.clip!) : null;
    final canMocap = animT != null && (clipAnim != null || (batsmanModel == null && motion != null));
    V3? mocapBatAxis;

    Rig poseRig(bool mocap) {
      final rig = Rig(model);
      if (mocap && clipAnim != null) {
        // The batsman's own clip, played directly (it is authored on this skeleton).
        rig.applyAnim(clipAnim, animT!);
        return rig;
      }
    // Hips follow the body height (and, with mocap, the clip's own hip travel).
    final hipsBind = rig.pos(bn.hips);
    var hipsTarget = tf.toScene(hipC);
    if (mocap) {
      motion!.sample(animT!);
      hipsTarget = V3(hipsBind.x, hipsBind.y, hipsTarget.z) + motion.hipsOffset(modelHeight) * 1.0 - V3(0, 0, motion.hipsOffset(modelHeight).z);
    }
    rig.lt[bn.hips] = [
      rig.lt[bn.hips][0] + hipsTarget.x - hipsBind.x,
      rig.lt[bn.hips][1] + hipsTarget.y - hipsBind.y,
      rig.lt[bn.hips][2] + hipsTarget.z - hipsBind.z,
    ];
    rig.updateFrom(bn.hips);

    void aimLimbBones(String srcFrom, String srcTo, int from, int to) => rig.aim(from, to, motion!.dir(srcFrom, srcTo));

    if (mocap) {
      // Pelvis turn, then every bone takes its direction from the clip.
      final latSrc = motion!.dir('LeftUpLeg', 'RightUpLeg');
      final latDst = rig.pos(bn.rUpLeg) - rig.pos(bn.lUpLeg);
      rig.yaw(bn.hips, math.atan2(latSrc.y, latSrc.x) - math.atan2(latDst.y, latDst.x));
      aimLimbBones('Spine', 'Spine1', bn.spine, bn.spine1);
      aimLimbBones('Spine1', 'Spine2', bn.spine1, bn.spine2);
      aimLimbBones('Spine2', 'Neck', bn.spine2, bn.neck);
      aimLimbBones('Neck', 'Head', bn.neck, bn.head);
      aimLimbBones('Head', 'HeadTop_End', bn.head, bn.headTop);
      // Twist the chest about the spine so the shoulder line matches.
      final spineAxis = (rig.pos(bn.neck) - rig.pos(bn.spine)).unit;
      V3 flat(V3 v) => (v - spineAxis * v.dot(spineAxis));
      final cur = flat(rig.pos(bn.rShoulder) - rig.pos(bn.lShoulder)).unit;
      final want = flat(motion.dir('LeftShoulder', 'RightShoulder')).unit;
      final ang = math.atan2(cur.cross(want).dot(spineAxis), cur.dot(want));
      if (ang.abs() > 1e-3) rig.rotateWorld(bn.spine1, _axisAngleOf(spineAxis, ang));
      for (final side in ['Left', 'Right']) {
        final l = side == 'Left';
        aimLimbBones('${side}Shoulder', '${side}Arm', l ? bn.lShoulder : bn.rShoulder, l ? bn.lArm : bn.rArm);
        aimLimbBones('${side}Arm', '${side}ForeArm', l ? bn.lArm : bn.rArm, l ? bn.lFore : bn.rFore);
        aimLimbBones('${side}ForeArm', '${side}Hand', l ? bn.lFore : bn.rFore, l ? bn.lHand : bn.rHand);
        aimLimbBones('${side}Hand', '${side}HandIndex1', l ? bn.lHand : bn.rHand, l ? bn.lMiddle : bn.rMiddle);
        aimLimbBones('${side}UpLeg', '${side}Leg', l ? bn.lUpLeg : bn.rUpLeg, l ? bn.lLeg : bn.rLeg);
        aimLimbBones('${side}Leg', '${side}Foot', l ? bn.lLeg : bn.rLeg, l ? bn.lFoot : bn.rFoot);
        aimLimbBones('${side}Foot', '${side}ToeBase', l ? bn.lFoot : bn.rFoot, l ? bn.lToe : bn.rToe);
      }
      mocapBatAxis = motion.batAxis();
    } else {
      // Spine: lean towards the neck, then turn the shoulders to match.
      final spineDir = tf.dirToScene(neck - hipC);
      rig.aim(bn.spine, bn.neck, spineDir, amount: 0.5);
      rig.aim(bn.spine1, bn.neck, spineDir);
      final shoulderNow = rig.pos(bn.rShoulder) - rig.pos(bn.lShoulder);
      final shoulderWant = tf.dirToScene(shR - shL);
      final twistFix = math.atan2(shoulderWant.y, shoulderWant.x) - math.atan2(shoulderNow.y, shoulderNow.x);
      if (twistFix.abs() > 1e-3) rig.yaw(bn.spine2, twistFix);
      rig.aim(bn.head, bn.headTop, tf.dirToScene(headC - neck));

      // Two-bone IK for arms and legs.
      void limb(int root, int mid, int tip, V3 targetScene, V3 poleScene) {
        final rootP = rig.pos(root);
        final l1 = math.sqrt((rig.pos(mid) - rootP).dot(rig.pos(mid) - rootP));
        final l2 = math.sqrt((rig.pos(tip) - rig.pos(mid)).dot(rig.pos(tip) - rig.pos(mid)));
        var d = targetScene - rootP;
        var dist = math.sqrt(d.dot(d));
        final maxReach = (l1 + l2) * 0.999;
        if (dist > maxReach) {
          d = d * (maxReach / dist);
          dist = maxReach;
        }
        if (dist < 1e-4) return;
        final dir = d * (1 / dist);
        final aLen = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist);
        final hLen = math.sqrt(math.max(0.0, l1 * l1 - aLen * aLen));
        var pole = poleScene - dir * poleScene.dot(dir);
        if (pole.dot(pole) < 1e-9) pole = const V3(0, -1, 0) - dir * dir.y;
        final elbow = rootP + dir * aLen + pole.unit * hLen;
        rig.aim(root, mid, elbow - rootP);
        final midP = rig.pos(mid);
        rig.aim(mid, tip, (rootP + d) - midP);
      }

      for (var i = 0; i < 2; i++) {
        final side = i == 0 ? -1.0 : 1.0;
        final armPole = tf.dirToScene(up * -1.0 + rightS * (side * 0.5) - fwdS * 0.3);
        limb(i == 0 ? bn.lArm : bn.rArm, i == 0 ? bn.lFore : bn.rFore, i == 0 ? bn.lHand : bn.rHand, tf.toScene(i == 0 ? handL : handR), armPole);
        rig.aim(i == 0 ? bn.lHand : bn.rHand, i == 0 ? bn.lMiddle : bn.rMiddle, rig.pos(i == 0 ? bn.lHand : bn.rHand) - rig.pos(i == 0 ? bn.lFore : bn.rFore));
        limb(i == 0 ? bn.lUpLeg : bn.rUpLeg, i == 0 ? bn.lLeg : bn.rLeg, i == 0 ? bn.lFoot : bn.rFoot, tf.toScene(feetW[i]), tf.dirToScene(fwd));
        rig.aim(i == 0 ? bn.lFoot : bn.rFoot, i == 0 ? bn.lToe : bn.rToe, tf.dirToScene(fwd * 0.9 - up * 0.25));
      }
      // The batsman's bat is a child of his top hand: turn it so it points where the pose wants.
      final batNode = bn.bat, batToe = bn.batToe;
      if (batsmanModel != null && batNode != null && batToe != null) {
        rig.aim(batNode, batToe, tf.dirToScene(batDir ?? (up * -0.9 + fwdS * 0.3).unit));
      }
    }

      return rig;
    }

    // The captured motion and the choreography pose are blended on the skeleton
    // itself, so changing from one to the other never snaps.
    final blendW = canMocap ? a.animBlend.clamp(0.0, 1.0) : 0.0;
    Rig rig;
    if (blendW >= 0.999) {
      rig = poseRig(true);
    } else if (blendW <= 0.001) {
      mocapBatAxis = null;
      rig = poseRig(false);
    } else {
      rig = poseRig(true);
      rig.blendToward(poseRig(false), 1 - blendW);
    }

    // Keep the lowest ankle on the ground (plus any jump).
    final ankleLow = math.min(rig.pos(bn.lFoot).z, rig.pos(bn.rFoot).z);
    final dz = 0.126 - ankleLow + p.lift * modelHeight * 0.6;
    final clipInCharge = clipAnim != null && blendW >= 0.999;
    if (!clipInCharge && dz.abs() > 1e-4) {
      rig.lt[bn.hips] = [rig.lt[bn.hips][0], rig.lt[bn.hips][1], rig.lt[bn.hips][2] + dz];
      rig.updateFrom(bn.hips);
    }

    // ---- kit drawn on top of the model ---------------------------------------------
    final att = MeshBuilder(_cam);
    V3 bone(int n) => tf.toWorld(rig.pos(n));
    final headW = V3.lerp(bone(bn.head), bone(bn.headTop), 0.5);
    // The head bone's own axes, so hats, caps and helmets stay on the head as it moves.
    final headTopW = bone(bn.headTop);
    final headUpW = (headTopW - bone(bn.head)).unit;
    final hr = rig.wr[bn.head];
    final headRightW = tf.dirToWorld(V3(-hr[1], -hr[4], -hr[7])).unit.cross(headUpW).unit;
    final headFwdW = headUpW.cross(headRightW).unit;
    final isUmpire = a.umpire;
    final isBatter = a.helmet;
    final isKeeper = a.kit == KitLook.keeper;
    final near = lod < 2;
    V3 gripW = (bone(bn.lHand) + bone(bn.rHand)) * 0.5;
    // The bat's direction follows the clip while it plays, blends to the pose, and when
    // the batter has no bat pose (running) it is carried hanging down at his side.
    final carried = (up * -0.9 + fwdS * 0.3).unit;
    final batAxisNow = mocapBatAxis;
    final mw = batAxisNow != null ? tf.dirToWorld(batAxisNow) : null;
    final poseBat = batDir ?? carried;
    final handleDir = (mw != null ? (mw * blendW + poseBat * (1 - blendW)) : poseBat).unit;
    if (isBatter) {
      const navy = Color(0xFF0D3B8A);
      att.sphere(headW + headUpW * (0.012 * H) - headFwdW * (0.008 * H), 0.064 * H, navy, lat: lod == 0 ? 6 : 4, lon: lod == 0 ? 10 : 6, sy: 1.08);
      if (near) {
        att.frustum(headW + headFwdW * (0.05 * H) + headUpW * (0.03 * H), headW + headFwdW * (0.11 * H) + headUpW * (0.018 * H), 0.05 * H, 0.004 * H, 0.04 * H, 0.004 * H, navy, lat: headRightW, sides: 4);
        for (var i = 0; i < 3; i++) {
          final y = -0.01 - 0.024 * i;
          att.limb(headW + headRightW * (-0.042 * H) + headFwdW * (0.062 * H) + headUpW * (y * H), headW + headRightW * (0.042 * H) + headFwdW * (0.062 * H) + headUpW * (y * H), 0.004 * H, 0.004 * H,
              const Color(0xFFE8E8E8), sides: 4);
        }
        att.sphere(bone(bn.lHand), 0.036 * H, Colors.white, lat: 4, lon: 7);
        att.sphere(bone(bn.rHand), 0.036 * H, Colors.white, lat: 4, lon: 7);
      }
      for (final k in [(bn.lUpLeg, bn.lLeg, bn.lFoot), (bn.rUpLeg, bn.rLeg, bn.rFoot)]) {
        final knee = bone(k.$2), ankle = bone(k.$3);
        att.limb(knee + up * (0.015 * H), ankle + up * (0.03 * H), 0.052 * H, 0.04 * H, Colors.white, sides: near ? 8 : 5);
        if (near) att.sphere(knee, 0.05 * H, Colors.white, lat: 4, lon: 7);
      }
    } else if (isUmpire) {
      const black = Color(0xFF15171B);
      // Brim and crown sit on the top of the head and follow its rotation.
      // A wide-brimmed hat sized to the head (head ~0.05 H wide): brim ~0.08 H, crown ~0.055 H.
      final rim = headTopW - headUpW * (0.040 * H);
      att.frustum(rim, rim + headUpW * (0.008 * H), 0.082 * H, 0.082 * H, 0.082 * H, 0.082 * H, black, lat: headRightW, sides: 14);
      att.frustum(rim + headUpW * (0.005 * H), rim + headUpW * (0.052 * H), 0.056 * H, 0.056 * H, 0.050 * H, 0.050 * H, black, lat: headRightW, sides: 12);
      if (p.finger) {
        att.limb(bone(bn.rHand), bone(bn.rHand) + up * (0.13 * H), 0.014 * H, 0.011 * H, const Color(0xFFD9A47A), sides: 5);
      }
    } else if (isKeeper) {
      att.sphere(bone(bn.lHand), 0.058 * H, Colors.white, lat: 4, lon: 7);
      att.sphere(bone(bn.rHand), 0.058 * H, Colors.white, lat: 4, lon: 7);
      for (final k in [(bn.lLeg, bn.lFoot), (bn.rLeg, bn.rFoot)]) {
        att.limb(bone(k.$1), bone(k.$2), 0.062 * H, 0.05 * H, const Color(0xFFDCE6F0), sides: near ? 8 : 5);
      }
    } else if (a.kit == KitLook.fielding) {
      // Fielding cap in the team colour.
      final capCol = _shade(a.shirt, -0.1);
      att.sphere(headW + headUpW * (0.02 * H) - headFwdW * (0.006 * H), 0.062 * H, capCol, lat: lod == 0 ? 6 : 4, lon: lod == 0 ? 10 : 6, sy: 0.95);
      if (near) {
        att.frustum(headW + headFwdW * (0.05 * H) + headUpW * (0.03 * H), headW + headFwdW * (0.11 * H) + headUpW * (0.02 * H), 0.05 * H, 0.004 * H, 0.04 * H, 0.004 * H, _shade(capCol, -0.15), lat: headRightW, sides: 4);
      }
    }

    final label = a.label;
    if (label != null && label.isNotEmpty && !isUmpire) {
      _labels.add((label, _cam.project(headW + up * (0.12 * H)).pt - const Offset(0, 8)));
    }

    // Shadow.
    final sw = 0.8 * H * cp.scale;
    canvas.drawOval(
      Rect.fromCenter(center: cp.pt, width: sw, height: sw * 0.34),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.33)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Skin tone, hair and kit differ per player.
    const skins = [(1.0, 1.0, 1.0), (0.92, 0.8, 0.68), (0.8, 0.64, 0.5), (1.0, 0.93, 0.86), (0.7, 0.55, 0.45)];
    const hairs = [0, 1, 2, 0, 3, 1];
    final style = HeroStyle(kit: a.kit, skin: skins[(a.variant ~/ 2) % skins.length], hair: hairs[a.variant % hairs.length]);

    final hideHair = isBatter || isUmpire;
    final bat = assets.bat;
    _heroJobs.add(_HeroJob(cp.depth, (c) {
      drawSkinnedModel(c, _cam, model, rig, tf, style, lod: lod, hair: !hideHair);
      att.flush(c);
      final batMeshes = assets.batMeshes;
      final batNode = bn.bat;
      if (isBatter && batsmanModel != null && batMeshes != null && batNode != null) {
        drawAttachedMeshes(c, _cam, batMeshes, rig, batNode, tf);
      } else if (isBatter && bat != null) {
        drawStaticModel(c, _cam, bat, grip: gripW - handleDir * (0.16 * H), along: handleDir, across: handleDir.cross(fwdS), metres: 0.96 * _metre);
      }
    }));
  }

  List<double> _axisAngleOf(V3 axis, double angle) {
    final a = axis.unit;
    final c = math.cos(angle), s = math.sin(angle), t = 1 - c;
    return [
      t * a.x * a.x + c, t * a.x * a.y - s * a.z, t * a.x * a.z + s * a.y,
      t * a.x * a.y + s * a.z, t * a.y * a.y + c, t * a.y * a.z - s * a.x,
      t * a.x * a.z - s * a.y, t * a.y * a.z + s * a.x, t * a.z * a.z + c,
    ];
  }

  /// A fully meshed, smooth-shaded person: pelvis, tapered torso with shoulders,
  /// two-segment legs and arms, boots, hands, neck, a head with nose, ears and
  /// eyes, hair / helmet / cap / umpire's hat, pads, gloves and a bat. Detail
  /// drops with distance so the fielders far away stay cheap to draw.
  void _buildFigure(Canvas canvas, _Actor a) {
    final ground = a.base;
    final cp = _cam.project(ground);
    if (cp.depth < 0.02) return;
    const H = _playerHeight;
    final p = a.pose;
    const up = V3(0, 0, 1);
    final mb = _mb;
    final detail = cp.depth < 0.25 ? 2 : (cp.depth < 0.6 ? 1 : 0);
    final sides = const [5, 7, 9][detail];
    final latR = const [4, 6, 8][detail];
    final lonR = const [6, 9, 12][detail];

    final lowYaw = a.yaw;
    final upYaw = a.yaw + p.twist;
    final fwd = V3(math.sin(lowYaw), math.cos(lowYaw), 0);
    final right = V3(math.cos(lowYaw), -math.sin(lowYaw), 0);
    final fwdS = V3(math.sin(upYaw), math.cos(upYaw), 0);
    final rightS = V3(math.cos(upYaw), -math.sin(upYaw), 0);
    final body = ground + fwd * (p.shift * H);

    V3 lo(double lat, double fw, double h) => body + right * (lat * H) + fwd * (fw * H) + up * (h * H);
    V3 hi(double lat, double fw, double h) => body + rightS * (lat * H) + fwdS * (fw * H) + up * (h * H);

    final crouchK = 1 - 0.2 * p.crouch;
    final lean = p.lean + 0.1 * p.crouch;
    final hipZ = 0.5 * crouchK + p.lift;
    final shZ = 0.8 * crouchK + p.lift;
    final hipC = lo(0, 0, hipZ);
    final waist = hi(0, lean * 0.4, hipZ + 0.09);
    final chest = hi(0, lean, shZ);
    final shL = hi(-0.135, lean, shZ - 0.015);
    final shR = hi(0.135, lean, shZ - 0.015);
    final neck = hi(0, lean * 1.1, shZ + 0.03);
    final bow = p.headBow;
    final headC = hi(0, lean * 1.3 + 0.06 * bow, shZ + 0.135 - 0.035 * bow);

    const skins = [Color(0xFFD9A47A), Color(0xFFB9824F), Color(0xFF8D5A34), Color(0xFFE6BC96)];
    const hairs = [Color(0xFF1E1610), Color(0xFF2E1F12), Color(0xFF4B3420), Color(0xFF0F0F10)];
    final skin = skins[a.variant % skins.length];
    final hairColor = hairs[(a.variant ~/ 2) % hairs.length];
    final shirt = a.shirt;
    final isUmpire = a.umpire;
    final isBatter = a.helmet;
    final isKeeper = p.glove && !isBatter && !isUmpire && a.shirt == _keeperColor;
    final padded = isBatter || isKeeper;
    final trouser = isUmpire ? const Color(0xFF3A4048) : _shade(shirt, -0.16);
    final shoe = isUmpire ? const Color(0xFFF1F1F1) : const Color(0xFF1B1B1B);
    final padColor = isKeeper ? const Color(0xFFDCE6F0) : Colors.white;

    // Soft ground shadow.
    final sw = 0.8 * H * cp.scale;
    canvas.drawOval(
      Rect.fromCenter(center: cp.pt, width: sw, height: sw * 0.34),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.33)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // ---- legs with a proper run cycle ---------------------------------------
    final ph = t * clipSeconds * 9.0 * (p.cadence > 0 ? p.cadence : 0.5 + 0.5 * p.run);
    final stride = 0.3 * p.run;
    for (final side in [-1.0, 1.0]) {
      final cyc = ph + (side > 0 ? math.pi : 0);
      final s = math.sin(cyc);
      final lift = math.max(0.0, math.cos(cyc)) * 0.16 * p.run;
      final hip = lo(side * 0.065, 0, hipZ);
      final foot = lo(side * 0.08, s * stride, lift + 0.035);
      final knee = (hip + foot) * 0.5 + fwd * (H * (0.05 + 0.1 * p.crouch + 0.12 * p.run * math.max(0.0, s + 0.3)));
      mb.limb(hip, knee, 0.072 * H, 0.056 * H, trouser, sides: sides);
      mb.limb(knee, foot, (padded ? 0.07 : 0.054) * H, (padded ? 0.056 : 0.036) * H, padded ? padColor : trouser, sides: sides, );
      if (detail > 0) {
        mb.sphere(knee, (padded ? 0.062 : 0.052) * H, padded ? padColor : trouser, lat: latR - 2, lon: lonR - 2);
      }
      mb.frustum(foot, foot + fwd * (0.15 * H), 0.04 * H, 0.032 * H, 0.038 * H, 0.022 * H, shoe, lat: right, sides: sides - 1);
    }

    // ---- pelvis and torso ------------------------------------------------------
    mb.frustum(hipC - up * (0.02 * H), waist, 0.115 * H, 0.07 * H, 0.1 * H, 0.064 * H, trouser, lat: right, sides: sides + 3, capA: false);
    mb.frustum(waist, chest, 0.1 * H, 0.064 * H, 0.14 * H, 0.078 * H, shirt, lat: rightS, sides: sides + 3, capA: false);
    mb.sphere(shL, 0.062 * H, shirt, lat: latR - 1, lon: lonR - 2);
    mb.sphere(shR, 0.062 * H, shirt, lat: latR - 1, lon: lonR - 2);
    if (detail > 0) {
      // Belt and collar.
      mb.frustum(waist - up * (0.01 * H), waist + up * (0.025 * H), 0.103 * H, 0.066 * H, 0.103 * H, 0.066 * H, _shade(shirt, -0.45),
          lat: rightS, sides: sides + 3, capA: false, capB: false);
      mb.frustum(chest - up * (0.02 * H), chest + up * (0.025 * H), 0.075 * H, 0.06 * H, 0.06 * H, 0.05 * H, _shade(shirt, -0.12),
          lat: rightS, sides: sides, capA: false, capB: false);
    }

    // ---- arms and bat ----------------------------------------------------------
    final cph = math.cos(p.plane), sph = math.sin(p.plane);
    V3 armDir(double ang) => rightS * (math.sin(ang) * cph) + fwdS * (math.sin(ang) * sph) + up * (-math.cos(ang));
    final batAngle = p.bat;
    V3 handL, handR;
    if (batAngle != null) {
      final grip = chest +
          rightS * (0.17 * H * math.sin(batAngle * 0.5)) +
          fwdS * (0.2 * H) -
          up * (0.22 * H * math.max(0.2, math.cos(batAngle * 0.5)));
      handL = grip - rightS * (0.02 * H);
      handR = grip + rightS * (0.02 * H);
      final bv = (rightS * math.sin(batAngle) + fwdS * 0.15 + up * (-math.cos(batAngle))).unit;
      final handle = grip + bv * (0.17 * H);
      final tip = grip + bv * (0.53 * H);
      mb.limb(grip - bv * (0.03 * H), handle, 0.014 * H, 0.014 * H, const Color(0xFF2B2B2B), sides: 6);
      // Flat willow blade, wide across and thin front to back.
      mb.frustum(handle, tip, 0.03 * H, 0.011 * H, 0.034 * H, 0.016 * H, const Color(0xFFE9D3A0), lat: bv.cross(fwdS), sides: 6);
    } else {
      handL = shL + armDir(p.armL) * (0.4 * H);
      handR = shR + armDir(p.armR) * (0.4 * H);
    }
    final glove = isBatter || p.glove;
    for (final e in [(shL, handL), (shR, handR)]) {
      final elbow = (e.$1 + e.$2) * 0.5 + fwdS * (0.025 * H) - up * (0.015 * H);
      mb.limb(e.$1, elbow, 0.05 * H, 0.04 * H, shirt, sides: sides, capA: false);
      mb.limb(elbow, e.$2, 0.04 * H, glove ? 0.046 * H : 0.03 * H, glove ? Colors.white : skin, sides: sides);
      if (detail > 0) mb.sphere(elbow, 0.042 * H, shirt, lat: latR - 2, lon: lonR - 2);
    }
    final handSize = isKeeper ? 0.078 : (isBatter ? 0.052 : 0.04);
    mb.sphere(handL, handSize * H, glove ? Colors.white : skin, lat: latR - 2, lon: lonR - 3);
    mb.sphere(handR, handSize * H, glove ? Colors.white : skin, lat: latR - 2, lon: lonR - 3);
    if (p.finger) {
      // The umpire's raised finger.
      mb.limb(handR, handR + up * (0.13 * H), 0.014 * H, 0.011 * H, skin, sides: 5);
    }

    // ---- neck, head and what's on it ----------------------------------------
    mb.limb(neck - up * (0.05 * H), neck + up * (0.05 * H), 0.034 * H, 0.032 * H, skin, sides: sides);
    mb.sphere(headC, 0.066 * H, skin, lat: latR, lon: lonR, sy: 1.12);
    if (detail > 0) {
      mb.sphere(headC + fwdS * (0.064 * H) - up * (0.006 * H), 0.014 * H, _shade(skin, -0.06), lat: 3, lon: 5); // nose
      for (final sg in [-1.0, 1.0]) {
        mb.sphere(headC + rightS * (0.066 * H * sg), 0.016 * H, skin, lat: 3, lon: 5, sx: 0.6); // ears
      }
    }
    final topC = headC + up * (0.018 * H) - fwdS * (0.012 * H);
    if (isUmpire) {
      // Wide-brimmed black hat.
      mb.frustum(headC + up * (0.07 * H), headC + up * (0.078 * H), 0.125 * H, 0.125 * H, 0.125 * H, 0.125 * H, const Color(0xFF15171B), lat: rightS, sides: sides + 5);
      mb.frustum(headC + up * (0.075 * H), headC + up * (0.125 * H), 0.074 * H, 0.074 * H, 0.066 * H, 0.066 * H, const Color(0xFF15171B), lat: rightS, sides: sides + 3);
    } else if (isBatter) {
      mb.sphere(topC, 0.08 * H, const Color(0xFF0D3B8A), lat: latR, lon: lonR, sy: 1.08);
      mb.frustum(headC + fwdS * (0.06 * H) + up * (0.04 * H), headC + fwdS * (0.125 * H) + up * (0.028 * H), 0.062 * H, 0.004 * H, 0.05 * H, 0.004 * H,
          const Color(0xFF0D3B8A), lat: rightS, sides: 4);
      for (var i = 0; i < 3; i++) {
        final y = -0.005 - 0.026 * i;
        mb.limb(headC + rightS * (-0.05 * H) + fwdS * (0.074 * H) + up * (y * H), headC + rightS * (0.05 * H) + fwdS * (0.074 * H) + up * (y * H),
            0.004 * H, 0.004 * H, const Color(0xFFE8E8E8), sides: 4);
      }
    } else {
      final isCap = isKeeper || shirt == _fielding || shirt == _batting;
      mb.sphere(topC, 0.073 * H, isCap ? _shade(shirt, -0.1) : hairColor, lat: latR, lon: lonR, sy: 1.05);
      if (isCap) {
        mb.frustum(headC + fwdS * (0.05 * H) + up * (0.03 * H), headC + fwdS * (0.12 * H) + up * (0.022 * H), 0.058 * H, 0.004 * H, 0.046 * H, 0.004 * H,
            _shade(shirt, -0.2), lat: rightS, sides: 4);
      }
    }
    if (detail > 0 && !isBatter) {
      // Eyes.
      for (final sg in [-1.0, 1.0]) {
        mb.sphere(headC + fwdS * (0.058 * H) + rightS * (0.026 * H * sg) + up * (0.012 * H), 0.01 * H, const Color(0xFF151515), lat: 2, lon: 4);
      }
    }

    final label = a.label;
    if (label != null && label.isNotEmpty && !isUmpire) {
      _labels.add((label, _cam.project(headC + up * (0.11 * H)).pt - const Offset(0, 8)));
    }
  }

  /// Lightens (k > 0) or darkens (k < 0) a colour.
  static Color _shade(Color c, double k) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + k).clamp(0.0, 1.0)).toColor();
  }

  void _label(Canvas canvas, String text, Offset center, Color color, double size, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.bold : FontWeight.w600,
          shadows: const [Shadow(blurRadius: 3, color: Colors.black87)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 110);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(ReplayFieldPainter old) => old.t != t || old.step != step;
}

enum _Swing { none, defend, drive, lofted, miss, leave }

enum _Umpire { none, out, four, six, wide, noBall, bye, legBye }

_Umpire _signalFor(BallEvent b) {
  switch (b.outcome) {
    case BallOutcome.wicket:
      return _Umpire.out;
    case BallOutcome.six:
      return _Umpire.six;
    case BallOutcome.four:
      return _Umpire.four;
    case BallOutcome.wide:
      return _Umpire.wide;
    case BallOutcome.noBall:
      return b.runs == 6 ? _Umpire.six : (b.runs == 4 ? _Umpire.four : _Umpire.noBall);
    case BallOutcome.bye:
      return _Umpire.bye;
    case BallOutcome.legBye:
      return _Umpire.legBye;
    case BallOutcome.dot:
    case BallOutcome.runs:
      return _Umpire.none;
  }
}

/// True when this delivery ends with a cutaway to the umpire (four, six,
/// wicket and every extra).
bool replayHasUmpireSignal(BallEvent b) => _signalFor(b) != _Umpire.none;

class _HeroJob {
  _HeroJob(this.depth, this.draw);
  final double depth;
  final void Function(Canvas) draw;
}

/// Bone indices of the rigged character, looked up once.
class _HeroBones {
  _HeroBones(GlbModel m)
      : hips = m.bone('Hips_'),
        spine = m.bone('Spine_'),
        spine1 = m.bone('Spine1_'),
        spine2 = m.bone('Spine2_'),
        neck = m.bone('Neck_'),
        head = m.bone('Head_'),
        headTop = m.bone('HeadTop_End_0'),
        lShoulder = m.bone('LeftShoulder_'),
        rShoulder = m.bone('RightShoulder_'),
        lArm = m.bone('LeftArm_'),
        rArm = m.bone('RightArm_'),
        lFore = m.bone('LeftForeArm_'),
        rFore = m.bone('RightForeArm_'),
        lHand = m.bone('LeftHand_'),
        rHand = m.bone('RightHand_'),
        lMiddle = m.bone('LeftHandMiddle1_'),
        rMiddle = m.bone('RightHandMiddle1_'),
        lUpLeg = m.bone('LeftUpLeg_'),
        rUpLeg = m.bone('RightUpLeg_'),
        lLeg = m.bone('LeftLeg_'),
        rLeg = m.bone('RightLeg_'),
        lFoot = m.bone('LeftFoot_'),
        rFoot = m.bone('RightFoot_'),
        lToe = m.bone('LeftToeBase_'),
        rToe = m.bone('RightToeBase_'),
        bat = m.byName['Bat'],
        batToe = m.byName['Bat_Toe'];

  static final Map<GlbModel, _HeroBones> _cache = {};
  static _HeroBones of(GlbModel m) => _cache.putIfAbsent(m, () => _HeroBones(m));

  final int hips, spine, spine1, spine2, neck, head, headTop;
  final int lShoulder, rShoulder, lArm, rArm, lFore, rFore, lHand, rHand, lMiddle, rMiddle;
  final int lUpLeg, rUpLeg, lLeg, rLeg, lFoot, rFoot, lToe, rToe;

  /// The bat node (child of the top hand) and its toe marker, on the batsman model only.
  final int? bat, batToe;
}
