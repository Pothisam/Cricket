import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'attached_mesh.dart';
import 'batting_clips.dart';
import 'glb_model.dart';
import 'scene3d.dart';
import 'stadium_model.dart';

/// Everything the replay loads once: the two player models, the motion-capture
/// batting clip (retargeted onto both) and the real bat model.
class HeroAssets {
  HeroAssets(this.players, this.motion, this.bat, this.stadium, this.batsman, this.batMeshes, this.battingClips);

  /// Player models. Different faces and kits, same skeleton family.
  final List<GlbModel> players;
  final MotionSource? motion;
  final StaticModel? bat;
  final StadiumModel? stadium;

  /// The batsman model (bat attached to the top hand, 16 batting clips) and its bat meshes.
  final GlbModel? batsman;
  final AttachedMeshes? batMeshes;
  final BattingClips? battingClips;

  static HeroAssets? ready;
  static Future<HeroAssets>? _loading;

  static Future<HeroAssets> shared() => ready != null ? Future.value(ready) : (_loading ??= _load().then((a) => ready = a));

  static Future<HeroAssets> _load() async {
    final a = await GlbModel.load('assets/models/cricketer.glb');
    final players = [a];
    try {
      players.add(await GlbModel.load('assets/models/cricketer_b.glb'));
    } catch (_) {}
    MotionSource? motion;
    try {
      motion = await MotionSource.load('assets/models/batting_anim.glb');
    } catch (_) {}
    StaticModel? bat;
    try {
      bat = await StaticModel.load('assets/models/bat.glb');
    } catch (_) {}
    StadiumModel? stadium;
    try {
      stadium = await StadiumModel.load('assets/models/stadium.glb');
    } catch (_) {}
    GlbModel? batsman;
    AttachedMeshes? batMeshes;
    BattingClips? clips;
    try {
      batsman = await GlbModel.load('assets/models/batsman.glb', neutralizeRoot: true);
      batMeshes = await AttachedMeshes.load('assets/models/batsman.glb', 'Bat_Model');
      if (batsman.batting != null) clips = BattingClips(batsman.batting!);
    } catch (_) {
      batsman = null;
      batMeshes = null;
      clips = null;
    }
    return HeroAssets(players, motion, bat, stadium, batsman, batMeshes, clips);
  }
}

// ---------------------------------------------------------------------------------------
// Motion source: retargets a Mixamo-style clip onto a Wolf3D skeleton by bone direction.
// ---------------------------------------------------------------------------------------

class MotionSource {
  static Future<MotionSource?> load(String asset) async {
    final model = await GlbModel.load(asset, atlas: false);
    if (model.anims.isEmpty) return null;
    final src = MotionSource(model, model.anims.first);
    // The clip also animates the bat as its own node; find its long axis in local space.
    final g = await GlbModel.readGlb(asset);
    final acc = AccessorReader(g.json, g.bin);
    final nodes = g.json['nodes'] as List;
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i] as Map<String, dynamic>;
      if ((n['name'] as String?) == 'Cricket Bat') {
        // The bat node is a child of the hand bone; its mesh sits on the node or a child.
        int? meshIdx = n['mesh'] as int?;
        for (final c in ((n['children'] as List?) ?? const [])) {
          meshIdx ??= (nodes[c as int] as Map)['mesh'] as int?;
        }
        if (meshIdx == null) break;
        final mesh = (g.json['meshes'] as List)[meshIdx] as Map<String, dynamic>;
        final pts = <V3>[];
        for (final pr in (mesh['primitives'] as List)) {
          final d = acc.read(((pr as Map)['attributes'] as Map)['POSITION'] as int);
          for (var v = 0; v < d.length ~/ 3; v++) {
            pts.add(V3(d[v * 3].toDouble(), d[v * 3 + 1].toDouble(), d[v * 3 + 2].toDouble()));
          }
        }
        if (pts.isEmpty) break;
        final mn = [1e18, 1e18, 1e18], mx = [-1e18, -1e18, -1e18];
        for (final p in pts) {
          final c = [p.x, p.y, p.z];
          for (var k = 0; k < 3; k++) {
            mn[k] = math.min(mn[k], c[k]);
            mx[k] = math.max(mx[k], c[k]);
          }
        }
        final ext = [for (var k = 0; k < 3; k++) mx[k] - mn[k]];
        final la = [0, 1, 2].reduce((a, b) => ext[a] >= ext[b] ? a : b);
        final wa = [0, 1, 2].where((k) => k != la).reduce((a, b) => ext[a] >= ext[b] ? a : b);
        double widthAt(bool high) {
          var lo = 1e18, hi = -1e18;
          for (final p in pts) {
            final c = [p.x, p.y, p.z];
            final t = (c[la] - mn[la]) / ext[la];
            if ((high && t > 0.8) || (!high && t < 0.2)) {
              lo = math.min(lo, c[wa]);
              hi = math.max(hi, c[wa]);
            }
          }
          return hi - lo;
        }

        final bladeHigh = widthAt(true) >= widthAt(false);
        final axis = [0.0, 0.0, 0.0];
        axis[la] = bladeHigh ? -1.0 : 1.0; // handle -> toe (checked against the backlift in the clip)
        final c = [(mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, (mn[2] + mx[2]) / 2];
        final handleEnd = bladeHigh ? mn[la] : mx[la];
        c[la] = handleEnd + (bladeHigh ? 1 : -1) * 0.12 * ext[la];
        src.batNode = i;
        src.batAxisLocal = V3(axis[0], axis[1], axis[2]);
        src.batGripLocal = V3(c[0], c[1], c[2]);
        break;
      }
    }
    if (src.batNode != null && model.anims.length > 1) src.batAnim = model.anims[1];
    src.sample(0);
    src.hipsStart = src.rig.pos(src.hipsBone);
    return src;
  }

  int? batNode;
  V3? batAxisLocal, batGripLocal;
  GlbAnim? batAnim;

  MotionSource(this.model, this.anim) : rig = Rig(model) {
    final bind = Rig(model);
    hipsBone = model.bone('mixamorig:Hips');
    final headTop = model.bone('mixamorig:HeadTop');
    final lFoot = model.bone('mixamorig:LeftFoot');
    final lToe = model.bone('mixamorig:LeftToeBase');
    final hips0 = bind.pos(hipsBone);
    up = (bind.pos(headTop) - hips0).unit;
    var f = bind.pos(lToe) - bind.pos(lFoot);
    f = (f - up * f.dot(up)).unit;
    fwd = f;
    left = up.cross(fwd);
    height = (bind.pos(headTop) - bind.pos(lFoot)).dot(up);
    names = {
      for (final n in const [
        'Hips', 'Spine', 'Spine1', 'Spine2', 'Neck', 'Head', 'HeadTop_End', 'LeftShoulder', 'RightShoulder', 'LeftArm', 'RightArm',
        'LeftForeArm', 'RightForeArm', 'LeftHand', 'RightHand', 'LeftUpLeg', 'RightUpLeg', 'LeftLeg', 'RightLeg', 'LeftFoot', 'RightFoot',
        'LeftToeBase', 'RightToeBase', 'LeftHandIndex1', 'RightHandIndex1',
      ])
        n: model.bone('mixamorig:${n}_')
    };
    hipsStart = bind.pos(hipsBone);
  }

  final GlbModel model;
  final GlbAnim anim;
  final Rig rig;
  late final int hipsBone;
  late final V3 up, fwd, left;
  late V3 hipsStart;
  late final double height;
  late final Map<String, int> names;

  double get duration => anim.duration;

  /// Poses the source skeleton at [t] seconds.
  void sample(double t) {
    rig.applyAnim(anim, t);
    final b = batAnim;
    if (b != null) rig.applyAnim(b, t);
  }

  /// Direction handle -> toe of the animated bat, in the Wolf3D scene frame.
  V3? batAxis() {
    final n = batNode, a = batAxisLocal;
    if (n == null || a == null) return null;
    return _toScene(_rot(rig.wr[n], a));
  }

  /// Where the animated bat's grip is, relative to the current hips, in target metres.
  V3? batGrip(double targetHeight) {
    final n = batNode, g = batGripLocal;
    if (n == null || g == null) return null;
    final p = _rot(rig.wr[n], g) + V3(rig.wt[n][0], rig.wt[n][1], rig.wt[n][2]);
    return _toScene(p - rig.pos(hipsBone)) * (targetHeight / height);
  }

  static V3 _rot(List<double> r, V3 v) => V3(r[0] * v.x + r[1] * v.y + r[2] * v.z, r[3] * v.x + r[4] * v.y + r[5] * v.z, r[6] * v.x + r[7] * v.y + r[8] * v.z);

  int bone(String n) => names[n]!;

  /// Direction between two source bones, expressed in the Wolf3D scene frame
  /// (x = left, -y = forward, z = up), independent of the source's own axes.
  V3 dir(String from, String to) => _toScene(rig.pos(bone(to)) - rig.pos(bone(from)));

  V3 _toScene(V3 d) => V3(d.dot(left), -d.dot(fwd), d.dot(up));

  /// How far the hips have moved from the first frame, in target metres.
  V3 hipsOffset(double targetHeight) => _toScene(rig.pos(hipsBone) - hipsStart) * (targetHeight / height);
}

// ---------------------------------------------------------------------------------------
// Static (unskinned) textured model: the bat.
// ---------------------------------------------------------------------------------------

class StaticGroup {
  StaticGroup(this.pos, this.uv, this.nor, this.indices, this.image, this.color);
  final Float32List pos, uv, nor;
  final Uint32List indices;
  final ui.Image? image;
  final ui.Color color;
}

class StaticModel {
  StaticModel(this.groups, this.length);
  final List<StaticGroup> groups;

  /// Authored length of the long axis (model units); positions are normalised so
  /// the handle end is at z = 0 and the toe at z = 1 (x = width, y = thickness).
  final double length;

  static Future<StaticModel> load(String asset) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final bd = ByteData.sublistView(bytes);
    var off = 12;
    Map<String, dynamic>? j;
    Uint8List? bin;
    while (off < bytes.length) {
      final len = bd.getUint32(off, Endian.little);
      final type = bd.getUint32(off + 4, Endian.little);
      off += 8;
      if (type == 0x4E4F534A) j = jsonDecode(utf8.decode(bytes.sublist(off, off + len))) as Map<String, dynamic>;
      if (type == 0x004E4942) bin = Uint8List.sublistView(bytes, off, off + len);
      off += len;
    }
    final json = j!;
    final binary = bin!;

    ByteData view(int bv) {
      final m = (json['bufferViews'] as List)[bv] as Map<String, dynamic>;
      final o = (m['byteOffset'] as int?) ?? 0;
      return ByteData.sublistView(binary, o, o + (m['byteLength'] as int));
    }

    List<num> read(int idx) {
      final a = (json['accessors'] as List)[idx] as Map<String, dynamic>;
      final count = a['count'] as int;
      final comps = const {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]!;
      final type = a['componentType'] as int;
      final size = const {5121: 1, 5123: 2, 5125: 4, 5126: 4}[type]!;
      final bvm = (json['bufferViews'] as List)[a['bufferView'] as int] as Map<String, dynamic>;
      final stride = (bvm['byteStride'] as int?) ?? comps * size;
      final d = view(a['bufferView'] as int);
      final base = (a['byteOffset'] as int?) ?? 0;
      final out = List<num>.filled(count * comps, 0);
      for (var i = 0; i < count; i++) {
        for (var c = 0; c < comps; c++) {
          final p = base + i * stride + c * size;
          out[i * comps + c] = switch (type) {
            5126 => d.getFloat32(p, Endian.little),
            5125 => d.getUint32(p, Endian.little),
            5123 => d.getUint16(p, Endian.little),
            _ => d.getUint8(p),
          };
        }
      }
      return out;
    }

    // Node world transforms (translation, rotation, scale) -> 4x4 column-major.
    final nodes = json['nodes'] as List;
    final parents = List<int>.filled(nodes.length, -1);
    for (var i = 0; i < nodes.length; i++) {
      for (final c in ((nodes[i] as Map)['children'] as List?) ?? const []) {
        parents[c as int] = i;
      }
    }
    final worldCache = <int, List<double>>{};
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

    List<double> world(int i) => worldCache[i] ??= parents[i] < 0 ? local(i) : mul4(world(parents[i]), local(i));

    final images = <int, ui.Image>{};
    Future<ui.Image?> image(int idx) async {
      if (images.containsKey(idx)) return images[idx];
      final im = (json['images'] as List)[idx] as Map<String, dynamic>;
      final b = view(im['bufferView'] as int);
      final codec = await ui.instantiateImageCodec(b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes));
      return images[idx] = (await codec.getNextFrame()).image;
    }

    // Gather all primitives with their world transform applied.
    final raw = <({List<double> pos, List<double> nor, List<double> uv, List<int> idx, ui.Image? img, ui.Color color})>[];
    for (var ni = 0; ni < nodes.length; ni++) {
      final n = nodes[ni] as Map<String, dynamic>;
      if (n['mesh'] == null) continue;
      final w = world(ni);
      final mesh = (json['meshes'] as List)[n['mesh'] as int] as Map<String, dynamic>;
      for (final pr in (mesh['primitives'] as List)) {
        final p = pr as Map<String, dynamic>;
        final attrs = p['attributes'] as Map<String, dynamic>;
        final pos = read(attrs['POSITION'] as int);
        final nor = attrs['NORMAL'] != null ? read(attrs['NORMAL'] as int) : List<num>.filled(pos.length, 0);
        final uv = attrs['TEXCOORD_0'] != null ? read(attrs['TEXCOORD_0'] as int) : List<num>.filled(pos.length ~/ 3 * 2, 0);
        final idx = read(p['indices'] as int).map((e) => e.toInt()).toList();
        final wp = <double>[], wn = <double>[];
        for (var v = 0; v < pos.length ~/ 3; v++) {
          final x = pos[v * 3].toDouble(), y = pos[v * 3 + 1].toDouble(), z = pos[v * 3 + 2].toDouble();
          wp
            ..add(w[0] * x + w[4] * y + w[8] * z + w[12])
            ..add(w[1] * x + w[5] * y + w[9] * z + w[13])
            ..add(w[2] * x + w[6] * y + w[10] * z + w[14]);
          final nx = nor[v * 3].toDouble(), ny = nor[v * 3 + 1].toDouble(), nz = nor[v * 3 + 2].toDouble();
          wn
            ..add(w[0] * nx + w[4] * ny + w[8] * nz)
            ..add(w[1] * nx + w[5] * ny + w[9] * nz)
            ..add(w[2] * nx + w[6] * ny + w[10] * nz);
        }
        final mat = (json['materials'] as List)[p['material'] as int] as Map<String, dynamic>;
        final pbr = (mat['pbrMetallicRoughness'] as Map?) ?? const {};
        final tex = pbr['baseColorTexture'] as Map?;
        ui.Image? img;
        if (tex != null) img = await image(((json['textures'] as List)[tex['index'] as int] as Map)['source'] as int);
        final f = ((pbr['baseColorFactor'] as List?) ?? const [0.8, 0.8, 0.8, 1]).map((e) => (e as num).toDouble()).toList();
        int ch(double v) => (255 * math.pow(v.clamp(0.0, 1.0), 1 / 2.2)).round();
        raw.add((pos: wp, nor: wn, uv: uv.map((e) => e.toDouble()).toList(), idx: idx, img: img, color: ui.Color.fromARGB(255, ch(f[0]), ch(f[1]), ch(f[2]))));
      }
    }

    // Find the long axis, orient handle -> toe, and normalise to local coordinates.
    final mn = [1e18, 1e18, 1e18], mx = [-1e18, -1e18, -1e18];
    for (final r in raw) {
      for (var v = 0; v < r.pos.length ~/ 3; v++) {
        for (var k = 0; k < 3; k++) {
          mn[k] = math.min(mn[k], r.pos[v * 3 + k]);
          mx[k] = math.max(mx[k], r.pos[v * 3 + k]);
        }
      }
    }
    final ext = [for (var k = 0; k < 3; k++) mx[k] - mn[k]];
    final order = [0, 1, 2]..sort((a, b) => ext[b].compareTo(ext[a]));
    final la = order[0], wa = order[1], ta = order[2]; // length, width, thickness axes
    final length = ext[la];
    // The blade end is the wider one.
    double widthNear(bool low) {
      var lo = 1e18, hi = -1e18;
      var any = false;
      for (final r in raw) {
        for (var v = 0; v < r.pos.length ~/ 3; v++) {
          final t = (r.pos[v * 3 + la] - mn[la]) / length;
          if ((low && t < 0.2) || (!low && t > 0.8)) {
            lo = math.min(lo, r.pos[v * 3 + wa]);
            hi = math.max(hi, r.pos[v * 3 + wa]);
            any = true;
          }
        }
      }
      return any ? hi - lo : 0;
    }

    final bladeAtHigh = widthNear(false) >= widthNear(true);
    final groups = <StaticGroup>[];
    for (final r in raw) {
      final n = r.pos.length ~/ 3;
      final p = Float32List(n * 3), nn = Float32List(n * 3);
      for (var v = 0; v < n; v++) {
        var zt = (r.pos[v * 3 + la] - mn[la]) / length;
        if (!bladeAtHigh) zt = 1 - zt;
        // x = width centred on 0, y = thickness centred on 0, z = 0 (handle) .. 1 (toe), in units of length.
        p[v * 3] = (r.pos[v * 3 + wa] - (mn[wa] + mx[wa]) / 2) / length;
        p[v * 3 + 1] = (r.pos[v * 3 + ta] - (mn[ta] + mx[ta]) / 2) / length;
        p[v * 3 + 2] = zt;
        final nz = r.nor[v * 3 + la] * (bladeAtHigh ? 1 : -1);
        nn[v * 3] = r.nor[v * 3 + wa];
        nn[v * 3 + 1] = r.nor[v * 3 + ta];
        nn[v * 3 + 2] = nz;
      }
      groups.add(StaticGroup(p, Float32List.fromList(r.uv), nn, Uint32List.fromList(r.idx), r.img, r.color));
    }
    return StaticModel(groups, length);
  }
}

/// Draws the bat: [grip] is where the hands hold the handle, [along] points
/// handle -> toe, [across] is the blade's width direction, [metres] its length.
void drawStaticModel(
  ui.Canvas canvas,
  Cam3 cam,
  StaticModel model, {
  required V3 grip,
  required V3 along,
  required V3 across,
  required double metres,
  V3 sun = const V3(-0.4, -0.35, 0.85),
}) {
  final a = along.unit;
  final w = (across - a * across.dot(a)).unit;
  final t = a.cross(w);
  final light = sun.unit;
  for (final g in model.groups) {
    final n = g.pos.length ~/ 3;
    final world = List<V3>.filled(n, const V3(0, 0, 0));
    final sp = List<ui.Offset>.filled(n, ui.Offset.zero);
    final sd = List<double>.filled(n, 0);
    final sc = List<int>.filled(n, 0);
    for (var v = 0; v < n; v++) {
      final lx = g.pos[v * 3], ly = g.pos[v * 3 + 1], lz = g.pos[v * 3 + 2];
      final p = grip + w * (lx * metres) + t * (ly * metres) + a * ((lz - 0.0) * metres);
      final nl = w * g.nor[v * 3] + t * g.nor[v * 3 + 1] + a * g.nor[v * 3 + 2];
      final nrm = nl.unit;
      final pr = cam.project(p);
      world[v] = p;
      sp[v] = pr.pt;
      sd[v] = pr.depth;
      final lit = (0.5 + 0.62 * math.max(0.0, nrm.dot(light)) + 0.12 * (nrm.z * 0.5 + 0.5)).clamp(0.0, 1.2);
      final ch = (255 * lit.clamp(0.0, 1.0)).round();
      sc[v] = (0xFF << 24) | (ch << 16) | (ch << 8) | ch;
    }
    final pos = <double>[], tex = <double>[], col = <int>[], depth = <double>[];
    final img = g.image;
    for (var i = 0; i + 2 < g.indices.length; i += 3) {
      final ia = g.indices[i], ib = g.indices[i + 1], ic = g.indices[i + 2];
      if (sd[ia] < 0.01 || sd[ib] < 0.01 || sd[ic] < 0.01) continue;
      depth.add((sd[ia] + sd[ib] + sd[ic]) / 3);
      for (final v in [ia, ib, ic]) {
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
      // Flat colour modulated by the lighting.
      final tinted = [
        for (final cc in c2)
          (0xFF << 24) |
              ((((cc >> 16) & 0xFF) * g.color.r).round().clamp(0, 255) << 16) |
              ((((cc >> 8) & 0xFF) * g.color.g).round().clamp(0, 255) << 8) |
              (((cc & 0xFF) * g.color.b).round().clamp(0, 255))
      ];
      canvas.drawVertices(ui.Vertices.raw(ui.VertexMode.triangles, p2, colors: Int32List.fromList(tinted)), ui.BlendMode.srcOver, paint);
    }
  }
}
