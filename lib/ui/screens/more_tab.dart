import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_dependencies.dart';
import '../../state/auth_controller.dart';
import '../../data/api/sync_manager.dart';
import '../widgets/common.dart';
import '../widgets/pull_refresh.dart';
import '../widgets/avatars.dart';
import 'account_screen.dart';
import 'devices_screen.dart';
import 'following_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';

class MoreTab extends StatelessWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: PullToRefresh(
        child: ListView(
          children: [
            const SectionHeader('ACCOUNT'),
            if (context.read<AppDependencies>().api != null) ...[
              ListTile(
                leading: const Icon(Icons.sports_cricket_outlined),
                title: const Text('My cricket profile'),
                subtitle: const Text('Role, batting, bowling, height, weight'),
                onTap: () => _open(context, const ProfileScreen()),
              ),
              ListTile(
                leading: const CurrentUserAvatar(),
                title: const Text('My account'),
                subtitle: const Text('Profile, feedback, delete account'),
                onTap: () => _open(context, const AccountScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notifications'),
                subtitle: const Text('Inbox and settings'),
                onTap: () => _open(context, const NotificationsScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: const Text('Signed-in devices'),
                onTap: () => _open(context, const DevicesScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: const Text('Following'),
                subtitle: const Text('Follow a shared match with its code'),
                onTap: () => _open(context, const FollowingScreen()),
              ),
              const _SyncTile(),
            ],
            ListTile(
              leading: const CurrentUserAvatar(),
              title: const Text('Sign out'),
              subtitle: Text(
                context.watch<AuthController>().user?.email ??
                    context.watch<AuthController>().user?.phoneNumber ??
                    '',
              ),
              onTap: () => context.read<AuthController>().signOut(),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Credits'),
              onTap: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Credits'),
                  content: const SingleChildScrollView(
                    child: Text(
                      '3D models, all licensed CC-BY 4.0 (creativecommons.org/licenses/by/4.0), from Sketchfab:\n'
                      '• Indian Cricket Player Rigged / - Rigged: numaan.k99\n'
                      '• Virat Kohli Cricket Batting Animation (motion data only): bhagathartworks\n'
                      '• Cricket Bat: omkar.jawake\n'
                      '• Narendra Modi Stadium | Low Poly | Game Ready: kevin_k_5124\n\n'
                      'Kits re-coloured, branding removed, animated and adapted for this app.',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _open(BuildContext context, Widget screen) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

/// Shows sync status and runs `POST /sync/push` + `GET /sync/pull`.
class _SyncTile extends StatelessWidget {
  const _SyncTile();

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncManager>();
    final t = sync.lastSyncedAt;
    return ListTile(
      leading: sync.syncing
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync),
      title: const Text('Sync now'),
      subtitle: Text(
        !sync.online
            ? 'Offline. ${sync.pendingCount} change(s) saved on this device, sent when you are back online'
            : sync.pendingCount > 0
            ? '${sync.pendingCount} change(s) waiting to sync'
            : sync.lastError != null
            ? 'Last error: ${sync.lastError}'
            : t == null
            ? (sync.signedIn ? 'Not synced yet' : 'Connecting to server...')
            : 'Last synced ${TimeOfDay.fromDateTime(t).format(context)}',
      ),
      onTap: sync.syncing
          ? null
          : () async {
              if (!sync.signedIn) {
                final uid = context.read<AuthController>().user?.uid;
                if (uid != null) await sync.startSession(uid);
              } else {
                await sync.syncAll();
              }
            },
    );
  }
}
