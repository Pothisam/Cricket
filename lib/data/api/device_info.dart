import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Body for `POST /auth/session` and `PUT /devices/token`.
Future<Map<String, dynamic>> devicePayload({
  required String deviceId,
  required String? fcmToken,
  required bool notificationsEnabled,
  String? previousToken,
}) async {
  final platform = kIsWeb
      ? 'web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => 'android',
          TargetPlatform.iOS => 'ios',
          _ => 'web',
        };
  String? model;
  String? os;
  try {
    final info = DeviceInfoPlugin();
    if (kIsWeb) {
      final w = await info.webBrowserInfo;
      model = w.browserName.name;
      os = w.platform;
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final a = await info.androidInfo;
      model = a.model;
      os = 'Android ${a.version.release}';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final i = await info.iosInfo;
      model = i.utsname.machine;
      os = 'iOS ${i.systemVersion}';
    }
  } catch (_) {}
  String? appVersion;
  try {
    final p = await PackageInfo.fromPlatform();
    appVersion = '${p.version}+${p.buildNumber}';
  } catch (_) {}

  String cut(String? v, int n) =>
      v == null ? '' : (v.length > n ? v.substring(0, n) : v);

  return {
    // The server requires a token. Web (no push yet) sends a placeholder.
    'fcmToken': (fcmToken == null || fcmToken.isEmpty)
        ? '$platform-$deviceId'
        : fcmToken,
    'deviceId': deviceId,
    'platform': platform,
    'deviceModel': cut(model, 120),
    'osVersion': cut(os, 40),
    'appVersion': cut(appVersion, 20),
    'locale': cut(PlatformDispatcher.instance.locale.toString(), 10),
    'notificationsEnabled': notificationsEnabled,
    if (previousToken != null) 'previousToken': previousToken,
  };
}
