import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api/api_models.dart';
import '../../data/api/cricket_api.dart';
import '../../data/api/sync_manager.dart';
import '../../data/app_dependencies.dart';
import '../../models/player.dart';
import '../../state/teams_controller.dart';
import '../widgets/cloud_actions.dart';
import '../widgets/common.dart';
import 'player_detail_screen.dart';

String _roleLabel(String name) =>
    PlayerRole.values.firstWhere((r) => r.name == name, orElse: () => PlayerRole.batter).label;

/// `GET /players/search` + `POST /players/from-user`.
/// Finds people in my player list and registered users (by name, or by their exact e-mail).
class PlayerSearchScreen extends StatefulWidget {
  const PlayerSearchScreen({super.key});

  @override
  State<PlayerSearchScreen> createState() => _PlayerSearchScreenState();
}

class _PlayerSearchScreenState extends State<PlayerSearchScreen> {
  late final CricketApi _api = context.read<AppDependencies>().api!;
  final _controller = TextEditingController();
  Timer? _debounce;
  List<PlayerSearchItem> _results = [];
  bool _loading = false;
  String? _error;
  String _last = '';
  final Set<String> _adding = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    if (q.length < 2) {
      setState(() {
        _results = [];
        _error = null;
        _loading = false;
        _last = '';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.searchPlayers(q);
      if (!mounted || _controller.text.trim() != q) return; // a newer search is running
      setState(() {
        _results = r;
        _last = q;
      });
    } catch (e) {
      if (mounted) setState(() => _error = apiMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add(PlayerSearchItem item) async {
    final id = item.userId!;
    final sync = context.read<SyncManager>();
    setState(() => _adding.add(id));
    try {
      await _api.addPlayerFromUser(id);
      await sync.syncAll(); // pulls the new player into the local list
      if (!mounted) return;
      toast(context, '${item.name} added to your players');
      await _search(_controller.text.trim());
    } catch (e) {
      if (mounted) toast(context, apiMessage(e));
    } finally {
      if (mounted) setState(() => _adding.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<TeamsController>();
    final mine = _results.where((r) => r.isMine).toList();
    final others = _results.where((r) => !r.isMine).toList();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          onSubmitted: (v) => _search(v.trim()),
          decoration: const InputDecoration(
            hintText: 'Name, or a full e-mail address',
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                _search('');
              },
            ),
        ],
      ),
      body: _error != null
          ? ErrorRetry(message: _error!, onRetry: () => _search(_controller.text.trim()))
          : ListView(
              children: [
                if (_loading) const LinearProgressIndicator(),
                if (!_loading && _last.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Type at least 2 letters of a name.\n'
                      'To find someone by e-mail, enter their full address.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (!_loading && _last.isNotEmpty && _results.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No players found', textAlign: TextAlign.center),
                  ),
                if (mine.isNotEmpty) const SectionHeader('IN MY PLAYERS'),
                for (final r in mine)
                  ListTile(
                    leading: _avatar(r),
                    title: Text(r.isSelf ? '${r.name} (you)' : r.name),
                    subtitle: Text([_roleLabel(r.role), if (r.email?.isNotEmpty == true) r.email!].join(' · ')),
                    trailing: r.isRegistered ? const Icon(Icons.verified_user_outlined, size: 18) : null,
                    onTap: () {
                      final id = r.playerId;
                      if (id != null && tc.playerById(id) != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: id)),
                        );
                      } else {
                        toast(context, 'Sync to load this player');
                      }
                    },
                  ),
                if (others.isNotEmpty) const SectionHeader('REGISTERED PLAYERS'),
                for (final r in others)
                  ListTile(
                    leading: _avatar(r),
                    title: Text(r.name),
                    subtitle: Text([
                      _roleLabel(r.role),
                      if (r.city?.isNotEmpty == true) r.city!,
                      if (r.email?.isNotEmpty == true) r.email!,
                    ].join(' · ')),
                    trailing: _adding.contains(r.userId)
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : FilledButton.tonal(onPressed: () => _add(r), child: const Text('Add')),
                  ),
              ],
            ),
    );
  }

  Widget _avatar(PlayerSearchItem r) => CircleAvatar(
        backgroundImage: r.photoUrl == null ? null : NetworkImage(r.photoUrl!),
        child: r.photoUrl == null ? Text(r.name.isEmpty ? '?' : r.name[0].toUpperCase()) : null,
      );
}
