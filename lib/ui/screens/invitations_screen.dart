import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/api/api_models.dart';
import '../../data/app_dependencies.dart';
import '../../state/membership_controller.dart';
import '../widgets/cloud_actions.dart';
import '../widgets/common.dart';
import '../widgets/pull_refresh.dart';
import 'new_match_screen.dart';

/// Match challenges: the ones I received (accept / reject) and the ones I sent.
class InvitationsScreen extends StatelessWidget {
  const InvitationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ms = context.watch<MembershipController>();
    final incoming = ms.invitations.where((i) => !i.outgoing).toList();
    final outgoing = ms.invitations.where((i) => i.outgoing).toList();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Match invitations'),
          bottom: TabBar(
            tabs: [
              Tab(
                text: ms.pendingIncoming > 0
                    ? 'Received (${ms.pendingIncoming})'
                    : 'Received',
              ),
              const Tab(text: 'Sent'),
            ],
          ),
        ),
        body: PullToRefresh(
          child: TabBarView(
            children: [
              _list(
                incoming,
                'No invitations received',
                'When another scorer challenges one of your teams, it shows up here.',
              ),
              _list(
                outgoing,
                'No invitations sent',
                'Use "Challenge a team" on the Matches tab.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(List<MatchInvitation> items, String title, String message) {
    if (items.isEmpty) {
      return RefreshableEmpty(
        child: EmptyState(
          icon: Icons.mail_outline,
          title: title,
          message: message,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [for (final i in items) InvitationCard(i)],
    );
  }
}

Color _statusColor(BuildContext context, String status) {
  final cs = Theme.of(context).colorScheme;
  return switch (status) {
    'accepted' => Colors.green,
    'started' => cs.primary,
    'rejected' || 'cancelled' => cs.error,
    _ => cs.tertiary,
  };
}

String _statusLabel(MatchInvitation i) => switch (i.status) {
  'pending' => i.outgoing ? 'Waiting for answer' : 'Needs your answer',
  'accepted' => 'Scheduled',
  'started' => 'Started',
  'rejected' => 'Declined',
  'cancelled' => 'Cancelled',
  _ => i.status,
};

/// One challenge / scheduled match, with the buttons that fit its state.
class InvitationCard extends StatefulWidget {
  const InvitationCard(this.inv, {super.key});
  final MatchInvitation inv;

  @override
  State<InvitationCard> createState() => _InvitationCardState();
}

class _InvitationCardState extends State<InvitationCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    final ms = context.read<MembershipController>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      await ms.load();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.inv;
    final api = context.read<AppDependencies>().api!;
    final theme = Theme.of(context);
    final when = i.scheduledAt == null
        ? null
        : DateFormat('EEE d MMM y, h:mm a').format(i.scheduledAt!);

    final actions = <Widget>[];
    if (i.isPending && !i.outgoing) {
      actions.addAll([
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => api.rejectInvitation(i.id),
                  'Invitation declined',
                ),
          child: const Text('Reject'),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => api.acceptInvitation(i.id),
                  'Accepted. The match is scheduled.',
                ),
          child: const Text('Accept'),
        ),
      ]);
    } else if (i.isPending && i.outgoing) {
      actions.add(
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => api.cancelInvitation(i.id),
                  'Invitation cancelled',
                ),
          child: const Text('Cancel'),
        ),
      );
    } else if (i.isAccepted) {
      actions.add(
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  if (await confirm(
                    context,
                    'Cancel this match?',
                    'The other team is told that the match is cancelled.',
                    action: 'Cancel match',
                  )) {
                    await _run(
                      () => api.cancelInvitation(i.id),
                      'Match cancelled',
                    );
                  }
                },
          child: const Text('Cancel match'),
        ),
      );
      if (i.outgoing) {
        actions.add(
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StartFixtureScreen(invitation: i),
                    ),
                  ),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start match'),
          ),
        );
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${i.fromTeamName} vs ${i.toTeamName}',
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(_statusLabel(i)),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: _statusColor(context, i.status)),
                  labelStyle: TextStyle(
                    color: _statusColor(context, i.status),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              i.outgoing
                  ? 'You challenged ${i.toUserName ?? 'another scorer'}'
                  : '${i.fromUserName ?? 'Another scorer'} challenged your team ${i.toTeamName}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _info(Icons.sports_cricket, '${i.overs} overs'),
                if (when != null) _info(Icons.event, when),
                if (i.venue?.isNotEmpty == true)
                  _info(Icons.place_outlined, i.venue!),
              ],
            ),
            if (i.message?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                '"${i.message}"',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (i.isAccepted && !i.outgoing) ...[
              const SizedBox(height: 6),
              Text(
                '${i.fromUserName ?? 'The other scorer'} will start and score the match.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _info(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15),
      const SizedBox(width: 4),
      Flexible(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
    ],
  );
}

/// "SCHEDULED MATCHES" block of the Matches tab: accepted challenges, both for the
/// scorer who starts them and for the team that was challenged.
class ScheduledSection extends StatelessWidget {
  const ScheduledSection({super.key});

  @override
  Widget build(BuildContext context) {
    final fixtures = context.watch<MembershipController>().fixtures;
    if (fixtures.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('SCHEDULED MATCHES'),
        for (final i in fixtures) InvitationCard(i),
      ],
    );
  }
}
