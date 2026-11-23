import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_dependencies.dart';
import '../../state/matches_controller.dart';
import '../../state/teams_controller.dart';
import '../widgets/common.dart';
import '../widgets/pull_refresh.dart';
import '../widgets/avatars.dart';
import 'player_detail_screen.dart';
import 'player_form.dart';
import 'player_search_screen.dart';

class PlayersTab extends StatefulWidget {
  const PlayersTab({super.key});

  @override
  State<PlayersTab> createState() => _PlayersTabState();
}

class _PlayersTabState extends State<PlayersTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<TeamsController>();
    final stats = context.watch<MatchesController>().stats;
    final players =
        tc.players.where((p) {
          final q = _query.toLowerCase();
          return p.name.toLowerCase().contains(q) ||
              (p.email ?? '').toLowerCase().contains(q);
        }).toList()..sort((a, b) {
          if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1; // me first
          return a.name.compareTo(b.name);
        });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Players'),
        actions: [
          if (context.read<AppDependencies>().api != null)
            IconButton(
              tooltip: 'Find players',
              icon: const Icon(Icons.person_search),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlayerSearchScreen()),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => showPlayerForm(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Add player'),
      ),
      body: PullToRefresh(
        child: tc.players.isEmpty
            ? const RefreshableEmpty(
                child: EmptyState(
                  icon: Icons.person,
                  title: 'No players yet',
                  message: 'Add players here or from a team page.',
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: SearchBar(
                      hintText: 'Search by name or e-mail',
                      leading: const Icon(Icons.search),
                      elevation: const WidgetStatePropertyAll(0),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: players.length,
                      itemBuilder: (_, i) {
                        final p = players[i];
                        final c = stats.player(p.id);
                        final teams = tc
                            .teamsOfPlayer(p.id)
                            .map((t) => t.shortName)
                            .join(', ');
                        return ListTile(
                          leading: PlayerAvatar(p),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  p.isSelf ? '${p.name} (you)' : p.name,
                                ),
                              ),
                              if (p.isRegistered && !p.isSelf) ...[
                                const SizedBox(width: 6),
                                Tooltip(
                                  message: 'Registered user',
                                  child: Icon(
                                    Icons.verified_user_outlined,
                                    size: 16,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            [
                              p.role.label,
                              if (teams.isNotEmpty) teams,
                              if (p.email?.isNotEmpty == true) p.email!,
                            ].join(' · '),
                          ),
                          trailing: c == null
                              ? null
                              : Text(
                                  '${c.runs} runs\n${c.wickets} wkts',
                                  textAlign: TextAlign.right,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PlayerDetailScreen(playerId: p.id),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
