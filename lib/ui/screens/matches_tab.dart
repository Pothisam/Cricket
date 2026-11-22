import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/matches_controller.dart';
import '../../state/membership_controller.dart';
import '../widgets/common.dart';
import '../widgets/match_card.dart';
import '../widgets/pull_refresh.dart';
import '../../data/app_dependencies.dart';
import 'challenge_screen.dart';
import 'invitations_screen.dart';
import 'joined_screens.dart';
import 'new_match_screen.dart';

class MatchesTab extends StatelessWidget {
  const MatchesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final mc = context.watch<MatchesController>();
    final live = mc.live;
    final done = mc.finished;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matches'),
        actions: [
          if (context.read<AppDependencies>().api != null) ...[
            IconButton(
              tooltip: 'Challenge a team',
              icon: const Icon(Icons.sports_kabaddi),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChallengeScreen()),
              ),
            ),
            IconButton(
              tooltip: 'Match invitations',
              icon: Badge(
                isLabelVisible:
                    context.watch<MembershipController>().pendingIncoming > 0,
                label: Text(
                  '${context.watch<MembershipController>().pendingIncoming}',
                ),
                child: const Icon(Icons.mail_outline),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const InvitationsScreen()),
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NewMatchScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New match'),
      ),
      body: PullToRefresh(
        child:
            (mc.matches.isEmpty &&
                context.watch<MembershipController>().matches.isEmpty &&
                context.watch<MembershipController>().fixtures.isEmpty)
            ? const RefreshableEmpty(
                child: EmptyState(
                  icon: Icons.sports_cricket,
                  title: 'No matches yet',
                  message: 'Create teams and players, then start a match.\nYou can also load sample data from the More tab.',
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                children: [
                  const ScheduledSection(),
                  if (live.isNotEmpty) ...[
                    const SectionHeader('LIVE MATCHES'),
                    for (final m in live) ...[
                      MatchCard(m),
                      const SizedBox(height: 10),
                    ],
                  ],
                  if (done.isNotEmpty) ...[
                    const SectionHeader('MATCH HISTORY'),
                    for (final m in done) ...[
                      MatchCard(m),
                      const SizedBox(height: 10),
                    ],
                  ],
                  const JoinedMatchesSection(),
                ],
              ),
      ),
    );
  }
}
