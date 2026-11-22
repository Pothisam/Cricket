import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Firebase options. Android/iOS read their config from google-services.json /
/// GoogleService-Info.plist, so only web needs explicit options.
class DefaultFirebaseOptions {
  static FirebaseOptions? get currentPlatform => kIsWeb ? web : null;

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD1Qnpolmguy_ELPYUEKkpvQXR8-ypAfiw',
    authDomain: 'cricket-run-notification.firebaseapp.com',
    projectId: 'cricket-run-notification',
    storageBucket: 'cricket-run-notification.firebasestorage.app',
    messagingSenderId: '592739044483',
    appId: '1:592739044483:web:1215037c8c4428b2e21fb6',
    measurementId: 'G-1Y3G110K8Z',
  );
}
