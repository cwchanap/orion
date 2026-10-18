import 'package:shared_preferences/shared_preferences.dart';

abstract interface class FirstMissionGuideStore {
  /// `null` when no record exists or the stored value is unreadable —
  /// callers resolve that through campaign progress instead of a default.
  Future<bool?> loadCompleted();
  Future<void> setCompleted(bool completed);
}

class SharedPreferencesFirstMissionGuideStore
    implements FirstMissionGuideStore {
  SharedPreferencesFirstMissionGuideStore({required this.preferences});

  static const key = 'orion.firstMissionGuide';

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
}

class InMemoryFirstMissionGuideStore implements FirstMissionGuideStore {
  InMemoryFirstMissionGuideStore({this.completed});

  /// `null` models a never-written record, matching a fresh install.
  bool? completed;

  @override
  Future<bool?> loadCompleted() async => completed;

  @override
  Future<void> setCompleted(bool completed) async {
    this.completed = completed;
  }
}
