import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api/api_client.dart';
import '../../data/api/api_models.dart';
import '../../data/api/cricket_api.dart';
import '../../data/app_dependencies.dart';
import '../../state/auth_controller.dart';
import '../widgets/cloud_actions.dart';
import '../widgets/common.dart';

/// `GET/PATCH/DELETE /me`, `POST /feedback`, `GET /health`, `GET /config`.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final CricketApi _api = context.read<AppDependencies>().api!;
  ApiUser? _me;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final me = await _api.me();
      final cfg = await _api.config();
      final ok = await _api.health();
      if (!mounted) return;
      setState(() {
        _me = me;
        _status =
            'Server ${ok ? 'online' : 'unreachable'} · min app ${cfg.minAppVersion}';
      });
    } catch (e) {
      if (mounted) setState(() => _error = apiMessage(e));
    }
  }

  Future<String?> _ask(
    String title,
    String initial, {
    int lines = 1,
    String? hint,
  }) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          maxLines: lines,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: me == null
          ? (_error != null
                ? ErrorRetry(message: _error!, onRetry: _load)
                : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundImage: me.photoUrl == null
                          ? null
                          : NetworkImage(me.photoUrl!),
                      child: me.photoUrl == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(
                      me.displayName?.isNotEmpty == true
                          ? me.displayName!
                          : 'No name set',
                    ),
                    subtitle: Text(
                      [me.email, me.phoneNumber].whereType<String>().join('\n'),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final name = await _ask(
                          'Display name',
                          me.displayName ?? '',
                        );
                        if (name == null || name.isEmpty) return;
                        try {
                          final u = await _api.updateMe(displayName: name);
                          if (mounted) setState(() => _me = u);
                        } on ApiException catch (e) {
                          if (mounted) toast(context, e.message);
                        }
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: const Text('Sign-in method'),
                    subtitle: Text(me.authProvider),
                  ),
                  if (_status != null)
                    ListTile(
                      leading: const Icon(Icons.cloud_done_outlined),
                      title: Text(_status!),
                    ),
                  const SectionHeader('SUPPORT'),
                  ListTile(
                    leading: const Icon(Icons.feedback_outlined),
                    title: const Text('Send feedback'),
                    onTap: () async {
                      final msg = await _ask(
                        'Feedback',
                        '',
                        lines: 4,
                        hint: 'Tell us what to improve',
                      );
                      if (msg == null || msg.isEmpty) return;
                      try {
                        await _api.feedback(msg);
                        if (mounted)
                          toast(context, 'Thank you for your feedback');
                      } on ApiException catch (e) {
                        if (mounted) toast(context, e.message);
                      }
                    },
                  ),
                  const SectionHeader('DANGER ZONE'),
                  ListTile(
                    leading: Icon(
                      Icons.person_remove_outlined,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Delete account'),
                    subtitle: const Text(
                      'Permanently removes your account and all cloud data',
                    ),
                    onTap: () async {
                      final auth = context.read<AuthController>();
                      if (!await confirm(
                        context,
                        'Delete account?',
                        'Your account, teams, players and matches are deleted from the server and this device. This cannot be undone.',
                        action: 'Delete',
                      )) {
                        return;
                      }
                      try {
                        await auth.deleteAccount();
                        if (mounted)
                          Navigator.of(context).popUntil((r) => r.isFirst);
                      } catch (e) {
                        if (mounted)
                          toast(context, e is ApiException ? e.message : '$e');
                      }
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
