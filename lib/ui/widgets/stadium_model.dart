import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'glb_model.dart';
import 'scene3d.dart';

/// The stadium: a static textured mesh scaled to our pitch and boundary
/// (pitch 22.6 m, boundary radius 65 m, one world unit = 65 m).
class StadiumModel {
  StadiumModel(this.pos, this.nor, this.uv, this.indices, this.atlas);
  final Float32List pos, nor, uv; // world units, atlas-pixel UVs
  final Uint32List indices;
  final ui.Image atlas;

  /// Sponsor boards / logos, the ground and the pitch are not drawn (we have our own).
  static const _skip = ['Vivo', 'Oppo', 'icc', 'Dreem', 'Ground00', 'pinch', 'display', 'ASP_paint'];

  static Future<StadiumModel> load(String asset) async {
    final g = await GlbModel.readGlb(asset);
    final j = g.json;
    final acc = AccessorReader(j, g.bin);
    final nodes = j['nodes'] as List;
    final parents = List<int>.filled(nodes.length, -1);
    for (var i = 0; i < nodes.length; i++) {
      for (final c in ((nodes[i] as Map)['children'] as List?) ?? const []) {
        parents[c as int] = i;
      }
    }

    List<double> mul4(List<double> a, List<double> b) {
      final o = List<double>.filled(16, 0);
      for (var c = 0; c < 4; c++) {
        for (var r = 0; r < 4; r++) {
          var s = 0.0;
          for (var k = 0; k < 4; k++) {
            s += a[k * 4 + r] * b[c * 4 + k];
          }
          o[c * 4 + r] = s;
        }
      }
      return o;
    }

    List<double> local(int i) {
      final n = nodes[i] as Map<String, dynamic>;
      if (n['matrix'] != null) return (n['matrix'] as List).map((e) => (e as num).toDouble()).toList();
      final t = ((n['translation'] as List?) ?? const [0, 0, 0]).map((e) => (e as num).toDouble()).toList();
      final q = ((n['rotation'] as List?) ?? const [0, 0, 0, 1]).map((e) => (e as num).toDouble()).toList();
      final s = ((n['scale'] as List?) ?? const [1, 1, 1]).map((e) => (e as num).toDouble()).toList();
      final r = quatToMat(q[0], q[1], q[2], q[3]);
      return [
        r[0] * s[0], r[3] * s[0], r[6] * s[0], 0,
        r[1] * s[1], r[4] * s[1], r[7] * s[1], 0,
        r[2] * s[2], r[5] * s[2], r[8] * s[2], 0,
        t[0], t[1], t[2], 1,
      ];
    }

    final cache = <int, List<double>>{};
    List<double> world(int i) => cache[i] ??= parents[i] < 0 ? local(i) : mul4(world(parents[i]), local(i));

    // Collect every mesh with its node transform applied.
    final parts = <({String name, int mat, List<double> pos, List<double> nor, List<double> uv, List<int> idx})>[];
    final bounds = <String, List<List<double>>>{};
    for (var ni = 0; ni < nodes.length; ni++) {
      final n = nodes[ni] as Map<String, dynamic>;
      if (n['mesh'] == null) continue;
      final name = (n['name'] as String?) ?? '';
      final w = world(ni);
      final mesh = (j['meshes'] as List)[n['mesh'] as int] as Map<String, dynamic>;
      for (final pr in (mesh['primitives'] as List)) {
        final p = pr as Map<String, dynamic>;
        final attrs = p['attributes'] as Map<String, dynamic>;
        final pos = acc.read(attrs['POSITION'] as int);
        final count = pos.length ~/ 3;
        final nor = attrs['NORMAL'] != null ? acc.read(attrs['NORMAL'] as int) : List<num>.filled(pos.length, 0);
        final uv = attrs['TEXCOORD_0'] != null ? acc.read(attrs['TEXCOORD_0'] as int) : List<num>.filled(count * 2, 0);
        final wp = <double>[], wn = <double>[];
        final mn = [1e18, 1e18, 1e18], mx = [-1e18, -1e18, -1e18];
        for (var v = 0; v < count; v++) {
          final x = pos[v * 3].toDouble(), y = pos[v * 3 + 1].toDouble(), z = pos[v * 3 + 2].toDouble();
          final px = w[0] * x + w[4] * y + w[8] * z + w[12];
          final py = w[1] * x + w[5] * y + w[9] * z + w[13];
          final pz = w[2] * x + w[6] * y + w[10] * z + w[14];
          wp..add(px)..add(py)..add(pz);
          final nx = nor[v * 3].toDouble(), ny = nor[v * 3 + 1].toDouble(), nz = nor[v * 3 + 2].toDouble();
          wn
            ..add(w[0] * nx + w[4] * ny + w[8] * nz)
            ..add(w[1] * nx + w[5] * ny + w[9] * nz)
            ..add(w[2] * nx + w[6] * ny + w[10] * nz);
          final c = [px, py, pz];
          for (var k = 0; k < 3; k++) {
            mn[k] = math.min(mn[k], c[k]);
            mx[k] = math.max(mx[k], c[k]);
          }
        }
        bounds[name] = [mn, mx];
        parts.add((name: name, mat: p['material'] as int, pos: wp, nor: wn, uv: uv.map((e) => e.toDouble()).toList(), idx: acc.read(p['indices'] as int).map((e) => e.toInt()).toList()));
      }
    }

    // Orientation: the flat ground plane gives "up", the pitch gives its long axis.
    final gb = bounds.entries.firstWhere((e) => e.key.contains('Ground00')).value;
    final pb = bounds.entries.firstWhere((e) => e.key.contains('pinch')).value;
    final gext = [for (var k = 0; k < 3; k++) gb[1][k] - gb[0][k]];
    final upAxis = [0, 1, 2].reduce((a, b) => gext[a] <= gext[b] ? a : b);
    final pext = [for (var k = 0; k < 3; k++) pb[1][k] - pb[0][k]];
    final longAxis = [0, 1, 2].where((k) => k != upAxis).reduce((a, b) => pext[a] >= pext[b] ? a : b);
    final sideAxis = [0, 1, 2].firstWhere((k) => k != upAxis && k != longAxis);
    V3 unit(int k) => V3(k == 0 ? 1 : 0, k == 1 ? 1 : 0, k == 2 ? 1 : 0);
    final yAx = unit(longAxis), zAx = unit(upAxis);
    final xAx = yAx.cross(zAx); // right-handed: x = y x z
    final scale = (22.6 / pext[longAxis]) / 65.0;
    final cx = (pb[0][sideAxis] + pb[1][sideAxis]) / 2;
    final cy = (pb[0][longAxis] + pb[1][longAxis]) / 2;
    final cz = gb[0][upAxis];

    // Atlas: textured materials get a 512 px cell, solid colours a swatch.
    final materials = j['materials'] as List;
    Future<ui.Image> decode(int imageIdx) async {
      final img = (j['images'] as List)[imageIdx] as Map<String, dynamic>;
      final b = acc.view(img['bufferView'] as int);
      final codec = await ui.instantiateImageCodec(b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes));
      return (await codec.getNextFrame()).image;
    }

    final used = parts.where((p) => !_skip.any((s) => p.name.contains(s))).toList();
    final cellOf = <int, int>{};
    final swatchOf = <int, int>{};
    final swatches = <ui.Color>[];
    final imageOf = <int, int>{};
    int srgb(double v) => (255 * math.pow(v.clamp(0.0, 1.0), 1 / 2.2)).round();
    for (final p in used) {
      if (cellOf.containsKey(p.mat) || swatchOf.containsKey(p.mat)) continue;
      final m = materials[p.mat] as Map<String, dynamic>;
      final pbr = (m['pbrMetallicRoughness'] as Map?) ?? const {};
      final tex = pbr['baseColorTexture'] as Map?;
      if (tex != null) {
        imageOf[p.mat] = ((j['textures'] as List)[tex['index'] as int] as Map)['source'] as int;
        cellOf[p.mat] = cellOf.length;
      } else {
        final f = ((pbr['baseColorFactor'] as List?) ?? const [0.8, 0.8, 0.8, 1]).map((e) => (e as num).toDouble()).toList();
        swatchOf[p.mat] = swatches.length;
        swatches.add(ui.Color.fromARGB(255, srgb(f[0]), srgb(f[1]), srgb(f[2])));
      }
    }
    const cell = 512.0;
    const cols = 4;
    final swatchCell = cellOf.length;
    final rows = ((swatchCell + 1) / cols).ceil();
    final rec = ui.PictureRecorder();
    final cv = ui.Canvas(rec);
    for (final e in cellOf.entries) {
      final img = await decode(imageOf[e.key]!);
      final r = ui.Rect.fromLTWH((e.value % cols) * cell, (e.value ~/ cols) * cell, cell, cell);
      cv.drawImageRect(img, ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), r, ui.Paint()..filterQuality = ui.FilterQuality.medium);
    }
    final sp = ui.Paint();
    final swx = (swatchCell % cols) * cell, swy = (swatchCell ~/ cols) * cell;
    for (var i = 0; i < swatches.length && i < 16; i++) {
      sp.color = swatches[i];
      cv.drawRect(ui.Rect.fromLTWH(swx + (i % 4) * cell / 4, swy + (i ~/ 4) * cell / 4, cell / 4, cell / 4), sp);
    }
    final atlas = await rec.endRecording().toImage((cols * cell).toInt(), (rows * cell).toInt());

    // Flatten into single arrays in our world space.
    final pos = <double>[], nor = <double>[], uv = <double>[], idx = <int>[];
    for (final p in used) {
      final base = pos.length ~/ 3;
      final cellIdx = cellOf[p.mat];
      final sw = swatchOf[p.mat];
      for (var v = 0; v < p.pos.length ~/ 3; v++) {
        final o = V3(p.pos[v * 3], p.pos[v * 3 + 1], p.pos[v * 3 + 2]);
        final comps = [o.x, o.y, o.z];
        // x along the right-handed side axis (sign from the cross product), centred on the pitch.
        final fx = (o.dot(xAx) - xAx.dot(unit(sideAxis)) * cx) * scale;
        final fy = (comps[longAxis] - cy) * scale;
        final fz = (comps[upAxis] - cz) * scale;
        pos..add(fx)..add(fy)..add(fz);
        final n = V3(p.nor[v * 3], p.nor[v * 3 + 1], p.nor[v * 3 + 2]);
        final nn = V3(n.dot(xAx), n.dot(yAx), n.dot(zAx)).unit;
        nor..add(nn.x)..add(nn.y)..add(nn.z);
        if (cellIdx != null) {
          uv
            ..add((cellIdx % cols) * cell + p.uv[v * 2] * cell)
            ..add((cellIdx ~/ cols) * cell + p.uv[v * 2 + 1] * cell);
        } else {
          final slot = sw ?? 0;
          uv
            ..add(swx + (slot % 4) * cell / 4 + cell / 8)
            ..add(swy + (slot ~/ 4) * cell / 4 + cell / 8);
        }
      }
      for (final i in p.idx) {
        idx.add(base + i);
      }
    }
    // The model's playing area is smaller than its ground plane. Find the nearest
    // low structure to the middle and scale so it sits just outside our rope.
    var rin = 1e9;
    for (var v = 0; v < pos.length ~/ 3; v++) {
      if (pos[v * 3 + 2] > 0.05) continue;
      final r = math.sqrt(pos[v * 3] * pos[v * 3] + pos[v * 3 + 1] * pos[v * 3 + 1]);
      if (r > 0.4 && r < rin) rin = r;
    }
    if (rin < 1e8 && rin > 0.05) {
      final k = 1.06 / rin;
      for (var v = 0; v < pos.length; v++) {
        pos[v] *= k;
      }
    }
    return StadiumModel(Float32List.fromList(pos), Float32List.fromList(nor), Float32List.fromList(uv), Uint32List.fromList(idx), atlas);
  }
}

/// Draws the stadium: projected inline for speed, double-sided, depth sorted.
void drawStadiumModel(ui.Canvas canvas, Cam3 cam, StadiumModel m, {V3 sun = const V3(-0.4, -0.35, 0.85)}) {
  final nV = m.pos.length ~/ 3;
  final sx = Float32List(nV), sy = Float32List(nV), sz = Float32List(nV);
  final w = cam.size.width, h = cam.size.height, cy = h * cam.centerY;
  final e = cam.eye, f = cam.f, r = cam.r, u = cam.u;
  final focal = cam.focal;
  final light = sun.unit;
  final shade = Int32List(nV);
  for (var v = 0; v < nV; v++) {
    final dx = m.pos[v * 3] - e.x, dy = m.pos[v * 3 + 1] - e.y, dz = m.pos[v * 3 + 2] - e.z;
    final zc = dx * f.x + dy * f.y + dz * f.z;
    sz[v] = zc;
    if (zc < 0.01) continue;
    final k = focal / zc;
    sx[v] = w / 2 + (dx * r.x + dy * r.y + dz * r.z) * k;
    sy[v] = cy - (dx * u.x + dy * u.y + dz * u.z) * k;
    final nl = (m.nor[v * 3] * light.x + m.nor[v * 3 + 1] * light.y + m.nor[v * 3 + 2] * light.z).abs();
    final lit = (0.55 + 0.5 * nl).clamp(0.0, 1.0);
    final c = (255 * lit).round();
    shade[v] = (0xFF << 24) | (c << 16) | (c << 8) | c;
  }
  final keep = <int>[];
  final depth = <double>[];
  for (var i = 0; i + 2 < m.indices.length; i += 3) {
    final a = m.indices[i], b = m.indices[i + 1], c = m.indices[i + 2];
    if (sz[a] < 0.01 || sz[b] < 0.01 || sz[c] < 0.01) continue;
    final minX = math.min(sx[a], math.min(sx[b], sx[c])), maxX = math.max(sx[a], math.max(sx[b], sx[c]));
    final minY = math.min(sy[a], math.min(sy[b], sy[c])), maxY = math.max(sy[a], math.max(sy[b], sy[c]));
    if (maxX < 0 || minX > w || maxY < 0 || minY > h) continue;
    if ((maxX - minX) > w * 4 || (maxY - minY) > h * 4) continue;
    keep.add(i);
    depth.add((sz[a] + sz[b] + sz[c]) / 3);
  }
  final n = keep.length;
  if (n == 0) return;
  final order = List<int>.generate(n, (i) => i)..sort((x, y) => depth[y].compareTo(depth[x]));
  final pos = Float32List(n * 6), tex = Float32List(n * 6);
  final col = Int32List(n * 3);
  for (var o = 0; o < n; o++) {
    final i = keep[order[o]];
    for (var k = 0; k < 3; k++) {
      final v = m.indices[i + k];
      pos[o * 6 + k * 2] = sx[v];
      pos[o * 6 + k * 2 + 1] = sy[v];
      tex[o * 6 + k * 2] = m.uv[v * 2];
      tex[o * 6 + k * 2 + 1] = m.uv[v * 2 + 1];
      col[o * 3 + k] = shade[v];
    }
  }
  final paint = ui.Paint()
    ..shader = ui.ImageShader(m.atlas, ui.TileMode.clamp, ui.TileMode.clamp, Float64List.fromList(const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
        filterQuality: ui.FilterQuality.medium);
  canvas.drawVertices(ui.Vertices.raw(ui.VertexMode.triangles, pos, textureCoordinates: tex, colors: col), ui.BlendMode.modulate, paint);
}
