import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api/api_models.dart';
import '../../data/api/cricket_api.dart';
import '../../data/app_dependencies.dart';
import '../../models/player.dart';
import '../../state/membership_controller.dart';
import '../widgets/avatars.dart';
import '../widgets/cloud_actions.dart';
import '../widgets/common.dart';
import '../widgets/squad_list.dart';

/// "MANAGED BY YOU" block of the Teams tab: teams that their creators handed over to me.
class ManagedTeamsSection extends StatelessWidget {
  const ManagedTeamsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final teams = context.watch<MembershipController>().managedTeams;
    if (teams.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('HANDED OVER TO YOU'),
        for (final t in teams)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: TeamAvatar(short: t.shortName, colorIndex: t.colorIndex),
              title: Text(
                t.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${t.ownerName ?? 'Another scorer'} · ${t.playerCount} players · you are an admin',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ManagedTeamScreen(team: t)),
              ),
            ),
          ),
      ],
    );
  }
}

/// A team its creator handed over to me. I can run it: rename, add and remove players, change the
/// batting order, set captain and vice-captain. I cannot delete it, make it public or private,
/// hand it to others, or remove the creator. Changes are saved straight to the server, so the
/// creator and everybody else see them.
class ManagedTeamScreen extends StatefulWidget {
  const ManagedTeamScreen({super.key, required this.team});
  final ManagedTeam team;

  @override
  State<ManagedTeamScreen> createState() => _ManagedTeamScreenState();
}

class _ManagedTeamScreenState extends State<ManagedTeamScreen> {
  ManagedTeam? _t;
  String? _error;
  bool _busy = false;

  CricketApi get _api => context.read<AppDependencies>().api!;
  ManagedTeam get _team => _t ?? widget.team;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final t = await _api.managedTeam(widget.team.ownerId, widget.team.teamId);
      if (mounted) setState(() => _t = t);
    } catch (e) {
      if (mounted) setState(() => _error = apiMessage(e));
    }
  }

  /// Sends the changed team to the server and shows what the server saved.
  Future<void> _save({
    String? name,
    String? shortName,
    int? colorIndex,
    List<String>? playerIds,
    String? captain,
    String? vice,
    bool clearCaptain = false,
    bool clearVice = false,
  }) async {
    final t = _team;
    setState(() => _busy = true);
    try {
      final updated = await _api.updateManagedTeam(
        t.ownerId,
        t.teamId,
        name: name ?? t.name,
        shortName: shortName ?? t.shortName,
        colorIndex: colorIndex ?? t.colorIndex,
        playerIds: playerIds ?? [for (final m in t.squad) m.playerId],
        captainPlayerId: clearCaptain ? null : (captain ?? t.captainPlayerId),
        viceCaptainPlayerId: clearVice ? null : (vice ?? t.viceCaptainPlayerId),
      );
      if (mounted) setState(() => _t = updated);
      if (mounted) unawaited(context.read<MembershipController>().load());
    } catch (e) {
      if (mounted) toast(context, apiMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final ids = [for (final m in _team.squad) m.playerId];
    ids.insert(newIndex.clamp(0, ids.length - 1), ids.removeAt(oldIndex));
    await _save(playerIds: ids);
  }

  Future<void> _remove(String id) async {
    final member = _team.squad.firstWhere((m) => m.playerId == id);
    if (member.isOwner) {
      toast(context, 'The creator of the team cannot be removed.');
      return;
    }
    await _save(
      playerIds: [
        for (final m in _team.squad)
          if (m.playerId != id) m.playerId,
      ],
    );
  }

  Future<void> _add(String id) async {
    await _save(playerIds: [for (final m in _team.squad) m.playerId, id]);
  }

  Future<void> _editDetails() async {
    final t = _team;
    final name = TextEditingController(text: t.name);
    final short = TextEditingController(text: t.shortName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Team details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Team name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: short,
              maxLength: 4,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Short name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true &&
        name.text.trim().isNotEmpty &&
        short.text.trim().isNotEmpty) {
      await _save(
        name: name.text.trim(),
        shortName: short.text.trim().toUpperCase(),
      );
    }
  }

  Future<void> _addPlayerSheet() async {
    final t = _team;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _AddPlayerSheet(
        team: t,
        onAddRoster: (id) async {
          Navigator.pop(ctx);
          await _add(id);
        },
        onAddUser: (userId) async {
          Navigator.pop(ctx);
          setState(() => _busy = true);
          try {
            final updated = await _api.addManagedPlayer(
              t.ownerId,
              t.teamId,
              userId: userId,
            );
            if (mounted) setState(() => _t = updated);
          } catch (e) {
            if (mounted) toast(context, apiMessage(e));
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        },
        onAddNew: (name) async {
          Navigator.pop(ctx);
          setState(() => _busy = true);
          try {
            final updated = await _api.addManagedPlayer(
              t.ownerId,
              t.teamId,
              name: name,
            );
            if (mounted) setState(() => _t = updated);
          } catch (e) {
            if (mounted) toast(context, apiMessage(e));
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        },
      ),
    );
  }

  Future<void> _leave() async {
    final t = _team;
    final navigator = Navigator.of(context);
    final ms = context.read<MembershipController>();
    if (!await confirm(
      context,
      'Give the team back?',
      '${t.name} will disappear from your phone. ${t.ownerName ?? 'The creator'} stays the owner.',
      action: 'Give back',
    )) {
      return;
    }
    try {
      await _api.leaveManagedTeam(t.ownerId, t.teamId);
      await ms.load();
      navigator.pop();
    } catch (e) {
      if (mounted) toast(context, apiMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _team;
    final loaded = _t != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.name),
        actions: [
          IconButton(
            tooltip: 'Edit name',
            icon: const Icon(Icons.edit_outlined),
            onPressed: loaded ? _editDetails : null,
          ),
        ],
      ),
      floatingActionButton: loaded
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: _busy ? null : _addPlayerSheet,
              icon: const Icon(Icons.person_add),
              label: const Text('Add player'),
            )
          : null,
      body: _error != null && !loaded
          ? ErrorRetry(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  ListTile(
                    leading: TeamAvatar(
                      short: t.shortName,
                      colorIndex: t.colorIndex,
                      size: 48,
                    ),
                    title: Text(
                      t.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      'Created by ${t.ownerName ?? 'another scorer'}. You are an admin of this team: you can run it, '
                      'but only the creator can delete it.',
                    ),
                    isThreeLine: true,
                  ),
                  SectionHeader('SQUAD (${t.squad.length})'),
                  if (!loaded)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (loaded && t.squad.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No players yet')),
                    ),
                  SquadList(
                    entries: [
                      for (final m in t.squad)
                        SquadEntry(
                          id: m.playerId,
                          avatar: UserAvatar(
                            name: m.name,
                            photoUrl: m.photoUrl,
                          ),
                          title: m.name,
                          subtitle: _role(m.role),
                          captain: t.captainPlayerId == m.playerId,
                          vice: t.viceCaptainPlayerId == m.playerId,
                          owner: m.isOwner,
                          admin: m.isAdmin,
                          removeNote: m.isOwner
                              ? 'The creator stays in the team'
                              : m.isMe
                              ? 'Give the team back instead'
                              : null,
                        ),
                    ],
                    onReorder: _reorder,
                    onCaptain: (id, make) =>
                        make ? _save(captain: id) : _save(clearCaptain: true),
                    onVice: (id, make) =>
                        make ? _save(vice: id) : _save(clearVice: true),
                    onRemove: _remove,
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: OutlinedButton.icon(
                      onPressed: _leave,
                      icon: const Icon(Icons.logout),
                      label: const Text('Give the team back'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  static String _role(String name) => PlayerRole.values
      .firstWhere((r) => r.name == name, orElse: () => PlayerRole.batter)
      .label;
}

/// Add a player to a team I manage: from the creator's players, a registered user, or a new name.
class _AddPlayerSheet extends StatefulWidget {
  const _AddPlayerSheet({
    required this.team,
    required this.onAddRoster,
    required this.onAddUser,
    required this.onAddNew,
  });

  final ManagedTeam team;
  final void Function(String playerId) onAddRoster;
  final void Function(String userId) onAddUser;
  final void Function(String name) onAddNew;

  @override
  State<_AddPlayerSheet> createState() => _AddPlayerSheetState();
}

class _AddPlayerSheetState extends State<_AddPlayerSheet> {
  final _name = TextEditingController();
  final _search = TextEditingController();
  Timer? _debounce;
  List<PlayerSearchItem> _found = [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final q = v.trim();
      if (q.length < 2) {
        setState(() => _found = []);
        return;
      }
      setState(() => _searching = true);
      try {
        final r = await context.read<AppDependencies>().api!.searchPlayers(q);
        if (mounted)
          setState(
            () =>
                _found = r.where((i) => i.userId != null && !i.isSelf).toList(),
          );
      } catch (_) {
        // the list simply stays empty
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final roster = widget.team.roster;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        children: [
          Text('Add a player', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'New player (name)',
              suffixIcon: IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  final n = _name.text.trim();
                  if (n.isNotEmpty) widget.onAddNew(n);
                },
              ),
            ),
            onSubmitted: (n) {
              if (n.trim().isNotEmpty) widget.onAddNew(n.trim());
            },
          ),
          const SectionHeader('REGISTERED PLAYERS'),
          TextField(
            controller: _search,
            onChanged: _onSearch,
            decoration: const InputDecoration(
              labelText: 'Search by name or full e-mail',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          for (final r in _found)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: UserAvatar(name: r.name, photoUrl: r.photoUrl),
              title: Text(r.name),
              subtitle: Text(r.email ?? ''),
              trailing: FilledButton.tonal(
                onPressed: () => widget.onAddUser(r.userId!),
                child: const Text('Add'),
              ),
            ),
          if (roster.isNotEmpty) ...[
            SectionHeader(
              '${widget.team.ownerName ?? 'THE CREATOR'}\'S PLAYERS'
                  .toUpperCase(),
            ),
            for (final m in roster)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(name: m.name, photoUrl: m.photoUrl),
                title: Text(m.name),
                subtitle: Text(_ManagedTeamScreenState._role(m.role)),
                trailing: FilledButton.tonal(
                  onPressed: () => widget.onAddRoster(m.playerId),
                  child: const Text('Add'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
