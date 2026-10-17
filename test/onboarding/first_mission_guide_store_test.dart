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

    test('loads false when the key is missing', () async {
      final store = await _store({});

      expect(await store.loadCompleted(), isFalse);
    });

    test('setCompleted(true) round-trips true', () async {
      final store = await _store({});

      await store.setCompleted(true);

      expect(await store.loadCompleted(), isTrue);
    });

    test('setCompleted(false) clears back to false', () async {
      final store = await _store({});
      await store.setCompleted(true);

      await store.setCompleted(false);

      expect(await store.loadCompleted(), isFalse);
    });

    test(
      'unexpected non-bool data under the key falls back to false',
      () async {
        final store = await _store(<String, Object>{
          SharedPreferencesFirstMissionGuideStore.key: 'yes',
        });

        expect(await store.loadCompleted(), isFalse);
      },
    );
  });

  group('InMemoryFirstMissionGuideStore', () {
    test('starts false and round-trips true and false', () async {
      final store = InMemoryFirstMissionGuideStore();

      expect(await store.loadCompleted(), isFalse);

      await store.setCompleted(true);
      expect(await store.loadCompleted(), isTrue);

      await store.setCompleted(false);
      expect(await store.loadCompleted(), isFalse);
    });
  });
}
