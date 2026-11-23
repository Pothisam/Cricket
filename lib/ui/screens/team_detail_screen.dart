import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/player.dart';
import '../../models/team.dart';
import '../../state/matches_controller.dart';
import '../../state/teams_controller.dart';
import '../../data/app_dependencies.dart';
import '../widgets/cloud_actions.dart';
import '../widgets/common.dart';
import '../widgets/match_card.dart';
import '../widgets/pull_refresh.dart';
import '../widgets/avatars.dart';
import 'player_detail_screen.dart';
import 'player_form.dart';
import 'teams_tab.dart';

class TeamDetailScreen extends StatelessWidget {
  const TeamDetailScreen({super.key, required this.teamId});
  final String teamId;

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<TeamsController>();
    final mc = context.watch<MatchesController>();
    final team = tc.teamById(teamId);
    if (team == null) return const Scaffold(body: SizedBox.shrink());
    final players = tc.playersOf(team);
    final rec = mc.stats.team(team.id);
    final matches = mc.matches
        .where((m) => m.teamAId == team.id || m.teamBId == team.id)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(team.name),
        actions: [
          if (context.read<AppDependencies>().api != null)
            IconButton(
              tooltip: 'Cloud record',
              icon: const Icon(Icons.cloud_outlined),
              onPressed: () => showTeamCloudStats(context, team.id, team.name),
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showTeamForm(context, team: team),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirm(
                context,
                'Delete team?',
                'Past matches stay in history. Players are kept.',
              )) {
                await tc.deleteTeam(team);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => _addPlayer(context, team),
        icon: const Icon(Icons.person_add),
        label: const Text('Add player'),
      ),
      body: PullToRefresh(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TeamAvatar.of(team, size: 56),
                      StatTile('Played', '${rec?.played ?? 0}'),
                      StatTile('Won', '${rec?.won ?? 0}'),
                      StatTile('Lost', '${rec?.lost ?? 0}'),
                      StatTile('Tied', '${rec?.tied ?? 0}'),
                    ],
                  ),
                ),
              ),
            ),
            if (rec != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        StatTile('Highest', '${rec.highest}'),
                        StatTile('Lowest', rec.lowestText),
                        StatTile('Runs for', '${rec.runsFor}'),
                        StatTile('Runs against', '${rec.runsAgainst}'),
                      ],
                    ),
                  ),
                ),
              ),
            SectionHeader('SQUAD (${players.length})'),
            if (players.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No players in this team yet')),
              ),
            for (final p in players)
              ListTile(
                leading: PlayerAvatar(p),
                title: Text(p.name),
                subtitle: Text(p.role.label),
                trailing: IconButton(
                  icon: const Icon(Icons.person_remove_outlined),
                  tooltip: 'Remove from team',
                  onPressed: () => tc.removeFromTeam(team, p.id),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerDetailScreen(playerId: p.id),
                  ),
                ),
              ),
            if (matches.isNotEmpty) ...[
              const SectionHeader('MATCHES'),
              for (final m in matches)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: MatchCard(m),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addPlayer(BuildContext context, Team team) async {
    final tc = context.read<TeamsController>();
    final others = tc.players
        .where((p) => !team.playerIds.contains(p.id))
        .toList();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt_1),
              title: const Text('Create new player'),
              onTap: () => Navigator.pop(ctx, 'new'),
            ),
            ListTile(
              leading: const Icon(Icons.people_alt_outlined),
              title: const Text('Add existing player'),
              enabled: others.isNotEmpty,
              subtitle: others.isEmpty
                  ? const Text('No other players available')
                  : null,
              onTap: () => Navigator.pop(ctx, 'existing'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'new') {
      await showPlayerForm(context, team: team);
    } else {
      final picked = await showModalBottomSheet<Set<String>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => _ExistingPlayersPicker(players: others),
      );
      if (picked != null) {
        for (final id in picked) {
          await tc.addToTeam(team, id);
        }
      }
    }
  }
}

class _ExistingPlayersPicker extends StatefulWidget {
  const _ExistingPlayersPicker({required this.players});
  final List<Player> players;

  @override
  State<_ExistingPlayersPicker> createState() => _ExistingPlayersPickerState();
}

class _ExistingPlayersPickerState extends State<_ExistingPlayersPicker> {
  final selected = <String>{};

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (_, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              children: [
                for (final p in widget.players)
                  CheckboxListTile(
                    value: selected.contains(p.id),
                    title: Text(p.name),
                    subtitle: Text(p.role.label),
                    onChanged: (v) => setState(() {
                      v == true ? selected.add(p.id) : selected.remove(p.id);
                    }),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, selected),
                child: Text('Add ${selected.length} player(s)'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
