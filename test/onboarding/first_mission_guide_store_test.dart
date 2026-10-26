import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/onboarding/contextual_tips.dart';
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

/// setCompleted always rejects so resetForReplay's rollback can be
/// observed against the real SharedPreferences write path.
class _FailingCompletionPrefsStore
    extends SharedPreferencesFirstMissionGuideStore {
  _FailingCompletionPrefsStore({required super.preferences});

  @override
  Future<void> setCompleted(bool completed) =>
      Future.error(StateError('simulated persistence failure'));
}

/// The same failure against the in-memory implementation.
class _FailingCompletionInMemoryStore extends InMemoryFirstMissionGuideStore {
  _FailingCompletionInMemoryStore({super.completed, super.seenTips});

  @override
  Future<void> setCompleted(bool completed) =>
      Future.error(StateError('simulated persistence failure'));
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

  group('SharedPreferences seen tips', () {
    test('exposes the persistence key', () {
      expect(
        SharedPreferencesFirstMissionGuideStore.tipsKey,
        'orion.contextualTips',
      );
    });

    test('loads empty when the key is missing', () async {
      final store = await _store({});

      expect(await store.loadSeenTips(), isEmpty);
    });

    test('loads empty when the stored value is unreadable', () async {
      final store = await _store(<String, Object>{
        SharedPreferencesFirstMissionGuideStore.tipsKey: true,
      });

      expect(await store.loadSeenTips(), isEmpty);
    });

    test('persists sorted enum names and reads them back typed', () async {
      final store = await _store({});

      await store.setSeenTips({
        ContextualTip.droneBay,
        ContextualTip.bossWave,
        ContextualTip.targeting,
      });

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getStringList(
          SharedPreferencesFirstMissionGuideStore.tipsKey,
        ),
        ['bossWave', 'droneBay', 'targeting'],
      );
      expect(await store.loadSeenTips(), {
        ContextualTip.bossWave,
        ContextualTip.droneBay,
        ContextualTip.targeting,
      });
    });

    test('drops unknown stored names', () async {
      final store = await _store({
        SharedPreferencesFirstMissionGuideStore.tipsKey: <String>[
          'bossWave',
          'notATip',
        ],
      });

      expect(await store.loadSeenTips(), {ContextualTip.bossWave});
    });

    test('writes preserve unknown IDs already on disk', () async {
      // A newer build's tip IDs must survive this build's
      // acknowledgements: writes replace the whole record, so dropping
      // them here would re-teach tips the player already dismissed.
      final store = await _store({
        SharedPreferencesFirstMissionGuideStore.tipsKey: <String>[
          'bossWave',
          'tipFromNewerBuild',
        ],
      });

      // The real flow: the seen set loads typed ({bossWave}) and an
      // acknowledgement writes its union — the unknown ID rides along.
      await store.setSeenTips({
        ContextualTip.bossWave,
        ContextualTip.targeting,
      });

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getStringList(
          SharedPreferencesFirstMissionGuideStore.tipsKey,
        ),
        ['bossWave', 'targeting', 'tipFromNewerBuild'],
      );
      // The unknown ID still stays out of the typed read…
      expect(await store.loadSeenTips(), {
        ContextualTip.bossWave,
        ContextualTip.targeting,
      });

      // …but an explicit empty-set write is the Replay Tutorial reset: it
      // clears the ENTIRE record, unknown IDs included — a reset that
      // preserved them could never replay those tips.
      await store.setSeenTips(const {});
      expect(
        preferences.getStringList(
          SharedPreferencesFirstMissionGuideStore.tipsKey,
        ),
        isEmpty,
      );
    });

    test('an unreadable stored record self-heals on write', () async {
      final store = await _store(<String, Object>{
        SharedPreferencesFirstMissionGuideStore.tipsKey: true,
      });

      await store.setSeenTips({ContextualTip.bossWave});

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getStringList(
          SharedPreferencesFirstMissionGuideStore.tipsKey,
        ),
        ['bossWave'],
      );
    });

    test('leaves the original guide flag record untouched', () async {
      final store = await _store({});

      await store.setSeenTips({ContextualTip.bossWave});

      expect(await store.loadCompleted(), isNull);
      await store.setCompleted(true);
      expect(await store.loadCompleted(), isTrue);
      expect(await store.loadSeenTips(), {ContextualTip.bossWave});
    });
  });

  group('resetForReplay', () {
    test('clears the entire record and the guide flag on success', () async {
      final store = await _store(<String, Object>{
        SharedPreferencesFirstMissionGuideStore.key: true,
        SharedPreferencesFirstMissionGuideStore.tipsKey: <String>[
          'bossWave',
          'tipFromNewerBuild',
        ],
      });

      await store.resetForReplay();

      final preferences = await SharedPreferences.getInstance();
      // A successful reset clears EVERYTHING — unknown newer-build IDs
      // included — or it could never replay those tips.
      expect(
        preferences.getStringList(
          SharedPreferencesFirstMissionGuideStore.tipsKey,
        ),
        isEmpty,
      );
      expect(await store.loadSeenTips(), isEmpty);
      expect(await store.loadCompleted(), isFalse);
    });

    test(
      'a failed reset restores the raw record, unknown IDs included',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          SharedPreferencesFirstMissionGuideStore.key: true,
          SharedPreferencesFirstMissionGuideStore.tipsKey: <String>[
            'bossWave',
            'tipFromNewerBuild',
          ],
        });
        final preferences = await SharedPreferences.getInstance();
        final store = _FailingCompletionPrefsStore(preferences: preferences);

        await expectLater(store.resetForReplay(), throwsStateError);

        // The clear landed but setCompleted threw: the rollback must
        // restore the record verbatim — a typed restore could re-emit
        // bossWave but never tipFromNewerBuild.
        expect(
          preferences.getStringList(
            SharedPreferencesFirstMissionGuideStore.tipsKey,
          ),
          ['bossWave', 'tipFromNewerBuild'],
        );
        expect(
          preferences.getBool(SharedPreferencesFirstMissionGuideStore.key),
          isTrue,
        );
      },
    );

    test('a failed in-memory reset restores the typed seen set', () async {
      final store = _FailingCompletionInMemoryStore(
        completed: true,
        seenTips: const {ContextualTip.bossWave},
      );

      await expectLater(store.resetForReplay(), throwsStateError);

      expect(await store.loadSeenTips(), {ContextualTip.bossWave});
      expect(await store.loadCompleted(), isTrue);
    });
  });

  group('InMemory seen tips', () {
    test('seeds from the constructor and round-trips', () async {
      final seeded = InMemoryFirstMissionGuideStore(
        seenTips: {ContextualTip.bossWave},
      );
      expect(await seeded.loadSeenTips(), {ContextualTip.bossWave});

      final store = InMemoryFirstMissionGuideStore();
      expect(await store.loadSeenTips(), isEmpty);

      await store.setSeenTips({ContextualTip.targeting});
      expect(await store.loadSeenTips(), {ContextualTip.targeting});
    });

    test('loaded sets cannot be mutated through the read reference', () async {
      final store = InMemoryFirstMissionGuideStore();
      await store.setSeenTips({ContextualTip.bossWave});

      final loaded = await store.loadSeenTips();

      expect(() => loaded.add(ContextualTip.railgun), throwsUnsupportedError);
    });
  });
}
