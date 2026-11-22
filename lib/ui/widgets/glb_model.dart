import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'scene3d.dart';

// Loader, skeleton, animation sampler and software skinner for rigged glTF
// (.glb) characters. Rendering goes through `drawVertices`, so it works on
// Android and the web with no 3D engine.
//
// Scene space of the Wolf3D characters: Z up, facing -Y, character's left = +X.

enum KitLook { batting, fielding, keeper, umpire }

/// How one character differs from the shared base model.
class HeroStyle {
  const HeroStyle({
    this.kit = KitLook.fielding,
    this.model = 0,
    this.skin = (1.0, 1.0, 1.0),
    this.hair = 0,
  });
  final KitLook kit;

  /// Which loaded character model to use.
  final int model;

  /// Multiplies skin colour (r, g, b); (1,1,1) leaves it as authored.
  final (double, double, double) skin;

  /// Hair colour: 0 black, 1 dark brown, 2 brown, 3 grey.
  final int hair;
}

// ---------------------------------------------------------------------------------------
// Small 3x3 matrix helpers (row-major, List<double> of 9)
// ---------------------------------------------------------------------------------------

List<double> quatToMat(double x, double y, double z, double w) => [
  1 - 2 * (y * y + z * z),
  2 * (x * y - z * w),
  2 * (x * z + y * w),
  2 * (x * y + z * w),
  1 - 2 * (x * x + z * z),
  2 * (y * z - x * w),
  2 * (x * z - y * w),
  2 * (y * z + x * w),
  1 - 2 * (x * x + y * y),
];

List<double> _mul(List<double> a, List<double> b) {
  final o = List<double>.filled(9, 0);
  for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 3; j++) {
      o[i * 3 + j] =
          a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j];
    }
  }
  return o;
}

List<double> _transpose(List<double> a) => [
  a[0],
  a[3],
  a[6],
  a[1],
  a[4],
  a[7],
  a[2],
  a[5],
  a[8],
];

V3 _mulV(List<double> a, V3 v) => V3(
  a[0] * v.x + a[1] * v.y + a[2] * v.z,
  a[3] * v.x + a[4] * v.y + a[5] * v.z,
  a[6] * v.x + a[7] * v.y + a[8] * v.z,
);

List<double> _axisAngle(V3 axis, double angle) {
  final a = axis.unit;
  final c = math.cos(angle), s = math.sin(angle), t = 1 - c;
  return [
    t * a.x * a.x + c,
    t * a.x * a.y - s * a.z,
    t * a.x * a.z + s * a.y,
    t * a.x * a.y + s * a.z,
    t * a.y * a.y + c,
    t * a.y * a.z - s * a.x,
    t * a.x * a.z - s * a.y,
    t * a.y * a.z + s * a.x,
    t * a.z * a.z + c,
  ];
}

// ---------------------------------------------------------------------------------------
// Model data
// ---------------------------------------------------------------------------------------

class GlbPrim {
  GlbPrim(
    this.name,
    this.matIndex,
    this.pos,
    this.nor,
    this.uv,
    this.joints,
    this.weights,
    this.indices,
  ) {
    _buildLods();
  }

  final String name;
  final int matIndex;
  final Float32List pos, nor, uv, weights;
  final Uint16List joints;
  final Uint32List indices;
  int get vertexCount => pos.length ~/ 3;

  // Atlas routing (filled in when the atlas is built).
  int cell = 0;
  int? swatch;
  bool kitTop = false,
      kitBottom = false,
      isHair = false,
      tintable = false,
      hidden = false;

  /// Index / vertex lists for detail levels 0 (full), 1 and 2 (merged vertices).
  late final List<Uint32List> lodIndices;
  late final List<Int32List> lodVerts;

  void _buildLods() {
    final n = vertexCount;
    lodIndices = [indices];
    lodVerts = [Int32List.fromList(List<int>.generate(n, (i) => i))];
    for (final size in const [0.035, 0.07]) {
      final rep = List<int>.filled(n, -1);
      final seen = <String, int>{};
      for (var v = 0; v < n; v++) {
        final key =
            '${(pos[v * 3] / size).floor()},${(pos[v * 3 + 1] / size).floor()},${(pos[v * 3 + 2] / size).floor()}';
        rep[v] = seen.putIfAbsent(key, () => v);
      }
      final tris = <int>[];
      final used = <int>{};
      for (var i = 0; i + 2 < indices.length; i += 3) {
        final a = rep[indices[i]],
            b = rep[indices[i + 1]],
            c = rep[indices[i + 2]];
        if (a == b || b == c || a == c) continue;
        tris
          ..add(a)
          ..add(b)
          ..add(c);
        used
          ..add(a)
          ..add(b)
          ..add(c);
      }
      lodIndices.add(Uint32List.fromList(tris));
      lodVerts.add(Int32List.fromList(used.toList()));
    }
  }
}

class GlbNode {
  GlbNode(this.name, this.parent, this.children, this.t, this.r);
  final String name;
  final int parent;
  final List<int> children;
  final List<double> t; // translation
  final List<double> r; // rotation 3x3 row-major
}

class AnimTrack {
  AnimTrack(this.node, this.path, this.times, this.values);
  final int node;
  final String path; // translation | rotation
  final Float32List times, values;
}

class GlbAnim {
  GlbAnim(this.name, this.duration, this.tracks);
  final String name;
  final double duration;
  final List<AnimTrack> tracks;
}

class GlbModel {
  GlbModel._(
    this.nodes,
    this.jointNodes,
    this.ibm,
    this.prims,
    this.atlas,
    this.byName,
    this.roots,
    this.anims,
    this.swatchHairBase,
    this.batting,
  );

  /// Cell size of the atlas, in pixels.
  static const cell = 512;
  static const cols = 4;

  final List<GlbNode> nodes;
  final List<int> jointNodes;
  final List<Float32List> ibm; // 16 floats per joint, column-major
  final List<GlbPrim> prims;
  final ui.Image? atlas;
  final Map<String, int> byName;
  final List<int> roots;
  final List<GlbAnim> anims;

  /// First swatch slot used for hair colour variants.
  final int swatchHairBase;

  /// Per-clip batting metadata (shot direction, footwork, contact time and point),
  /// from the file's scene extras, when the model has any.
  final Map<String, dynamic>? batting;

  GlbAnim? animByName(String name) {
    for (final a in anims) {
      if (a.name == name) return a;
    }
    return null;
  }

  int bone(String prefix) {
    for (final e in byName.entries) {
      if (e.key.startsWith(prefix)) return e.value;
    }
    throw StateError('Bone $prefix not found');
  }

  /// Loads a character. With [atlas] false only the skeleton, meshes and
  /// animations are read (no textures), e.g. for a motion source.
  ///
  /// [neutralizeRoot] removes the file's Y-up export rotation on the root nodes, so
  /// the skeleton uses the same Z-up, facing -Y, left = +X frame as the other models.
  static Future<GlbModel> load(
    String asset, {
    bool atlas = true,
    bool neutralizeRoot = false,
  }) async {
    final g = await readGlb(asset);
    final j = g.json;
    final acc = AccessorReader(j, g.bin);

    // ---- nodes ---------------------------------------------------------------------
    final rawNodes = j['nodes'] as List;
    final parents = List<int>.filled(rawNodes.length, -1);
    for (var i = 0; i < rawNodes.length; i++) {
      for (final c in ((rawNodes[i] as Map)['children'] as List?) ?? const []) {
        parents[c as int] = i;
      }
    }
    final nodes = <GlbNode>[];
    final byName = <String, int>{};
    for (var i = 0; i < rawNodes.length; i++) {
      final n = rawNodes[i] as Map<String, dynamic>;
      final t = ((n['translation'] as List?) ?? const [0, 0, 0])
          .map((e) => (e as num).toDouble())
          .toList();
      final q = ((n['rotation'] as List?) ?? const [0, 0, 0, 1])
          .map((e) => (e as num).toDouble())
          .toList();
      final name = (n['name'] as String?) ?? 'node$i';
      nodes.add(
        GlbNode(
          name,
          parents[i],
          ((n['children'] as List?) ?? const []).cast<int>(),
          t,
          quatToMat(q[0], q[1], q[2], q[3]),
        ),
      );
      byName.putIfAbsent(name, () => i);
    }
    final roots = [
      for (var i = 0; i < nodes.length; i++)
        if (nodes[i].parent < 0) i,
    ];
    if (neutralizeRoot) {
      // Root chain rotations (-90, +90, -90 about X) multiply to a single Y-up conversion;
      // dropping the first one leaves the skeleton in its own Z-up frame.
      for (final r in roots) {
        nodes[r].r.setAll(0, const [1, 0, 0, 0, 1, 0, 0, 0, 1]);
      }
    }

    // ---- skin -----------------------------------------------------------------------
    final jointNodes = <int>[];
    final ibm = <Float32List>[];
    if ((j['skins'] as List?)?.isNotEmpty ?? false) {
      final skin = (j['skins'] as List).first as Map<String, dynamic>;
      jointNodes.addAll((skin['joints'] as List).cast<int>());
      final ibmAcc = acc.read(skin['inverseBindMatrices'] as int);
      for (var k = 0; k < jointNodes.length; k++) {
        ibm.add(
          Float32List.fromList([
            for (var c = 0; c < 16; c++) ibmAcc[k * 16 + c].toDouble(),
          ]),
        );
      }
    }

    // ---- meshes ---------------------------------------------------------------------
    final prims = <GlbPrim>[];
    if (atlas) {
      for (final m in (j['meshes'] as List)) {
        for (final pr in ((m as Map<String, dynamic>)['primitives'] as List)) {
          final p = pr as Map<String, dynamic>;
          final attrs = p['attributes'] as Map<String, dynamic>;
          if (attrs['JOINTS_0'] == null) continue;
          final mi = p['material'] as int;
          final mat = (j['materials'] as List)[mi] as Map<String, dynamic>;
          Float32List f32(List<num> l) =>
              Float32List.fromList(l.map((e) => e.toDouble()).toList());
          prims.add(
            GlbPrim(
              (mat['name'] as String?) ?? 'mat$mi',
              mi,
              f32(acc.read(attrs['POSITION'] as int)),
              f32(acc.read(attrs['NORMAL'] as int)),
              f32(acc.read(attrs['TEXCOORD_0'] as int)),
              Uint16List.fromList(
                acc
                    .read(attrs['JOINTS_0'] as int)
                    .map((e) => e.toInt())
                    .toList(),
              ),
              f32(acc.read(attrs['WEIGHTS_0'] as int)),
              Uint32List.fromList(
                acc.read(p['indices'] as int).map((e) => e.toInt()).toList(),
              ),
            ),
          );
        }
      }
    }

    // ---- animations -----------------------------------------------------------------
    final anims = <GlbAnim>[];
    for (final a in ((j['animations'] as List?) ?? const [])) {
      final am = a as Map<String, dynamic>;
      final samplers = am['samplers'] as List;
      final tracks = <AnimTrack>[];
      var dur = 0.0;
      for (final c in (am['channels'] as List)) {
        final cm = c as Map<String, dynamic>;
        final target = cm['target'] as Map<String, dynamic>;
        if (target['node'] == null) continue;
        final path = target['path'] as String;
        if (path == 'scale') continue;
        final s = samplers[cm['sampler'] as int] as Map<String, dynamic>;
        final times = Float32List.fromList(
          acc.read(s['input'] as int).map((e) => e.toDouble()).toList(),
        );
        final values = Float32List.fromList(
          acc.read(s['output'] as int).map((e) => e.toDouble()).toList(),
        );
        if (times.isNotEmpty) dur = math.max(dur, times.last.toDouble());
        tracks.add(AnimTrack(target['node'] as int, path, times, values));
      }
      anims.add(GlbAnim((am['name'] as String?) ?? 'anim', dur, tracks));
    }

    // ---- atlas ------------------------------------------------------------------------
    ui.Image? atlasImage;
    var hairBase = 0;
    if (atlas) {
      final built = await _buildAtlas(j, g.bin, prims);
      atlasImage = built.image;
      hairBase = built.hairBase;
    }
    final scenes = j['scenes'] as List?;
    final extras = (scenes != null && scenes.isNotEmpty)
        ? (scenes.first as Map)['extras'] as Map?
        : null;
    final batting = extras?['batting'] == null
        ? null
        : Map<String, dynamic>.from(extras!['batting'] as Map);
    return GlbModel._(
      nodes,
      jointNodes,
      ibm,
      prims,
      atlasImage,
      byName,
      roots,
      anims,
      hairBase,
      batting,
    );
  }

  static Future<({Map<String, dynamic> json, Uint8List bin})> readGlb(
    String asset,
  ) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final bd = ByteData.sublistView(bytes);
    var off = 12;
    Map<String, dynamic>? json;
    Uint8List? bin;
    while (off < bytes.length) {
      final len = bd.getUint32(off, Endian.little);
      final type = bd.getUint32(off + 4, Endian.little);
      off += 8;
      if (type == 0x4E4F534A) {
        json = jsonDecode(
          utf8.decode(bytes.sublist(off, off + len)),
        ) as Map<String, dynamic>;
      } else if (type == 0x004E4942) {
        bin = Uint8List.sublistView(bytes, off, off + len);
      }
      off += len;
    }
    return (json: json!, bin: bin!);
  }

  static Future<({ui.Image image, int hairBase})> _buildAtlas(
    Map<String, dynamic> j,
    Uint8List bin,
    List<GlbPrim> prims,
  ) async {
    final acc = AccessorReader(j, bin);
    Future<ui.Image> decode(int imageIdx) async {
      final img = (j['images'] as List)[imageIdx] as Map<String, dynamic>;
      final b = acc.view(img['bufferView'] as int);
      final codec = await ui.instantiateImageCodec(
        b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes),
      );
      return (await codec.getNextFrame()).image;
    }

    final materials = j['materials'] as List;
    // Plan the cells: one per textured material, four kit variants for the shirt and
    // trousers, and one shared cell of flat-colour swatches.
    final cells = <_CellSpec>[];
    final swatchColors = <ui.Color>[];
    final matCell = <int, _CellSpec>{};
    final matSwatch = <int, int>{};
    int srgb(double v) => (255 * math.pow(v.clamp(0.0, 1.0), 1 / 2.2)).round();
    for (var mi = 0; mi < materials.length; mi++) {
      final m = materials[mi] as Map<String, dynamic>;
      final name = (m['name'] as String?) ?? '';
      final pbr = (m['pbrMetallicRoughness'] as Map?) ?? const {};
      final tex = pbr['baseColorTexture'] as Map?;
      if (name.contains('Glasses')) continue;
      if (tex != null) {
        final image =
            ((j['textures'] as List)[tex['index'] as int] as Map)['source']
                as int;
        final kit = name.contains('Outfit_Top')
            ? 1
            : (name.contains('Outfit_Bottom') ? 2 : 0);
        final spec = _CellSpec(image, cells.length, kit: kit);
        cells.add(spec);
        if (kit != 0) {
          for (var i = 1; i < 4; i++) {
            cells.add(_CellSpec(image, cells.length, kit: kit));
          }
        }
        matCell[mi] = spec;
      } else {
        final f =
            ((pbr['baseColorFactor'] as List?) ?? const [0.8, 0.8, 0.8, 1])
                .map((e) => (e as num).toDouble())
                .toList();
        matSwatch[mi] = swatchColors.length;
        swatchColors.add(
          ui.Color.fromARGB(255, srgb(f[0]), srgb(f[1]), srgb(f[2])),
        );
      }
    }
    // Hair colour variants live after the authored swatches.
    final hairBase = swatchColors.length;
    swatchColors.addAll(const [
      ui.Color(0xFF0B0A09),
      ui.Color(0xFF2B1A12),
      ui.Color(0xFF4A2F1C),
      ui.Color(0xFF8A8A8A),
    ]);
    final swatchCell = cells.length;
    cells.add(_CellSpec(-1, swatchCell));

    final rows = (cells.length / cols).ceil();
    final recorder = ui.PictureRecorder();
    final c = ui.Canvas(recorder);
    final size = cell.toDouble();
    ui.Rect cellRect(int idx) =>
        ui.Rect.fromLTWH((idx % cols) * size, (idx ~/ cols) * size, size, size);

    final decoded = <int, ui.Image>{};
    Future<ui.Image> img(int i) async => decoded[i] ??= await decode(i);

    final looks = {
      KitLook.batting: const ColorFilterSpec.identity(),
      KitLook.fielding: ColorFilterSpec.hue(
        150,
        saturation: 1.05,
        brightness: 0.95,
      ),
      KitLook.keeper: ColorFilterSpec.hue(
        185,
        saturation: 1.1,
        brightness: 1.15,
      ),
      KitLook.umpire: ColorFilterSpec.hue(
        0,
        saturation: 0.08,
        brightness: 0.42,
      ),
    };
    var kitTopIdx = 0, kitBottomIdx = 0;
    for (final spec in cells) {
      if (spec.image < 0) continue;
      var source = await img(spec.image);
      ColorFilterSpec? filter;
      if (spec.kit == 1) {
        if (kitTopIdx == 0) {
          source = await paintOutBranding(source);
          decoded[spec.image] = source;
        }
        filter = looks[KitLook.values[kitTopIdx % 4]];
        kitTopIdx++;
      } else if (spec.kit == 2) {
        filter = looks[KitLook.values[kitBottomIdx % 4]];
        kitBottomIdx++;
      }
      final paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
      if (filter != null)
        paint.colorFilter = ui.ColorFilter.matrix(filter.matrix);
      c.drawImageRect(
        source,
        ui.Rect.fromLTWH(
          0,
          0,
          source.width.toDouble(),
          source.height.toDouble(),
        ),
        cellRect(spec.index),
        paint,
      );
    }
    // Swatches: a 4x4 grid inside one cell.
    final sr = cellRect(swatchCell);
    final slot = size / 4;
    final sp = ui.Paint();
    for (var i = 0; i < swatchColors.length && i < 16; i++) {
      sp.color = swatchColors[i];
      c.drawRect(
        ui.Rect.fromLTWH(
          sr.left + (i % 4) * slot,
          sr.top + (i ~/ 4) * slot,
          slot,
          slot,
        ),
        sp,
      );
    }
    final image = await recorder.endRecording().toImage(
      cols * cell,
      rows * cell,
    );

    // Route every primitive to its atlas cell.
    for (final p in prims) {
      final name = p.name;
      p.hidden = name.contains('Glasses');
      p.isHair = name.contains('Hair');
      p.tintable = name.contains('Skin') || name.contains('Body');
      final spec = matCell[p.matIndex];
      if (spec != null) {
        p.cell = spec.index;
        p.kitTop = spec.kit == 1;
        p.kitBottom = spec.kit == 2;
        p.swatch = null;
      } else {
        p.cell = swatchCell;
        p.swatch = matSwatch[p.matIndex] ?? 0;
      }
    }
    return (image: image, hairBase: hairBase);
  }

  /// Paints over the printed team name, logo and number with the jersey colour.
  static Future<ui.Image> paintOutBranding(ui.Image src) async {
    final bytes = (await src.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    ui.Color sample(double fx, double fy) {
      final x = (fx * src.width).round().clamp(0, src.width - 1);
      final y = (fy * src.height).round().clamp(0, src.height - 1);
      final i = (y * src.width + x) * 4;
      return ui.Color.fromARGB(
        255,
        bytes.getUint8(i),
        bytes.getUint8(i + 1),
        bytes.getUint8(i + 2),
      );
    }

    final rec = ui.PictureRecorder();
    final cv = ui.Canvas(rec);
    cv.drawImage(src, ui.Offset.zero, ui.Paint());
    final w = src.width.toDouble(), h = src.height.toDouble();
    // The embedded jersey texture is stored flipped vertically: the lettering
    // and logo are in the lower half, the number on the right-hand (back) panel.
    final front = sample(0.08, 0.62), back = sample(0.8, 0.45);
    ui.Paint fill(ui.Color c) => ui.Paint()..color = c;
    cv.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(0.14 * w, 0.585 * h, 0.33 * w, 0.15 * h),
        const ui.Radius.circular(10),
      ),
      fill(front),
    );
    cv.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(0.13 * w, 0.715 * h, 0.12 * w, 0.13 * h),
        const ui.Radius.circular(10),
      ),
      fill(front),
    );
    cv.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(0.65 * w, 0.5 * h, 0.33 * w, 0.37 * h),
        const ui.Radius.circular(10),
      ),
      fill(back),
    );
    return rec.endRecording().toImage(src.width, src.height);
  }
}

class _CellSpec {
  _CellSpec(this.image, this.index, {this.kit = 0});
  final int image;
  final int index;
  final int kit; // 0 none, 1 shirt, 2 trousers
}

/// Reads glTF accessors into flat lists.
class AccessorReader {
  AccessorReader(this.j, this.bin);
  final Map<String, dynamic> j;
  final Uint8List bin;

  ByteData view(int bufferView) {
    final bv = (j['bufferViews'] as List)[bufferView] as Map<String, dynamic>;
    final o = (bv['byteOffset'] as int?) ?? 0;
    return ByteData.sublistView(bin, o, o + (bv['byteLength'] as int));
  }

  List<num> read(int idx) {
    final a = (j['accessors'] as List)[idx] as Map<String, dynamic>;
    final count = a['count'] as int;
    final comps = const {
      'SCALAR': 1,
      'VEC2': 2,
      'VEC3': 3,
      'VEC4': 4,
      'MAT4': 16,
    }[a['type']]!;
    final type = a['componentType'] as int;
    final size = const {
      5120: 1,
      5121: 1,
      5122: 2,
      5123: 2,
      5125: 4,
      5126: 4,
    }[type]!;
    final bv =
        (j['bufferViews'] as List)[a['bufferView'] as int]
            as Map<String, dynamic>;
    final stride = (bv['byteStride'] as int?) ?? comps * size;
    final d = view(a['bufferView'] as int);
    final base = (a['byteOffset'] as int?) ?? 0;
    final normalized = (a['normalized'] as bool?) ?? false;
    final out = List<num>.filled(count * comps, 0);
    for (var i = 0; i < count; i++) {
      for (var c = 0; c < comps; c++) {
        final p = base + i * stride + c * size;
        num v;
        switch (type) {
          case 5126:
            v = d.getFloat32(p, Endian.little);
          case 5125:
            v = d.getUint32(p, Endian.little);
          case 5123:
            v = d.getUint16(p, Endian.little);
            if (normalized) v = v / 65535;
          case 5122:
            v = d.getInt16(p, Endian.little);
          case 5121:
            v = d.getUint8(p);
            if (normalized) v = v / 255;
          default:
            v = d.getInt8(p);
        }
        out[i * comps + c] = v;
      }
    }
    return out;
  }
}

/// A colour matrix (hue rotation / saturation / brightness).
class ColorFilterSpec {
  const ColorFilterSpec._(this.matrix);
  const ColorFilterSpec.identity()
    : matrix = const [
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ];

  factory ColorFilterSpec.hue(
    double degrees, {
    double saturation = 1,
    double brightness = 1,
  }) {
    final a = degrees * math.pi / 180;
    final cs = math.cos(a), sn = math.sin(a);
    final hue = [
      0.213 + cs * 0.787 - sn * 0.213,
      0.715 - cs * 0.715 - sn * 0.715,
      0.072 - cs * 0.072 + sn * 0.928,
      0.213 - cs * 0.213 + sn * 0.143,
      0.715 + cs * 0.285 + sn * 0.140,
      0.072 - cs * 0.072 - sn * 0.283,
      0.213 - cs * 0.213 - sn * 0.787,
      0.715 - cs * 0.715 + sn * 0.715,
      0.072 + cs * 0.928 + sn * 0.072,
    ];
    final s = saturation;
    final sat = [
      0.213 * (1 - s) + s,
      0.715 * (1 - s),
      0.072 * (1 - s),
      0.213 * (1 - s),
      0.715 * (1 - s) + s,
      0.072 * (1 - s),
      0.213 * (1 - s),
      0.715 * (1 - s),
      0.072 * (1 - s) + s,
    ];
    final m = _mul(sat, hue);
    return ColorFilterSpec._([
      m[0] * brightness,
      m[1] * brightness,
      m[2] * brightness,
      0,
      0,
      m[3] * brightness,
      m[4] * brightness,
      m[5] * brightness,
      0,
      0,
      m[6] * brightness,
      m[7] * brightness,
      m[8] * brightness,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  final List<double> matrix;
}

// ---------------------------------------------------------------------------------------
// Skeleton instance, animation sampling and skinning
// ---------------------------------------------------------------------------------------

class Rig {
  Rig(this.m)
    : lr = [for (final n in m.nodes) List<double>.of(n.r)],
      lt = [for (final n in m.nodes) List<double>.of(n.t)],
      wr = List.generate(m.nodes.length, (_) => List<double>.filled(9, 0)),
      wt = List.generate(m.nodes.length, (_) => List<double>.filled(3, 0)) {
    updateAll();
  }

  final GlbModel m;
  final List<List<double>> lr, lt, wr, wt;

  void _update(int i) {
    final n = m.nodes[i];
    if (n.parent < 0) {
      wr[i] = List<double>.of(lr[i]);
      wt[i] = List<double>.of(lt[i]);
    } else {
      final pr = wr[n.parent], pt = wt[n.parent];
      wr[i] = _mul(pr, lr[i]);
      final t = lt[i];
      wt[i] = [
        pr[0] * t[0] + pr[1] * t[1] + pr[2] * t[2] + pt[0],
        pr[3] * t[0] + pr[4] * t[1] + pr[5] * t[2] + pt[1],
        pr[6] * t[0] + pr[7] * t[1] + pr[8] * t[2] + pt[2],
      ];
    }
    for (final c in n.children) {
      _update(c);
    }
  }

  void updateAll() {
    for (final r in m.roots) {
      _update(r);
    }
  }

  void updateFrom(int i) => _update(i);

  V3 pos(int node) => V3(wt[node][0], wt[node][1], wt[node][2]);

  /// Samples an animation clip at [time] seconds (looping) into the local transforms.
  void applyAnim(GlbAnim anim, double time) {
    final t = anim.duration <= 0 ? 0.0 : time % anim.duration;
    for (final tr in anim.tracks) {
      final times = tr.times;
      final n = times.length;
      if (n == 0) continue;
      var lo = 0, hi = n - 1;
      if (t <= times[0]) {
        hi = 0;
      } else if (t >= times[n - 1]) {
        lo = n - 1;
      } else {
        while (hi - lo > 1) {
          final mid = (lo + hi) >> 1;
          if (times[mid] <= t) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
      }
      final span = times[hi] - times[lo];
      final f = (hi == lo || span <= 0) ? 0.0 : (t - times[lo]) / span;
      if (tr.path == 'translation') {
        lt[tr.node] = [
          tr.values[lo * 3] + (tr.values[hi * 3] - tr.values[lo * 3]) * f,
          tr.values[lo * 3 + 1] +
              (tr.values[hi * 3 + 1] - tr.values[lo * 3 + 1]) * f,
          tr.values[lo * 3 + 2] +
              (tr.values[hi * 3 + 2] - tr.values[lo * 3 + 2]) * f,
        ];
      } else {
        // Quaternion nlerp (short path).
        final ax = tr.values[lo * 4].toDouble(),
            ay = tr.values[lo * 4 + 1].toDouble(),
            az = tr.values[lo * 4 + 2].toDouble(),
            aw = tr.values[lo * 4 + 3].toDouble();
        var bx = tr.values[hi * 4].toDouble(),
            by = tr.values[hi * 4 + 1].toDouble(),
            bz = tr.values[hi * 4 + 2].toDouble(),
            bw = tr.values[hi * 4 + 3].toDouble();
        if (ax * bx + ay * by + az * bz + aw * bw < 0) {
          bx = -bx;
          by = -by;
          bz = -bz;
          bw = -bw;
        }
        var x = ax + (bx - ax) * f,
            y = ay + (by - ay) * f,
            z = az + (bz - az) * f,
            w = aw + (bw - aw) * f;
        final l = math.sqrt(x * x + y * y + z * z + w * w);
        if (l > 0) {
          x /= l;
          y /= l;
          z /= l;
          w /= l;
        }
        lr[tr.node] = quatToMat(x, y, z, w);
      }
    }
    updateAll();
  }

  /// Blends this pose toward [other] by [w] (0 = this pose, 1 = [other]): local
  /// rotations are mixed and re-orthonormalised, translations interpolated.
  void blendToward(Rig other, double w) {
    for (var i = 0; i < lr.length; i++) {
      final a = lr[i], b = other.lr[i];
      lr[i] = _orthonormal([
        for (var k = 0; k < 9; k++) a[k] + (b[k] - a[k]) * w,
      ]);
      for (var k = 0; k < 3; k++) {
        lt[i][k] = lt[i][k] + (other.lt[i][k] - lt[i][k]) * w;
      }
    }
    updateAll();
  }

  static List<double> _orthonormal(List<double> m) {
    var r0 = V3(m[0], m[1], m[2]).unit;
    var r1 = V3(m[3], m[4], m[5]);
    r1 = (r1 - r0 * r1.dot(r0)).unit;
    final r2 = r0.cross(r1);
    return [r0.x, r0.y, r0.z, r1.x, r1.y, r1.z, r2.x, r2.y, r2.z];
  }

  /// Rotates [bone] (and everything below it) by the world rotation [r].
  void rotateWorld(int bone, List<double> r) {
    final p = m.nodes[bone].parent;
    final newWorld = _mul(r, wr[bone]);
    lr[bone] = p < 0 ? newWorld : _mul(_transpose(wr[p]), newWorld);
    _update(bone);
  }

  /// Turns [bone] so the direction to [child] points along [desired] (scene space).
  void aim(int bone, int child, V3 desired, {double amount = 1}) {
    final cur = (pos(child) - pos(bone)).unit;
    final des = desired.unit;
    final d = (cur.dot(des)).clamp(-1.0, 1.0);
    final angle = math.acos(d);
    if (angle < 1e-4) return;
    var axis = cur.cross(des);
    if (axis.dot(axis) < 1e-12) axis = const V3(0, 0, 1);
    rotateWorld(bone, _axisAngle(axis, angle * amount));
  }

  /// Rotates [bone] about the vertical axis through itself.
  void yaw(int bone, double angle) =>
      rotateWorld(bone, _axisAngle(const V3(0, 0, 1), angle));

  /// Skin matrices (rotation 3x3 + translation) for every joint.
  List<({List<double> r, List<double> t})> skinMatrices() {
    final out = <({List<double> r, List<double> t})>[];
    for (var k = 0; k < m.jointNodes.length; k++) {
      final node = m.jointNodes[k];
      final ib = m.ibm[k];
      final rib = [
        ib[0],
        ib[4],
        ib[8],
        ib[1],
        ib[5],
        ib[9],
        ib[2],
        ib[6],
        ib[10],
      ];
      final tib = V3(ib[12].toDouble(), ib[13].toDouble(), ib[14].toDouble());
      final r = _mul(wr[node], rib.map((e) => e.toDouble()).toList());
      final tv = _mulV(wr[node], tib);
      out.add((
        r: r,
        t: [tv.x + wt[node][0], tv.y + wt[node][1], tv.z + wt[node][2]],
      ));
    }
    return out;
  }
}

/// Maps the model's scene space into the game world.
class HeroTransform {
  HeroTransform({
    required this.base,
    required this.right,
    required this.fwd,
    required this.scale,
  });
  final V3 base, right, fwd;

  /// World units per model metre.
  final double scale;
  static const up = V3(0, 0, 1);

  /// Model scene space (x = left, -y = forward, z = up) to game world.
  V3 toWorld(V3 s) =>
      base + right * (-s.x * scale) + fwd * (-s.y * scale) + up * (s.z * scale);
  V3 dirToWorld(V3 s) => right * (-s.x) + fwd * (-s.y) + up * s.z;

  /// Game world to model scene space.
  V3 toScene(V3 w) {
    final d = w - base;
    return V3(-d.dot(right) / scale, -d.dot(fwd) / scale, d.dot(up) / scale);
  }

  V3 dirToScene(V3 d) => V3(-d.dot(right), -d.dot(fwd), d.dot(up));
}

/// Skins and draws the model (depth sorted, one draw call). [lod] 0..2 picks
/// the detail level; distant players use merged, cheaper geometry.
void drawSkinnedModel(
  ui.Canvas canvas,
  Cam3 cam,
  GlbModel model,
  Rig rig,
  HeroTransform tf,
  HeroStyle style, {
  int lod = 0,
  bool hair = true,
  V3 sun = const V3(-0.4, -0.35, 0.85),
}) {
  final atlas = model.atlas;
  if (atlas == null) return;
  final skin = rig.skinMatrices();
  final lightDir = sun.unit;
  final posList = <double>[];
  final texList = <double>[];
  final colList = <int>[];
  final depths = <double>[];
  final cellPx = GlbModel.cell.toDouble();
  final tint = style.skin;

  for (final p in model.prims) {
    if (p.hidden) continue;
    if (p.isHair && !hair) continue;
    final cellIdx = (p.kitTop || p.kitBottom)
        ? p.cell + style.kit.index
        : p.cell;
    final origin = ui.Offset(
      (cellIdx % GlbModel.cols) * cellPx,
      (cellIdx ~/ GlbModel.cols) * cellPx,
    );
    int? swatch = p.swatch;
    if (p.isHair) swatch = model.swatchHairBase + style.hair.clamp(0, 3);
    final verts = p.lodVerts[lod];
    final n = p.vertexCount;
    final wp = <int, V3>{};
    final sp = List<ui.Offset>.filled(n, ui.Offset.zero);
    final sd = List<double>.filled(n, 0);
    final sc = List<int>.filled(n, 0);
    final tr = p.tintable ? tint.$1 : 1.0,
        tg = p.tintable ? tint.$2 : 1.0,
        tb = p.tintable ? tint.$3 : 1.0;
    for (final v in verts) {
      final px = p.pos[v * 3], py = p.pos[v * 3 + 1], pz = p.pos[v * 3 + 2];
      final nx = p.nor[v * 3], ny = p.nor[v * 3 + 1], nz = p.nor[v * 3 + 2];
      double ox = 0, oy = 0, oz = 0, qx = 0, qy = 0, qz = 0;
      for (var k = 0; k < 4; k++) {
        final w = p.weights[v * 4 + k];
        if (w <= 0) continue;
        final s = skin[p.joints[v * 4 + k]];
        final r = s.r, t = s.t;
        ox += w * (r[0] * px + r[1] * py + r[2] * pz + t[0]);
        oy += w * (r[3] * px + r[4] * py + r[5] * pz + t[1]);
        oz += w * (r[6] * px + r[7] * py + r[8] * pz + t[2]);
        qx += w * (r[0] * nx + r[1] * ny + r[2] * nz);
        qy += w * (r[3] * nx + r[4] * ny + r[5] * nz);
        qz += w * (r[6] * nx + r[7] * ny + r[8] * nz);
      }
      final world = tf.toWorld(V3(ox, oy, oz));
      final normal = tf.dirToWorld(V3(qx, qy, qz)).unit;
      final pr = cam.project(world);
      wp[v] = world;
      sp[v] = pr.pt;
      sd[v] = pr.depth;
      final lit =
          (0.44 +
                  0.66 * math.max(0.0, normal.dot(lightDir)) +
                  0.14 * (normal.z * 0.5 + 0.5))
              .clamp(0.0, 1.25);
      int ch(double t2) => (255 * (lit * t2).clamp(0.0, 1.0)).round();
      sc[v] = (0xFF << 24) | (ch(tr) << 16) | (ch(tg) << 8) | ch(tb);
    }
    final idx = p.lodIndices[lod];
    for (var i = 0; i + 2 < idx.length; i += 3) {
      final a = idx[i], b = idx[i + 1], c = idx[i + 2];
      if (sd[a] < 0.01 || sd[b] < 0.01 || sd[c] < 0.01) continue;
      final face = (wp[b]! - wp[a]!).cross(wp[c]! - wp[a]!);
      final centre = (wp[a]! + wp[b]! + wp[c]!) * (1 / 3);
      if (face.dot(cam.eye - centre) <= 0) continue; // back face
      depths.add((sd[a] + sd[b] + sd[c]) / 3);
      for (final v in [a, b, c]) {
        posList
          ..add(sp[v].dx)
          ..add(sp[v].dy);
        if (swatch != null) {
          final slot = cellPx / 4;
          texList
            ..add(origin.dx + (swatch % 4) * slot + slot / 2)
            ..add(origin.dy + (swatch ~/ 4) * slot + slot / 2);
        } else {
          texList
            ..add(origin.dx + p.uv[v * 2] * cellPx)
            ..add(origin.dy + p.uv[v * 2 + 1] * cellPx);
        }
        colList.add(sc[v]);
      }
    }
  }

  final tris = depths.length;
  if (tris == 0) return;
  final order = List<int>.generate(tris, (i) => i)
    ..sort((x, y) => depths[y].compareTo(depths[x]));
  final pos = Float32List(tris * 6), tex = Float32List(tris * 6);
  final col = Int32List(tris * 3);
  for (var o = 0; o < tris; o++) {
    final t = order[o];
    for (var k = 0; k < 6; k++) {
      pos[o * 6 + k] = posList[t * 6 + k];
      tex[o * 6 + k] = texList[t * 6 + k];
    }
    for (var k = 0; k < 3; k++) {
      col[o * 3 + k] = colList[t * 3 + k];
    }
  }
  final vertices = ui.Vertices.raw(
    ui.VertexMode.triangles,
    pos,
    textureCoordinates: tex,
    colors: col,
  );
  final paint = ui.Paint()
    ..shader = ui.ImageShader(
      atlas,
      ui.TileMode.clamp,
      ui.TileMode.clamp,
      Float64List.fromList(const [
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
      ]),
      filterQuality: ui.FilterQuality.medium,
    );
  canvas.drawVertices(vertices, ui.BlendMode.modulate, paint);
}
