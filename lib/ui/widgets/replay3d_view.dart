import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../domain/replay_engine.dart';
import '../../models/ball_event.dart';

/// Serves `assets/replay3d/` on the loopback interface, so the WebView can load
/// the page, the three.js modules and the GLB models over http (file:// blocks
/// ES modules and fetch in the Android WebView).
class Replay3dServer {
  Replay3dServer._(this._server);

  final HttpServer _server;
  static Future<Replay3dServer>? _shared;

  static Future<Replay3dServer> shared() => _shared ??= _start();

  static Future<Replay3dServer> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final s = Replay3dServer._(server);
    server.listen(s._handle);
    return s;
  }

  Uri get index => Uri.parse('http://127.0.0.1:${_server.port}/index.html');

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'glb': 'model/gltf-binary',
  };

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path == '/' ? 'index.html' : req.uri.path.substring(1);
    try {
      if (path.contains('..')) {
        throw const FormatException('bad path');
      }
      final data = await rootBundle.load('assets/replay3d/$path');
      req.response.headers.contentType = ContentType.parse(
        _types[path.split('.').last] ?? 'application/octet-stream',
      );
      req.response.headers.set('Cache-Control', 'max-age=3600');
      req.response.add(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (_) {
      req.response.statusCode = HttpStatus.notFound;
    }
    await req.response.close();
  }
}

/// What the 3D replay needs to know about one recorded ball (see `toEvent` in
/// `assets/replay3d/index.html`).
///
/// [newBatsman] is the name of the batter who comes in if this ball is a wicket (from the next recorded ball).
Map<String, dynamic> replay3dBall(
  ReplayStep step, {
  int seed = 1,
  String? newBatsman,
}) {
  final b = step.ball;
  final out = <String, dynamic>{'seed': seed, 'bowling': 'fast'};
  if (newBatsman != null && b.isWicket) out['entry'] = {'name': newBatsman};

  // The page uses -90 = point (off side), +90 = square leg; the scorecard uses the opposite sign.
  double? angle;
  final path = b.shotPath;
  if (path != null && path.isNotEmpty) {
    final end = path.last;
    if (end.distance > 0.05) {
      angle = -math.atan2(end.dx, end.dy) * 180 / math.pi;
    }
  }
  angle ??= b.shotDirection == null ? null : -b.shotDirection!.angle;
  if (angle != null) out['angle'] = angle;
  if (b.loft != null) out['loft'] = b.loft!.name;

  switch (b.outcome) {
    case BallOutcome.wide:
      out['noShot'] = true;
      out['result'] = 'dot';
      out['wide'] = true;
    case BallOutcome.bye:
    case BallOutcome.legBye:
      out['noShot'] = true;
      out['result'] = 'dot';
    case BallOutcome.dot:
      out['result'] = 'dot';
    case BallOutcome.runs:
    case BallOutcome.noBall:
      out['result'] = 'runs';
      out['runs'] = b.runs.clamp(0, 3);
    case BallOutcome.four:
      out['result'] = 'runs';
      out['runs'] = 4;
      out['boundary'] = 4;
    case BallOutcome.six:
      out['result'] = 'runs';
      out['runs'] = 6;
      out['boundary'] = 6;
    case BallOutcome.wicket:
      switch (b.wicket!) {
        case WicketType.caught:
          out['result'] = (angle != null && angle.abs() >= 130)
              ? 'caught-behind'
              : 'caught';
        case WicketType.stumped:
          out['result'] = 'stumped';
          out['noShot'] = true;
        case WicketType.runOut:
          out['result'] = 'runout';
          out['runs'] = b.runs.clamp(0, 2);
          out['outBatsman'] = b.outPlayerId == b.nonStrikerId
              ? 'nonStriker'
              : 'striker';
        case WicketType.lbw:
          out['result'] = 'lbw';
        case WicketType.bowled:
        case WicketType.hitWicket:
          out['result'] = 'bowled';
      }
  }
  return out;
}

/// Controls the 3D replay page. Create one, hand it to [Replay3dView], then call [load].
class Replay3dController {
  WebViewController? _web;
  var _ready = false;
  Map<String, dynamic>? _pending;
  var _rate = 1.0;
  var _autoplay = true;
  final _planned = StreamController<Replay3dPlan>.broadcast();

  /// `live`, `replay` (slow-motion wicket replay) or `umpire` (decision close-up).
  final mode = ValueNotifier<String>('live');

  /// Fires when a ball has been planned and starts playing; carries its length.
  Stream<Replay3dPlan> get planned => _planned.stream;

  void _attach(WebViewController web) => _web = web;

  void _onMessage(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    switch (m['type']) {
      case 'ready':
        _ready = true;
        final p = _pending;
        if (p != null) load(p, autoplay: _autoplay, rate: _rate);
      case 'planned':
        mode.value = 'live';
        _planned.add(
          Replay3dPlan(
            (m['start'] as num).toDouble(),
            (m['duration'] as num).toDouble(),
            (m['reveal'] as num).toDouble(),
          ),
        );
      case 'mode':
        mode.value = m['mode'] as String;
    }
  }

  void _run(String js) => _web?.runJavaScript(js);

  void load(
    Map<String, dynamic> ball, {
    bool autoplay = true,
    double rate = 1,
  }) {
    _pending = ball;
    _autoplay = autoplay;
    _rate = rate;
    if (_ready) {
      _run(
        'Replay.load(${jsonEncode(ball)}, ${jsonEncode({'autoplay': autoplay, 'rate': rate})})',
      );
    }
  }

  void play() => _run('Replay.play()');
  void pause() => _run('Replay.pause()');
  void setRate(double r) {
    _rate = r;
    _run('Replay.setRate($r)');
  }

  void setCamera(String name) => _run('Replay.setCamera(${jsonEncode(name)})');

  void dispose() {
    _planned.close();
    mode.dispose();
  }
}

class Replay3dPlan {
  const Replay3dPlan(this.start, this.duration, this.reveal);

  /// The replay lasts from [start] to [duration] seconds (live action, slow-motion replays and umpire close-ups
  /// included); the outcome becomes clear at [reveal].
  final double start, duration, reveal;
  double get length => duration - start;
}

class Replay3dView extends StatefulWidget {
  const Replay3dView({super.key, required this.controller});
  final Replay3dController controller;

  @override
  State<Replay3dView> createState() => _Replay3dViewState();
}

class _Replay3dViewState extends State<Replay3dView> {
  WebViewController? _web;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final server = await Replay3dServer.shared();
      final web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF8FB8D8))
        ..addJavaScriptChannel(
          'Replay3D',
          onMessageReceived: (m) => widget.controller._onMessage(m.message),
        );
      widget.controller._attach(web);
      await web.loadRequest(server.index);
      if (mounted) setState(() => _web = web);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(
          '3D replay unavailable\n$_error',
          textAlign: TextAlign.center,
        ),
      );
    }
    final web = _web;
    if (web == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return WebViewWidget(controller: web);
  }
}
