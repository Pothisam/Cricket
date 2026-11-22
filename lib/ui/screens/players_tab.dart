import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/matches_controller.dart';
import '../../state/teams_controller.dart';
import '../widgets/common.dart';
import 'player_detail_screen.dart';
import 'player_form.dart';

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
    final players = tc.players
        .where((p) => p.name.toLowerCase().contains(_query.toLowerCase()))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(title: const Text('Players')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => showPlayerForm(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Add player'),
      ),
      body: tc.players.isEmpty
          ? const EmptyState(
              icon: Icons.person,
              title: 'No players yet',
              message: 'Add players here or from a team page.',
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: SearchBar(
                    hintText: 'Search players',
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
                      final teams = tc.teamsOfPlayer(p.id).map((t) => t.shortName).join(', ');
                      return ListTile(
                        leading: CircleAvatar(child: Text(p.name[0].toUpperCase())),
                        title: Text(p.name),
                        subtitle: Text([p.role.label, if (teams.isNotEmpty) teams].join(' · ')),
                        trailing: c == null
                            ? null
                            : Text('${c.runs} runs\n${c.wickets} wkts',
                                textAlign: TextAlign.right,
                                style: Theme.of(context).textTheme.labelSmall),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: p.id)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
