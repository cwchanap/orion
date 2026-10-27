import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class FeedbackPreferences {
  const FeedbackPreferences({
    this.soundEffectsEnabled = true,
    this.hapticsEnabled = true,
    this.musicEnabled = true,
  });

  final bool soundEffectsEnabled;
  final bool hapticsEnabled;
  final bool musicEnabled;

  FeedbackPreferences copyWith({
    bool? soundEffectsEnabled,
    bool? hapticsEnabled,
    bool? musicEnabled,
  }) {
    return FeedbackPreferences(
      soundEffectsEnabled: soundEffectsEnabled ?? this.soundEffectsEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      musicEnabled: musicEnabled ?? this.musicEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedbackPreferences &&
          soundEffectsEnabled == other.soundEffectsEnabled &&
          hapticsEnabled == other.hapticsEnabled &&
          musicEnabled == other.musicEnabled;

  @override
  int get hashCode =>
      Object.hash(soundEffectsEnabled, hapticsEnabled, musicEnabled);
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
        'music': value.musicEnabled,
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
    final music = decoded['music'];
    if (sound is! bool || haptics is! bool) {
      return const FeedbackPreferences();
    }
    return FeedbackPreferences(
      soundEffectsEnabled: sound,
      hapticsEnabled: haptics,
      musicEnabled: music is bool ? music : true,
    );
  } on FormatException {
    return const FeedbackPreferences();
  }
  // A TypeError here (e.g. an unexpected runtime type surfaced by jsonDecode)
  // propagates to load()'s `on TypeError` handler, which falls back to
  // defaults — so a duplicate catch here would be unreachable.
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
