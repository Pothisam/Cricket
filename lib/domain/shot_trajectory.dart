import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/animation.dart' show Curves;

import '../models/ball_event.dart';

/// The path of the ball after it leaves the bat: a smoothed ground track plus
/// a height profile (skips along the turf, a lofted bounce, or a full arc).
/// Used both to preview a shot while scoring and to replay it.
///
/// Heights are in "z units" of 1.3 m (a 6 peaks around 20 m).
class ShotTrajectory {
  ShotTrajectory(List<Offset> raw, this.loft) : points = _prepare(raw);

  /// Where the ball meets the bat.
  static const origin = Offset(
    0,
    -0.1385,
  ); // bat contact, just in front of the popping crease
  static const _samples = 48;

  /// Dense, evenly spaced (by arc length) ground points, starting at [origin].
  final List<Offset> points;
  final ShotLoft loft;

  /// A straight shot of length [frac] (ground radius = 1) towards [dir].
  factory ShotTrajectory.fromDirection(
    ShotDirection dir,
    double frac,
    ShotLoft loft,
  ) {
    final a = dir.angle * math.pi / 180;
    return ShotTrajectory([
      origin,
      Offset(math.sin(a), math.cos(a)) * frac,
    ], loft);
  }

  static List<Offset> _prepare(List<Offset> raw) {
    var pts = [origin, ...raw.skip(1)];
    if (raw.isEmpty) pts = [origin, origin + const Offset(0, 0.1)];
    // Drop near-duplicates, then smooth the hand-drawn corners.
    final clean = <Offset>[pts.first];
    for (final p in pts.skip(1)) {
      if ((p - clean.last).distance > 0.01) clean.add(p);
    }
    if (clean.length < 2) clean.add(clean.first + const Offset(0, 0.1));
    var cur = clean;
    for (var pass = 0; pass < 2 && cur.length > 2; pass++) {
      final next = <Offset>[cur.first];
      for (var i = 0; i < cur.length - 1; i++) {
        next.add(Offset.lerp(cur[i], cur[i + 1], 0.25)!);
        next.add(Offset.lerp(cur[i], cur[i + 1], 0.75)!);
      }
      next.add(cur.last);
      cur = next;
    }
    // Resample evenly by arc length.
    final cum = <double>[0];
    for (var i = 1; i < cur.length; i++) {
      cum.add(cum.last + (cur[i] - cur[i - 1]).distance);
    }
    final total = cum.last;
    final out = <Offset>[];
    var j = 0;
    for (var i = 0; i <= _samples; i++) {
      final d = total * i / _samples;
      while (j < cum.length - 2 && cum[j + 1] < d) {
        j++;
      }
      final seg = cum[j + 1] - cum[j];
      out.add(
        seg == 0
            ? cur[j]
            : Offset.lerp(cur[j], cur[j + 1], (d - cum[j]) / seg)!,
      );
    }
    return out;
  }

  Offset get end => points.last;

  double get length {
    var l = 0.0;
    for (var i = 1; i < points.length; i++) {
      l += (points[i] - points[i - 1]).distance;
    }
    return l;
  }

  /// Compass angle of the end point around the middle of the ground, degrees.
  double get endAngle => math.atan2(end.dx, end.dy) * 180 / math.pi;

  /// Nearest named fielding direction to where the ball finished.
  ShotDirection get direction {
    var best = ShotDirection.straight;
    var bestDiff = 999.0;
    for (final d in ShotDirection.values) {
      var diff = (d.angle - endAngle).abs();
      if (diff > 180) diff = 360 - diff;
      if (diff < bestDiff) {
        bestDiff = diff;
        best = d;
      }
    }
    return best;
  }

  /// Ground point at fraction [s] (0..1) of the way along the path.
  Offset pointAt(double s) {
    final f = s.clamp(0.0, 1.0) * (points.length - 1);
    final i = f.floor().clamp(0, points.length - 2);
    return Offset.lerp(points[i], points[i + 1], f - i)!;
  }

  /// Fractions along the path where the ball touches the ground.
  List<double> get bounces {
    switch (loft) {
      case ShotLoft.ground:
        return const [0.25, 0.5, 0.75];
      case ShotLoft.lofted:
        return const [_landing, _landing + 0.15, _landing + 0.28];
      case ShotLoft.aerial:
        return const [];
    }
  }

  static const _landing = 0.6;

  /// Height of the ball at fraction [s] of the path.
  double heightAt(double s) {
    s = s.clamp(0.0, 1.0);
    switch (loft) {
      case ShotLoft.ground:
        // Small decaying skips along the turf.
        return 0.3 * math.pow(1 - s, 1.4) * math.sin(4 * math.pi * s).abs();
      case ShotLoft.lofted:
        if (s < _landing) return 6.0 * math.sin(math.pi * s / _landing);
        final u = (s - _landing) / (1 - _landing);
        return 2.2 * math.pow(1 - u, 1.2) * math.sin(2.5 * math.pi * u).abs();
      case ShotLoft.aerial:
        return 16.0 * math.pow(math.sin(math.pi * s), 0.85).toDouble();
    }
  }

  /// How far along the path the ball is after fraction [tau] of its flight time.
  double progress(double tau) {
    tau = tau.clamp(0.0, 1.0);
    switch (loft) {
      case ShotLoft.ground:
        return Curves.easeOutCubic.transform(tau);
      case ShotLoft.lofted:
        return Curves.easeOutSine.transform(tau);
      case ShotLoft.aerial:
        return tau;
    }
  }

  /// A copy that keeps going in the final heading until it reaches [radius]
  /// from the middle of the ground (boundaries) and uses at least [minLoft].
  ShotTrajectory extendedTo(double radius, {ShotLoft? minLoft}) {
    var l = loft;
    if (minLoft != null && l.index < minLoft.index) l = minLoft;
    if (end.distance >= radius) return ShotTrajectory(points, l);
    final heading = points.length > 3
        ? (end - points[points.length - 4])
        : (end - points.first);
    final dir = heading.distance == 0
        ? const Offset(0, 1)
        : heading / heading.distance;
    // Walk forward until the rope is crossed.
    var tip = end;
    var steps = 0;
    while (tip.distance < radius && steps++ < 200) {
      tip += dir * 0.02;
    }
    return ShotTrajectory([...points, tip], l);
  }
}

/// Where each named fielder stands (ground radius = 1, +y towards the bowler).
const fielderRadius = {
  ShotDirection.straight: 0.78,
  ShotDirection.midOff: 0.5,
  ShotDirection.cover: 0.62,
  ShotDirection.point: 0.5,
  ShotDirection.thirdMan: 0.82,
  ShotDirection.fineLeg: 0.82,
  ShotDirection.squareLeg: 0.55,
  ShotDirection.midWicket: 0.62,
  ShotDirection.midOn: 0.5,
};

Offset fielderHome(ShotDirection d) {
  final a = d.angle * math.pi / 180;
  return Offset(math.sin(a), math.cos(a)) * fielderRadius[d]!;
}
