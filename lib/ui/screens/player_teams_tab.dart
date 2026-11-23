import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/api/api_models.dart';
import '../../data/app_dependencies.dart';
import '../../models/cricket_match.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../state/matches_controller.dart';
import '../../state/membership_controller.dart';
import '../../state/teams_controller.dart';
import '../widgets/cloud_actions.dart';
import '../widgets/common.dart';
import 'joined_screens.dart';
import 'match_detail_screen.dart';
import 'team_detail_screen.dart';

/// "Teams" tab of a player: every team the player is part of, the matches those
/// teams played and their results (tap a match to see the scorecard).
///
/// * my teams that include the player, with all their matches
/// * for the account owner: the teams other scorers added them to, and those matches
/// * for another registered player: other scorers' PUBLIC teams they also play for
class PlayerTeamsTab extends StatefulWidget {
  const PlayerTeamsTab({super.key, required this.player});
  final Player player;

  @override
  State<PlayerTeamsTab> createState() => _PlayerTeamsTabState();
}

class _PlayerTeamsTabState extends State<PlayerTeamsTab> {
  Future<List<JoinedTeam>>? _publicTeams;

  Player get _p => widget.player;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppDependencies>().api;
    if (api != null && _p.isRegistered && !_p.isSelf) {
      _publicTeams = api.playerPublicTeams(_p.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<TeamsController>();
    final mc = context.watch<MatchesController>();
    final ms = context.watch<MembershipController>();
    final myTeams = tc.teamsOfPlayer(_p.id);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionHeader('MY TEAMS'),
        if (myTeams.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Not in any of your teams yet. Add the player from a team page.',
            ),
          ),
        for (final t in myTeams)
          _TeamCard(team: t, player: _p, local: mc.matches, remote: ms.matches),

        // The account owner also plays for teams of other scorers.
        if (_p.isSelf && ms.teams.isNotEmpty) ...[
          const SectionHeader('ADDED BY OTHER SCORERS'),
          for (final t in ms.teams)
            _JoinedTeamCard(team: t, matches: ms.matchesOf(t)),
        ],

        // Another registered player: their public teams elsewhere (private teams are never shown).
        if (_publicTeams != null) ...[
          const SectionHeader('ALSO PLAYS FOR (PUBLIC TEAMS)'),
          FutureBuilder<List<JoinedTeam>>(
            future: _publicTeams,
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(apiMessage(snap.error!)),
                );
              }
              final list = snap.data;
              if (list == null) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text('No public teams of other scorers.'),
                );
              }
              return Column(
                children: [
                  for (final t in list)
                    ListTile(
                      leading: TeamAvatar(
                        short: t.shortName,
                        colorIndex: t.colorIndex,
                      ),
                      title: Text(t.name),
                      subtitle: Text(
                        'by ${t.ownerName ?? 'another scorer'} · ${t.playerCount} players',
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

String _score(CricketMatch m) {
  if (m.isLive) return 'LIVE';
  return m.resultText.isEmpty ? m.status.name : m.resultText;
}

/// One of my teams: its record and every match it played.
class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.player,
    required this.local,
    required this.remote,
  });
  final Team team;
  final Player player;
  final List<CricketMatch> local;

  /// Matches of other scorers in which this team played (for example against my team).
  final List<MatchSummary> remote;

  @override
  Widget build(BuildContext context) {
    final mine =
        local
            .where((m) => m.teamAId == team.id || m.teamBId == team.id)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final theirs = remote
        .where((m) => m.teamAId == team.id || m.teamBId == team.id)
        .toList();
    final finished = mine
        .where((m) => !m.isLive && m.status == MatchStatus.completed)
        .toList();
    final won = finished.where((m) => m.winnerId == team.id).length;
    final lost = finished
        .where((m) => m.winnerId != null && m.winnerId != team.id)
        .length;
    final total = mine.length + theirs.length;
    final df = DateFormat('d MMM y');

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: total > 0 && total <= 4,
        shape: const Border(),
        leading: TeamAvatar.of(team),
        title: Text(
          team.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${team.playerIds.length} players · $total matches · W$won L$lost',
        ),
        children: [
          if (total == 0)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('No matches yet'),
              ),
            ),
          for (final m in mine)
            ListTile(
              dense: true,
              leading: Icon(
                m.isLive ? Icons.sensors : Icons.sports_cricket,
                size: 20,
              ),
              title: Text('${m.teamAShort} vs ${m.teamBShort}'),
              subtitle: Text('${df.format(m.date)} · ${_score(m)}'),
              trailing:
                  m.teamAPlayers.contains(player.id) ||
                      m.teamBPlayers.contains(player.id)
                  ? const Chip(
                      label: Text('Played'),
                      visualDensity: VisualDensity.compact,
                    )
                  : null,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MatchDetailScreen(matchId: m.id),
                ),
              ),
            ),
          for (final m in theirs)
            ListTile(
              dense: true,
              leading: Icon(
                m.isLive ? Icons.sensors : Icons.sports_cricket,
                size: 20,
              ),
              title: Text('${m.teamAShort} vs ${m.teamBShort}'),
              subtitle: Text(
                '${df.format(m.date)} · ${m.resultText?.isNotEmpty == true ? m.resultText! : (m.isLive ? 'LIVE' : m.status)}',
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => JoinedMatchScreen(summary: m),
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TeamDetailScreen(teamId: team.id),
                ),
              ),
              child: const Text('Open team'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A team of another scorer that added me, with the matches I can see.
class _JoinedTeamCard extends StatelessWidget {
  const _JoinedTeamCard({required this.team, required this.matches});
  final JoinedTeam team;
  final List<MatchSummary> matches;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM y');
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: matches.isNotEmpty && matches.length <= 4,
        shape: const Border(),
        leading: TeamAvatar(short: team.shortName, colorIndex: team.colorIndex),
        title: Text(
          team.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'by ${team.ownerName ?? 'another scorer'} · ${matches.length} matches',
        ),
        children: [
          if (matches.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('No matches yet'),
              ),
            ),
          for (final m in matches)
            ListTile(
              dense: true,
              leading: Icon(
                m.isLive ? Icons.sensors : Icons.sports_cricket,
                size: 20,
              ),
              title: Text('${m.teamAShort} vs ${m.teamBShort}'),
              subtitle: Text(
                '${df.format(m.date)} · ${m.resultText?.isNotEmpty == true ? m.resultText! : (m.isLive ? 'LIVE' : m.status)}',
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => JoinedMatchScreen(summary: m),
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => JoinedTeamScreen(team: team)),
              ),
              child: const Text('Open team'),
            ),
          ),
        ],
      ),
    );
  }
}
