import 'package:shared_preferences/shared_preferences.dart';

/// App-level preferences: whether the user accepted the disclosure, and the server idle timeout.
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _consentKey = 'consent_accepted';
  static const _idleKey = 'idle_minutes';
  static const defaultIdleMinutes = 15;

  bool get consentAccepted => _prefs.getBool(_consentKey) ?? false;

  Future<void> acceptConsent() => _prefs.setBool(_consentKey, true);

  int get idleMinutes => (_prefs.getInt(_idleKey) ?? defaultIdleMinutes).clamp(1, 240);

  Future<void> setIdleMinutes(int minutes) => _prefs.setInt(_idleKey, minutes.clamp(1, 240));
}
