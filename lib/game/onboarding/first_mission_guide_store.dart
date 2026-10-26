import 'package:shared_preferences/shared_preferences.dart';

import 'contextual_tips.dart';

abstract interface class FirstMissionGuideStore {
  /// `null` when no record exists or the stored value is unreadable —
  /// callers resolve that through campaign progress instead of a default.
  Future<bool?> loadCompleted();
  Future<void> setCompleted(bool completed);

  /// Typed seen-tip set; empty when nothing was acknowledged yet or the
  /// stored record is missing/unreadable.
  Future<Set<ContextualTip>> loadSeenTips();
  Future<void> setSeenTips(Set<ContextualTip> tips);

  /// The Replay Tutorial reset as ONE operation: clears the seen-tip
  /// record AND marks the guide incomplete. If the completion write
  /// fails after the clear has landed, the prior tip record is restored
  /// verbatim — unknown newer-build IDs included, which the typed
  /// [setSeenTips] path could never write back — so a reported failure
  /// never leaves a partial reset behind it.
  Future<void> resetForReplay();
}

class SharedPreferencesFirstMissionGuideStore
    implements FirstMissionGuideStore {
  SharedPreferencesFirstMissionGuideStore({required this.preferences});

  static const key = 'orion.firstMissionGuide';

  /// Sorted `ContextualTip.name` strings; unknown IDs are dropped on read
  /// but preserved on non-empty writes (a newer build's IDs outlive this
  /// build's acknowledgements). An explicit empty-set write is a reset —
  /// Replay Tutorial — and clears the record entirely.
  static const tipsKey = 'orion.contextualTips';

  final SharedPreferences preferences;

  @override
  Future<bool?> loadCompleted() async {
    try {
      if (!preferences.containsKey(key)) {
        return null;
      }
      return preferences.getBool(key);
    } on TypeError {
      // A non-bool value stored under key (e.g. a stray string) makes
      // SharedPreferences.getBool throw — no usable record.
      return null;
    }
  }

  @override
  Future<void> setCompleted(bool completed) async {
    final persisted = await preferences.setBool(key, completed);
    if (!persisted) {
      throw StateError('Failed to save first mission guide completion.');
    }
  }

  @override
  Future<Set<ContextualTip>> loadSeenTips() async {
    try {
      final names = preferences.getStringList(tipsKey);
      if (names == null) {
        return const {};
      }
      final byName = ContextualTip.values.asNameMap();
      return {for (final name in names) ?byName[name]};
    } on TypeError {
      // A non-string-list value under tipsKey is unusable — no record.
      return const {};
    }
  }

  @override
  Future<void> setSeenTips(Set<ContextualTip> tips) async {
    // Non-empty writes replace the whole record, so unrecognized names
    // already on disk are re-emitted: an ID written by a NEWER build must
    // survive this build's acknowledgements, or upgrading back re-teaches
    // tips the player already dismissed. An EMPTY set is the explicit
    // Replay Tutorial reset — it clears the entire record, unknown IDs
    // included, or a "successful" reset could never replay them. A value
    // this build cannot even read as a string list has nothing
    // preservable — the write self-heals it.
    final names = <String>{for (final tip in tips) tip.name};
    if (tips.isNotEmpty) {
      final known = ContextualTip.values.asNameMap();
      List<String>? stored;
      try {
        stored = preferences.getStringList(tipsKey);
      } on TypeError {
        stored = null;
      }
      names.addAll([
        for (final name in stored ?? const <String>[])
          if (!known.containsKey(name)) name,
      ]);
    }
    final sorted = names.toList()..sort();
    final persisted = await preferences.setStringList(tipsKey, sorted);
    if (!persisted) {
      throw StateError('Failed to save contextual tips.');
    }
  }

  @override
  Future<void> resetForReplay() async {
    // Snapshot the RAW record before the clear: a downgraded build can
    // hold IDs written by a newer build, and restoring through the typed
    // setSeenTips path could never re-emit them.
    List<String>? previous;
    try {
      previous = preferences.getStringList(tipsKey);
    } on TypeError {
      previous = null; // unreadable record — nothing preservable anyway
    }
    await setSeenTips(const {});
    try {
      await setCompleted(false);
    } catch (_) {
      // The clear already persisted: roll the prior record back so a
      // reported failure leaves no partially-reset state. Best-effort —
      // the original error must still surface to the sheet.
      try {
        await preferences.setStringList(tipsKey, previous ?? const []);
      } catch (_) {}
      rethrow;
    }
  }
}

class InMemoryFirstMissionGuideStore implements FirstMissionGuideStore {
  InMemoryFirstMissionGuideStore({
    this.completed,
    Set<ContextualTip> seenTips = const {},
  }) : seenTips = Set.unmodifiable(seenTips);

  /// `null` models a never-written record, matching a fresh install.
  bool? completed;

  /// Unmodifiable snapshot; [setSeenTips] replaces the whole set.
  Set<ContextualTip> seenTips;

  @override
  Future<bool?> loadCompleted() async => completed;

  @override
  Future<void> setCompleted(bool completed) async {
    this.completed = completed;
  }

  @override
  Future<Set<ContextualTip>> loadSeenTips() async => seenTips;

  @override
  Future<void> setSeenTips(Set<ContextualTip> tips) async {
    seenTips = Set.unmodifiable(tips);
  }

  @override
  Future<void> resetForReplay() async {
    // Routed through the virtual methods so fakes that gate or fail
    // setSeenTips/setCompleted observe the same two writes as the real
    // store; the restore assigns directly so it can never hang behind a
    // test's write gate.
    final previous = seenTips;
    await setSeenTips(const {});
    try {
      await setCompleted(false);
    } catch (_) {
      seenTips = previous;
      rethrow;
    }
  }
}
