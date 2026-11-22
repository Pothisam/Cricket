import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/matches_controller.dart';
import '../../state/membership_controller.dart';
import '../widgets/common.dart';
import '../widgets/match_card.dart';
import '../widgets/pull_refresh.dart';
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
      appBar: AppBar(title: const Text('Matches')),
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
        child: (mc.matches.isEmpty && context.watch<MembershipController>().matches.isEmpty)
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
