import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_models.dart';
import 'campaign_progress.dart';
import 'stage_definition.dart';

/// Aggregate of everything persisted under one SharedPreferences key.
///
/// `CampaignProgress` (stage results, Endless bests) and the character
/// profile — `ownedLevels` plus the ordered `squad` — are saved atomically:
/// splitting them across two keys would invite save-tearing bugs. See the
/// HPA-922 spec "Profile and persistence" section.
class CampaignSave {
  CampaignSave({
    required this.progress,
    required Map<Character, int> ownedLevels,
    required List<Character> squad,
  }) : ownedLevels = Map.unmodifiable(ownedLevels),
       squad = List.unmodifiable(squad);

  final CampaignProgress progress;

  /// Owned characters mapped to their persistent level
  /// (1–[GameBalance.characterMaxLevel]).
  final Map<Character, int> ownedLevels;

  /// Ordered squad roster — distinct members of [ownedLevels], at most
  /// [GameBalance.squadMaxSize] entries.
  final List<Character> squad;

  /// A copy of this save with the ordered squad replaced — the single
  /// committed-base write the stage briefing issues on Launch (HPA-922
  /// task 6). Progress and roster levels ride along untouched.
  CampaignSave withSquad(List<Character> draft) =>
      CampaignSave(progress: progress, ownedLevels: ownedLevels, squad: draft);

  /// Fresh-profile starters (HPA-922): aliases [GameBalance]'s single
  /// canonical definition.
  static const Map<Character, int> starterOwnedLevels =
      GameBalance.starterOwnedLevels;
  static const List<Character> starterSquad = GameBalance.starterSquad;

  // `static const` is impossible here because `CampaignProgress` wraps its
  // inputs in `Map.unmodifiable` (not const). `static final` preserves the
  // "one shared empty instance" intent — the wrapped objects are deeply
  // immutable.
  static final CampaignSave empty = CampaignSave(
    progress: CampaignProgress(),
    ownedLevels: starterOwnedLevels,
    squad: starterSquad,
  );
}

abstract class CampaignProgressStore {
  Future<CampaignSave> load();
  Future<void> save(CampaignSave save);
  Future<void> reset();
}

class CampaignProgressCodec {
  const CampaignProgressCodec._();

  static const int _version = 4;

  static String encode(CampaignSave save) {
    final stageIds = save.progress.bestResultsByStageId.keys.toList()..sort();
    final stageResults = <String, Object>{};
    for (final stageId in stageIds) {
      stageResults[stageId] = save.progress.bestResultsByStageId[stageId]!
          .toJson();
    }

    final endlessIds = save.progress.endlessBestByStageId.keys.toList()..sort();
    final endlessBest = <String, Object>{};
    for (final stageId in endlessIds) {
      endlessBest[stageId] = save.progress.endlessBestByStageId[stageId]!;
    }

    // `Character.name` is the stable save key; sorting keeps the payload
    // deterministic regardless of map insertion order.
    final ownedEntries = save.ownedLevels.entries.toList()
      ..sort((a, b) => a.key.name.compareTo(b.key.name));
    final ownedCharacters = <String, Object>{
      for (final entry in ownedEntries) entry.key.name: entry.value,
    };

    return jsonEncode({
      'version': _version,
      'stageResults': stageResults,
      'endlessBest': endlessBest,
      'ownedCharacters': ownedCharacters,
      'squad': [for (final member in save.squad) member.name],
    });
  }

  static CampaignSave decode(
    String? source, {
    required Iterable<StageDefinition> knownStages,
  }) {
    if (source == null || source.isEmpty) {
      return CampaignSave.empty;
    }

    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?>) {
        return CampaignSave.empty;
      }

      // Only v4 is readable. Versions 1–3 carried cleared-stage ids or tech
      // purchases that predate the character profile; they — and any unknown
      // or absent version — start a fresh two-starter profile rather than
      // migrate (HPA-922).
      if (decoded['version'] != _version) {
        return CampaignSave.empty;
      }

      final ownedLevels = _decodeOwnedCharacters(decoded['ownedCharacters']);
      return CampaignSave(
        progress: _decodeProgress(decoded, knownStages: knownStages),
        ownedLevels: ownedLevels,
        squad: _decodeSquad(decoded['squad'], ownedLevels),
      );
    } on FormatException {
      return CampaignSave.empty;
    } on TypeError {
      return CampaignSave.empty;
    }
  }

  static CampaignProgress _decodeProgress(
    Map<String, Object?> decoded, {
    required Iterable<StageDefinition> knownStages,
  }) {
    final knownIds = knownStages.map((stage) => stage.id).toSet();
    final rawResults = decoded['stageResults'];
    final results = <String, StageResult>{};
    if (rawResults is Map<String, Object?>) {
      for (final entry in rawResults.entries) {
        if (!knownIds.contains(entry.key)) {
          continue;
        }
        final result = StageResult.fromJson(entry.value);
        if (result == null) {
          continue;
        }
        results[entry.key] = result;
      }
    }
    // Endless records decode independently of mission results: a malformed
    // `stageResults` must not discard valid `endlessBest` entries, or the
    // next save would permanently overwrite them.
    final endlessBest = _decodeEndlessBest(decoded['endlessBest'], knownIds);
    return CampaignProgress(
      bestResultsByStageId: results,
      endlessBestByStageId: endlessBest,
    );
  }

  static Map<String, int> _decodeEndlessBest(
    Object? raw,
    Set<String> knownIds,
  ) {
    if (raw is! Map<String, Object?>) {
      return const <String, int>{};
    }
    final bests = <String, int>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (!knownIds.contains(entry.key) || value is! int || value <= 0) {
        continue;
      }
      bests[entry.key] = value;
    }
    return bests;
  }

  // Character ids are decoded only here, via `Character.values.asNameMap()` —
  // nowhere else may turn save strings back into enum values.
  static Map<Character, int> _decodeOwnedCharacters(Object? raw) {
    if (raw is Map<String, Object?>) {
      final characters = Character.values.asNameMap();
      final owned = <Character, int>{};
      for (final entry in raw.entries) {
        final character = characters[entry.key];
        final level = entry.value;
        if (character == null ||
            level is! int ||
            level < 1 ||
            level > GameBalance.characterMaxLevel) {
          continue;
        }
        owned[character] = level;
      }
      if (owned.isNotEmpty) {
        return owned;
      }
    }
    // A missing, malformed, or fully invalid roster restores the two
    // starters so the profile is never left owning nothing.
    return CampaignSave.starterOwnedLevels;
  }

  static List<Character> _decodeSquad(
    Object? raw,
    Map<Character, int> ownedLevels,
  ) {
    if (raw is! List) {
      return const <Character>[];
    }
    final characters = Character.values.asNameMap();
    final squad = <Character>[];
    for (final entry in raw) {
      if (squad.length >= GameBalance.squadMaxSize) {
        break;
      }
      if (entry is! String) {
        continue;
      }
      final character = characters[entry];
      if (character == null ||
          !ownedLevels.containsKey(character) ||
          squad.contains(character)) {
        continue;
      }
      squad.add(character);
    }
    return squad;
  }
}

class SharedPreferencesCampaignProgressStore implements CampaignProgressStore {
  SharedPreferencesCampaignProgressStore({
    required SharedPreferences preferences,
    required Iterable<StageDefinition> knownStages,
    String key = 'orion.campaign.progress',
  }) : this._(preferences, knownStages: knownStages, key: key);

  SharedPreferencesCampaignProgressStore._(
    this._preferences, {
    required Iterable<StageDefinition> knownStages,
    required this.key,
  }) : _knownStages = List.unmodifiable(knownStages);

  final SharedPreferences _preferences;
  final List<StageDefinition> _knownStages;
  final String key;

  @override
  Future<CampaignSave> load() async {
    final String? source;
    try {
      source = _preferences.getString(key);
    } on TypeError {
      return CampaignSave.empty;
    }
    return CampaignProgressCodec.decode(source, knownStages: _knownStages);
  }

  @override
  Future<void> save(CampaignSave save) async {
    final persisted = await _preferences.setString(
      key,
      CampaignProgressCodec.encode(save),
    );
    if (!persisted) {
      throw StateError('Failed to save campaign progress.');
    }
  }

  @override
  Future<void> reset() async {
    final persisted = await _preferences.remove(key);
    if (!persisted) {
      throw StateError('Failed to reset campaign progress.');
    }
  }
}

class InMemoryCampaignProgressStore implements CampaignProgressStore {
  InMemoryCampaignProgressStore({
    required Iterable<StageDefinition> knownStages,
  }) : _knownStages = List.unmodifiable(knownStages);

  final List<StageDefinition> _knownStages;
  String? _source;

  @override
  Future<CampaignSave> load() async {
    return CampaignProgressCodec.decode(_source, knownStages: _knownStages);
  }

  @override
  Future<void> save(CampaignSave save) async {
    _source = CampaignProgressCodec.encode(save);
  }

  @override
  Future<void> reset() async {
    _source = null;
  }
}
