import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

/// Firebase credentials are supplied at build time using --dart-define.
/// Keep these values public Firebase app configuration only; never put a
/// service-account private key or other server secret in the mobile app.
class DefaultFirebaseOptions {
  static String _v(String key) => String.fromEnvironment(key);

  static bool get isConfigured {
    final common = _v('FIREBASE_PROJECT_ID').isNotEmpty &&
        _v('FIREBASE_MESSAGING_SENDER_ID').isNotEmpty;
    if (!common) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _v('FIREBASE_IOS_API_KEY').isNotEmpty &&
          _v('FIREBASE_IOS_APP_ID').isNotEmpty;
    }
    return _v('FIREBASE_ANDROID_API_KEY').isNotEmpty &&
        _v('FIREBASE_ANDROID_APP_ID').isNotEmpty;
  }

  static FirebaseOptions get currentPlatform {
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    return FirebaseOptions(
      apiKey: _v(ios ? 'FIREBASE_IOS_API_KEY' : 'FIREBASE_ANDROID_API_KEY'),
      appId: _v(ios ? 'FIREBASE_IOS_APP_ID' : 'FIREBASE_ANDROID_APP_ID'),
      messagingSenderId: _v('FIREBASE_MESSAGING_SENDER_ID'),
      projectId: _v('FIREBASE_PROJECT_ID'),
      iosBundleId: ios ? _v('FIREBASE_IOS_BUNDLE_ID') : null,
    );
  }
}
