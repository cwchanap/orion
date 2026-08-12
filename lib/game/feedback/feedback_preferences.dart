import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class FeedbackPreferences {
  const FeedbackPreferences({
    this.soundEffectsEnabled = true,
    this.hapticsEnabled = true,
  });

  final bool soundEffectsEnabled;
  final bool hapticsEnabled;

  FeedbackPreferences copyWith({
    bool? soundEffectsEnabled,
    bool? hapticsEnabled,
  }) {
    return FeedbackPreferences(
      soundEffectsEnabled: soundEffectsEnabled ?? this.soundEffectsEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedbackPreferences &&
          soundEffectsEnabled == other.soundEffectsEnabled &&
          hapticsEnabled == other.hapticsEnabled;

  @override
  int get hashCode => Object.hash(soundEffectsEnabled, hapticsEnabled);
}

abstract interface class FeedbackPreferencesStore {
  Future<FeedbackPreferences> load();
  Future<void> save(FeedbackPreferences preferences);
}

class SharedPreferencesFeedbackPreferencesStore
    implements FeedbackPreferencesStore {
  SharedPreferencesFeedbackPreferencesStore({required this.preferences});

  static const key = 'orion.feedback';

  final SharedPreferences preferences;

  @override
  Future<FeedbackPreferences> load() async {
    try {
      return _decode(preferences.getString(key));
    } on TypeError {
      // A non-string value stored under key (e.g. a stray bool) makes
      // SharedPreferences.getString throw before _decode is reached.
      return const FeedbackPreferences();
    }
  }

  @override
  Future<void> save(FeedbackPreferences value) async {
    final persisted = await preferences.setString(
      key,
      jsonEncode({
        'soundEffects': value.soundEffectsEnabled,
        'haptics': value.hapticsEnabled,
      }),
    );
    if (!persisted) {
      throw StateError('Failed to save feedback preferences.');
    }
  }
}

FeedbackPreferences _decode(String? source) {
  if (source == null || source.isEmpty) {
    return const FeedbackPreferences();
  }
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      return const FeedbackPreferences();
    }
    final sound = decoded['soundEffects'];
    final haptics = decoded['haptics'];
    if (sound is! bool || haptics is! bool) {
      return const FeedbackPreferences();
    }
    return FeedbackPreferences(
      soundEffectsEnabled: sound,
      hapticsEnabled: haptics,
    );
  } on FormatException {
    return const FeedbackPreferences();
  } on TypeError {
    return const FeedbackPreferences();
  }
}

class InMemoryFeedbackPreferencesStore implements FeedbackPreferencesStore {
  InMemoryFeedbackPreferencesStore({this.value = const FeedbackPreferences()});

  FeedbackPreferences value;

  @override
  Future<FeedbackPreferences> load() async => value;

  @override
  Future<void> save(FeedbackPreferences preferences) async {
    value = preferences;
  }
}
