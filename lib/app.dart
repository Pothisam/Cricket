import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'data/app_dependencies.dart';
import 'services/auth_service.dart';
import 'state/auth_controller.dart';
import 'state/matches_controller.dart';
import 'state/teams_controller.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/login_screen.dart';

class CricketApp extends StatelessWidget {
  const CricketApp({super.key, required this.deps});

  final AppDependencies deps;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDependencies>.value(value: deps),
        if (deps.sync != null) ChangeNotifierProvider.value(value: deps.sync!),
        ChangeNotifierProvider(
            create: (_) => AuthController(AuthService(), sync: deps.sync)),
        ChangeNotifierProvider(
          create: (_) {
            final c = TeamsController(deps.teams, deps.players)..load();
            deps.sync?.addReloader(c.load);
            return c;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final c = MatchesController(deps.matches)..load();
            deps.sync?.addReloader(c.load);
            return c;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Cricket Scorer',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: Builder(
          builder: (context) => context.watch<AuthController>().signedIn
              ? const HomeShell()
              : const LoginScreen(),
        ),
      ),
    );
  }
}
