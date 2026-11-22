import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ids.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../state/teams_controller.dart';

/// Create (when [player] is null) or edit a player. New players are added to [team] if given.
Future<void> showPlayerForm(BuildContext context, {Player? player, Team? team}) async {
  final tc = context.read<TeamsController>();
  final name = TextEditingController(text: player?.name ?? '');
  var role = player?.role ?? PlayerRole.batter;
  var batting = player?.battingStyle ?? battingStyles.first;
  var bowling = player?.bowlingStyle ?? bowlingStyles.first;
  final formKey = GlobalKey<FormState>();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(player == null ? 'New player' : 'Edit player',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Player name'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PlayerRole>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final r in PlayerRole.values)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (v) => setState(() => role = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: batting,
                decoration: const InputDecoration(labelText: 'Batting style'),
                items: [for (final s in battingStyles) DropdownMenuItem(value: s, child: Text(s))],
                onChanged: (v) => setState(() => batting = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: bowling,
                decoration: const InputDecoration(labelText: 'Bowling style'),
                items: [for (final s in bowlingStyles) DropdownMenuItem(value: s, child: Text(s))],
                onChanged: (v) => setState(() => bowling = v!),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    if (player == null) {
                      await tc.addPlayer(
                        Player(
                          id: newId(),
                          name: name.text.trim(),
                          role: role,
                          battingStyle: batting,
                          bowlingStyle: bowling,
                        ),
                        team: team,
                      );
                    } else {
                      player
                        ..name = name.text.trim()
                        ..role = role
                        ..battingStyle = batting
                        ..bowlingStyle = bowling;
                      await tc.updatePlayer(player);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(player == null ? 'Add player' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
