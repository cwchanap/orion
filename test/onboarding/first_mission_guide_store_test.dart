import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/onboarding/first_mission_guide_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferencesFirstMissionGuideStore> _store(
  Map<String, Object> values,
) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferencesFirstMissionGuideStore(
    preferences: await SharedPreferences.getInstance(),
  );
}

void main() {
  group('SharedPreferencesFirstMissionGuideStore', () {
    test('exposes the persistence key', () {
      expect(
        SharedPreferencesFirstMissionGuideStore.key,
        'orion.firstMissionGuide',
      );
    });

    test('loads null when the key is missing (no record)', () async {
      final store = await _store({});

      expect(await store.loadCompleted(), isNull);
    });

    test('setCompleted(true) round-trips true', () async {
      final store = await _store({});

      await store.setCompleted(true);

      expect(await store.loadCompleted(), isTrue);
    });

    test('setCompleted(false) writes back an explicit false', () async {
      final store = await _store({});
      await store.setCompleted(true);

      await store.setCompleted(false);

      // An explicit false is a real record — not the same as no record —
      // so replay survives restarts instead of resolving through progress.
      expect(await store.loadCompleted(), isFalse);
    });

    test('unexpected non-bool data under the key loads null', () async {
      final store = await _store(<String, Object>{
        SharedPreferencesFirstMissionGuideStore.key: 'yes',
      });

      expect(await store.loadCompleted(), isNull);
    });
  });

  group('InMemoryFirstMissionGuideStore', () {
    test('starts with no record and round-trips true and false', () async {
      final store = InMemoryFirstMissionGuideStore();

      expect(await store.loadCompleted(), isNull);

      await store.setCompleted(true);
      expect(await store.loadCompleted(), isTrue);

      await store.setCompleted(false);
      expect(await store.loadCompleted(), isFalse);
    });
  });
}
