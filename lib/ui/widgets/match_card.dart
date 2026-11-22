import 'package:flutter/material.dart';

import '../../domain/innings_summary.dart';
import '../../models/cricket_match.dart';
import '../screens/match_detail_screen.dart';
import 'common.dart';

class MatchCard extends StatelessWidget {
  const MatchCard(this.match, {super.key});
  final CricketMatch match;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final live = match.isLive;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: match.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (live)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('LIVE',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                  else
                    Text('RESULT', style: TextStyle(color: cs.outline, fontSize: 11, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${match.overs} overs · ${formatDate(match.date)}',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 10),
              _teamRow(context, match.teamAId),
              const SizedBox(height: 8),
              _teamRow(context, match.teamBId),
              const SizedBox(height: 10),
              Text(
                live ? _liveStatus() : match.resultText,
                style: TextStyle(
                  color: live ? cs.primary : cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _liveStatus() {
    final cur = match.currentInnings;
    if (cur == null) return match.tossText;
    final t = match.target;
    if (t != null) {
      final s = InningsSummary(match, cur);
      final need = t - s.runs;
      final left = match.overs * 6 - s.legalBalls;
      return '${match.teamShort(cur.battingTeamId)} need $need run${need == 1 ? '' : 's'} in $left ball${left == 1 ? '' : 's'}';
    }
    return match.tossText;
  }

  Widget _teamRow(BuildContext context, String teamId) {
    final idx = match.innings.indexWhere((i) => i.battingTeamId == teamId);
    final colorIndex = teamId == match.teamAId ? 0 : 1;
    String score = '';
    String overs = '';
    if (idx >= 0) {
      final s = InningsSummary(match, match.innings[idx]);
      score = s.score;
      overs = '(${s.oversString})';
    }
    final isWinner = match.winnerId == teamId;
    return Row(
      children: [
        TeamAvatar(short: match.teamShort(teamId), colorIndex: colorIndex + (teamId == match.teamAId ? 0 : 2), size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Text(match.teamName(teamId),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: isWinner ? FontWeight.bold : FontWeight.w500)),
        ),
        Text(score, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(width: 6),
        SizedBox(width: 56, child: Text(overs, style: const TextStyle(fontSize: 12))),
      ],
    );
  }
}
