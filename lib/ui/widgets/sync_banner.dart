import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api/sync_manager.dart';
import '../../data/app_dependencies.dart';

/// Thin strip above the navigation bar that tells the user what happens to their data:
/// offline (saved on the device), syncing, or changes waiting to be sent.
/// Shows nothing when everything is on the server.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.read<AppDependencies>().sync;
    if (sync == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) => _content(context, sync),
    );
  }

  Widget _content(BuildContext context, SyncManager sync) {
    final cs = Theme.of(context).colorScheme;
    final pending = sync.pendingCount;
    final waiting = pending == 1 ? '1 change' : '$pending changes';

    if (!sync.online) {
      return _strip(
        context,
        color: cs.errorContainer,
        onColor: cs.onErrorContainer,
        icon: Icons.cloud_off,
        text: pending == 0
            ? "You're offline. Everything you do is saved on this device and sent when you're back online."
            : "You're offline. $waiting saved on this device, they are sent when you're back online.",
      );
    }
    if (sync.syncing && pending > 0) {
      return _strip(
        context,
        color: cs.secondaryContainer,
        onColor: cs.onSecondaryContainer,
        icon: Icons.sync,
        text: 'Syncing $waiting...',
        progress: true,
      );
    }
    if (pending > 0 && sync.signedIn) {
      return _strip(
        context,
        color: cs.secondaryContainer,
        onColor: cs.onSecondaryContainer,
        icon: Icons.cloud_upload_outlined,
        text: '$waiting waiting to sync',
        action: TextButton(
          onPressed: sync.syncAll,
          child: const Text('Sync now'),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _strip(
    BuildContext context, {
    required Color color,
    required Color onColor,
    required IconData icon,
    required String text,
    bool progress = false,
    Widget? action,
  }) {
    return Material(
      color: color,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (progress) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(icon, size: 18, color: onColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(color: onColor, fontSize: 12.5),
                  ),
                ),
                if (action != null) action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
