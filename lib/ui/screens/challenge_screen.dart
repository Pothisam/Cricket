import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/api/api_models.dart';
import '../../data/api/sync_manager.dart';
import '../../data/app_dependencies.dart';
import '../../models/team.dart';
import '../../state/membership_controller.dart';
import '../../state/teams_controller.dart';
import '../widgets/cloud_actions.dart';
import '../widgets/common.dart';

/// Challenge a team that belongs to another user: pick one of my teams, search
/// the opponent by team name and send the invitation. The opponent's owner has to accept.
class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key});

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  final _search = TextEditingController();
  final _overs = TextEditingController(text: '20');
  final _venue = TextEditingController();
  final _message = TextEditingController();
  Timer? _debounce;

  Team? _mine;
  TeamSearchItem? _opponent;
  List<TeamSearchItem> _results = [];
  DateTime? _when;
  bool _searching = false;
  bool _sending = false;
  String? _searchError;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_search, _overs, _venue, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _runSearch(v.trim()),
    );
  }

  Future<void> _runSearch(String q) async {
    if (q.length < 2) {
      setState(() {
        _results = [];
        _lastQuery = '';
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final r = await context.read<AppDependencies>().api!.searchTeams(q);
      if (!mounted || _search.text.trim() != q) return;
      setState(() {
        _results = r;
        _lastQuery = q;
      });
    } catch (e) {
      if (mounted) setState(() => _searchError = apiMessage(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _when ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _when ?? now.add(const Duration(hours: 2)),
      ),
    );
    if (t == null) return;
    setState(() => _when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  bool get _valid =>
      _mine != null &&
      _opponent != null &&
      (int.tryParse(_overs.text) ?? 0) > 0;

  Future<void> _send() async {
    final api = context.read<AppDependencies>().api!;
    final sync = context.read<SyncManager>();
    final ms = context.read<MembershipController>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await sync
          .syncAll(); // my team has to be on the server before it can challenge
      final inv = await api.createInvitation(
        fromTeamId: _mine!.id,
        toOwnerId: _opponent!.ownerId,
        toTeamId: _opponent!.teamId,
        overs: int.parse(_overs.text),
        scheduledAt: _when,
        venue: _venue.text.trim().isEmpty ? null : _venue.text.trim(),
        message: _message.text.trim().isEmpty ? null : _message.text.trim(),
      );
      await ms.load();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Challenge sent to ${inv.toUserName ?? inv.toTeamName}. You are notified when they answer.',
          ),
        ),
      );
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiMessage(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<TeamsController>();
    final eligible = tc.teams.where((t) => t.playerIds.length >= 2).toList();
    final theme = Theme.of(context);

    if (eligible.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Challenge a team')),
        body: const EmptyState(
          icon: Icons.groups,
          title: 'You need a team',
          message: 'Create a team with at least 2 players, then challenge a team of another scorer.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Challenge a team')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _valid && !_sending ? _send : null,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: const Text('Send invitation'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Your team plays a team of another scorer. They get an invitation, and the match is created when they accept.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<Team>(
            initialValue: _mine,
            decoration: const InputDecoration(labelText: 'My team'),
            items: [
              for (final t in eligible)
                DropdownMenuItem(value: t, child: Text(t.name)),
            ],
            onChanged: (t) => setState(() => _mine = t),
          ),
          const SectionHeader('OPPONENT'),
          if (_opponent != null)
            Card(
              child: ListTile(
                leading: TeamAvatar(
                  short: _opponent!.shortName,
                  colorIndex: _opponent!.colorIndex,
                ),
                title: Text(_opponent!.name),
                subtitle: Text(
                  '${_opponent!.ownerName ?? 'Another scorer'} · ${_opponent!.playerCount} players',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Choose another team',
                  onPressed: () => setState(() => _opponent = null),
                ),
              ),
            )
          else ...[
            TextField(
              controller: _search,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                labelText: 'Search a public team by name',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (_searchError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _searchError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (!_searching && _lastQuery.isNotEmpty && _results.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('No team with that name'),
              ),
            for (final t in _results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: TeamAvatar(
                  short: t.shortName,
                  colorIndex: t.colorIndex,
                ),
                title: Text(t.name),
                subtitle: Text(
                  '${t.ownerName ?? 'Another scorer'} · ${t.playerCount} players',
                ),
                onTap: () => setState(() => _opponent = t),
              ),
          ],
          const SectionHeader('MATCH'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _overs,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Overs'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _venue,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Venue (optional)',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickWhen,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Date and time (optional)',
                suffixIcon: _when == null
                    ? const Icon(Icons.event)
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _when = null),
                      ),
              ),
              child: Text(
                _when == null
                    ? 'Not set'
                    : DateFormat('EEE d MMM y, h:mm a').format(_when!),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            maxLength: 300,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Message (optional)'),
          ),
        ],
      ),
    );
  }
}
