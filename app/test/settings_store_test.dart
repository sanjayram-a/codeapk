import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_app/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SettingsStore> store([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    return SettingsStore(await SharedPreferences.getInstance());
  }

  test('defaults', () async {
    final s = await store();
    expect(s.idleMinutes, 15);
    expect(s.consentAccepted, isFalse);
  });

  test('idle minutes are clamped to 1..240', () async {
    final s = await store();
    await s.setIdleMinutes(0);
    expect(s.idleMinutes, 1);
    await s.setIdleMinutes(9999);
    expect(s.idleMinutes, 240);
    await s.setIdleMinutes(30);
    expect(s.idleMinutes, 30);
  });

  test('a stored out-of-range value is clamped when read', () async {
    final s = await store({'idle_minutes': 100000});
    expect(s.idleMinutes, 240);
  });

  test('consent persists across store instances on the same prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await SettingsStore(prefs).acceptConsent();
    expect(SettingsStore(prefs).consentAccepted, isTrue);
  });
}
