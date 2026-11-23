import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ids.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_models.dart';
import '../../data/api/sync_manager.dart';
import '../../data/app_dependencies.dart';
import '../../models/cricket_match.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../state/matches_controller.dart';
import '../../state/membership_controller.dart';
import '../../state/teams_controller.dart';
import '../widgets/cloud_actions.dart';
import '../widgets/common.dart';
import 'scoring_screen.dart';

class NewMatchScreen extends StatefulWidget {
  const NewMatchScreen({super.key});

  @override
  State<NewMatchScreen> createState() => _NewMatchScreenState();
}

class _NewMatchScreenState extends State<NewMatchScreen> {
  Team? _a;
  Team? _b;
  final _overs = TextEditingController(text: '20');
  final _venue = TextEditingController();
  bool _tossA = true;
  bool _bat = true;
  List<String> _xiA = [];
  List<String> _xiB = [];

  void _setTeam(bool isA, Team? t, TeamsController tc) {
    setState(() {
      if (isA) {
        _a = t;
        _xiA = t == null ? [] : t.playerIds.take(11).toList();
      } else {
        _b = t;
        _xiB = t == null ? [] : t.playerIds.take(11).toList();
      }
    });
  }

  Future<void> _pickXi(bool isA, TeamsController tc) async {
    final team = isA ? _a : _b;
    if (team == null) return;
    final res = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _XiPicker(
        team: team,
        players: tc.playersOf(team),
        initial: isA ? _xiA : _xiB,
      ),
    );
    if (res != null) setState(() => isA ? _xiA = res : _xiB = res);
  }

  bool get _valid =>
      _a != null &&
      _b != null &&
      _a!.id != _b!.id &&
      _xiA.length >= 2 &&
      _xiB.length >= 2 &&
      (int.tryParse(_overs.text) ?? 0) > 0;

  Future<void> _start(TeamsController tc, MatchesController mc) async {
    final a = _a!, b = _b!;
    final names = <String, String>{
      for (final id in [..._xiA, ..._xiB])
        id: tc.playerById(id)?.name ?? 'Unknown',
    };
    final m = CricketMatch(
      id: newId(),
      teamAId: a.id,
      teamBId: b.id,
      teamAName: a.name,
      teamBName: b.name,
      teamAShort: a.shortName,
      teamBShort: b.shortName,
      overs: int.parse(_overs.text),
      tossWinnerId: _tossA ? a.id : b.id,
      electedToBat: _bat,
      teamAPlayers: _xiA,
      teamBPlayers: _xiB,
      playerNames: names,
      date: DateTime.now(),
      venue: _venue.text.trim(),
    );
    await mc.add(m);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ScoringScreen(matchId: m.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<TeamsController>();
    final mc = context.read<MatchesController>();
    final eligible = tc.teams.where((t) => t.playerIds.length >= 2).toList();

    if (eligible.length < 2) {
      return Scaffold(
        appBar: AppBar(title: const Text('New match')),
        body: const EmptyState(
          icon: Icons.groups,
          title: 'Two teams needed',
          message: 'Create at least two teams with 2 or more players each.\nYou can also load sample data from the More tab.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('New match')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _valid ? () => _start(tc, mc) : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start match'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _teamPicker('Team A', true, eligible, tc),
          const SizedBox(height: 12),
          _teamPicker('Team B', false, eligible, tc),
          const SizedBox(height: 20),
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
          if (_a != null && _b != null) ...[
            const SectionHeader('TOSS'),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text('${_a!.shortName} won toss'),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('${_b!.shortName} won toss'),
                ),
              ],
              selected: {_tossA},
              onSelectionChanged: (s) => setState(() => _tossA = s.first),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Chose to bat'),
                  icon: Icon(Icons.sports_cricket),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Chose to bowl'),
                  icon: Icon(Icons.sports_baseball),
                ),
              ],
              selected: {_bat},
              onSelectionChanged: (s) => setState(() => _bat = s.first),
            ),
          ],
          if (_a != null && _a!.id == _b?.id)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Choose two different teams',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  Widget _teamPicker(
    String label,
    bool isA,
    List<Team> teams,
    TeamsController tc,
  ) {
    final team = isA ? _a : _b;
    final xi = isA ? _xiA : _xiB;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            DropdownButtonFormField<Team>(
              initialValue: team,
              decoration: InputDecoration(labelText: label),
              items: [
                for (final t in teams)
                  DropdownMenuItem(value: t, child: Text(t.name)),
              ],
              onChanged: (t) => _setTeam(isA, t, tc),
            ),
            if (team != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Playing XI: ${xi.length} selected',
                      style: TextStyle(
                        color: xi.length < 2
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _pickXi(isA, tc),
                    child: const Text('Select players'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _XiPicker extends StatefulWidget {
  const _XiPicker({
    required this.team,
    required this.players,
    required this.initial,
  });
  final Team team;
  final List<Player> players;
  final List<String> initial;

  @override
  State<_XiPicker> createState() => _XiPickerState();
}

class _XiPickerState extends State<_XiPicker> {
  late final Set<String> _sel = widget.initial.toSet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (_, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.team.name} · ${_sel.length} selected',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => _sel
                      ..clear()
                      ..addAll(widget.players.map((p) => p.id)),
                  ),
                  child: const Text('All'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              children: [
                for (final p in widget.players)
                  CheckboxListTile(
                    value: _sel.contains(p.id),
                    title: Text(p.name),
                    subtitle: Text(p.role.label),
                    onChanged: (v) => setState(
                      () => v == true ? _sel.add(p.id) : _sel.remove(p.id),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _sel.length < 2
                    ? null
                    : () => Navigator.pop(context, [
                        // keep batting order = team order
                        for (final p in widget.players)
                          if (_sel.contains(p.id)) p.id,
                      ]),
                child: const Text('Done'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Starts a match that was agreed with another user's team (an accepted invitation).
/// The scorer (the owner of team A) picks both playing XIs, because the opponent's
/// players live in the opponent's account and are fetched from the server.
class StartFixtureScreen extends StatefulWidget {
  const StartFixtureScreen({super.key, required this.invitation});
  final MatchInvitation invitation;

  @override
  State<StartFixtureScreen> createState() => _StartFixtureScreenState();
}

class _StartFixtureScreenState extends State<StartFixtureScreen> {
  late final TextEditingController _overs = TextEditingController(
    text: '${widget.invitation.overs}',
  );
  late final TextEditingController _venue = TextEditingController(
    text: widget.invitation.venue ?? '',
  );
  JoinedTeam? _opponent;
  String? _error;
  bool _starting = false;
  bool _tossMine = true;
  bool _bat = true;
  List<String> _xiA = [];
  List<String> _xiB = [];

  MatchInvitation get _inv => widget.invitation;

  @override
  void initState() {
    super.initState();
    final mine = context.read<TeamsController>().teamById(_inv.fromTeamId);
    _xiA = mine == null ? [] : mine.playerIds.take(11).toList();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final t = await context.read<AppDependencies>().api!.opponentSquad(
        _inv.id,
      );
      if (!mounted) return;
      setState(() {
        _opponent = t;
        _xiB = t.squad.take(11).map((m) => m.playerId).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = apiMessage(e));
    }
  }

  List<Player> get _opponentPlayers => [
    for (final m in _opponent?.squad ?? const <SquadMember>[])
      Player(
        id: m.playerId,
        name: m.name,
        role: PlayerRole.values.firstWhere(
          (r) => r.name == m.role,
          orElse: () => PlayerRole.batter,
        ),
        battingStyle: m.battingStyle.isEmpty
            ? battingStyles.first
            : m.battingStyle,
        bowlingStyle: m.bowlingStyle.isEmpty ? 'None' : m.bowlingStyle,
      ),
  ];

  Future<void> _pick(bool mineSide) async {
    final tc = context.read<TeamsController>();
    final team = mineSide
        ? tc.teamById(_inv.fromTeamId)
        : Team(
            id: _inv.toTeamId,
            name: _inv.toTeamName,
            shortName: _inv.toTeamShort,
          );
    if (team == null) return;
    final res = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _XiPicker(
        team: team,
        players: mineSide ? tc.playersOf(team) : _opponentPlayers,
        initial: mineSide ? _xiA : _xiB,
      ),
    );
    if (res != null) setState(() => mineSide ? _xiA = res : _xiB = res);
  }

  bool get _valid =>
      _opponent != null &&
      _xiA.length >= 2 &&
      _xiB.length >= 2 &&
      (int.tryParse(_overs.text) ?? 0) > 0;

  Future<void> _start() async {
    final tc = context.read<TeamsController>();
    final mc = context.read<MatchesController>();
    final sync = context.read<SyncManager>();
    final ms = context.read<MembershipController>();
    final navigator = Navigator.of(context);
    setState(() => _starting = true);

    final names = <String, String>{
      for (final id in _xiA) id: tc.playerById(id)?.name ?? 'Unknown',
      for (final m in _opponent!.squad)
        if (_xiB.contains(m.playerId)) m.playerId: m.name,
    };
    final match = CricketMatch(
      id: newId(),
      teamAId: _inv.fromTeamId,
      teamBId: _inv.toTeamId,
      teamAName: _inv.fromTeamName,
      teamBName: _inv.toTeamName,
      teamAShort: _inv.fromTeamShort,
      teamBShort: _inv.toTeamShort,
      overs: int.parse(_overs.text),
      tossWinnerId: _tossMine ? _inv.fromTeamId : _inv.toTeamId,
      electedToBat: _bat,
      teamAPlayers: _xiA,
      teamBPlayers: _xiB,
      playerNames: names,
      date: DateTime.now(),
      venue: _venue.text.trim(),
      invitationId: _inv.id,
      opponentUserId: _inv.toUserId,
    );

    // The server has to accept the match first: that links it to the invitation, turns the
    // scheduled match into "started" (nobody can cancel it any more) and shows it to the other team.
    try {
      final res = await context.read<AppDependencies>().api!.syncPush(
        teams: const [],
        players: const [],
        matches: [match],
      );
      final rejected = (res['rejected'] as List?) ?? const [];
      if (rejected.isNotEmpty) {
        final r = Map<String, dynamic>.from(rejected.first as Map);
        throw ApiException(
          409,
          '${r['reason'] ?? 'REJECTED'}',
          '${r['message'] ?? 'The server did not accept the match'}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _starting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start the match: ${apiMessage(e)}'),
          ),
        );
      }
      unawaited(ms.load()); // the invitation may have been cancelled meanwhile
      return;
    }

    await sync.state.setServerHasMatch(
      match.id,
      true,
    ); // live scoring can use the live endpoints
    await mc.add(match);
    unawaited(ms.load());
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => ScoringScreen(matchId: match.id)),
      (r) => r.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<TeamsController>();
    final mine = tc.teamById(_inv.fromTeamId);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_inv.title)),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _valid && mine != null && !_starting ? _start : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start match'),
          ),
        ),
      ),
      body: mine == null
          ? const EmptyState(
              icon: Icons.groups,
              title: 'Your team is missing',
              message: 'This team is no longer on this device. Pull down on the Teams tab to sync, then try again.',
            )
          : _error != null && _opponent == null
          ? ErrorRetry(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Playing against ${_inv.toTeamName}'
                  '${_inv.toUserName == null ? '' : ' (${_inv.toUserName})'}. '
                  'You score this match; the other team sees it live.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                _teamCard(_inv.fromTeamName, _xiA, () => _pick(true)),
                const SizedBox(height: 12),
                if (_opponent == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  _teamCard(_inv.toTeamName, _xiB, () => _pick(false)),
                const SizedBox(height: 20),
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
                const SectionHeader('TOSS'),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text('${_inv.fromTeamShort} won toss'),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('${_inv.toTeamShort} won toss'),
                    ),
                  ],
                  selected: {_tossMine},
                  onSelectionChanged: (s) =>
                      setState(() => _tossMine = s.first),
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Chose to bat'),
                      icon: Icon(Icons.sports_cricket),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Chose to bowl'),
                      icon: Icon(Icons.sports_baseball),
                    ),
                  ],
                  selected: {_bat},
                  onSelectionChanged: (s) => setState(() => _bat = s.first),
                ),
              ],
            ),
    );
  }

  Widget _teamCard(String name, List<String> xi, VoidCallback onPick) => Card(
    child: ListTile(
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        'Playing XI: ${xi.length} selected',
        style: TextStyle(
          color: xi.length < 2 ? Theme.of(context).colorScheme.error : null,
        ),
      ),
      trailing: TextButton(
        onPressed: onPick,
        child: const Text('Select players'),
      ),
    ),
  );
}
