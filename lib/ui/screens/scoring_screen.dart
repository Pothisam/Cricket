import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/innings_summary.dart';
import '../../models/ball_event.dart';
import '../../data/app_dependencies.dart';
import '../../state/matches_controller.dart';
import '../../state/scoring_controller.dart';
import '../widgets/common.dart';
import '../widgets/shot_direction_picker.dart';
import 'match_detail_screen.dart';

class ScoringScreen extends StatelessWidget {
  const ScoringScreen({super.key, required this.matchId});
  final String matchId;

  @override
  Widget build(BuildContext context) {
    final mc = context.read<MatchesController>();
    final match = mc.byId(matchId);
    if (match == null) return const Scaffold(body: SizedBox.shrink());
    return ChangeNotifierProvider(
      create: (_) => ScoringController(
        match,
        mc,
        live: context.read<AppDependencies>().live,
      ),
      child: const _ScoringBody(),
    );
  }
}

class _ScoringBody extends StatefulWidget {
  const _ScoringBody();

  @override
  State<_ScoringBody> createState() => _ScoringBodyState();
}

class _ScoringBodyState extends State<_ScoringBody> {
  bool _prompting = false;

  Future<String?> _pick(
    String title,
    List<String> ids,
    String Function(String) nameOf,
  ) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                children: [
                  for (final id in ids)
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(nameOf(id)),
                      onTap: () => Navigator.pop(ctx, id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _maybePrompt(ScoringController c) async {
    if (_prompting || !mounted || !c.match.isLive || c.innings.completed)
      return;
    if (c.needsBatter) {
      _prompting = true;
      await _chooseBatters(c);
      _prompting = false;
    } else if (c.needsBowler) {
      _prompting = true;
      await _chooseBowler(c);
      _prompting = false;
    }
  }

  Future<void> _chooseBatters(ScoringController c) async {
    final m = c.match;
    final avail = c.availableBatters;
    if (avail.isEmpty) return;
    final inn = c.innings;
    if (inn.strikerId == null && inn.nonStrikerId == null) {
      final striker = await _pick('Select striker', avail, m.playerName);
      if (striker == null || !mounted) return;
      final rest = avail.where((id) => id != striker).toList();
      final non = await _pick('Select non-striker', rest, m.playerName);
      if (non == null) return;
      await c.setOpeners(striker, non);
    } else {
      final id = await _pick('New batter', avail, m.playerName);
      if (id != null) await c.setNewBatter(id);
    }
  }

  Future<void> _chooseBowler(ScoringController c) async {
    final id = await _pick(
      'Select bowler',
      c.availableBowlers,
      c.match.playerName,
    );
    if (id != null) await c.setBowler(id);
  }

  Future<int?> _pickNumber(String title, String subtitle, List<int> values) {
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(ctx).textTheme.titleLarge),
              Text(subtitle),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final v in values)
                    SizedBox(
                      width: 64,
                      height: 52,
                      child: FilledButton.tonal(
                        onPressed: () => Navigator.pop(ctx, v),
                        child: Text('$v', style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Records bat runs, asking where the ball went when the batter hit it.
  Future<void> _scoreRuns(ScoringController c, int runs) async {
    ShotChoice? shot;
    if (runs > 0) {
      shot = await pickShot(
        context,
        title: '$runs run${runs == 1 ? '' : 's'} — draw the shot',
        runs: runs,
      );
      if (shot == null) return;
    }
    await c.recordBall(
      runs: runs,
      shotDirection: shot?.direction,
      shotPath: shot?.path,
      loft: shot?.loft,
    );
  }

  Future<void> _extra(ScoringController c, ExtraType type) async {
    switch (type) {
      case ExtraType.wide:
        final n = await _pickNumber('Wide', 'Additional runs run', [
          0,
          1,
          2,
          3,
          4,
        ]);
        if (n != null) await c.recordBall(extra: type, extraRuns: 1 + n);
      case ExtraType.noBall:
        final n = await _pickNumber('No ball', 'Runs off the bat', [
          0,
          1,
          2,
          3,
          4,
          6,
        ]);
        if (n == null || !mounted) return;
        ShotChoice? shot;
        if (n > 0) {
          shot = await pickShot(
            context,
            title: 'No ball + $n — draw the shot',
            runs: n,
          );
          if (shot == null) return;
        }
        await c.recordBall(
          extra: type,
          extraRuns: 1,
          runs: n,
          shotDirection: shot?.direction,
          shotPath: shot?.path,
          loft: shot?.loft,
        );
      case ExtraType.bye:
      case ExtraType.legBye:
        final n = await _pickNumber(
          type == ExtraType.bye ? 'Byes' : 'Leg byes',
          'Runs run',
          [1, 2, 3, 4],
        );
        if (n != null) await c.recordBall(extra: type, extraRuns: n);
      case ExtraType.none:
    }
  }

  Future<void> _wicket(ScoringController c) async {
    final m = c.match;
    final inn = c.innings;
    final fielders = m.squad(inn.bowlingTeamId);
    var type = WicketType.bowled;
    var outId = inn.strikerId!;
    String? fielder;
    var runs = 0;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final needsFielder =
              type == WicketType.caught ||
              type == WicketType.stumped ||
              type == WicketType.runOut;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Wicket', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in WicketType.values)
                      ChoiceChip(
                        label: Text(t.label),
                        selected: type == t,
                        onSelected: (_) => setState(() {
                          type = t;
                          if (t != WicketType.runOut) outId = inn.strikerId!;
                          fielder = null;
                        }),
                      ),
                  ],
                ),
                if (type == WicketType.runOut) ...[
                  const SizedBox(height: 16),
                  const Text('Who is out?'),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: inn.strikerId!,
                        label: Text(m.playerName(inn.strikerId)),
                      ),
                      ButtonSegment(
                        value: inn.nonStrikerId!,
                        label: Text(m.playerName(inn.nonStrikerId)),
                      ),
                    ],
                    selected: {outId},
                    onSelectionChanged: (s) => setState(() => outId = s.first),
                  ),
                  const SizedBox(height: 16),
                  const Text('Runs completed'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final r in [0, 1, 2, 3])
                        ChoiceChip(
                          label: Text('$r'),
                          selected: runs == r,
                          onSelected: (_) => setState(() => runs = r),
                        ),
                    ],
                  ),
                ],
                if (needsFielder) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: fielder,
                    decoration: InputDecoration(
                      labelText: type == WicketType.stumped
                          ? 'Wicket-keeper'
                          : 'Fielder',
                    ),
                    items: [
                      for (final id in fielders)
                        DropdownMenuItem(
                          value: id,
                          child: Text(m.playerName(id)),
                        ),
                    ],
                    onChanged: (v) => setState(() => fielder = v),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Confirm wicket'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (ok == true) {
      ShotChoice? shot;
      if (type == WicketType.caught && mounted) {
        shot = await pickShot(
          context,
          title: 'Caught — draw the shot',
          caught: true,
        );
        if (shot == null) return;
      }
      await c.recordBall(
        runs: runs,
        wicket: type,
        outPlayerId: outId,
        fielderId: fielder,
        shotDirection: shot?.direction,
        shotPath: shot?.path,
        loft: shot?.loft,
      );
    }
  }

  void _openScorecard(ScoringController c) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: c.match.id)),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ScoringController>();
    final m = c.match;
    final inn = c.innings;
    final s = c.summary;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrompt(c));

    return Scaffold(
      appBar: AppBar(
        title: Text('${m.teamAShort} vs ${m.teamBShort}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: 'Scorecard',
            onPressed: () => _openScorecard(c),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'swap':
                  await c.swapStrike();
                case 'endInnings':
                  if (await confirm(
                    context,
                    'End innings?',
                    'The innings will be closed with the current score.',
                    action: 'End',
                  )) {
                    await c.endInningsEarly();
                  }
                case 'endMatch':
                  if (await confirm(
                    context,
                    'End match?',
                    'The match will be finished using the current position.',
                    action: 'End',
                  )) {
                    await c.endMatch();
                  }
              }
            },
            itemBuilder: (_) => [
              if (c.canScore)
                const PopupMenuItem(value: 'swap', child: Text('Swap batters')),
              if (m.isLive && !inn.completed)
                const PopupMenuItem(
                  value: 'endInnings',
                  child: Text('End innings'),
                ),
              if (m.isLive)
                const PopupMenuItem(
                  value: 'endMatch',
                  child: Text('End match'),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _header(context, c, s),
          const SizedBox(height: 12),
          _crease(context, c, s),
          const SizedBox(height: 12),
          _overStrip(context, s),
          const SizedBox(height: 16),
          _actions(context, c),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, ScoringController c, InningsSummary s) {
    final m = c.match;
    final cs = Theme.of(context).colorScheme;
    final t = m.target;
    String? chase;
    if (t != null && c.isSecondInnings) {
      final need = t - s.runs;
      final left = m.overs * 6 - s.legalBalls;
      if (need > 0 && !c.innings.completed) {
        final rrr = left == 0 ? 0.0 : need * 6 / left;
        chase = 'Need $need from $left balls · RRR ${two(rrr)}';
      }
    }
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              m.teamName(c.innings.battingTeamId),
              style: TextStyle(color: cs.onPrimaryContainer),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  s.score,
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '(${s.oversString}/${m.overs})',
                  style: TextStyle(fontSize: 18, color: cs.onPrimaryContainer),
                ),
                const Spacer(),
                Text(
                  'CRR ${two(s.runRate)}',
                  style: TextStyle(color: cs.onPrimaryContainer),
                ),
              ],
            ),
            if (t != null && c.isSecondInnings)
              Text('Target $t', style: TextStyle(color: cs.onPrimaryContainer)),
            if (chase != null)
              Text(
                chase,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimaryContainer,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _crease(BuildContext context, ScoringController c, InningsSummary s) {
    final inn = c.innings;
    final m = c.match;
    final head = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

    TableRow batRow(String? id, bool striker) {
      final b = s.batter(id);
      return TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              id == null ? '—' : '${m.playerName(id)}${striker ? ' *' : ''}',
              style: TextStyle(
                fontWeight: striker ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            '${b?.runs ?? 0}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text('${b?.balls ?? 0}', textAlign: TextAlign.right),
          Text('${b?.fours ?? 0}', textAlign: TextAlign.right),
          Text('${b?.sixes ?? 0}', textAlign: TextAlign.right),
          Text(
            b == null || b.balls == 0 ? '-' : two(b.strikeRate),
            textAlign: TextAlign.right,
          ),
        ],
      );
    }

    final bw = s.bowler(inn.bowlerId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Table(
              columnWidths: const {
                1: FixedColumnWidth(36),
                2: FixedColumnWidth(36),
                3: FixedColumnWidth(28),
                4: FixedColumnWidth(28),
                5: FixedColumnWidth(52),
              },
              children: [
                TableRow(
                  children: [
                    Text('Batter', style: head),
                    Text('R', textAlign: TextAlign.right, style: head),
                    Text('B', textAlign: TextAlign.right, style: head),
                    Text('4s', textAlign: TextAlign.right, style: head),
                    Text('6s', textAlign: TextAlign.right, style: head),
                    Text('SR', textAlign: TextAlign.right, style: head),
                  ],
                ),
                batRow(inn.strikerId, true),
                batRow(inn.nonStrikerId, false),
              ],
            ),
            const Divider(height: 20),
            Table(
              columnWidths: const {
                1: FixedColumnWidth(40),
                2: FixedColumnWidth(28),
                3: FixedColumnWidth(36),
                4: FixedColumnWidth(28),
                5: FixedColumnWidth(52),
              },
              children: [
                TableRow(
                  children: [
                    Text('Bowler', style: head),
                    Text('O', textAlign: TextAlign.right, style: head),
                    Text('M', textAlign: TextAlign.right, style: head),
                    Text('R', textAlign: TextAlign.right, style: head),
                    Text('W', textAlign: TextAlign.right, style: head),
                    Text('Econ', textAlign: TextAlign.right, style: head),
                  ],
                ),
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        inn.bowlerId == null ? '—' : m.playerName(inn.bowlerId),
                      ),
                    ),
                    Text(bw?.overs ?? '0.0', textAlign: TextAlign.right),
                    Text('${bw?.maidens ?? 0}', textAlign: TextAlign.right),
                    Text('${bw?.runs ?? 0}', textAlign: TextAlign.right),
                    Text(
                      '${bw?.wickets ?? 0}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      bw == null || bw.balls == 0 ? '-' : two(bw.economy),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _overStrip(BuildContext context, InningsSummary s) {
    final balls = s.currentOverBalls;
    return Row(
      children: [
        Text('This over', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: 12),
        Expanded(
          child: balls.isEmpty
              ? const Text('—')
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final b in balls) BallBubble(b)],
                ),
        ),
      ],
    );
  }

  Widget _actions(BuildContext context, ScoringController c) {
    final m = c.match;
    final inn = c.innings;

    if (!m.isLive) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                m.resultText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: c.undo,
                      child: const Text('Undo last ball'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _openScorecard(c),
                      child: const Text('Scorecard'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (c.inningsBreak) {
      final first = m.innings.first;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Innings break',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${m.teamName(first.battingTeamId)} scored ${first.runs}/${first.wickets}. '
                '${m.teamName(first.bowlingTeamId)} need ${first.runs + 1} to win.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: c.undo,
                      child: const Text('Undo last ball'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: c.startSecondInnings,
                      child: const Text('Start 2nd innings'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (c.needsBatter || c.needsBowler) {
      final batter = c.needsBatter;
      return Column(
        children: [
          FilledButton.icon(
            onPressed: () => batter ? _chooseBatters(c) : _chooseBowler(c),
            icon: const Icon(Icons.person_add_alt_1),
            label: Text(
              batter
                  ? (inn.strikerId == null && inn.nonStrikerId == null
                        ? 'Select openers'
                        : 'Select new batter')
                  : 'Select bowler',
            ),
          ),
          if (inn.balls.isNotEmpty)
            TextButton.icon(
              onPressed: c.undo,
              icon: const Icon(Icons.undo),
              label: const Text('Undo last ball'),
            ),
        ],
      );
    }

    Widget runBtn(
      String label,
      VoidCallback onTap, {
      Color? color,
      Color? fg,
    }) => SizedBox(
      height: 56,
      child: FilledButton.tonal(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: fg,
          padding: EdgeInsets.zero,
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );

    Widget extraBtn(String label, ExtraType t) => SizedBox(
      height: 48,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
        onPressed: () => _extra(c, t),
        child: Text(label),
      ),
    );

    return Column(
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.0,
          children: [
            for (final r in [0, 1, 2, 3]) runBtn('$r', () => _scoreRuns(c, r)),
            runBtn(
              '4',
              () => _scoreRuns(c, 4),
              color: Colors.blue.shade600,
              fg: Colors.white,
            ),
            runBtn(
              '6',
              () => _scoreRuns(c, 6),
              color: Colors.purple.shade600,
              fg: Colors.white,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: extraBtn('Wide', ExtraType.wide)),
            const SizedBox(width: 8),
            Expanded(child: extraBtn('No ball', ExtraType.noBall)),
            const SizedBox(width: 8),
            Expanded(child: extraBtn('Bye', ExtraType.bye)),
            const SizedBox(width: 8),
            Expanded(child: extraBtn('Leg bye', ExtraType.legBye)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                  ),
                  onPressed: () => _wicket(c),
                  icon: const Icon(Icons.close),
                  label: const Text('WICKET'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: inn.balls.isEmpty ? null : c.undo,
                icon: const Icon(Icons.undo),
                label: const Text('Undo'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: c.swapStrike,
                child: const Icon(Icons.swap_horiz),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
