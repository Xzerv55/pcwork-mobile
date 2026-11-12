import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/pcwork_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences? preferences;
  try {
    preferences = await SharedPreferences.getInstance();
  } catch (_) {
    // The app can still start with its defaults if local preferences fail.
  }
  runApp(PCWorkApp(initialPreferences: preferences));
}
