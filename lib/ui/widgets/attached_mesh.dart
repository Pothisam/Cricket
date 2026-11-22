import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'glb_model.dart';
import 'scene3d.dart';

/// One textured (or flat-coloured) piece of an attached mesh.
class AttachedGroup {
  AttachedGroup(this.pos, this.uv, this.nor, this.indices, this.image, this.color);
  final Float32List pos, uv, nor;
  final Uint32List indices;
  final ui.Image? image;
  final ui.Color color;
}

/// Static meshes that ride on a bone of a character (here the bat, a child of the
/// top-hand bone). The mesh node's own transform is applied first, then the bone's
/// world transform from the skeleton, so the bat always stays in the hand.
class AttachedMeshes {
  AttachedMeshes(this.groups, this.localR, this.localT, this.scale);

  final List<AttachedGroup> groups;

  /// Rotation (3x3, row-major), translation and uniform scale of the mesh node
  /// relative to its parent bone node (e.g. `Bat_Model` under `Bat`).
  final List<double> localR, localT;
  final double scale;

  static Future<AttachedMeshes> load(String asset, String nodeName) async {
    final g = await GlbModel.readGlb(asset);
    final j = g.json;
    final acc = AccessorReader(j, g.bin);
    final nodes = j['nodes'] as List;
    final idx = nodes.indexWhere((n) => (n as Map)['name'] == nodeName);
    if (idx < 0) throw StateError('Node $nodeName not found');
    final node = nodes[idx] as Map<String, dynamic>;
    final t = ((node['translation'] as List?) ?? const [0, 0, 0]).map((e) => (e as num).toDouble()).toList();
    final q = ((node['rotation'] as List?) ?? const [0, 0, 0, 1]).map((e) => (e as num).toDouble()).toList();
    final sc = ((node['scale'] as List?) ?? const [1, 1, 1]).map((e) => (e as num).toDouble()).toList();

    Future<ui.Image> decode(int imageIdx) async {
      final img = (j['images'] as List)[imageIdx] as Map<String, dynamic>;
      final b = acc.view(img['bufferView'] as int);
      final codec = await ui.instantiateImageCodec(b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes));
      return (await codec.getNextFrame()).image;
    }

    final groups = <AttachedGroup>[];
    int srgb(double v) => (255 * math.pow(v.clamp(0.0, 1.0), 1 / 2.2)).round();
    for (final c in ((node['children'] as List?) ?? const [])) {
      final child = nodes[c as int] as Map<String, dynamic>;
      if (child['mesh'] == null) continue;
      final mesh = (j['meshes'] as List)[child['mesh'] as int] as Map<String, dynamic>;
      for (final pr in (mesh['primitives'] as List)) {
        final p = pr as Map<String, dynamic>;
        final attrs = p['attributes'] as Map<String, dynamic>;
        final pos = acc.read(attrs['POSITION'] as int);
        final nor = attrs['NORMAL'] != null ? acc.read(attrs['NORMAL'] as int) : List<num>.filled(pos.length, 0);
        final uv = attrs['TEXCOORD_0'] != null ? acc.read(attrs['TEXCOORD_0'] as int) : List<num>.filled(pos.length ~/ 3 * 2, 0);
        final ind = acc.read(p['indices'] as int);
        final mat = (j['materials'] as List)[p['material'] as int] as Map<String, dynamic>;
        final pbr = (mat['pbrMetallicRoughness'] as Map?) ?? const {};
        final tex = pbr['baseColorTexture'] as Map?;
        ui.Image? image;
        if (tex != null) image = await decode(((j['textures'] as List)[tex['index'] as int] as Map)['source'] as int);
        final f = ((pbr['baseColorFactor'] as List?) ?? const [0.8, 0.8, 0.8, 1]).map((e) => (e as num).toDouble()).toList();
        groups.add(AttachedGroup(
          Float32List.fromList(pos.map((e) => e.toDouble()).toList()),
          Float32List.fromList(uv.map((e) => e.toDouble()).toList()),
          Float32List.fromList(nor.map((e) => e.toDouble()).toList()),
          Uint32List.fromList(ind.map((e) => e.toInt()).toList()),
          image,
          ui.Color.fromARGB(255, srgb(f[0]), srgb(f[1]), srgb(f[2])),
        ));
      }
    }
    return AttachedMeshes(groups, quatToMat(q[0], q[1], q[2], q[3]), t, sc[0]);
  }
}

/// Draws [m] attached to skeleton node [parentNode]: the bat sits exactly where the
/// bone puts it, whatever animation or pose is playing.
void drawAttachedMeshes(
  ui.Canvas canvas,
  Cam3 cam,
  AttachedMeshes m,
  Rig rig,
  int parentNode,
  HeroTransform tf, {
  V3 sun = const V3(-0.4, -0.35, 0.85),
}) {
  final wr = rig.wr[parentNode], wt = rig.wt[parentNode];
  final r = m.localR;
  final light = sun.unit;

  V3 mul3(List<double> a, V3 v) => V3(a[0] * v.x + a[1] * v.y + a[2] * v.z, a[3] * v.x + a[4] * v.y + a[5] * v.z, a[6] * v.x + a[7] * v.y + a[8] * v.z);

  for (final g in m.groups) {
    final n = g.pos.length ~/ 3;
    final world = List<V3>.filled(n, const V3(0, 0, 0));
    final sp = List<ui.Offset>.filled(n, ui.Offset.zero);
    final sd = List<double>.filled(n, 0);
    final sc = List<int>.filled(n, 0);
    for (var v = 0; v < n; v++) {
      final local = V3(g.pos[v * 3], g.pos[v * 3 + 1], g.pos[v * 3 + 2]);
      // node transform (scale, rotation, translation), then the bone's world transform
      final inBone = mul3(r, local * m.scale) + V3(m.localT[0], m.localT[1], m.localT[2]);
      final scene = mul3(wr, inBone) + V3(wt[0], wt[1], wt[2]);
      final w = tf.toWorld(scene);
      final nrm = tf.dirToWorld(mul3(wr, mul3(r, V3(g.nor[v * 3], g.nor[v * 3 + 1], g.nor[v * 3 + 2])))).unit;
      final pr = cam.project(w);
      world[v] = w;
      sp[v] = pr.pt;
      sd[v] = pr.depth;
      final lit = (0.5 + 0.62 * math.max(0.0, nrm.dot(light)) + 0.12 * (nrm.z * 0.5 + 0.5)).clamp(0.0, 1.2);
      final ch = (255 * lit.clamp(0.0, 1.0)).round();
      sc[v] = (0xFF << 24) | (ch << 16) | (ch << 8) | ch;
    }
    final pos = <double>[], tex = <double>[], col = <int>[], depth = <double>[];
    final img = g.image;
    for (var i = 0; i + 2 < g.indices.length; i += 3) {
      final a = g.indices[i], b = g.indices[i + 1], c = g.indices[i + 2];
      if (sd[a] < 0.01 || sd[b] < 0.01 || sd[c] < 0.01) continue;
      depth.add((sd[a] + sd[b] + sd[c]) / 3);
      for (final v in [a, b, c]) {
        pos..add(sp[v].dx)..add(sp[v].dy);
        tex
          ..add(img == null ? 0.0 : g.uv[v * 2] * img.width)
          ..add(img == null ? 0.0 : g.uv[v * 2 + 1] * img.height);
        col.add(sc[v]);
      }
    }
    final tris = depth.length;
    if (tris == 0) continue;
    final order = List<int>.generate(tris, (i) => i)..sort((x, y) => depth[y].compareTo(depth[x]));
    final p2 = Float32List(tris * 6), t2 = Float32List(tris * 6);
    final c2 = Int32List(tris * 3);
    for (var o = 0; o < tris; o++) {
      final s = order[o];
      for (var k = 0; k < 6; k++) {
        p2[o * 6 + k] = pos[s * 6 + k];
        t2[o * 6 + k] = tex[s * 6 + k];
      }
      for (var k = 0; k < 3; k++) {
        c2[o * 3 + k] = col[s * 3 + k];
      }
    }
    final paint = ui.Paint();
    if (img != null) {
      paint.shader = ui.ImageShader(img, ui.TileMode.repeated, ui.TileMode.repeated, Float64List.fromList(const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
          filterQuality: ui.FilterQuality.medium);
      canvas.drawVertices(ui.Vertices.raw(ui.VertexMode.triangles, p2, textureCoordinates: t2, colors: c2), ui.BlendMode.modulate, paint);
    } else {
      final tinted = Int32List.fromList([
        for (final cc in c2)
          (0xFF << 24) |
              ((((cc >> 16) & 0xFF) * g.color.r).round().clamp(0, 255) << 16) |
              ((((cc >> 8) & 0xFF) * g.color.g).round().clamp(0, 255) << 8) |
              (((cc & 0xFF) * g.color.b).round().clamp(0, 255))
      ]);
      canvas.drawVertices(ui.Vertices.raw(ui.VertexMode.triangles, p2, colors: tinted), ui.BlendMode.srcOver, paint);
    }
  }
}
