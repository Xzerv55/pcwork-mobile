import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

/// Public Firebase app configuration is injected at build time with
/// --dart-define. Never place service-account keys or other private secrets here.
class DefaultFirebaseOptions {
  static const String _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String _messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String _androidApiKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
  static const String _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const String _iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const String _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const String _iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

  static bool get isConfigured {
    if (_projectId.isEmpty || _messagingSenderId.isEmpty) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _iosApiKey.isNotEmpty && _iosAppId.isNotEmpty;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _androidApiKey.isNotEmpty && _androidAppId.isNotEmpty;
    }
    return false;
  }

  static FirebaseOptions get currentPlatform {
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    return FirebaseOptions(
      apiKey: ios ? _iosApiKey : _androidApiKey,
      appId: ios ? _iosAppId : _androidAppId,
      messagingSenderId: _messagingSenderId,
      projectId: _projectId,
      iosBundleId: ios ? (_iosBundleId.isEmpty ? null : _iosBundleId) : null,
    );
  }
}
