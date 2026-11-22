import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_dependencies.dart';
import '../../state/auth_controller.dart';
import '../../state/matches_controller.dart';
import '../../state/membership_controller.dart';
import '../../state/teams_controller.dart';

/// Pull down to refresh: syncs with the server (push local changes, pull the
/// others' changes) and reloads the lists. Works offline too, then it only reloads.
Future<void> refreshAll(BuildContext context) async {
  final sync = context.read<AppDependencies>().sync;
  final auth = context.read<AuthController>();
  final tc = context.read<TeamsController>();
  final mc = context.read<MatchesController>();
  final ms = context.read<MembershipController>();
  final messenger = ScaffoldMessenger.maybeOf(context);

  if (sync != null) {
    final uid = auth.user?.uid;
    if (!sync.signedIn && uid != null) {
      await sync.startSession(uid); // also syncs
    } else {
      await sync.syncAll();
    }
    final error = sync.lastError;
    if (error != null) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Could not sync: $error')));
    }
  }
  await tc.load();
  await mc.load();
  await ms.load();
}

/// Wrap the body of a screen. Any vertical list inside it (also inside tabs)
/// can be pulled down to refresh.
class PullToRefresh extends StatelessWidget {
  const PullToRefresh({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    // Tabs sit in a horizontal PageView: only react to the vertical lists inside.
    notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
    onRefresh: () => refreshAll(context),
    child: child,
  );
}

/// Lets short lists be pulled down, and the mouse drag the content (Chrome / desktop),
/// which Flutter does not allow by default.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const AlwaysScrollableScrollPhysics().applyTo(
        super.getScrollPhysics(context),
      );
}

/// A centred message that can still be pulled down (an empty list must refresh too).
class RefreshableEmpty extends StatelessWidget {
  const RefreshableEmpty({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: box.maxHeight),
        child: Center(child: child),
      ),
    ),
  );
}
