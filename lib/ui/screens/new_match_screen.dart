import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ids.dart';
import '../../models/cricket_match.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../state/matches_controller.dart';
import '../../state/teams_controller.dart';
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
      for (final id in [..._xiA, ..._xiB]) id: tc.playerById(id)?.name ?? 'Unknown',
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
          message:
              'Create at least two teams with 2 or more players each.\nYou can also load sample data from the More tab.',
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
                  decoration: const InputDecoration(labelText: 'Venue (optional)'),
                ),
              ),
            ],
          ),
          if (_a != null && _b != null) ...[
            const SectionHeader('TOSS'),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text('${_a!.shortName} won toss')),
                ButtonSegment(value: false, label: Text('${_b!.shortName} won toss')),
              ],
              selected: {_tossA},
              onSelectionChanged: (s) => setState(() => _tossA = s.first),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Chose to bat'), icon: Icon(Icons.sports_cricket)),
                ButtonSegment(value: false, label: Text('Chose to bowl'), icon: Icon(Icons.sports_baseball)),
              ],
              selected: {_bat},
              onSelectionChanged: (s) => setState(() => _bat = s.first),
            ),
          ],
          if (_a != null && _a!.id == _b?.id)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text('Choose two different teams',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }

  Widget _teamPicker(String label, bool isA, List<Team> teams, TeamsController tc) {
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
              items: [for (final t in teams) DropdownMenuItem(value: t, child: Text(t.name))],
              onChanged: (t) => _setTeam(isA, t, tc),
            ),
            if (team != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text('Playing XI: ${xi.length} selected',
                        style: TextStyle(
                            color: xi.length < 2 ? Theme.of(context).colorScheme.error : null)),
                  ),
                  TextButton(onPressed: () => _pickXi(isA, tc), child: const Text('Select players')),
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
  const _XiPicker({required this.team, required this.players, required this.initial});
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
                  child: Text('${widget.team.name} · ${_sel.length} selected',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: () => setState(() => _sel
                    ..clear()
                    ..addAll(widget.players.map((p) => p.id))),
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
                    onChanged: (v) => setState(() => v == true ? _sel.add(p.id) : _sel.remove(p.id)),
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
                            if (_sel.contains(p.id)) p.id
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
