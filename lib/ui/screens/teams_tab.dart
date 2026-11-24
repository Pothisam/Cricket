import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/team.dart';
import '../../state/membership_controller.dart';
import '../../state/teams_controller.dart';
import '../widgets/common.dart';
import '../widgets/pull_refresh.dart';
import '../../state/team_membership.dart';
import 'joined_screens.dart';
import 'managed_team_screen.dart';
import 'team_detail_screen.dart';

class TeamsTab extends StatelessWidget {
  const TeamsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<TeamsController>();
    return Scaffold(
      appBar: AppBar(
        title: Text('Teams (${tc.teams.length}/${TeamsController.maxTeams})'),
      ),
      floatingActionButton: tc.canCreateTeam
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => showTeamForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Add team'),
            )
          : null,
      body: PullToRefresh(
        child:
            (tc.teams.isEmpty &&
                context.watch<MembershipController>().teams.isEmpty)
            ? const RefreshableEmpty(
                child: EmptyState(
                  icon: Icons.groups,
                  title: 'No teams yet',
                  message: 'Add your first team to get started.',
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  const _MyTeamsSummaryCard(),
                  if (!tc.canCreateTeam)
                    Card(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: const ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('Team limit reached'),
                        subtitle: Text(TeamsController.limitMessage),
                      ),
                    ),
                  for (final t in tc.teams)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: TeamAvatar.of(t),
                        title: Text(
                          t.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${t.playerIds.length} players · ${t.isPublic ? 'Public' : 'Private'}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (tc.canCreateTeam)
                              IconButton(
                                tooltip: 'Duplicate team',
                                icon: const Icon(Icons.copy_all_outlined),
                                onPressed: () async {
                                  final Team copy;
                                  try {
                                    copy = await tc.duplicateTeam(t);
                                  } on TeamLimitException catch (e) {
                                    if (context.mounted)
                                      toast(context, e.message);
                                    return;
                                  }
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(
                                      SnackBar(
                                        content: Text('Created "${copy.name}"'),
                                        action: SnackBarAction(
                                          label: 'Rename',
                                          onPressed: () =>
                                              showTeamForm(context, team: copy),
                                        ),
                                      ),
                                    );
                                },
                              ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TeamDetailScreen(teamId: t.id),
                          ),
                        ),
                      ),
                    ),
                  const ManagedTeamsSection(),
                  const JoinedTeamsSection(),
                ],
              ),
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
  var isPublic = team?.isPublic ?? false;
  String? limitError; // why the chosen visibility / a new team is not allowed
  final formKey = GlobalKey<FormState>();
  var shortEdited = team != null;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
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
                team == null ? 'New team' : 'Edit team',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Team name'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a name' : null,
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
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a short name' : null,
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
                            ? const Icon(
                                Icons.check,
                                size: 18,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(isPublic ? Icons.public : Icons.lock_outline),
                title: Text(isPublic ? 'Public team' : 'Private team'),
                subtitle: Text(
                  isPublic
                      ? 'Other scorers can search this team by name and challenge it to a match.'
                      : 'Only you can see this team.',
                ),
                value: isPublic,
                onChanged: (v) {
                  final blocked = team == null
                      ? tc.creationBlockedReason(isPublic: v)
                      : tc.visibilityBlockedReason(team, v);
                  setState(() {
                    if (blocked == null) {
                      isPublic = v;
                      limitError = null;
                    } else {
                      limitError = blocked; // the switch stays where it was
                    }
                  });
                },
              ),
              if (limitError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    limitError!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    if (team == null) {
                      try {
                        await tc.addTeam(
                          name.text,
                          short.text,
                          color,
                          isPublic: isPublic,
                        );
                      } on TeamLimitException catch (e) {
                        setState(() => limitError = e.message);
                        return;
                      }
                    } else {
                      team
                        ..name = name.text.trim()
                        ..shortName = short.text.trim().toUpperCase()
                        ..colorIndex = color
                        ..isPublic = isPublic;
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
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';
  if (words.length == 1) {
    final w = words.first;
    return (w.length > 3 ? w.substring(0, 3) : w).toUpperCase();
  }
  return words.take(4).map((w) => w[0]).join().toUpperCase();
}

/// "You are in 5 teams": how many I created, administer, or was added to.
class _MyTeamsSummaryCard extends StatelessWidget {
  const _MyTeamsSummaryCard();

  @override
  Widget build(BuildContext context) {
    final sum = MyTeamsSummary(
      context.watch<TeamsController>(),
      context.watch<MembershipController>(),
    );
    final theme = Theme.of(context);
    Widget chip(IconData icon, String text) => Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sum.total == 1
                  ? 'You are in 1 team'
                  : 'You are in ${sum.total} teams',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                chip(Icons.star_outline, '${sum.created} created by you'),
                if (sum.admin > 0)
                  chip(
                    Icons.admin_panel_settings_outlined,
                    '${sum.admin} you are admin',
                  ),
                if (sum.addedBy > 0)
                  chip(
                    Icons.group_add_outlined,
                    '${sum.addedBy} added by others',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
