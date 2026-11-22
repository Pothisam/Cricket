import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/api/api_client.dart';
import '../../data/app_dependencies.dart';
import 'common.dart';

String _msg(Object e) => e is ApiException ? e.message : '$e';

Widget _pad(Widget child) => SafeArea(
      child: Padding(padding: const EdgeInsets.all(24), child: Center(child: child)),
    );

/// `GET /players/{id}/stats` shown in a bottom sheet.
Future<void> showPlayerCloudStats(BuildContext context, String id, String name) async {
  final api = context.read<AppDependencies>().api;
  if (api == null) return;
  await showModalBottomSheet<void>(
    context: context,
    builder: (_) => FutureBuilder(
      future: api.playerStats(id),
      builder: (context, snap) {
        if (snap.hasError) return _pad(Text(_msg(snap.error!)));
        final s = snap.data;
        if (s == null) return _pad(const CircularProgressIndicator());
        String v(Map<String, dynamic> m, String k) => '${m[k] ?? '-'}';
        return _pad(Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name · cloud stats', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Matches: ${s.matches}'),
            const SizedBox(height: 8),
            Text('Batting: ${v(s.batting, 'runs')} runs, ${v(s.batting, 'innings')} inns, '
                'HS ${v(s.batting, 'highestScore')}, avg ${v(s.batting, 'average')}, '
                'SR ${v(s.batting, 'strikeRate')}, 4s ${v(s.batting, 'fours')}, '
                '6s ${v(s.batting, 'sixes')}, 50s ${v(s.batting, 'fifties')}, 100s ${v(s.batting, 'hundreds')}'),
            const SizedBox(height: 8),
            Text('Bowling: ${v(s.bowling, 'wickets')} wkts, ${v(s.bowling, 'overs')} ov, '
                '${v(s.bowling, 'runsConceded')} runs, econ ${v(s.bowling, 'economy')}, '
                'best ${v(s.bowling, 'bestFigures')}'),
          ],
        ));
      },
    ),
  );
}

/// `GET /teams/{id}/stats` shown in a bottom sheet.
Future<void> showTeamCloudStats(BuildContext context, String id, String name) async {
  final api = context.read<AppDependencies>().api;
  if (api == null) return;
  await showModalBottomSheet<void>(
    context: context,
    builder: (_) => FutureBuilder(
      future: api.teamStats(id),
      builder: (context, snap) {
        if (snap.hasError) return _pad(Text(_msg(snap.error!)));
        final s = snap.data;
        if (s == null) return _pad(const CircularProgressIndicator());
        return _pad(Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name · cloud record', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Played ${s.played} · Won ${s.won} · Lost ${s.lost} · '
                'Tied ${s.tied} · No result ${s.noResult}'),
          ],
        ));
      },
    ),
  );
}

/// `POST /matches/{id}/share` (and `DELETE` to stop sharing).
Future<void> showShareSheet(BuildContext context, String matchId) async {
  final api = context.read<AppDependencies>().api;
  if (api == null) return;
  try {
    final info = await api.share(matchId);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Share this match', style: Theme.of(sheet).textTheme.titleMedium),
              const SizedBox(height: 12),
              const Text('Friends can follow it live with this code:'),
              const SizedBox(height: 8),
              SelectableText(info.shareCode,
                  style: Theme.of(sheet).textTheme.headlineMedium?.copyWith(letterSpacing: 4)),
              if (info.url.isNotEmpty) ...[const SizedBox(height: 8), SelectableText(info.url)],
              const SizedBox(height: 16),
              Row(children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy code'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: info.shareCode));
                    toast(sheet, 'Code copied');
                  },
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () async {
                    try {
                      await api.unshare(matchId);
                      if (sheet.mounted) {
                        Navigator.pop(sheet);
                        toast(sheet, 'Sharing stopped');
                      }
                    } catch (e) {
                      if (sheet.mounted) toast(sheet, _msg(e));
                    }
                  },
                  child: const Text('Stop sharing'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) toast(context, _msg(e));
  }
}
