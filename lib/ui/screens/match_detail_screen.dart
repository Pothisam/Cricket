import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/innings_summary.dart';
import '../../models/cricket_match.dart';
import '../../state/matches_controller.dart';
import '../../data/app_dependencies.dart';
import '../widgets/cloud_actions.dart';
import '../widgets/common.dart';
import '../widgets/scorecard_view.dart';
import '../widgets/pull_refresh.dart';
import 'match_replay_screen.dart';
import 'scoring_screen.dart';

class MatchDetailScreen extends StatelessWidget {
  const MatchDetailScreen({super.key, required this.matchId});
  final String matchId;

  @override
  Widget build(BuildContext context) {
    final mc = context.watch<MatchesController>();
    final m = mc.byId(matchId);
    if (m == null) return const Scaffold(body: SizedBox.shrink());

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${m.teamAShort} vs ${m.teamBShort}'),
          actions: [
            if (context.read<AppDependencies>().api != null)
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.share_outlined),
                onPressed: () => showShareSheet(context, m.id),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(
                  context,
                  'Delete match?',
                  'This removes the match and its statistics.',
                )) {
                  await mc.delete(m);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Summary'),
              Tab(text: 'Scorecard'),
              Tab(text: 'Overs'),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit_note),
                    label: Text(
                      m.isLive ? 'Continue scoring' : 'Edit scorecard',
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScoringScreen(matchId: m.id),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play match'),
                    onPressed: m.innings.every((i) => i.balls.isEmpty)
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MatchReplayScreen(matchId: m.id),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: PullToRefresh(
          child: TabBarView(
            children: [
              _Summary(match: m),
              ListView(
                children: [
                  if (m.innings.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Match has not started'),
                    ),
                  for (final i in m.innings)
                    ScorecardView(match: m, innings: i),
                ],
              ),
              ListView(
                children: [
                  for (final i in m.innings) OversView(match: m, innings: i),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.match});
  final CricketMatch match;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: cs.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final i in match.innings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            match.teamName(i.battingTeamId),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Builder(
                          builder: (_) {
                            final s = InningsSummary(match, i);
                            return Text(
                              '${s.score}  (${s.oversString})',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                const Divider(),
                Text(
                  match.isLive ? 'Match in progress' : match.resultText,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SectionHeader('MATCH INFO'),
        Card(
          child: Column(
            children: [
              _info('Toss', match.tossText),
              _info('Format', '${match.overs} overs'),
              _info('Date', formatDate(match.date)),
              if (match.venue.isNotEmpty) _info('Venue', match.venue),
            ],
          ),
        ),
        for (final i in match.innings) ...[
          SectionHeader(
            'TOP PERFORMERS · ${match.teamShort(i.battingTeamId)} INNINGS',
          ),
          _performers(context, InningsSummary(match, i)),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _info(String k, String v) => ListTile(
    dense: true,
    title: Text(k),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Text(v, textAlign: TextAlign.right),
    ),
  );

  Widget _performers(BuildContext context, InningsSummary s) {
    final bats = [...s.batters]..sort((a, b) => b.runs.compareTo(a.runs));
    final bowls = [...s.bowlers]
      ..sort((a, b) {
        final c = b.wickets.compareTo(a.wickets);
        return c != 0 ? c : a.runs.compareTo(b.runs);
      });
    return Card(
      child: Column(
        children: [
          for (final b in bats.take(2))
            ListTile(
              dense: true,
              leading: const Icon(Icons.sports_cricket, size: 20),
              title: Text(b.name),
              trailing: Text(
                '${b.runs}${b.out ? '' : '*'} (${b.balls})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          for (final b in bowls.take(2))
            ListTile(
              dense: true,
              leading: const Icon(Icons.sports_baseball, size: 20),
              title: Text(b.name),
              trailing: Text(
                '${b.wickets}/${b.runs} (${b.overs})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
