import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ids.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../state/teams_controller.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Create (when [player] is null) or edit a player. New players are added to [team] if given.
///
/// The e-mail is optional: when it belongs to someone who has signed in to the
/// app, the player is linked to that person automatically.
Future<void> showPlayerForm(
  BuildContext context, {
  Player? player,
  Team? team,
}) async {
  if (player != null && player.isReadOnly) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${player.name} is a registered user. Only they can edit their profile.',
          ),
        ),
      );
    return;
  }
  final tc = context.read<TeamsController>();
  if (player == null && !tc.canAddPlayer) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text(TeamsController.playerLimitMessage)),
      );
    return;
  }
  final name = TextEditingController(text: player?.name ?? '');
  final email = TextEditingController(text: player?.email ?? '');
  final city = TextEditingController(text: player?.city ?? '');
  final height = TextEditingController(
    text: player?.heightCm == null ? '' : '${player!.heightCm}',
  );
  final weight = TextEditingController(
    text: player?.weightKg == null ? '' : '${player!.weightKg}',
  );
  final jersey = TextEditingController(
    text: player?.jerseyNumber == null ? '' : '${player!.jerseyNumber}',
  );
  var role = player?.role ?? PlayerRole.batter;
  var batting = player?.battingStyle ?? battingStyles.first;
  var bowling = player?.bowlingStyle ?? bowlingStyles.first;
  String? gender = player?.gender;
  String? dob = player?.dateOfBirth;
  final isSelf = player?.isSelf ?? false;
  final formKey = GlobalKey<FormState>();

  String? emptyOr(String s) => s.trim().isEmpty ? null : s.trim();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                player == null
                    ? 'New player'
                    : isSelf
                    ? 'Edit my player'
                    : 'Edit player',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Player name'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: email,
                enabled: !isSelf,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'E-mail (optional)',
                  helperText: isSelf ? 'Comes from your sign-in' : 'If this person signs in with this e-mail, they are linked to this player',
                  helperMaxLines: 2,
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  return t.isEmpty || _emailPattern.hasMatch(t)
                      ? null
                      : 'Enter a valid e-mail';
                },
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
                items: [
                  for (final s in battingStyles)
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) => setState(() => batting = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: bowling,
                decoration: const InputDecoration(labelText: 'Bowling style'),
                items: [
                  for (final s in bowlingStyles)
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) => setState(() => bowling = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: gender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Not set')),
                  for (final g in genders)
                    DropdownMenuItem(
                      value: g,
                      child: Text(g[0].toUpperCase() + g.substring(1)),
                    ),
                ],
                onChanged: (v) => setState(() => gender = v),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate:
                        DateTime.tryParse(dob ?? '') ?? DateTime(now.year - 20),
                    firstDate: DateTime(1940),
                    lastDate: now,
                  );
                  if (d == null) return;
                  setState(
                    () => dob =
                        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
                  );
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Date of birth',
                    suffixIcon: dob == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => dob = null),
                          ),
                  ),
                  child: Text(dob ?? 'Not set'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: height,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Height (cm)',
                      ),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) return null;
                        final n = double.tryParse(v!.trim());
                        return n == null || n < 50 || n > 260
                            ? '50 to 260'
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: weight,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Weight (kg)',
                      ),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) return null;
                        final n = double.tryParse(v!.trim());
                        return n == null || n < 10 || n > 300
                            ? '10 to 300'
                            : null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: jersey,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Jersey no.',
                      ),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) return null;
                        final n = int.tryParse(v!.trim());
                        return n == null || n < 0 || n > 999
                            ? '0 to 999'
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: city,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'City'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final p = player ?? Player(id: newId(), name: '');
                    p
                      ..name = name.text.trim()
                      ..role = role
                      ..battingStyle = batting
                      ..bowlingStyle = bowling
                      ..gender = gender
                      ..dateOfBirth = dob
                      ..heightCm = double.tryParse(height.text.trim())
                      ..weightKg = double.tryParse(weight.text.trim())
                      ..jerseyNumber = int.tryParse(jersey.text.trim())
                      ..city = emptyOr(city.text);
                    if (!isSelf) p.email = emptyOr(email.text)?.toLowerCase();
                    if (player == null) {
                      await tc.addPlayer(p, team: team);
                    } else {
                      await tc.updatePlayer(p);
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
