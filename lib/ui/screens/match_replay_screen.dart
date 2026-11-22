import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/replay_engine.dart';
import '../../models/ball_event.dart';
import '../../state/matches_controller.dart';
import '../widgets/common.dart';
import '../widgets/hero_assets.dart';
import '../widgets/replay_field.dart';
import '../widgets/replay3d_view.dart';
import '../widgets/replay_scene.dart';

/// Replays a recorded match ball by ball. Nothing is generated here: every
/// delivery, score and animation comes from the stored scorecard.
class MatchReplayScreen extends StatefulWidget {
  const MatchReplayScreen({super.key, required this.matchId});
  final String matchId;

  @override
  State<MatchReplayScreen> createState() => _MatchReplayScreenState();
}

class _MatchReplayScreenState extends State<MatchReplayScreen>
    with SingleTickerProviderStateMixin {
  static const _speeds = [0.5, 1.0, 2.0, 4.0];

  /// When the outcome shows in the score and in the banner, as a fraction of the clip.
  double _revealFor(ReplayStep s) {
    if (_use3d && _reveal3d != null) return _reveal3d!;
    final b = s.ball;
    if (b.outcome == BallOutcome.wicket) return 0.40;
    if (replayHasUmpireSignal(b)) return 0.5;
    if (replayRunsRun(b) > 0) return 0.85; // once the runs have been completed
    return 0.6;
  }

  double _bannerAt(ReplayStep s) {
    if (_use3d && _reveal3d != null) return _reveal3d!;
    final b = s.ball;
    if (b.outcome == BallOutcome.wicket) return 0.46;
    if (replayHasUmpireSignal(b)) return 0.72;
    if (replayRunsRun(b) > 0) return 0.85;
    return 0.6;
  }

  /// Each clip lasts as long as the action really takes: runs take their real
  /// time, wickets leave room for the walk off.
  Duration _durationFor(ReplayStep s) => Duration(
    milliseconds:
        ((_use3d && _plan3d != null
                    ? _plan3d!.length
                    : replayClipSeconds(s.ball)) *
                1000 /
                _speed)
            .round(),
  );

  /// The rigged 3D replay (three.js in a WebView) is used where a WebView exists;
  /// otherwise the built-in painter draws the replay.
  final bool _canUse3d = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  late bool _use3d = _canUse3d;
  final _r3d = Replay3dController();
  StreamSubscription<Replay3dPlan>? _planSub;
  Replay3dPlan? _plan3d;
  double? _reveal3d;

  void _loadBall3d() {
    if (!_use3d) return;
    _plan3d = null;
    _reveal3d = null;
    _r3d.load(
      replay3dBall(
        _engine.steps[_index],
        seed: _index + 1,
        newBatsman: _newBatsmanAfter(_index),
      ),
      rate: _speed,
    );
  }

  /// On a wicket: the batter who comes in, taken from the next recorded ball of the same innings
  /// (the one of its two batters who was not at the crease for this ball).
  String? _newBatsmanAfter(int i) {
    final s = _engine.steps[i];
    if (!s.ball.isWicket || i + 1 >= _engine.steps.length) return null;
    final n = _engine.steps[i + 1];
    if (n.inningsIndex != s.inningsIndex) return null;
    final here = {s.ball.strikerId, s.ball.nonStrikerId};
    for (final id in [n.ball.strikerId, n.ball.nonStrikerId]) {
      if (!here.contains(id)) return _engine.match.playerName(id);
    }
    return null;
  }

  void _onPlan3d(Replay3dPlan p) {
    if (!mounted || !_use3d) return;
    _plan3d = p;
    _reveal3d = (p.reveal / p.length).clamp(0.2, 0.95);
    _ctl.duration = _durationFor(_engine.steps[_index]);
    if (_ctl.isAnimating) _ctl.forward(from: _ctl.value);
    setState(() {});
  }

  late final ReplayEngine _engine;
  late final AnimationController _ctl;
  var _index = 0;
  var _playing = true;
  var _speed = 1.0;
  var _finished = false;

  @override
  void initState() {
    super.initState();
    final match = context.read<MatchesController>().byId(widget.matchId)!;
    _engine = ReplayEngine(match);
    _ctl =
        AnimationController(
          vsync: this,
          duration: _durationFor(_engine.steps.first),
        )..addStatusListener((s) {
          if (s == AnimationStatus.completed) _onBallDone();
        });
    // The rigged 3D characters load in the background; until then (or if they
    // can't load) the replay uses the built-in procedural players.
    HeroAssets.shared().then((_) {
      if (mounted) setState(() {});
    }, onError: (Object _) {});
    if (!_engine.isEmpty) {
      _ctl.forward();
      _planSub = _r3d.planned.listen(_onPlan3d);
      _loadBall3d();
    }
  }

  @override
  void dispose() {
    _planSub?.cancel();
    _r3d.dispose();
    _ctl.dispose();
    super.dispose();
  }

  int get _last => _engine.steps.length - 1;

  void _onBallDone() {
    if (!mounted || !_playing) return;
    if (_index >= _last) {
      setState(() {
        _playing = false;
        _finished = true;
      });
    } else {
      setState(() => _index++);
      _loadBall3d();
      _ctl.duration = _durationFor(_engine.steps[_index]);
      _ctl.forward(from: 0);
    }
  }

  void _seek(int i, {bool? play}) {
    setState(() {
      _index = i.clamp(0, _last);
      _finished = false;
      if (play != null) _playing = play;
    });
    _loadBall3d();
    _ctl.duration = _durationFor(_engine.steps[_index]);
    _ctl.forward(from: 0);
  }

  void _togglePlay() {
    if (_finished) return _seek(0, play: true);
    setState(() => _playing = !_playing);
    if (_use3d) _playing ? _r3d.play() : _r3d.pause();
    if (_playing && _ctl.isCompleted) {
      _onBallDone();
    } else if (_playing) {
      _ctl.forward();
    } else {
      _ctl.stop();
    }
  }

  void _cycleSpeed() {
    setState(
      () => _speed = _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length],
    );
    _r3d.setRate(_speed);
    _ctl.duration = _durationFor(_engine.steps[_index]);
  }

  @override
  Widget build(BuildContext context) {
    final match = _engine.match;
    return Scaffold(
      appBar: AppBar(
        title: Text('Replay · ${match.teamAShort} vs ${match.teamBShort}'),
        actions: [
          if (_canUse3d)
            TextButton(
              onPressed: () {
                setState(() => _use3d = !_use3d);
                if (_use3d) _seek(_index, play: _playing);
              },
              child: Text(_use3d ? '3D' : '2D'),
            ),
        ],
      ),
      body: _engine.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No balls have been scored yet.'),
              ),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  AnimatedBuilder(
                    animation: _ctl,
                    builder: (_, _) => _scoreCard(context),
                  ),
                  const SizedBox(height: 12),
                  _field(context),
                  const SizedBox(height: 8),
                  _controls(context),
                  if (_finished) _result(context),
                ],
              ),
            ),
    );
  }

  Widget _scoreCard(BuildContext context) {
    final step = _engine.steps[_index];
    final match = _engine.match;
    final cs = Theme.of(context).colorScheme;
    final revealed = _ctl.value >= _revealFor(step);
    final s = revealed ? step.after : step.before;
    final b = step.ball;
    final striker = s.batter(b.strikerId);
    final non = s.batter(b.nonStrikerId);
    final bowler = s.bowler(b.bowlerId);
    final overBalls = s.overs.length >= step.over
        ? s.overs[step.over - 1].balls
        : const [];
    final inn = step.innings;
    final chasing = step.inningsIndex == 1 && match.target != null;
    final fg = TextStyle(color: cs.onPrimaryContainer);

    Widget batLine(String name, String runs, {bool bold = false}) => Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: fg.copyWith(fontWeight: bold ? FontWeight.bold : null),
          ),
        ),
        Text(runs, style: fg.copyWith(fontWeight: FontWeight.bold)),
      ],
    );

    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(match.teamName(inn.battingTeamId), style: fg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  s.score,
                  style: fg.copyWith(fontSize: 38, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                Text(
                  '(${s.oversString}/${match.overs})',
                  style: fg.copyWith(fontSize: 16),
                ),
                const Spacer(),
                if (chasing)
                  Text(
                    'Target ${match.target}',
                    style: fg.copyWith(fontWeight: FontWeight.bold),
                  ),
              ],
            ),
            const Divider(height: 18),
            batLine(
              '${match.playerName(b.strikerId)} *',
              '${striker?.runs ?? 0} (${striker?.balls ?? 0})',
              bold: true,
            ),
            batLine(
              match.playerName(b.nonStrikerId),
              '${non?.runs ?? 0} (${non?.balls ?? 0})',
            ),
            const SizedBox(height: 6),
            batLine(
              match.playerName(b.bowlerId),
              '${bowler?.wickets ?? 0}-${bowler?.runs ?? 0} (${bowler?.overs ?? '0.0'})',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Over ${step.over}',
                  style: fg.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final ball in overBalls) BallBubble(ball, size: 26),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A compact broadcast-style bar on the bottom of the picture.
  Widget _scoreBar(ReplayStep step) {
    final match = _engine.match;
    return AnimatedBuilder(
      animation: _ctl,
      builder: (context, _) {
        final s = _ctl.value >= _revealFor(step) ? step.after : step.before;
        final b = step.ball;
        final striker = s.batter(b.strikerId);
        final non = s.batter(b.nonStrikerId);
        final bowler = s.bowler(b.bowlerId);
        const small = TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        );
        Widget batter(String name, String score) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(name, style: small, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            Text(score, style: small.copyWith(fontWeight: FontWeight.w400)),
          ],
        );
        return Container(
          height: 38,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFD4A81C), Color(0xFF1B2A41), Color(0xFF0B3C8C)],
              stops: [0.0, 0.3, 1.0],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                alignment: Alignment.center,
                color: const Color(0xFFD4A81C),
                child: Text(
                  match.teamShort(step.innings.battingTeamId),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    batter(
                      '${match.playerName(b.strikerId)}*',
                      '${striker?.runs ?? 0} (${striker?.balls ?? 0})',
                    ),
                    batter(
                      match.playerName(b.nonStrikerId),
                      '${non?.runs ?? 0} (${non?.balls ?? 0})',
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                margin: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E8C74),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${match.teamShort(step.innings.battingTeamId)}  ${s.runs} - ${s.wickets}   ${s.oversString}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      batter(
                        match.playerName(b.bowlerId),
                        '${bowler?.wickets ?? 0}-${bowler?.runs ?? 0} (${bowler?.overs ?? '0.0'})',
                      ),
                      Text(
                        'Over ${step.overLabel}',
                        style: small.copyWith(fontWeight: FontWeight.w400),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _field(BuildContext context) {
    final step = _engine.steps[_index];
    final match = _engine.match;
    final b = step.ball;
    final banner = bannerFor(step);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Text(
              '${step.overLabel} · ${match.playerName(b.bowlerId)} to ${match.playerName(b.strikerId)}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            AspectRatio(
              aspectRatio: 1.6,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _use3d
                        ? Replay3dView(controller: _r3d)
                        : ClipRect(
                            child: AnimatedBuilder(
                              animation: _ctl,
                              builder: (_, _) => CustomPaint(
                                painter: ReplayFieldPainter(
                                  step: step,
                                  t: _ctl.value,
                                  strikerName: match.playerName(b.strikerId),
                                  nonStrikerName: match.playerName(
                                    b.nonStrikerId,
                                  ),
                                  bowlerName: match.playerName(b.bowlerId),
                                  fielderName: b.fielderId == null
                                      ? null
                                      : match.playerName(b.fielderId),
                                  assets: HeroAssets.ready,
                                  clipSeconds: replayClipSeconds(b),
                                ),
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _scoreBar(step),
                  ),
                  if (_use3d)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: ValueListenableBuilder<String>(
                        valueListenable: _r3d.mode,
                        builder: (_, mode, _) => mode == 'live'
                            ? const SizedBox.shrink()
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: mode == 'replay'
                                      ? Colors.red.shade700
                                      : Colors.black87,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  mode == 'replay'
                                      ? 'SLOW-MO REPLAY'
                                      : 'UMPIRE',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  if (banner != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 8,
                      child: AnimatedBuilder(
                        animation: _ctl,
                        builder: (_, child) => Opacity(
                          opacity: _ctl.value >= _bannerAt(step) ? 1 : 0,
                          child: child,
                        ),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: banner.color,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  banner.text,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (banner.detail != null)
                                  Text(
                                    banner.detail!,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final match = _engine.match;
    final step = _engine.steps[_index];
    return Column(
      children: [
        Slider(
          value: _index.toDouble(),
          max: _last == 0 ? 1 : _last.toDouble(),
          onChanged: _last == 0 ? null : (v) => _seek(v.round(), play: false),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Restart',
              icon: const Icon(Icons.replay),
              onPressed: () => _seek(0, play: true),
            ),
            IconButton(
              tooltip: 'Previous ball',
              icon: const Icon(Icons.skip_previous),
              onPressed: _index == 0
                  ? null
                  : () => _seek(_index - 1, play: false),
            ),
            IconButton.filled(
              iconSize: 32,
              tooltip: _playing ? 'Pause' : 'Play',
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              onPressed: _togglePlay,
            ),
            IconButton(
              tooltip: 'Next ball',
              icon: const Icon(Icons.skip_next),
              onPressed: _index >= _last
                  ? null
                  : () => _seek(_index + 1, play: false),
            ),
            TextButton(
              onPressed: _cycleSpeed,
              child: Text(
                '${_speed == _speed.roundToDouble() ? _speed.round() : _speed}x',
              ),
            ),
          ],
        ),
        if (match.innings.length > 1)
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (var i = 0; i < match.innings.length; i++)
                ButtonSegment(
                  value: i,
                  label: Text(
                    '${match.teamShort(match.innings[i].battingTeamId)} innings',
                  ),
                ),
            ],
            selected: {step.inningsIndex},
            onSelectionChanged: (v) {
              final i = _engine.firstStepOfInnings(v.first);
              if (i != null) _seek(i, play: true);
            },
          ),
      ],
    );
  }

  Widget _result(BuildContext context) {
    final m = _engine.match;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            m.isLive ? 'End of recorded balls' : m.resultText,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
