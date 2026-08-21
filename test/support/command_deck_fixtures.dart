import 'package:orion/game/models/game_models.dart';

GameSnapshot commandDeckSnapshot({
  GamePhase phase = GamePhase.build,
  int gold = 150,
  int baseHealth = 20,
  int startingBaseHealth = 20,
  int waveNumber = 1,
  int waveTotal = 8,
  String stageId = 'outpost-alpha',
  String stageName = 'Outpost Alpha',
  String stageLabel = 'Alpha',
  List<TowerType> unlockedTowerTypes = const [
    TowerType.laser,
    TowerType.rocket,
    TowerType.cryo,
    TowerType.railgun,
    TowerType.ionChain,
    TowerType.nanite,
    TowerType.gravityWell,
    TowerType.droneBay,
  ],
  List<StageModifier> stageModifiers = const [],
  WavePreview? nextWavePreview,
  GridPosition? selectedCell,
  PlacedTower? selectedTower,
  TowerStats? selectedTowerStats,
  String? feedback,
  bool isPaused = false,
  double speedMultiplier = 1,
  bool autoStartEnabled = false,
  double? autoStartCountdownRemaining,
  RunModuleOffer? pendingRunModuleOffer,
  List<RunModuleId> acquiredRunModules = const [],
}) {
  return GameSnapshot(
    phase: phase,
    gold: gold,
    baseHealth: baseHealth,
    startingBaseHealth: startingBaseHealth,
    waveNumber: waveNumber,
    waveTotal: waveTotal,
    stageId: stageId,
    stageName: stageName,
    stageLabel: stageLabel,
    unlockedTowerTypes: unlockedTowerTypes,
    stageModifiers: stageModifiers,
    nextWavePreview: nextWavePreview,
    selectedCell: selectedCell,
    selectedTower: selectedTower,
    selectedTowerStats: selectedTowerStats,
    feedback: feedback,
    isPaused: isPaused,
    speedMultiplier: speedMultiplier,
    autoStartEnabled: autoStartEnabled,
    autoStartCountdownRemaining: autoStartCountdownRemaining,
    pendingRunModuleOffer: pendingRunModuleOffer,
    acquiredRunModules: acquiredRunModules,
  );
}

WavePreview commandDeckPreview({
  int waveNumber = 1,
  int waveTotal = 8,
  List<WavePreviewGroup>? groups,
  Set<EnemyTrait> traits = const {},
  int clearBonus = 30,
  List<TowerType> recommendedTowerTypes = const [TowerType.laser],
}) {
  return WavePreview(
    waveNumber: waveNumber,
    waveTotal: waveTotal,
    groups:
        groups ??
        [WavePreviewGroup(enemyCount: 8, label: 'Drones', traits: const {})],
    traits: traits,
    clearBonus: clearBonus,
    recommendedTowerTypes: recommendedTowerTypes,
  );
}
