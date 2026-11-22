import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/team.dart';
import '../../state/teams_controller.dart';
import '../widgets/common.dart';
import 'team_detail_screen.dart';

class TeamsTab extends StatelessWidget {
  const TeamsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<TeamsController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Teams')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => showTeamForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Add team'),
      ),
      body: tc.teams.isEmpty
          ? const EmptyState(
              icon: Icons.groups,
              title: 'No teams yet',
              message: 'Add your first team to get started.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: tc.teams.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final t = tc.teams[i];
                return Card(
                  child: ListTile(
                    leading: TeamAvatar.of(t),
                    title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${t.playerIds.length} players'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TeamDetailScreen(teamId: t.id)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Create (when [team] is null) or edit a team.
Future<void> showTeamForm(BuildContext context, {Team? team}) async {
  final tc = context.read<TeamsController>();
  final name = TextEditingController(text: team?.name ?? '');
  final short = TextEditingController(text: team?.shortName ?? '');
  var color = team?.colorIndex ?? tc.teams.length % teamColors.length;
  final formKey = GlobalKey<FormState>();
  var shortEdited = team != null;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(team == null ? 'New team' : 'Edit team',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Team name'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                onChanged: (v) {
                  if (!shortEdited) short.text = _abbr(v);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: short,
                textCapitalization: TextCapitalization.characters,
                maxLength: 4,
                onChanged: (_) => shortEdited = true,
                decoration: const InputDecoration(labelText: 'Short name'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a short name' : null,
              ),
              Wrap(
                spacing: 10,
                children: [
                  for (var i = 0; i < teamColors.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => color = i),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: teamColors[i],
                        child: color == i
                            ? const Icon(Icons.check, size: 18, color: Colors.white)
                            : null,
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
                    if (team == null) {
                      await tc.addTeam(name.text, short.text, color);
                    } else {
                      team
                        ..name = name.text.trim()
                        ..shortName = short.text.trim().toUpperCase()
                        ..colorIndex = color;
                      await tc.updateTeam(team);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(team == null ? 'Create team' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _abbr(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '';
  if (words.length == 1) {
    final w = words.first;
    return (w.length > 3 ? w.substring(0, 3) : w).toUpperCase();
  }
  return words.take(4).map((w) => w[0]).join().toUpperCase();
}
