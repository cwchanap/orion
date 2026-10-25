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
}

class SharedPreferencesFirstMissionGuideStore
    implements FirstMissionGuideStore {
  SharedPreferencesFirstMissionGuideStore({required this.preferences});

  static const key = 'orion.firstMissionGuide';

  /// Sorted `ContextualTip.name` strings; unknown IDs are dropped on read
  /// but preserved on write (a newer build's IDs outlive this build's
  /// acknowledgements — including an explicit replay clear).
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
    // Writes replace the whole record, so unrecognized names already on
    // disk are re-emitted: an ID written by a NEWER build must survive
    // this build's acknowledgements, or upgrading back re-teaches tips
    // the player already dismissed. A value this build cannot even read
    // as a string list has nothing preservable — the write self-heals it.
    final known = ContextualTip.values.asNameMap();
    List<String>? stored;
    try {
      stored = preferences.getStringList(tipsKey);
    } on TypeError {
      stored = null;
    }
    final names = <String>{
      for (final name in stored ?? const <String>[])
        if (!known.containsKey(name)) name,
      for (final tip in tips) tip.name,
    }.toList()..sort();
    final persisted = await preferences.setStringList(tipsKey, names);
    if (!persisted) {
      throw StateError('Failed to save contextual tips.');
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
}
