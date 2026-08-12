import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/feedback/feedback_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// An in-memory store whose [setValue] always reports failure, so the
/// SharedPreferences-backed save path surfaces a `false` persistence result.
class _FailingSetValueSharedPreferencesStore
    extends InMemorySharedPreferencesStore {
  _FailingSetValueSharedPreferencesStore() : super.empty();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}

void main() {
  group('FeedbackPreferences', () {
    test('preferences compare by value', () {
      const a = FeedbackPreferences(
        soundEffectsEnabled: false,
        hapticsEnabled: true,
      );
      const b = FeedbackPreferences(
        soundEffectsEnabled: false,
        hapticsEnabled: true,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith can restore a changed draft', () {
      const original = FeedbackPreferences(
        soundEffectsEnabled: false,
        hapticsEnabled: true,
      );
      final changed = original.copyWith(hapticsEnabled: false);
      final restored = changed.copyWith(hapticsEnabled: true);

      expect(changed, isNot(original));
      expect(restored, original);
    });
  });

  group('SharedPreferencesFeedbackPreferencesStore', () {
    test('missing key falls back to defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesFeedbackPreferencesStore(
        preferences: preferences,
      );

      expect(await store.load(), const FeedbackPreferences());
    });

    test('all four boolean combinations round-trip through one key', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesFeedbackPreferencesStore(
        preferences: preferences,
      );

      for (final soundEffectsEnabled in [false, true]) {
        for (final hapticsEnabled in [false, true]) {
          final value = FeedbackPreferences(
            soundEffectsEnabled: soundEffectsEnabled,
            hapticsEnabled: hapticsEnabled,
          );
          await store.save(value);
          expect(await store.load(), value);
        }
      }

      expect(preferences.getKeys(), {
        SharedPreferencesFeedbackPreferencesStore.key,
      });
    });

    test('malformed persisted feedback falls back to defaults', () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesFeedbackPreferencesStore.key: '{not-json',
      });
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesFeedbackPreferencesStore(
        preferences: preferences,
      );

      expect(await store.load(), const FeedbackPreferences());
    });

    test('missing or wrong-typed fields fall back to defaults', () async {
      for (final raw in [
        '{"soundEffects":true}',
        '{"haptics":false}',
        '{"soundEffects":true,"haptics":"yes"}',
        '{"soundEffects":1,"haptics":true}',
        '[true,true]',
        'null',
      ]) {
        SharedPreferences.setMockInitialValues({
          SharedPreferencesFeedbackPreferencesStore.key: raw,
        });
        final preferences = await SharedPreferences.getInstance();
        final store = SharedPreferencesFeedbackPreferencesStore(
          preferences: preferences,
        );

        expect(await store.load(), const FeedbackPreferences());
      }
    });

    // Regression: a non-string value stored under the key (e.g. a stray
    // bool) makes SharedPreferences.getString throw a TypeError before
    // _decode is ever reached. load() must absorb that and fall back.
    test('non-string persisted value falls back to defaults', () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesFeedbackPreferencesStore.key: true,
      });
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesFeedbackPreferencesStore(
        preferences: preferences,
      );

      expect(await store.load(), const FeedbackPreferences());
    });

    // SharedPreferences.setString returns false when the platform store
    // rejects the write; the store must surface that as a StateError so
    // callers can route it through the persistence-failure breadcrumb.
    test('save throws when SharedPreferences rejects the write', () async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance =
          _FailingSetValueSharedPreferencesStore();
      addTearDown(() {
        // Restore the default in-memory store so later tests are unaffected.
        SharedPreferences.setMockInitialValues({});
      });
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesFeedbackPreferencesStore(
        preferences: preferences,
      );

      await expectLater(
        store.save(
          const FeedbackPreferences(
            soundEffectsEnabled: false,
            hapticsEnabled: true,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
