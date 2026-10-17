import 'package:shared_preferences/shared_preferences.dart';

abstract interface class FirstMissionGuideStore {
  Future<bool> loadCompleted();
  Future<void> setCompleted(bool completed);
}

class SharedPreferencesFirstMissionGuideStore
    implements FirstMissionGuideStore {
  SharedPreferencesFirstMissionGuideStore({required this.preferences});

  static const key = 'orion.firstMissionGuide';

  final SharedPreferences preferences;

  @override
  Future<bool> loadCompleted() async {
    try {
      return preferences.getBool(key) ?? false;
    } on TypeError {
      // A non-bool value stored under key (e.g. a stray string) makes
      // SharedPreferences.getBool throw before the fallback is reached.
      return false;
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
  InMemoryFirstMissionGuideStore({this.completed = false});

  bool completed;

  @override
  Future<bool> loadCompleted() async => completed;

  @override
  Future<void> setCompleted(bool completed) async {
    this.completed = completed;
  }
}
