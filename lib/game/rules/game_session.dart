// The private offer picker is injected through the public factory's named
// argument to keep the private constructor inaccessible to callers.
// ignore_for_file: prefer_initializing_formals

import '../campaign/campaign_progress.dart';
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
import '../models/game_models.dart';
import 'board_layout.dart';
import 'module_offer_picker.dart';
import 'stage_modifier_rules.dart';
import 'tower_stats_resolver.dart';

class GameSession {
  factory GameSession.initial({
    StageDefinition? stage,
    CampaignModifiers campaignModifiers = CampaignModifiers.empty,
    int? gold,
    int? baseHealth,
    ModuleOfferPicker? offerPicker,
  }) {
    final resolvedStage = stage ?? OrionCampaign.stageOne;
    final resolvedGold = gold ?? campaignModifiers.adjustedStartingGold;
    final campaignAdjustedBaseHealth =
        baseHealth ?? campaignModifiers.adjustedStartingBaseHealth;
    final resolvedBaseHealth = StageModifierRules.effectiveStartingBaseHealth(
      campaignAdjustedBaseHealth: campaignAdjustedBaseHealth,
      stageModifiers: resolvedStage.modifiers,
    );
    return GameSession._(
      stage: resolvedStage,
      campaignModifiers: campaignModifiers,
      startingGold: resolvedGold,
      startingBaseHealth: resolvedBaseHealth,
      offerPicker: offerPicker ?? RandomModuleOfferPicker(),
    );
  }

  GameSession._({
    required this.stage,
    required this.campaignModifiers,
    required this.startingGold,
    required this.startingBaseHealth,
    required ModuleOfferPicker offerPicker,
  }) : _gold = startingGold,
       _baseHealth = startingBaseHealth,
       _offerPicker = offerPicker {
    if (stage.waves.isEmpty) {
      throw ArgumentError.value(
        stage.id,
        'stage',
        'Stage must define at least one wave',
      );
    }
  }

  final StageDefinition stage;
  final int startingGold;
  final int startingBaseHealth;
  final CampaignModifiers campaignModifiers;
  final ModuleOfferPicker _offerPicker;
  final Map<GridPosition, PlacedTower> _towersByPosition = {};
  final List<RunModuleId> _acquiredRunModules = [];
  int _nextTowerId = 1;
  int _gold;
  int _baseHealth;
  int _waveIndex = 0;
  RunModuleOffer? _pendingRunModuleOffer;
  int _nextModuleOfferId = 1;
  GamePhase _phase = GamePhase.build;

  int get gold => _gold;
  int get baseHealth => _baseHealth;
  int get waveIndex => _waveIndex;
  int get clearedWaveCount => _waveIndex;
  GamePhase get phase => _phase;
  List<PlacedTower> get towers => List.unmodifiable(_towersByPosition.values);
  RunModuleOffer? get pendingRunModuleOffer => _pendingRunModuleOffer;
  List<RunModuleId> get acquiredRunModules =>
      List.unmodifiable(_acquiredRunModules);
  List<TowerType> get unlockedTowerTypes {
    final nextWaveNumber = _waveIndex + 1;
    return TowerType.values
        .where((type) => GameBalance.towerUnlockWave(type) <= nextWaveNumber)
        .toList(growable: false);
  }

  WaveDefinition? get activeWave {
    if (_waveIndex >= stage.waves.length) {
      return null;
    }
    return stage.waves[_waveIndex];
  }

  bool isTowerUnlocked(TowerType type) => unlockedTowerTypes.contains(type);

  bool get _canMutateBuild =>
      _phase == GamePhase.build && _pendingRunModuleOffer == null;

  GameSnapshot snapshot({
    GridPosition? selectedCell,
    PlacedTower? selectedTower,
    String? feedback,
    bool isPaused = false,
    double speedMultiplier = 1,
    bool autoStartEnabled = false,
    double? autoStartCountdownRemaining,
  }) {
    final waveNumber = (_waveIndex + 1).clamp(1, stage.waves.length).toInt();
    final unlockedTypes = unlockedTowerTypes;
    final wave = activeWave;
    final nextWavePreview = _phase == GamePhase.build && wave != null
        ? GameBalance.wavePreview(
            wave: wave,
            waveNumber: waveNumber,
            waveTotal: stage.waves.length,
            unlockedTowerTypes: unlockedTypes,
            effectiveClearBonus: _effectiveClearBonus(wave.clearBonus),
          )
        : null;

    return GameSnapshot(
      phase: _phase,
      gold: _gold,
      baseHealth: _baseHealth,
      startingBaseHealth: startingBaseHealth,
      waveNumber: waveNumber,
      waveTotal: stage.waves.length,
      stageId: stage.id,
      stageName: stage.name,
      stageLabel: stage.mapLabel,
      unlockedTowerTypes: unlockedTypes,
      stageModifiers: stage.modifiers,
      nextWavePreview: nextWavePreview,
      selectedCell: selectedCell,
      selectedTower: selectedTower,
      feedback: feedback,
      isPaused: isPaused,
      speedMultiplier: speedMultiplier,
      autoStartEnabled: autoStartEnabled,
      autoStartCountdownRemaining: autoStartCountdownRemaining,
      pendingRunModuleOffer: _pendingRunModuleOffer,
      acquiredRunModules: _acquiredRunModules,
      selectedTowerStats: selectedTower == null
          ? null
          : resolveTowerStats(selectedTower),
    );
  }

  TowerStats resolveTowerStats(PlacedTower tower) {
    return TowerStatsResolver.resolve(
      tower,
      campaignModifiers: campaignModifiers,
      stageModifiers: stage.modifiers,
      runModules: _acquiredRunModules,
    );
  }

  PlacementResult validatePlacement(GridPosition position, TowerType type) {
    if (_phase != GamePhase.build) {
      return const PlacementResult.denied(PlacementFailure.invalidPhase);
    }
    if (_pendingRunModuleOffer != null) {
      return const PlacementResult.denied(PlacementFailure.pendingModuleDraft);
    }
    if (!BoardLayout.isInBounds(position)) {
      return const PlacementResult.denied(PlacementFailure.offBoard);
    }
    if (BoardLayout.isPathCell(position, pathCells: stage.pathCells)) {
      return const PlacementResult.denied(PlacementFailure.pathBlocked);
    }
    if (_towersByPosition.containsKey(position)) {
      return const PlacementResult.denied(PlacementFailure.occupied);
    }
    if (!isTowerUnlocked(type)) {
      return const PlacementResult.denied(PlacementFailure.lockedTower);
    }
    final cost = GameBalance.towerStats(type, level: 1).cost;
    if (_gold < cost) {
      return const PlacementResult.denied(PlacementFailure.insufficientGold);
    }
    return const PlacementResult.allowed();
  }

  PlacementResult placeTower(GridPosition position, TowerType type) {
    final result = validatePlacement(position, type);
    if (!result.isAllowed) {
      return result;
    }

    final stats = GameBalance.towerStats(type, level: 1);
    _gold -= stats.cost;
    _towersByPosition[position] = PlacedTower(
      id: _nextTowerId,
      type: type,
      position: position,
    );
    _nextTowerId += 1;
    return result;
  }

  bool upgradeTower(int towerId) {
    if (!_canMutateBuild) {
      return false;
    }

    final entry = _findTowerEntry(towerId);
    if (entry == null) {
      return false;
    }

    final tower = entry.value;
    if (!tower.canUpgrade) {
      return false;
    }

    final stats = GameBalance.towerStats(tower.type, level: tower.level);
    if (_gold < stats.upgradeCost) {
      return false;
    }

    _gold -= stats.upgradeCost;
    _towersByPosition[entry.key] = tower.upgraded();
    return true;
  }

  bool specializeTower(int towerId, TowerSpecialization specialization) {
    if (!_canMutateBuild) {
      return false;
    }

    final entry = _findTowerEntry(towerId);
    if (entry == null) {
      return false;
    }

    final tower = entry.value;
    if (!tower.canSpecialize || specialization.type != tower.type) {
      return false;
    }

    final stats = GameBalance.towerStats(tower.type, level: 2);
    if (_gold < stats.specializationCost) {
      return false;
    }

    _gold -= stats.specializationCost;
    _towersByPosition[entry.key] = tower.specialized(specialization);
    return true;
  }

  int? sellTower(int towerId) {
    if (!_canMutateBuild) {
      return null;
    }
    final entry = _findTowerEntry(towerId);
    if (entry == null) {
      return null;
    }
    final refund = GameBalance.refundValue(entry.value);
    _towersByPosition.remove(entry.key);
    _gold += refund;
    return refund;
  }

  bool setTargetingMode(int towerId, TowerTargetingMode mode) {
    if (!_canMutateBuild) {
      return false;
    }

    final entry = _findTowerEntry(towerId);
    if (entry == null) {
      return false;
    }

    _towersByPosition[entry.key] = entry.value.copyWith(targetingMode: mode);
    return true;
  }

  bool startWave() {
    if (!_canMutateBuild || _waveIndex >= stage.waves.length) {
      return false;
    }
    _phase = GamePhase.wave;
    return true;
  }

  void finishActiveWave() {
    if (_phase != GamePhase.wave) {
      return;
    }

    final completedWave = activeWave;
    final clearBonus = _effectiveClearBonus(completedWave?.clearBonus ?? 0);
    _waveIndex += 1;
    _gold += clearBonus;
    if (_waveIndex >= stage.waves.length) {
      _phase = GamePhase.won;
      return;
    }

    _phase = GamePhase.build;
    _openModuleDraftIfDue();
  }

  bool selectRunModule({required int offerId, required RunModuleId moduleId}) {
    final offer = _pendingRunModuleOffer;
    if (offer == null ||
        offer.offerId != offerId ||
        !offer.moduleIds.contains(moduleId) ||
        _acquiredRunModules.contains(moduleId)) {
      return false;
    }

    _acquiredRunModules.add(moduleId);
    _gold += runModuleDefinition(moduleId).immediateGold;
    _pendingRunModuleOffer = null;
    return true;
  }

  void rewardKill(int goldReward) {
    if (_phase != GamePhase.wave || goldReward <= 0) {
      return;
    }
    _gold += goldReward;
  }

  void damageBase(int amount) {
    if (_phase != GamePhase.wave || amount <= 0) {
      return;
    }
    _baseHealth = (_baseHealth - amount).clamp(0, startingBaseHealth).toInt();
    if (_baseHealth == 0) {
      _phase = GamePhase.lost;
    }
  }

  PlacedTower? towerAt(GridPosition position) => _towersByPosition[position];

  void restart() {
    _towersByPosition.clear();
    _nextTowerId = 1;
    _gold = startingGold;
    _baseHealth = startingBaseHealth;
    _waveIndex = 0;
    _phase = GamePhase.build;
    _acquiredRunModules.clear();
    _pendingRunModuleOffer = null;
  }

  int _effectiveClearBonus(int baseClearBonus) {
    if (_waveIndex >= stage.waves.length - 1) {
      return 0;
    }
    final campaignAdjusted =
        (baseClearBonus * (1 + campaignModifiers.clearBonusFraction)).round();
    return StageModifierRules.effectiveClearBonus(
      campaignAdjustedClearBonus: campaignAdjusted,
      stageModifiers: stage.modifiers,
    );
  }

  MapEntry<GridPosition, PlacedTower>? _findTowerEntry(int towerId) {
    for (final entry in _towersByPosition.entries) {
      if (entry.value.id == towerId) {
        return entry;
      }
    }
    return null;
  }

  TowerType? _affinityTower(RunModuleAffinity affinity) => switch (affinity) {
    RunModuleAffinity.universal => null,
    RunModuleAffinity.cryo => TowerType.cryo,
    RunModuleAffinity.rocket => TowerType.rocket,
  };

  List<RunModuleId> _moduleCandidates() {
    final acquired = _acquiredRunModules.toSet();
    final placedTypes = _towersByPosition.values
        .map((tower) => tower.type)
        .toSet();
    final unlockedTypes = unlockedTowerTypes.toSet();
    final remaining = runModuleCatalog
        .where((definition) => !acquired.contains(definition.id))
        .toList(growable: false);
    final candidates = <RunModuleId>[];

    void addMatching(bool Function(RunModuleDefinition definition) matches) {
      for (final definition in remaining) {
        if (matches(definition) && !candidates.contains(definition.id)) {
          candidates.add(definition.id);
        }
      }
    }

    addMatching((definition) {
      final tower = _affinityTower(definition.affinity);
      return tower == null || placedTypes.contains(tower);
    });

    if (candidates.length < 3) {
      addMatching((definition) {
        final tower = _affinityTower(definition.affinity);
        return tower != null && unlockedTypes.contains(tower);
      });
    }

    if (candidates.length < 3) {
      addMatching((_) => true);
    }

    return candidates;
  }

  void _openModuleDraftIfDue() {
    if (_pendingRunModuleOffer != null ||
        !GameBalance.moduleDraftWaves.contains(_waveIndex)) {
      return;
    }

    final candidates = _moduleCandidates();
    if (candidates.length < 3) {
      return;
    }

    _pendingRunModuleOffer = RunModuleOffer(
      offerId: _nextModuleOfferId++,
      draftNumber: _waveIndex ~/ 2,
      draftTotal: GameBalance.moduleDraftWaves.length,
      moduleIds: _offerPicker.pick(candidates, count: 3),
    );
  }
}
