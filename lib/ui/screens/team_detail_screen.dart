import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/player.dart';
import '../../models/team.dart';
import '../../state/matches_controller.dart';
import '../../state/teams_controller.dart';
import '../../data/api/api_models.dart';
import '../../data/api/cricket_api.dart';
import '../../data/api/sync_manager.dart';
import '../../data/app_dependencies.dart';
import '../widgets/cloud_actions.dart';
import '../widgets/common.dart';
import '../widgets/match_card.dart';
import '../widgets/pull_refresh.dart';
import '../widgets/avatars.dart';
import '../widgets/squad_list.dart';
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
            _OwnSquad(team: team, players: players),
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
              enabled: tc.canAddPlayer,
              subtitle: tc.canAddPlayer
                  ? Text('${tc.playersLeft} more can be added')
                  : const Text(TeamsController.playerLimitMessage),
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

/// The squad of my own team. The menu of each player gives the roles: captain, vice-captain and
/// admin (hand the team over to a registered player: they run it on their own phone, but cannot delete it).
class _OwnSquad extends StatefulWidget {
  const _OwnSquad({required this.team, required this.players});
  final Team team;
  final List<Player> players;

  @override
  State<_OwnSquad> createState() => _OwnSquadState();
}

class _OwnSquadState extends State<_OwnSquad> {
  Set<String> _adminUserIds = {};
  String? _loadedFor;

  CricketApi? get _api => context.read<AppDependencies>().api;

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  @override
  void didUpdateWidget(_OwnSquad old) {
    super.didUpdateWidget(old);
    if (old.team.id != widget.team.id) _loadAdmins();
  }

  Future<void> _loadAdmins() async {
    final api = _api;
    if (api == null) return;
    _loadedFor = widget.team.id;
    try {
      final list = await api.teamManagers(widget.team.id);
      if (mounted && _loadedFor == widget.team.id) {
        setState(() => _adminUserIds = {for (final m in list) m.userId});
      }
    } catch (_) {
      // not on the server yet / offline: no admins to show
    }
  }

  Future<void> _setAdmin(Player p, bool make) async {
    final api = _api;
    if (api == null || p.linkedUserId == null) return;
    final sync = context.read<SyncManager>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      List<TeamManagerInfo> list;
      if (make) {
        await sync.syncAll(); // the team and its squad have to be on the server
        list = await api.addTeamManager(widget.team.id, p.linkedUserId!);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${p.name} is now an admin of ${widget.team.name}. They are notified.',
            ),
          ),
        );
      } else {
        list = await api.removeTeamManager(widget.team.id, p.linkedUserId!);
        messenger.showSnackBar(
          SnackBar(content: Text('${p.name} is no longer an admin.')),
        );
      }
      if (mounted)
        setState(() => _adminUserIds = {for (final m in list) m.userId});
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.read<TeamsController>();
    final team = widget.team;
    final hasApi = _api != null;
    return SquadList(
      entries: [
        for (final p in widget.players)
          SquadEntry(
            id: p.id,
            avatar: PlayerAvatar(p),
            title: p.name,
            subtitle: p.role.label,
            captain: team.captainPlayerId == p.id,
            vice: team.viceCaptainPlayerId == p.id,
            owner: p.isSelf,
            admin:
                p.linkedUserId != null &&
                _adminUserIds.contains(p.linkedUserId),
            canBeAdmin: p.isRegistered && !p.isSelf,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlayerDetailScreen(playerId: p.id),
              ),
            ),
          ),
      ],
      onReorder: (a, b) => tc.moveInSquad(team, a, b),
      onCaptain: (id, make) => tc.setCaptain(team, make ? id : null),
      onVice: (id, make) => tc.setViceCaptain(team, make ? id : null),
      onAdmin: hasApi
          ? (id, make) =>
                _setAdmin(widget.players.firstWhere((p) => p.id == id), make)
          : null,
      onRemove: (id) async {
        final p = widget.players.firstWhere((x) => x.id == id);
        await tc.removeFromTeam(team, id);
        // an admin must be in the squad: take the access away with the player
        if (p.linkedUserId != null &&
            _adminUserIds.contains(p.linkedUserId) &&
            hasApi) {
          try {
            final list = await _api!.removeTeamManager(
              team.id,
              p.linkedUserId!,
            );
            if (mounted)
              setState(() => _adminUserIds = {for (final m in list) m.userId});
          } catch (_) {}
        }
      },
    );
  }
}
