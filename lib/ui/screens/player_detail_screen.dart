import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/stats_service.dart';
import '../../state/matches_controller.dart';
import '../../state/membership_controller.dart';
import '../../state/team_membership.dart';
import '../../state/teams_controller.dart';
import '../../data/app_dependencies.dart';
import '../widgets/cloud_actions.dart';
import '../widgets/common.dart';
import '../widgets/pull_refresh.dart';
import '../widgets/avatars.dart';
import 'match_detail_screen.dart';
import 'player_form.dart';
import 'player_teams_tab.dart';

class PlayerDetailScreen extends StatelessWidget {
  const PlayerDetailScreen({super.key, required this.playerId});
  final String playerId;

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<TeamsController>();
    final stats = context.watch<MatchesController>().stats;
    final player = tc.playerById(playerId);
    if (player == null) return const Scaffold(body: SizedBox.shrink());
    final c = stats.player(playerId) ?? PlayerCareer(playerId, player.name);
    final tm = TeamMembership.of(
      player,
      tc,
      context.watch<MembershipController>(),
    );

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(player.name),
          actions: [
            if (context.read<AppDependencies>().api != null)
              IconButton(
                tooltip: 'Cloud stats',
                icon: const Icon(Icons.cloud_outlined),
                onPressed: () =>
                    showPlayerCloudStats(context, player.id, player.name),
              ),
            IconButton(
              tooltip: player.isReadOnly ? 'Managed by the player' : 'Edit',
              icon: Icon(
                player.isReadOnly ? Icons.lock_outline : Icons.edit_outlined,
              ),
              onPressed: () => showPlayerForm(context, player: player),
            ),
            if (!player.isSelf)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(
                    context,
                    'Delete player?',
                    'The player is removed from all teams. Past scorecards keep their name.',
                  )) {
                    await tc.deletePlayer(player);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Batting'),
              Tab(text: 'Bowling'),
              Tab(text: 'Matches'),
              Tab(text: 'Teams'),
            ],
          ),
        ),
        body: PullToRefresh(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    PlayerAvatar(player, radius: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            player.role.label,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(player.battingStyle),
                          if (player.bowlingStyle != 'None')
                            Text(player.bowlingStyle),
                          Text(
                            tm.line,
                            style: TextStyle(
                              color: tm.total == 0
                                  ? null
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          if (tm.breakdown.isNotEmpty) Text(tm.breakdown),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _grid([
                      ('Matches', '${c.matches}'),
                      ('Innings', '${c.innings}'),
                      ('Runs', '${c.runs}'),
                      ('Highest', c.highScoreText),
                      ('Average', c.innings == 0 ? '-' : two(c.average)),
                      ('Strike rate', c.balls == 0 ? '-' : two(c.strikeRate)),
                      ('Not outs', '${c.notOuts}'),
                      ('Balls', '${c.balls}'),
                      ('4s', '${c.fours}'),
                      ('6s', '${c.sixes}'),
                      ('50s', '${c.fifties}'),
                      ('100s', '${c.hundreds}'),
                      ('Ducks', '${c.ducks}'),
                      ('Catches', '${c.catches}'),
                      ('Stumpings', '${c.stumpings}'),
                      ('Run outs', '${c.runOuts}'),
                    ]),
                    _grid([
                      ('Innings', '${c.bowlInnings}'),
                      ('Overs', c.oversBowled),
                      ('Wickets', '${c.wickets}'),
                      ('Runs', '${c.runsConceded}'),
                      ('Best', c.bestBowling),
                      ('Economy', c.ballsBowled == 0 ? '-' : two(c.economy)),
                      ('Average', c.wickets == 0 ? '-' : two(c.bowlingAverage)),
                      ('Maidens', '${c.maidens}'),
                    ]),
                    _records(context, c),
                    PlayerTeamsTab(player: player),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(List<(String, String)> items) {
    return GridView.count(
      crossAxisCount: 3,
      padding: const EdgeInsets.all(16),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.4,
      children: [
        for (final (label, value) in items)
          Card(child: Center(child: StatTile(label, value))),
      ],
    );
  }

  Widget _records(BuildContext context, PlayerCareer c) {
    if (c.records.isEmpty) {
      return const RefreshableEmpty(
        child: EmptyState(
          icon: Icons.history,
          title: 'No match records',
          message: 'Records appear after the player plays a completed match.',
        ),
      );
    }
    final recs = c.records.reversed.toList();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: recs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = recs[i];
        final m = r.match;
        return Card(
          child: ListTile(
            title: Text('${m.teamAShort} vs ${m.teamBShort}'),
            subtitle: Text('${formatDate(m.date)}\n${m.resultText}'),
            isThreeLine: true,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (r.batted)
                  Text(
                    '${r.runs}${r.out ? '' : '*'} (${r.ballsFaced})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                if (r.bowled)
                  Text(
                    '${r.wickets}/${r.runsConceded} (${oversTextOf(r.ballsBowled)})',
                  ),
              ],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MatchDetailScreen(matchId: m.id),
              ),
            ),
          ),
        );
      },
    );
  }

  String oversTextOf(int balls) => '${balls ~/ 6}.${balls % 6}';
}
