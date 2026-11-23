import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/app_dependencies.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.init();
  final prefs = await SharedPreferences.getInstance();
  final deps = AppDependencies.synced(prefs);
  deps.sync?.startMonitoring(); // sync by itself when the network is back
  runApp(CricketApp(deps: deps));
}
