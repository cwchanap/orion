import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'campaign_progress.dart';
import 'stage_definition.dart';
import 'tech_tree.dart';

/// Aggregate of everything persisted under one SharedPreferences key.
///
/// `CampaignProgress` (stage results) and `CampaignTechTree` (purchased
/// upgrades) are saved atomically — splitting them across two keys would
/// invite save-tearing bugs and complicate the v2 → v3 migration. See HPA-100
/// spec "Persistence" section.
class CampaignSave {
  const CampaignSave({required this.progress, required this.techTree});

  final CampaignProgress progress;
  final CampaignTechTree techTree;

  // `static const` is impossible here because `CampaignProgress` and
  // `CampaignTechTree` default constructors are non-`const` (they wrap their
  // inputs in `Map.unmodifiable` / `Set.unmodifiable`, which are not const).
  // `static final` preserves the "one shared empty instance" intent — both
  // wrapped objects are deeply immutable.
  static final CampaignSave empty = CampaignSave(
    progress: CampaignProgress(),
    techTree: CampaignTechTree(),
  );
}

abstract class CampaignProgressStore {
  Future<CampaignSave> load();
  Future<void> save(CampaignSave save);
  Future<void> reset();
}

class CampaignProgressCodec {
  const CampaignProgressCodec._();

  static String encode(CampaignSave save) {
    final stageIds = save.progress.bestResultsByStageId.keys.toList()..sort();
    final stageResults = <String, Object>{};
    for (final stageId in stageIds) {
      stageResults[stageId] = save.progress.bestResultsByStageId[stageId]!
          .toJson();
    }

    return jsonEncode({
      'version': 3,
      'stageResults': stageResults,
      'techPurchases': save.techTree.toIdList(),
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

      final version = decoded['version'];
      if (version == 1) {
        return CampaignSave(
          progress: _decodeVersionOne(decoded, knownStages: knownStages),
          techTree: CampaignTechTree(),
        );
      }
      if (version == 2) {
        return CampaignSave(
          progress: _decodeStageResults(decoded, knownStages: knownStages),
          techTree: CampaignTechTree(),
        );
      }
      if (version != 3) {
        // Unknown future version: return empty save (existing policy).
        return CampaignSave.empty;
      }

      return CampaignSave(
        progress: _decodeStageResults(decoded, knownStages: knownStages),
        techTree: _decodeTechPurchases(decoded['techPurchases']),
      );
    } on FormatException {
      return CampaignSave.empty;
    } on TypeError {
      return CampaignSave.empty;
    }
  }

  static CampaignProgress _decodeStageResults(
    Map<String, Object?> decoded, {
    required Iterable<StageDefinition> knownStages,
  }) {
    final rawResults = decoded['stageResults'];
    if (rawResults is! Map<String, Object?>) {
      return CampaignProgress();
    }
    final knownIds = knownStages.map((stage) => stage.id).toSet();
    final results = <String, StageResult>{};
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
    return CampaignProgress(bestResultsByStageId: results);
  }

  static CampaignTechTree _decodeTechPurchases(Object? raw) {
    if (raw is! List) {
      return CampaignTechTree();
    }
    final ids = raw.whereType<String>().toList();
    return CampaignTechTree.fromIdList(ids);
  }

  static CampaignProgress _decodeVersionOne(
    Map<String, Object?> decoded, {
    required Iterable<StageDefinition> knownStages,
  }) {
    final rawIds = decoded['clearedStageIds'];
    if (rawIds is! List) {
      return CampaignProgress();
    }
    final knownIds = knownStages.map((stage) => stage.id).toSet();
    final results = <String, StageResult>{};
    for (final id in rawIds.whereType<String>()) {
      if (!knownIds.contains(id) || results.containsKey(id)) {
        continue;
      }
      results[id] = const StageResult(
        medal: StageMedal.clear,
        bestBaseHealth: 0,
      );
    }
    return CampaignProgress(bestResultsByStageId: results);
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
