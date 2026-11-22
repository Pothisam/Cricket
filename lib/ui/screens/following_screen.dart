import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api/api_client.dart';
import '../../data/api/api_models.dart';
import '../../data/api/cricket_api.dart';
import '../../data/app_dependencies.dart';
import '../../models/cricket_match.dart';
import '../widgets/cloud_actions.dart';
import '../widgets/common.dart';
import '../widgets/scorecard_view.dart';

/// Matches shared by others: `POST /matches/follow`, `GET /following`,
/// `DELETE /matches/{ownerId}/{id}/follow`, `GET /public/matches/{code}`.
class FollowingScreen extends StatefulWidget {
  const FollowingScreen({super.key});

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  late final CricketApi _api = context.read<AppDependencies>().api!;
  List<MatchSummary>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await _api.following();
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = apiMessage(e));
    }
  }

  Future<void> _follow() async {
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Follow a match'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Share code'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text.trim().toUpperCase()),
              child: const Text('Follow')),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.follow(code);
      await _load();
      if (mounted) {
        toast(context, 'Following match');
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PublicMatchScreen(shareCode: code)),
        );
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.code == 'NOT_FOUND' ? 'No match with that code' : e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Following')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _follow,
        icon: const Icon(Icons.add),
        label: const Text('Enter code'),
      ),
      body: _error != null && items == null
          ? ErrorRetry(message: _error!, onRetry: _load)
          : RefreshIndicator(
        onRefresh: _load,
        child: items == null
            ? ListView(children: const [
                SizedBox(height: 120),
                Center(child: CircularProgressIndicator()),
              ])
            : items.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 120),
                    Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'You are not following any match.\nAsk the scorer for a share code to follow a live match and get its notifications.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ])
                : ListView(children: [
                    for (final m in items)
                      Dismissible(
                        key: ValueKey('${m.ownerId}/${m.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Theme.of(context).colorScheme.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.notifications_off_outlined),
                        ),
                        onDismissed: (_) async {
                          setState(() => items.remove(m));
                          try {
                            await _api.unfollow(m.ownerId, m.id);
                          } on ApiException catch (e) {
                            if (mounted) toast(context, e.message);
                          }
                        },
                        child: ListTile(
                          leading: Icon(m.isLive ? Icons.sensors : Icons.sports_cricket),
                          title: Text('${m.teamAShort} vs ${m.teamBShort}'),
                          subtitle: Text([
                            for (final i in m.innings) i.score,
                            if (m.resultText?.isNotEmpty == true) m.resultText!,
                          ].join('  ·  ')),
                          trailing: m.isLive ? const Text('LIVE') : null,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => SharedMatchScreen(summary: m)),
                          ),
                        ),
                      ),
                  ]),
      ),
    );
  }
}

/// Read-only scorecard of a followed match. Uses the public endpoint when the
/// match has a share code, which needs no login.
class SharedMatchScreen extends StatelessWidget {
  const SharedMatchScreen({super.key, required this.summary});
  final MatchSummary summary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${summary.teamAShort} vs ${summary.teamBShort}')),
      body: ListView(children: [
        ListTile(title: Text(summary.tossText), subtitle: Text(summary.resultText ?? '')),
        for (final i in summary.innings)
          ListTile(
            title: Text(i.battingTeamId == summary.teamAId ? summary.teamAName : summary.teamBName),
            trailing: Text(i.score),
          ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Pull down on the Following list to refresh the score.'),
        ),
      ]),
    );
  }
}

/// Shows a public match (by share code) using the normal scorecard widget.
class PublicMatchScreen extends StatelessWidget {
  const PublicMatchScreen({super.key, required this.shareCode});
  final String shareCode;

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppDependencies>().api!;
    return Scaffold(
      appBar: AppBar(title: Text('Match $shareCode')),
      body: FutureBuilder<CricketMatch>(
        future: api.publicMatch(shareCode),
        builder: (context, snap) {
          if (snap.hasError) {
            final e = snap.error;
            return Center(child: Text(e is ApiException ? e.message : '$e'));
          }
          final m = snap.data;
          if (m == null) return const Center(child: CircularProgressIndicator());
          return ListView(children: [
            for (final i in m.innings) ScorecardView(match: m, innings: i),
          ]);
        },
      ),
    );
  }
}
