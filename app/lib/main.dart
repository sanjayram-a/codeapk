import 'package:flutter/material.dart';
import 'package:opencode_runtime/opencode_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'app_deps.dart';
import 'settings/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(OpencodeApp(deps: AppDeps(runtime: OpencodeRuntime(), settings: SettingsStore(prefs))));
}
