import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/shot_trajectory.dart';
import '../../models/ball_event.dart';
import 'mesh3d.dart';
import 'scene3d.dart';

/// Result of [pickShot]: `null` = cancelled, `path == null` = skipped.
typedef ShotChoice = ({
  ShotDirection? direction,
  List<Offset>? path,
  ShotLoft? loft,
});

/// Opens the 3D shot planner. Drag on the ground to draw how the ball travelled
/// (curve and distance), then choose how it travelled: along the ground,
/// lofted with a bounce, or fully in the air.
Future<ShotChoice?> pickShot(
  BuildContext context, {
  required String title,
  int runs = 1,
  bool caught = false,
}) {
  return showModalBottomSheet<ShotChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _ShotSheet(title: title, runs: runs, caught: caught),
  );
}

class _ShotSheet extends StatefulWidget {
  const _ShotSheet({
    required this.title,
    required this.runs,
    required this.caught,
  });
  final String title;
  final int runs;
  final bool caught;

  @override
  State<_ShotSheet> createState() => _ShotSheetState();
}

class _ShotSheetState extends State<_ShotSheet> {
  var _raw = <Offset>[];
  late ShotLoft _loft = widget.runs == 6
      ? ShotLoft.aerial
      : widget.caught
      ? ShotLoft.lofted
      : ShotLoft.ground;
  Cam3? _cam;

  ShotTrajectory? get _plan {
    if (_raw.length < 2) return null;
    var t = ShotTrajectory(_raw, _loft);
    if (widget.runs == 4 && !widget.caught) t = t.extendedTo(0.99);
    if (widget.runs == 6) t = t.extendedTo(1.14, minLoft: ShotLoft.aerial);
    return t;
  }

  void _add(Offset px, {bool force = false}) {
    final g = _cam?.groundAt(px);
    if (g == null) return;
    var p = g;
    if (p.distance > 1.25) p = p / p.distance * 1.25;
    if (!force && _raw.isNotEmpty && (p - _raw.last).distance < 0.03) return;
    setState(() => _raw = [..._raw, p]);
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final hint = widget.runs == 6
        ? 'Draw the shot — it carries over the rope.'
        : widget.runs == 4
        ? 'Draw the shot — it runs on to the boundary.'
        : 'Drag from the batter to where the ball went, or tap a spot.';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            Text(hint),
            const SizedBox(height: 10),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final size = Size(box.maxWidth, box.maxHeight);
                      _cam = Cam3(
                        const V3(0, -2.05, 2.15),
                        const V3(0, 0.08, 0),
                        size,
                        39,
                        centerY: 0.5,
                      );
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (d) {
                            setState(() => _raw = [ShotTrajectory.origin]);
                            _add(d.localPosition, force: true);
                          },
                          onPanUpdate: (d) => _add(d.localPosition),
                          onTapUp: (d) {
                            setState(() => _raw = [ShotTrajectory.origin]);
                            _add(d.localPosition, force: true);
                          },
                          child: CustomPaint(
                            size: size,
                            painter: _PlannerPainter(_cam!, plan, _raw),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 54,
              child: CustomPaint(
                size: const Size(double.infinity, 54),
                painter: _ProfilePainter(
                  plan,
                  Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan == null
                        ? 'Nothing drawn yet'
                        : '${plan.direction.label} · ${_loft.label}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: _raw.isEmpty
                      ? null
                      : () => setState(() => _raw = []),
                  child: const Text('Clear'),
                ),
              ],
            ),
            SegmentedButton<ShotLoft>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ShotLoft.ground,
                  label: Text('Ground'),
                  icon: Icon(Icons.horizontal_rule),
                ),
                ButtonSegment(
                  value: ShotLoft.lofted,
                  label: Text('Lofted'),
                  icon: Icon(Icons.trending_up),
                ),
                ButtonSegment(
                  value: ShotLoft.aerial,
                  label: Text('Aerial'),
                  icon: Icon(Icons.rocket_launch_outlined),
                ),
              ],
              selected: {_loft},
              onSelectionChanged: (v) => setState(() => _loft = v.first),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, (
                    direction: null,
                    path: null,
                    loft: null,
                  )),
                  child: const Text('Skip'),
                ),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Save shot'),
                  onPressed: plan == null
                      ? null
                      : () => Navigator.pop(context, (
                          direction: plan.direction,
                          path: plan.points,
                          loft: plan.loft,
                        )),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlannerPainter extends CustomPainter {
  _PlannerPainter(this.cam, this.plan, this.raw);
  final Cam3 cam;
  final ShotTrajectory? plan;
  final List<Offset> raw;

  static const _m = 1 / 65;
  static const _zUnit = 1.3 * _m;

  /// Simple 3D player, drawn larger than life so the whole ground stays readable.
  void _person(
    MeshBuilder mb,
    V3 base,
    Color shirt,
    double yaw, {
    bool bat = false,
  }) {
    const k = 4.2; // exaggeration
    const h = 1.8 * _m * k;
    final fwd = V3(math.sin(yaw), math.cos(yaw), 0);
    final right = V3(math.cos(yaw), -math.sin(yaw), 0);
    const up = V3(0, 0, 1);
    V3 at(double lat, double fw, double z) =>
        base + right * (lat * h) + fwd * (fw * h) + up * (z * h);
    const trouser = Color(0xFFF2F2F2);
    const skin = Color(0xFFD9A47A);
    for (final s in [-1.0, 1.0]) {
      mb.limb(
        at(s * 0.07, 0, 0.5),
        at(s * 0.08, 0, 0.04),
        0.06 * h,
        0.04 * h,
        trouser,
        sides: 5,
      );
      mb.limb(
        at(s * 0.08, 0, 0.04),
        at(s * 0.08, 0.1, 0.0),
        0.04 * h,
        0.03 * h,
        const Color(0xFF222222),
        sides: 4,
      );
    }
    mb.frustum(
      at(0, 0, 0.5),
      at(0, 0, 0.8),
      0.105 * h,
      0.065 * h,
      0.135 * h,
      0.075 * h,
      shirt,
      lat: right,
      sides: 7,
    );
    for (final s in [-1.0, 1.0]) {
      mb.limb(
        at(s * 0.13, 0, 0.78),
        at(s * 0.16, bat ? 0.12 : 0.0, 0.5),
        0.045 * h,
        0.032 * h,
        shirt,
        sides: 5,
      );
    }
    mb.sphere(at(0, 0, 0.93), 0.075 * h, skin, lat: 4, lon: 7);
    mb.sphere(
      at(0, -0.01, 0.95),
      0.082 * h,
      bat ? const Color(0xFF0D3B8A) : const Color(0xFF8E1E1E),
      lat: 4,
      lon: 7,
    );
    if (bat) {
      mb.limb(
        at(0.1, 0.12, 0.5),
        at(0.2, 0.2, 0.05),
        0.03 * h,
        0.05 * h,
        const Color(0xFFEBD8A6),
        sides: 5,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    paintBackdrop(canvas, cam);
    paintGround(canvas, cam);

    final mb = MeshBuilder(cam);
    final labels = <(String, Offset)>[];

    // Stumps at both ends, a little larger than real so they show.
    for (final y in [-10.06 * _m, 10.06 * _m]) {
      for (var i = -1; i <= 1; i++) {
        mb.limb(
          V3(i * 0.114 * _m * 2, y, 0),
          V3(i * 0.114 * _m * 2, y, 0.71 * _m * 2),
          0.03 * _m,
          0.03 * _m,
          const Color(0xFFF5E6B0),
          sides: 5,
        );
      }
    }

    // Keeper, batter and the nine named fielders.
    _person(mb, const V3(0, -23 * _m, 0), const Color(0xFFF2A516), 0);
    _person(
      mb,
      const V3(-0.6 * _m, -9.6 * _m, 0),
      const Color(0xFF1E66D0),
      0.3,
      bat: true,
    );
    for (final d in ShotDirection.values) {
      final h = fielderHome(d);
      final base = V3(h.dx, h.dy, 0);
      final to = Offset.zero - h;
      _person(mb, base, const Color(0xFFD64545), math.atan2(to.dx, to.dy));
      labels.add((
        d.label,
        cam.project(base + const V3(0, 0, 1.8 * _m * 4.2 * 1.12)).pt -
            const Offset(0, 6),
      ));
    }

    final p = plan;
    if (p != null) {
      final e = p.end;
      mb.sphere(
        V3(e.dx, e.dy, p.heightAt(1) * _zUnit + 0.014),
        0.014,
        const Color(0xFFD32F2F),
        lat: 4,
        lon: 8,
      );
    }
    mb.flush(canvas);

    if (p != null) {
      // Track on the ground (exactly under the finger) and the real 3D flight above it.
      final ground = Path();
      final air = Path();
      for (var i = 0; i < p.points.length; i++) {
        final w = p.points[i];
        final s = i / (p.points.length - 1);
        final g = cam.project(V3(w.dx, w.dy, 0.0005)).pt;
        final a = cam
            .project(V3(w.dx, w.dy, p.heightAt(s) * _zUnit + 0.003))
            .pt;
        if (i == 0) {
          ground.moveTo(g.dx, g.dy);
          air.moveTo(a.dx, a.dy);
        } else {
          ground.lineTo(g.dx, g.dy);
          air.lineTo(a.dx, a.dy);
        }
        if (i % 6 == 0 && p.heightAt(s) > 0.5) {
          canvas.drawLine(
            g,
            a,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.3)
              ..strokeWidth = 1,
          );
        }
      }
      canvas.drawPath(
        ground,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.amber.withValues(alpha: 0.9),
      );
      canvas.drawPath(
        air,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      );
      for (final s in p.bounces) {
        final w = p.pointAt(s);
        final g = cam.project(V3(w.dx, w.dy, 0.001));
        canvas.drawOval(
          Rect.fromCenter(
            center: g.pt,
            width: 0.05 * g.scale,
            height: 0.018 * g.scale,
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = Colors.white,
        );
      }
    }

    for (final l in labels) {
      _label(canvas, l.$1, l.$2, Colors.white, 10);
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset center,
    Color color,
    double size,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w600,
          shadows: const [Shadow(blurRadius: 3, color: Colors.black87)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_PlannerPainter old) => true;
}

/// Side view of the ball's flight: height against distance, with bounce marks.
class _ProfilePainter extends CustomPainter {
  _ProfilePainter(this.plan, this.color);
  final ShotTrajectory? plan;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.height - 6;
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..strokeWidth = 1.5,
    );
    final p = plan;
    if (p == null) return;
    final path = Path();
    const n = 80;
    for (var i = 0; i <= n; i++) {
      final s = i / n;
      final x = 8 + s * (size.width - 16);
      final y = base - p.heightAt(s) / 16 * (size.height - 14);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.amber,
    );
    for (final b in p.bounces) {
      canvas.drawCircle(
        Offset(8 + b * (size.width - 16), base),
        3,
        Paint()..color = Colors.white,
      );
    }
    final tp = TextPainter(
      text: TextSpan(
        text: 'bat',
        style: TextStyle(color: color, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(10, 2));
  }

  @override
  bool shouldRepaint(_ProfilePainter old) => true;
}
