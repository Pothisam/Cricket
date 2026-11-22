import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// Minimal dependency-free 3D: world space has +x to the off side, +y down the
// pitch towards the bowler and +z up. The ground has radius 1.

class V3 {
  const V3(this.x, this.y, this.z);
  final double x, y, z;
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  V3 get unit {
    final l = math.sqrt(dot(this));
    return l == 0 ? this : this * (1 / l);
  }

  static V3 lerp(V3 a, V3 b, double t) => a + (b - a) * t;
}

class Proj3 {
  const Proj3(this.pt, this.scale, this.depth);
  final Offset pt;

  /// Pixels per world unit at this depth.
  final double scale;
  final double depth;
}

class Cam3 {
  Cam3(this.eye, this.target, this.size, double fovDeg, {this.centerY = 0.56})
    : focal = size.height / 2 / math.tan(fovDeg * math.pi / 360) {
    f = (target - eye).unit;
    r = f.cross(const V3(0, 0, 1)).unit;
    u = r.cross(f);
  }

  final V3 eye, target;
  final Size size;
  final double focal;
  late final V3 f, r, u;

  final double centerY;
  double get _cy => size.height * centerY;

  Proj3 project(V3 p) {
    final d = p - eye;
    final zc = math.max(d.dot(f), 0.004);
    final s = focal / zc;
    return Proj3(
      Offset(size.width / 2 + d.dot(r) * s, _cy - d.dot(u) * s),
      s,
      zc,
    );
  }

  double get horizonY {
    final h = V3(f.x, f.y, 0).unit;
    final hf = h.dot(f);
    return hf.abs() < 1e-6 ? size.height : _cy - h.dot(u) / hf * focal;
  }

  /// Ground (z = 0) point under a screen pixel, or null above the horizon.
  Offset? groundAt(Offset px) {
    final dir =
        f +
        r * ((px.dx - size.width / 2) / focal) +
        u * ((_cy - px.dy) / focal);
    if (dir.z >= -1e-6) return null;
    final k = -eye.z / dir.z;
    return Offset(eye.x + dir.x * k, eye.y + dir.y * k);
  }
}

Path ring3(Cam3 cam, double radius, {double z = 0}) {
  final path = Path();
  for (var i = 0; i <= 96; i++) {
    final a = i / 96 * 2 * math.pi;
    final p = cam.project(V3(math.cos(a) * radius, math.sin(a) * radius, z)).pt;
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

Path quad3(
  Cam3 cam,
  double x0,
  double y0,
  double x1,
  double y1, {
  double z = 0,
}) {
  final pts = [
    V3(x0, y0, z),
    V3(x1, y0, z),
    V3(x1, y1, z),
    V3(x0, y1, z),
  ].map((v) => cam.project(v).pt).toList();
  return Path()..addPolygon(pts, true);
}

void paintBackdrop(Canvas canvas, Cam3 cam) {
  final size = cam.size;
  final horizon = cam.horizonY.clamp(0.0, size.height);
  canvas.drawRect(
    Rect.fromLTRB(0, 0, size.width, horizon),
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF7DB8E6), Color(0xFFDDEFF8)],
      ).createShader(Rect.fromLTRB(0, 0, size.width, math.max(horizon, 1))),
  );
  // Distant tree line.
  canvas.drawRect(
    Rect.fromLTRB(0, horizon - 6, size.width, horizon),
    Paint()..color = const Color(0xFF557A5A),
  );
  canvas.drawRect(
    Rect.fromLTRB(0, horizon, size.width, size.height),
    Paint()..color = const Color(0xFF2B6E31),
  );
}

List<V3>? _speckle;

void paintGround(Canvas canvas, Cam3 cam) {
  final ground = ring3(cam, 1);
  canvas.drawPath(ground, Paint()..color = const Color(0xFF3F8B3D));
  canvas.save();
  canvas.clipPath(ground);
  // Mowing stripes, finer than before.
  const stripes = 28;
  for (var i = 0; i < stripes; i += 2) {
    final y0 = -1.0 + 2.0 * i / stripes, y1 = y0 + 2.0 / stripes;
    canvas.drawPath(
      quad3(cam, -1.1, y0, 1.1, y1),
      Paint()..color = const Color(0x1FFFFFFF),
    );
  }
  // Grass texture: a fixed scatter of light and dark blades in world space.
  final pts = _speckle ??= () {
    final rnd = math.Random(11);
    return List.generate(5200, (_) {
      final a = rnd.nextDouble() * 2 * math.pi, r = math.sqrt(rnd.nextDouble());
      return V3(math.cos(a) * r, math.sin(a) * r, 0);
    });
  }();
  final dark = <Offset>[], light = <Offset>[];
  for (var i = 0; i < pts.length; i++) {
    final pr = cam.project(pts[i]);
    if (pr.pt.dx < 0 ||
        pr.pt.dx > cam.size.width ||
        pr.pt.dy < 0 ||
        pr.pt.dy > cam.size.height)
      continue;
    (i.isEven ? dark : light).add(pr.pt);
  }
  canvas.drawPoints(
    ui.PointMode.points,
    dark,
    Paint()
      ..color = const Color(0x33154A1A)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round,
  );
  canvas.drawPoints(
    ui.PointMode.points,
    light,
    Paint()
      ..color = const Color(0x2ABFE59A)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round,
  );
  canvas.restore();
  canvas.drawPath(
    ring3(cam, 0.42),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.3),
  );
  canvas.drawPath(
    ground,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = Colors.white,
  );

  // The pitch: 22.6 m x 3.05 m, worn brown with darker ends; popping creases 1.22 m
  // in front of the stumps.
  const m = 1 / 65;
  final pitch = quad3(
    cam,
    -1.52 * m,
    -11.3 * m,
    1.52 * m,
    11.3 * m,
    z: 0.00004,
  );
  final top = cam.project(const V3(0, 11.3 * m, 0)).pt;
  final bottom = cam.project(const V3(0, -11.3 * m, 0)).pt;
  canvas.drawPath(
    pitch,
    Paint()
      ..shader = ui.Gradient.linear(
        bottom,
        top,
        const [
          Color(0xFFB8996A),
          Color(0xFFD4BC8A),
          Color(0xFFD9C595),
          Color(0xFFD4BC8A),
          Color(0xFFB8996A),
        ],
        const [0.0, 0.2, 0.5, 0.8, 1.0],
      ),
  );
  final crease = Paint()
    ..color = Colors.white
    ..strokeWidth = 1.6;
  for (final y in [-8.84 * m, 8.84 * m]) {
    canvas.drawLine(
      cam.project(V3(-1.32 * m, y, 0.00005)).pt,
      cam.project(V3(1.32 * m, y, 0.00005)).pt,
      crease,
    );
  }
  for (final x in [-1.32 * m, 1.32 * m]) {
    canvas.drawLine(
      cam.project(V3(x, -10.06 * m, 0.00005)).pt,
      cam.project(V3(x, -8.84 * m, 0.00005)).pt,
      crease,
    );
    canvas.drawLine(
      cam.project(V3(x, 10.06 * m, 0.00005)).pt,
      cam.project(V3(x, 8.84 * m, 0.00005)).pt,
      crease,
    );
  }
  // Stump lines.
  for (final y in [-10.06 * m, 10.06 * m]) {
    canvas.drawLine(
      cam.project(V3(-1.32 * m, y, 0.00005)).pt,
      cam.project(V3(1.32 * m, y, 0.00005)).pt,
      crease,
    );
  }
}
