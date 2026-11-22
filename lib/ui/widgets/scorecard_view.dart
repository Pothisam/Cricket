import 'package:flutter/material.dart';

import '../../domain/innings_summary.dart';
import '../../models/cricket_match.dart';
import '../../models/innings.dart';
import 'common.dart';

/// Full batting + bowling scorecard for one innings.
class ScorecardView extends StatelessWidget {
  const ScorecardView({super.key, required this.match, required this.innings});
  final CricketMatch match;
  final Innings innings;

  @override
  Widget build(BuildContext context) {
    final s = InningsSummary(match, innings);
    final t = Theme.of(context);
    final head = t.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: t.colorScheme.onSurfaceVariant,
    );

    Widget row(List<Widget> cells, {Color? bg}) => Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: cells),
    );
    Widget num(String v, {double w = 36, bool bold = false}) => SizedBox(
      width: w,
      child: Text(
        v,
        textAlign: TextAlign.right,
        style: TextStyle(fontWeight: bold ? FontWeight.bold : null),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row([
          Expanded(
            child: Text(
              '${match.teamName(innings.battingTeamId)}  ${s.score}  (${s.oversString} ov)',
              style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ], bg: t.colorScheme.primaryContainer.withValues(alpha: 0.5)),
        row([
          Expanded(child: Text('BATTING', style: head)),
          SizedBox(
            width: 36,
            child: Text('R', textAlign: TextAlign.right, style: head),
          ),
          SizedBox(
            width: 36,
            child: Text('B', textAlign: TextAlign.right, style: head),
          ),
          SizedBox(
            width: 30,
            child: Text('4s', textAlign: TextAlign.right, style: head),
          ),
          SizedBox(
            width: 30,
            child: Text('6s', textAlign: TextAlign.right, style: head),
          ),
          SizedBox(
            width: 52,
            child: Text('SR', textAlign: TextAlign.right, style: head),
          ),
        ]),
        for (final b in s.batters)
          row([
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    b.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: b.atCrease ? t.colorScheme.primary : null,
                    ),
                  ),
                  Text(
                    b.out ? b.howOut : (b.atCrease ? 'batting' : 'not out'),
                    style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            num('${b.runs}', bold: true),
            num('${b.balls}'),
            num('${b.fours}', w: 30),
            num('${b.sixes}', w: 30),
            num(b.balls == 0 ? '-' : two(b.strikeRate), w: 52),
          ]),
        row([
          Expanded(child: Text('Extras', style: head)),
          Text(
            '${s.extras}  (b ${s.byes}, lb ${s.legByes}, w ${s.wides}, nb ${s.noBalls})',
            style: t.textTheme.bodySmall,
          ),
        ]),
        row([
          const Expanded(
            child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Text(
            '${s.runs}/${s.wickets}  (${s.oversString} ov, RR ${two(s.runRate)})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ]),
        if (s.yetToBat.isNotEmpty && !innings.completed)
          row([
            Expanded(
              child: Text(
                'Yet to bat: ${s.yetToBat.map(match.playerName).join(', ')}',
                style: t.textTheme.bodySmall,
              ),
            ),
          ]),
        const SizedBox(height: 8),
        row([
          Expanded(child: Text('BOWLING', style: head)),
          SizedBox(
            width: 40,
            child: Text('O', textAlign: TextAlign.right, style: head),
          ),
          SizedBox(
            width: 30,
            child: Text('M', textAlign: TextAlign.right, style: head),
          ),
          SizedBox(
            width: 36,
            child: Text('R', textAlign: TextAlign.right, style: head),
          ),
          SizedBox(
            width: 30,
            child: Text('W', textAlign: TextAlign.right, style: head),
          ),
          SizedBox(
            width: 52,
            child: Text('Econ', textAlign: TextAlign.right, style: head),
          ),
        ]),
        for (final b in s.bowlers)
          row([
            Expanded(
              child: Text(
                b.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            num(b.overs, w: 40),
            num('${b.maidens}', w: 30),
            num('${b.runs}'),
            num('${b.wickets}', w: 30, bold: true),
            num(two(b.economy), w: 52),
          ]),
        if (s.fow.isNotEmpty) ...[
          const SectionHeader('FALL OF WICKETS'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              s.fow
                  .map(
                    (f) =>
                        '${f.score}-${f.number} (${f.playerName}, ${f.over} ov)',
                  )
                  .join('   '),
              style: t.textTheme.bodySmall,
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Ball-by-ball listing grouped by over.
class OversView extends StatelessWidget {
  const OversView({super.key, required this.match, required this.innings});
  final CricketMatch match;
  final Innings innings;

  @override
  Widget build(BuildContext context) {
    final s = InningsSummary(match, innings);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            match.teamName(innings.battingTeamId),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        for (final o in s.overs.reversed)
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              child: Text('${o.number}', style: const TextStyle(fontSize: 13)),
            ),
            title: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final b in o.balls) BallBubble(b)],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${o.bowlerName} · ${o.runs} runs'),
            ),
          ),
        if (s.overs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No balls bowled yet'),
          ),
      ],
    );
  }
}
