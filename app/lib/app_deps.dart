import 'package:opencode_runtime/opencode_runtime.dart';

import 'api/opencode_api.dart';
import 'settings/settings_store.dart';

/// What the screens need from the outside world. Tests pass fakes.
class AppDeps {
  const AppDeps({required this.runtime, required this.settings, this.apiFactory = _defaultApi});

  final RuntimeApi runtime;
  final SettingsStore settings;
  final OpencodeApi Function(Uri base, String password) apiFactory;

  static OpencodeApi _defaultApi(Uri base, String password) => HttpOpencodeApi(base: base, password: password);
}
