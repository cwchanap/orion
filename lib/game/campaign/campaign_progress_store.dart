import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'campaign_progress.dart';
import 'stage_definition.dart';

abstract class CampaignProgressStore {
  Future<CampaignProgress> load();
  Future<void> save(CampaignProgress progress);
  Future<void> reset();
}

class CampaignProgressCodec {
  const CampaignProgressCodec._();

  static String encode(CampaignProgress progress) {
    final stageIds = progress.bestResultsByStageId.keys.toList()..sort();
    final stageResults = <String, Object>{};
    for (final stageId in stageIds) {
      stageResults[stageId] = progress.bestResultsByStageId[stageId]!.toJson();
    }

    return jsonEncode({'version': 2, 'stageResults': stageResults});
  }

  static CampaignProgress decode(
    String? source, {
    required Iterable<StageDefinition> knownStages,
  }) {
    if (source == null || source.isEmpty) {
      return CampaignProgress();
    }

    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?> || decoded['version'] != 2) {
        return CampaignProgress();
      }

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
    } on FormatException {
      return CampaignProgress();
    } on TypeError {
      return CampaignProgress();
    }
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
  Future<CampaignProgress> load() async {
    final String? source;
    try {
      source = _preferences.getString(key);
    } on TypeError {
      return CampaignProgress();
    }

    return CampaignProgressCodec.decode(source, knownStages: _knownStages);
  }

  @override
  Future<void> save(CampaignProgress progress) async {
    final persisted = await _preferences.setString(
      key,
      CampaignProgressCodec.encode(progress),
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
  Future<CampaignProgress> load() async {
    return CampaignProgressCodec.decode(_source, knownStages: _knownStages);
  }

  @override
  Future<void> save(CampaignProgress progress) async {
    _source = CampaignProgressCodec.encode(progress);
  }

  @override
  Future<void> reset() async {
    _source = null;
  }
}
