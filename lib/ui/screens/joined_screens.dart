import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/api/api_models.dart';
import '../../data/app_dependencies.dart';
import '../../models/cricket_match.dart';
import '../../models/player.dart';
import '../../state/membership_controller.dart';
import '../widgets/cloud_actions.dart';
import '../widgets/common.dart';
import '../widgets/scorecard_view.dart';

String _roleLabel(String name) => PlayerRole.values
    .firstWhere((r) => r.name == name, orElse: () => PlayerRole.batter)
    .label;

/// A team created by someone else in which I am a player: squad and its matches (read only).
class JoinedTeamScreen extends StatefulWidget {
  const JoinedTeamScreen({super.key, required this.team});
  final JoinedTeam team;

  @override
  State<JoinedTeamScreen> createState() => _JoinedTeamScreenState();
}

class _JoinedTeamScreenState extends State<JoinedTeamScreen> {
  JoinedTeam? _detail;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final t = widget.team;
      final d = await context.read<AppDependencies>().api!.joinedTeam(
        t.ownerId,
        t.teamId,
      );
      if (mounted) setState(() => _detail = d);
    } catch (e) {
      if (mounted) setState(() => _error = apiMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.team;
    final d = _detail;
    final matches = context.watch<MembershipController>().matchesOf(t);
    return Scaffold(
      appBar: AppBar(title: Text(t.name)),
      body: RefreshIndicator(
        onRefresh: () async {
          await _load();
          if (context.mounted)
            await context.read<MembershipController>().load();
        },
        child: _error != null && d == null
            ? ErrorRetry(message: _error!, onRetry: _load)
            : ListView(
                children: [
                  ListTile(
                    leading: TeamAvatar(
                      short: t.shortName,
                      colorIndex: t.colorIndex,
                      size: 48,
                    ),
                    title: Text(
                      t.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      'Managed by ${t.ownerName ?? 'another scorer'}\n'
                      'You are a player in this team. Only the scorer can change it.',
                    ),
                    isThreeLine: true,
                  ),
                  const SectionHeader('SQUAD'),
                  if (d == null)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  for (final m in d?.squad ?? const <SquadMember>[])
                    ListTile(
                      leading: CircleAvatar(
                        backgroundImage: m.photoUrl == null
                            ? null
                            : NetworkImage(m.photoUrl!),
                        child: m.photoUrl == null
                            ? Text(
                                m.name.isEmpty ? '?' : m.name[0].toUpperCase(),
                              )
                            : null,
                      ),
                      title: Text(m.isMe ? '${m.name} (you)' : m.name),
                      subtitle: Text(
                        [
                          _roleLabel(m.role),
                          m.battingStyle,
                        ].where((e) => e.isNotEmpty).join(' · '),
                      ),
                      trailing: m.isRegistered && !m.isMe
                          ? Icon(
                              Icons.verified_user_outlined,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                    ),
                  if (matches.isNotEmpty) const SectionHeader('MATCHES'),
                  for (final m in matches) JoinedMatchCard(m),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }
}

/// A match of another scorer in which I played (or my team played).
class JoinedMatchCard extends StatelessWidget {
  const JoinedMatchCard(
    this.match, {
    super.key,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 10),
  });
  final MatchSummary match;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scores = [
      for (final i in match.innings)
        '${i.battingTeamId == match.teamAId ? match.teamAShort : match.teamBShort} ${i.score}',
    ].join('  ·  ');
    return Card(
      margin: margin,
      child: ListTile(
        leading: Icon(
          match.isLive ? Icons.sensors : Icons.sports_cricket,
          color: match.isLive ? cs.error : null,
        ),
        title: Text('${match.teamAShort} vs ${match.teamBShort}'),
        subtitle: Text(
          [
            DateFormat('d MMM y').format(match.date),
            if (scores.isNotEmpty) scores,
            if (match.resultText?.isNotEmpty == true) match.resultText!,
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => JoinedMatchScreen(summary: match)),
        ),
      ),
    );
  }
}

/// Scorecard of a match I took part in but did not score (read only).
class JoinedMatchScreen extends StatefulWidget {
  const JoinedMatchScreen({super.key, required this.summary});
  final MatchSummary summary;

  @override
  State<JoinedMatchScreen> createState() => _JoinedMatchScreenState();
}

class _JoinedMatchScreenState extends State<JoinedMatchScreen> {
  CricketMatch? _match;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = widget.summary;
      final m = await context.read<AppDependencies>().api!.myMatch(
        s.ownerId,
        s.id,
      );
      if (mounted) setState(() => _match = m);
    } catch (e) {
      if (mounted) setState(() => _error = apiMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final m = _match;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${s.teamAShort} vs ${s.teamBShort}'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Scorecard'),
              Tab(text: 'Overs'),
            ],
          ),
        ),
        body: m == null
            ? (_error != null
                  ? ErrorRetry(message: _error!, onRetry: _load)
                  : const Center(child: CircularProgressIndicator()))
            : TabBarView(
                children: [
                  RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      children: [
                        ListTile(
                          title: Text(m.tossText),
                          subtitle: Text(m.resultText),
                        ),
                        if (m.innings.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Match has not started'),
                          ),
                        for (final i in m.innings)
                          ScorecardView(match: m, innings: i),
                      ],
                    ),
                  ),
                  RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      children: [
                        for (final i in m.innings)
                          OversView(match: m, innings: i),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// "PLAYING FOR" and "MATCHES AS A PLAYER" blocks, used by the Teams and Matches tabs.
class JoinedTeamsSection extends StatelessWidget {
  const JoinedTeamsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ms = context.watch<MembershipController>();
    if (ms.teams.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('PLAYING FOR (ADDED BY OTHERS)'),
        for (final t in ms.teams)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: TeamAvatar(short: t.shortName, colorIndex: t.colorIndex),
              title: Text(
                t.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'by ${t.ownerName ?? 'another scorer'} · ${t.playerCount} players',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => JoinedTeamScreen(team: t)),
              ),
            ),
          ),
      ],
    );
  }
}

class JoinedMatchesSection extends StatelessWidget {
  const JoinedMatchesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ms = context.watch<MembershipController>();
    if (ms.matches.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('MATCHES AS A PLAYER'),
        for (final m in ms.matches)
          JoinedMatchCard(m, margin: const EdgeInsets.only(bottom: 10)),
      ],
    );
  }
}
