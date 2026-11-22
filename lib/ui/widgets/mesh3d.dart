import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'scene3d.dart';

/// A small software 3D renderer: solid triangle meshes with smooth (Gouraud)
/// sun lighting, back-face culling and painter's-algorithm depth sorting,
/// drawn with `drawVertices`. Players, the umpire, the bat, the ball, the
/// stumps and the stadium are all real meshes with volume and shading.
class MeshBuilder {
  MeshBuilder(this.cam, {V3 sun = const V3(-0.4, -0.35, 0.85)})
    : sun = sun.unit;

  final Cam3 cam;
  final V3 sun;
  final List<_Tri> _tris = [];

  static const _ambient = 0.42;
  static const _diffuse = 0.66;
  static const _sky = 0.14;

  int get triangleCount => _tris.length;

  /// A lit triangle. [outward] says which side is the front; [na]/[nb]/[nc]
  /// are optional per-vertex normals for smooth shading (flat otherwise).
  void tri(
    V3 a,
    V3 b,
    V3 c,
    Color color,
    V3 outward, {
    V3? na,
    V3? nb,
    V3? nc,
  }) {
    var n = (b - a).cross(c - a);
    final len = math.sqrt(n.dot(n));
    if (len < 1e-16) return;
    n = n * (1 / len);
    if (n.dot(outward) < 0) n = n * -1;
    final centre = (a + b + c) * (1 / 3);
    if (n.dot(cam.eye - centre) <= 0) return; // back face
    final pa = cam.project(a), pb = cam.project(b), pc = cam.project(c);
    if (pa.depth < 0.01 || pb.depth < 0.01 || pc.depth < 0.01) return;
    _tris.add(
      _Tri(
        (pa.depth + pb.depth + pc.depth) / 3,
        pa.pt,
        pb.pt,
        pc.pt,
        _lit(color, na ?? n),
        _lit(color, nb ?? n),
        _lit(color, nc ?? n),
      ),
    );
  }

  int _lit(Color c, V3 n) {
    final k =
        (_ambient +
                _diffuse * math.max(0.0, n.dot(sun)) +
                _sky * (n.z * 0.5 + 0.5))
            .clamp(0.0, 1.25);
    int ch(double v) => (v * 255 * k).round().clamp(0, 255);
    return (0xFF << 24) | (ch(c.r) << 16) | (ch(c.g) << 8) | ch(c.b);
  }

  /// Elliptical frustum (a limb, torso, bat blade...) from [a] to [b].
  /// [lat] hints which way the wide axis of the ellipse points.
  void frustum(
    V3 a,
    V3 b,
    double rax,
    double ray,
    double rbx,
    double rby,
    Color color, {
    V3 lat = const V3(1, 0, 0),
    int sides = 8,
    bool capA = true,
    bool capB = true,
    bool smooth = true,
  }) {
    final d = (b - a).unit;
    var u = lat - d * lat.dot(d);
    if (u.dot(u) < 1e-6) u = const V3(0, 1, 0) - d * d.y;
    u = u.unit;
    final v = d.cross(u);
    final ringA = <V3>[], ringB = <V3>[], radial = <V3>[];
    for (var i = 0; i < sides; i++) {
      final th = 2 * math.pi * i / sides;
      final cu = math.cos(th), sv = math.sin(th);
      ringA.add(a + u * (cu * rax) + v * (sv * ray));
      ringB.add(b + u * (cu * rbx) + v * (sv * rby));
      radial.add(
        (u * (cu / math.max(rax, 1e-9)) + v * (sv / math.max(ray, 1e-9))).unit,
      );
    }
    for (var i = 0; i < sides; i++) {
      final j = (i + 1) % sides;
      final out = radial[i] + radial[j];
      if (smooth) {
        tri(
          ringA[i],
          ringA[j],
          ringB[j],
          color,
          out,
          na: radial[i],
          nb: radial[j],
          nc: radial[j],
        );
        tri(
          ringA[i],
          ringB[j],
          ringB[i],
          color,
          out,
          na: radial[i],
          nb: radial[j],
          nc: radial[i],
        );
      } else {
        tri(ringA[i], ringA[j], ringB[j], color, out);
        tri(ringA[i], ringB[j], ringB[i], color, out);
      }
    }
    if (capA) {
      for (var i = 0; i < sides; i++) {
        tri(a, ringA[(i + 1) % sides], ringA[i], color, d * -1);
      }
    }
    if (capB) {
      for (var i = 0; i < sides; i++) {
        tri(b, ringB[i], ringB[(i + 1) % sides], color, d);
      }
    }
  }

  /// Round limb / cylinder.
  void limb(
    V3 a,
    V3 b,
    double ra,
    double rb,
    Color color, {
    int sides = 8,
    bool capA = true,
    bool capB = true,
  }) => frustum(
    a,
    b,
    ra,
    ra,
    rb,
    rb,
    color,
    sides: sides,
    capA: capA,
    capB: capB,
  );

  /// A sphere (or ellipsoid via [sy] / [sx]) with smooth shading.
  void sphere(
    V3 c,
    double r,
    Color color, {
    int lat = 6,
    int lon = 10,
    double sy = 1,
    double sx = 1,
  }) {
    V3 pt(int i, int j) {
      final phi = math.pi * i / lat; // 0 (top) .. pi (bottom)
      final th = 2 * math.pi * j / lon;
      return c +
          V3(
            math.sin(phi) * math.cos(th) * r * sx,
            math.sin(phi) * math.sin(th) * r,
            math.cos(phi) * r * sy,
          );
    }

    V3 nrm(V3 p) =>
        V3((p.x - c.x) / (sx * sx), p.y - c.y, (p.z - c.z) / (sy * sy)).unit;
    for (var i = 0; i < lat; i++) {
      for (var j = 0; j < lon; j++) {
        final a = pt(i, j),
            b = pt(i, j + 1),
            cc = pt(i + 1, j + 1),
            d = pt(i + 1, j);
        final out = ((a + b + cc + d) * 0.25) - c;
        tri(a, d, cc, color, out, na: nrm(a), nb: nrm(d), nc: nrm(cc));
        tri(a, cc, b, color, out, na: nrm(a), nb: nrm(cc), nc: nrm(b));
      }
    }
  }

  /// A flat quad facing [outward] (stands, boards).
  void quad(V3 a, V3 b, V3 c, V3 d, Color color, V3 outward) {
    tri(a, b, c, color, outward);
    tri(a, c, d, color, outward);
  }

  /// Draws every collected triangle, far to near.
  void flush(Canvas canvas) {
    if (_tris.isEmpty) return;
    _tris.sort((x, y) => y.depth.compareTo(x.depth));
    final pos = Float32List(_tris.length * 6);
    final col = Int32List(_tris.length * 3);
    var p = 0, c = 0;
    for (final t in _tris) {
      pos[p++] = t.a.dx;
      pos[p++] = t.a.dy;
      pos[p++] = t.b.dx;
      pos[p++] = t.b.dy;
      pos[p++] = t.c.dx;
      pos[p++] = t.c.dy;
      col[c++] = t.ca;
      col[c++] = t.cb;
      col[c++] = t.cc;
    }
    final vertices = ui.Vertices.raw(ui.VertexMode.triangles, pos, colors: col);
    canvas.drawVertices(vertices, BlendMode.srcOver, Paint());
    _tris.clear();
  }
}

class _Tri {
  _Tri(this.depth, this.a, this.b, this.c, this.ca, this.cb, this.cc);
  final double depth;
  final Offset a, b, c;
  final int ca, cb, cc;
}
