import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_models.dart';
import '../rules/flare_rules.dart';
import 'campaign_progress.dart';
import 'stage_definition.dart';

/// Aggregate of everything persisted under one SharedPreferences key.
///
/// `CampaignProgress` (stage results, Endless bests), the character
/// profile — `ownedLevels` plus the ordered `squad` — and the Scrip
/// wallet are saved atomically: splitting them across two keys would
/// invite save-tearing bugs. See the HPA-922 spec "Profile and
/// persistence" section and HPA-923 "Scrip economy".
class CampaignSave {
  CampaignSave({
    required this.progress,
    required Map<Character, int> ownedLevels,
    required List<Character> squad,
    required this.scrip,
  }) : ownedLevels = Map.unmodifiable(ownedLevels),
       squad = List.unmodifiable(squad) {
    // The wallet can never be negative — rejecting at construction means
    // copyWith and every transform fail fast instead of persisting an
    // invalid profile that would silently decode to zero on reload.
    if (scrip < 0) {
      throw ArgumentError.value(scrip, 'scrip', 'must be nonnegative');
    }
  }

  final CampaignProgress progress;

  /// Owned characters mapped to their persistent level
  /// (1–[GameBalance.characterMaxLevel]).
  final Map<Character, int> ownedLevels;

  /// Ordered squad roster — distinct members of [ownedLevels], at most
  /// [GameBalance.squadMaxSize] entries.
  final List<Character> squad;

  /// Persistent Scrip wallet (HPA-923): mission awards and flare duplicate
  /// refunds add to it; level ups and flare packs spend from it.
  final int scrip;

  /// A copy of this save with the given fields replaced. Copying — never a
  /// partial reconstruction — is the only way writes may rebuild the
  /// aggregate, so no operation can accidentally zero the wallet or drop
  /// the roster.
  CampaignSave copyWith({
    CampaignProgress? progress,
    Map<Character, int>? ownedLevels,
    List<Character>? squad,
    int? scrip,
  }) {
    return CampaignSave(
      progress: progress ?? this.progress,
      ownedLevels: ownedLevels ?? this.ownedLevels,
      squad: squad ?? this.squad,
      scrip: scrip ?? this.scrip,
    );
  }

  /// A copy of this save with the ordered squad replaced — the single
  /// committed-base write the stage briefing issues on Launch (HPA-922
  /// task 6). Progress, roster levels and the wallet ride along untouched.
  CampaignSave withSquad(List<Character> draft) => copyWith(squad: draft);

  /// Raises [character]'s persistent level by one, debiting
  /// [GameBalance.levelUpCost] from the wallet. Throws [StateError] when
  /// the character is unowned, already at the level cap, or the wallet
  /// cannot cover the cost — the save is never left half-mutated.
  ///
  /// [expectedLevel] is the level the caller priced the purchase at; when
  /// it no longer matches the committed level the request went stale under
  /// an earlier write and rejects without a debit rather than charging the
  /// next level's cost.
  CampaignSave withLevelUp(Character character, {int? expectedLevel}) {
    final level = ownedLevels[character];
    if (level == null) {
      throw StateError('Cannot level up unowned ${character.name}.');
    }
    if (expectedLevel != null && level != expectedLevel) {
      throw StateError(
        'Level up for ${character.name} was priced at level '
        '$expectedLevel; committed level is $level.',
      );
    }
    final cost = GameBalance.levelUpCost(level);
    if (cost == null) {
      throw StateError(
        '${character.name} is already at the level cap '
        '(${GameBalance.characterMaxLevel}).',
      );
    }
    if (scrip < cost) {
      throw StateError(
        'Level up for ${character.name} costs $cost Scrip; only $scrip '
        'available.',
      );
    }
    return copyWith(
      scrip: scrip - cost,
      ownedLevels: {...ownedLevels, character: level + 1},
    );
  }

  /// Applies a rolled [FlareBatch]: charges the pack upfront, adds every
  /// NEW recruit at level 1 and credits every DUPLICATE's Scrip refund.
  ///
  /// The batch is replayed against this save's roster — earlier draws in
  /// the batch count as owned for later ones — so a stale or hand-built
  /// outcome (wrong NEW/DUPLICATE flag, a refund that does not match
  /// [GameBalance.flareDuplicateScripRefund] for the draw's rank) throws
  /// [StateError] even when the wallet could afford the pack.
  CampaignSave withFlareBatch(FlareBatch batch) {
    if (!FlareRules.allowedPackCounts.contains(batch.draws.length)) {
      throw StateError(
        'Flare pack size ${batch.draws.length} is not one of '
        '${FlareRules.allowedPackCounts}.',
      );
    }
    if (scrip < batch.cost) {
      throw StateError(
        'Flare pack costs ${batch.cost} Scrip; only $scrip available.',
      );
    }

    final owned = Set<Character>.of(ownedLevels.keys);
    final updatedOwnedLevels = Map<Character, int>.of(ownedLevels);
    for (final draw in batch.draws) {
      final expectedIsNew = !owned.contains(draw.character);
      if (draw.isNew != expectedIsNew) {
        throw StateError(
          'Flare draw for ${draw.character.name} was classified '
          '${draw.isNew ? 'NEW' : 'DUPLICATE'} but replays as '
          '${expectedIsNew ? 'NEW' : 'DUPLICATE'} against the committed '
          'roster.',
        );
      }
      final expectedRefund = expectedIsNew
          ? 0
          : GameBalance.flareDuplicateScripRefund[draw.rank]!;
      if (draw.scripRefund != expectedRefund) {
        throw StateError(
          'Flare draw for ${draw.character.name} declares refund '
          '${draw.scripRefund}; expected $expectedRefund.',
        );
      }
      if (expectedIsNew) {
        owned.add(draw.character);
        updatedOwnedLevels[draw.character] = 1;
      }
    }

    return copyWith(
      scrip: scrip - batch.cost + batch.totalScripRefund,
      ownedLevels: updatedOwnedLevels,
    );
  }

  /// Records a mission victory: [result] competes for the stage's saved
  /// best via [CampaignProgress.recordResult] and the captured
  /// [scripAward] is credited — even when the stored best does not
  /// improve. Throws [StateError] on a negative award.
  CampaignSave withMissionWin(
    String stageId,
    StageResult result,
    int scripAward,
  ) {
    if (scripAward < 0) {
      throw StateError('Mission Scrip award must be nonnegative.');
    }
    return copyWith(
      progress: progress.recordResult(stageId, result),
      scrip: scrip + scripAward,
    );
  }

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
    scrip: 0,
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
      'scrip': save.scrip,
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
        scrip: _decodeScrip(decoded['scrip']),
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

  /// The wallet tolerates a missing or malformed `scrip` field — v4 saves
  /// written before Scrip existed and hand-edited values alike read as a
  /// 0-Scrip wallet while the rest of the record decodes normally.
  static int _decodeScrip(Object? raw) {
    return raw is int && raw >= 0 ? raw : 0;
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
    // The legacy SharedPreferences write path mutates its in-memory cache
    // before the platform store reports the result, so a write the platform
    // rejects — `false` or thrown — leaves the cache ahead of durable
    // storage for every store sharing the instance. Refresh before every
    // read: durable storage is the only trustworthy source, and a failed
    // refresh must surface rather than return data the platform cannot
    // confirm.
    await _preferences.reload();
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
