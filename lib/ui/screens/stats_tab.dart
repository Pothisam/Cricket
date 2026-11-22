import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/stats_service.dart';
import '../../state/matches_controller.dart';
import '../widgets/common.dart';
import '../widgets/pull_refresh.dart';
import 'player_detail_screen.dart';

class StatsTab extends StatelessWidget {
  const StatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<MatchesController>().stats;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Statistics'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Batting'),
              Tab(text: 'Bowling'),
              Tab(text: 'Teams'),
              Tab(text: 'Records'),
            ],
          ),
        ),
        body: PullToRefresh(
          child: s.totalMatches == 0
              ? const RefreshableEmpty(
                  child: EmptyState(
                    icon: Icons.leaderboard,
                    title: 'No statistics yet',
                    message:
                        'Complete a match to see leaderboards and records.',
                  ),
                )
              : TabBarView(
                  children: [
                    _leaderboard(
                      context,
                      s.topRunScorers(),
                      (p) => '${p.runs}',
                      (p) =>
                          'Inns ${p.innings} · HS ${p.highScoreText} · Avg ${two(p.average)} · SR ${two(p.strikeRate)}',
                    ),
                    _leaderboard(
                      context,
                      s.topWicketTakers(),
                      (p) => '${p.wickets}',
                      (p) =>
                          'Best ${p.bestBowling} · Econ ${two(p.economy)} · Ov ${p.oversBowled}',
                    ),
                    _teams(s),
                    _records(s),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _leaderboard(
    BuildContext context,
    List<PlayerCareer> list,
    String Function(PlayerCareer) value,
    String Function(PlayerCareer) sub,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final p = list[i];
        return ListTile(
          leading: CircleAvatar(child: Text('${i + 1}')),
          title: Text(p.name),
          subtitle: Text(sub(p)),
          trailing: Text(
            value(p),
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlayerDetailScreen(playerId: p.id),
            ),
          ),
        );
      },
    );
  }

  Widget _teams(CricketStats s) {
    final rows = s.standings();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 20,
              columns: const [
                DataColumn(label: Text('Team')),
                DataColumn(label: Text('P'), numeric: true),
                DataColumn(label: Text('W'), numeric: true),
                DataColumn(label: Text('L'), numeric: true),
                DataColumn(label: Text('T'), numeric: true),
                DataColumn(label: Text('Pts'), numeric: true),
                DataColumn(label: Text('High'), numeric: true),
              ],
              rows: [
                for (final t in rows)
                  DataRow(
                    cells: [
                      DataCell(Text(t.name)),
                      DataCell(Text('${t.played}')),
                      DataCell(Text('${t.won}')),
                      DataCell(Text('${t.lost}')),
                      DataCell(Text('${t.tied}')),
                      DataCell(
                        Text(
                          '${t.points}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataCell(Text('${t.highest}')),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _records(CricketStats s) {
    final runs = s.topRunScorers(1);
    final wkts = s.topWicketTakers(1);
    PlayerCareer? bestHs;
    PlayerCareer? mostSixes;
    for (final p in s.players.values) {
      if (bestHs == null || p.highScore > bestHs.highScore) bestHs = p;
      if (mostSixes == null || p.sixes > mostSixes.sixes) mostSixes = p;
    }
    final items = <(String, String, String)>[
      ('Matches played', '${s.totalMatches}', ''),
      ('Total runs scored', '${s.totalRuns}', ''),
      ('Total wickets', '${s.totalWickets}', ''),
      ('Fours / Sixes', '${s.totalFours} / ${s.totalSixes}', ''),
      ('Highest team total', '${s.highestTeamTotal}', s.highestTeamTotalBy),
      if (runs.isNotEmpty) ('Most runs', '${runs.first.runs}', runs.first.name),
      if (bestHs != null && bestHs.highScore > 0)
        ('Highest individual score', bestHs.highScoreText, bestHs.name),
      if (wkts.isNotEmpty)
        ('Most wickets', '${wkts.first.wickets}', wkts.first.name),
      if (mostSixes != null && mostSixes.sixes > 0)
        ('Most sixes', '${mostSixes.sixes}', mostSixes.name),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (label, value, who) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                title: Text(label),
                subtitle: who.isEmpty ? null : Text(who),
                trailing: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
