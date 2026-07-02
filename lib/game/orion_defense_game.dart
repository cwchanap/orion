import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import 'assets/game_path_tiles.dart';
import 'assets/game_sprite_sheet.dart';
import 'assets/game_tower_variety_sheet.dart';
import 'assets/game_terrain.dart';
import 'campaign/campaign_progress.dart';
import 'campaign/orion_campaign.dart';
import 'campaign/stage_definition.dart';
import 'components/board_component.dart';
import 'components/drone_component.dart';
import 'components/enemy_component.dart';
import 'components/gravity_field_component.dart';
import 'components/projectile_component.dart';
import 'components/tower_component.dart';
import 'models/game_models.dart';
import 'rules/board_layout.dart';
import 'rules/combat_effects.dart';
import 'rules/game_session.dart';
import 'rules/tower_targeting.dart';

class StageCompletion {
  const StageCompletion({required this.stage, required this.result});

  final StageDefinition stage;
  final StageResult result;
}

class OrionDefenseGame extends FlameGame with TapCallbacks, HasTimeScale {
  OrionDefenseGame({
    StageDefinition? stage,
    this.onStageWon,
    this.onReturnToMap,
  }) : stage = stage ?? OrionCampaign.stageOne,
       _session = GameSession.initial(stage: stage ?? OrionCampaign.stageOne) {
    _resetPacing();
  }

  final StageDefinition stage;
  final ValueChanged<StageCompletion>? onStageWon;
  final VoidCallback? onReturnToMap;
  final GameSession _session;

  late final ValueNotifier<GameSnapshot> stateNotifier = ValueNotifier(
    _session.snapshot(),
  );

  BoardComponent? _board;
  GridPosition? _selectedCell;
  PlacedTower? _selectedTower;
  double _cellSize = 0;
  Offset _boardOrigin = Offset.zero;
  double _spawnTimer = 0;
  int _spawnedCount = 0;
  int _activeGroupIndex = 0;
  int _spawnedInGroup = 0;
  int _nextEnemyId = 1;
  static const double defaultSpeedMultiplier = 1;
  static final Set<double> supportedSpeedMultipliers = Set.unmodifiable({
    1.0,
    2.0,
    3.0,
  });
  static const double autoStartCountdownSeconds = 3;

  bool _isPaused = false;
  double _speedMultiplier = defaultSpeedMultiplier;
  bool _autoStartEnabled = false;
  double? _autoStartCountdownRemaining;

  GamePathTiles? _pathTiles;
  GameSpriteSheet? _spriteSheet;
  GameTowerVarietySheet? _towerVarietySheet;
  Image? _terrainImage;
  final Map<int, TowerComponent> _towerComponents = {};
  final Map<int, EnemyComponent> _activeEnemyComponents = {};
  final Map<int, int> _activeDronesByTower = {};

  GameSnapshot get snapshot => stateNotifier.value;
  bool get isPaused => _isPaused;
  double get speedMultiplier => _speedMultiplier;
  bool get autoStartEnabled => _autoStartEnabled;
  double? get autoStartCountdownRemaining => _autoStartCountdownRemaining;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _terrainImage = await images.load(GameTerrain.fileName);
    _pathTiles = await GamePathTiles.load(images);
    _spriteSheet = await GameSpriteSheet.load(images);
    _towerVarietySheet = await GameTowerVarietySheet.load(images);
    _layoutBoard(size);
    _publishSnapshot();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // Enemy paths are immutable after spawn, so keep active-wave coordinates stable.
    if (_session.phase == GamePhase.wave) {
      return;
    }
    _layoutBoard(size);
  }

  @override
  void onRemove() {
    stateNotifier.dispose();
    super.onRemove();
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (_session.phase == GamePhase.won || _session.phase == GamePhase.lost) {
      return;
    }

    final tappedCell = BoardLayout.cellAt(
      event.canvasPosition.toOffset(),
      cellSize: _cellSize,
      boardOrigin: _boardOrigin,
    );

    if (tappedCell == null) {
      _clearSelection();
      _publishSnapshot();
      return;
    }

    final tower = _session.towerAt(tappedCell);
    if (tower != null) {
      _selectedCell = null;
      _selectedTower = tower;
      _board?.selectedCell = tower.position;
    } else {
      _selectedCell = tappedCell;
      _selectedTower = null;
      _board?.selectedCell = tappedCell;
    }

    _publishSnapshot();
  }

  void placeTower(TowerType type) {
    final position = _selectedCell;
    if (position == null) {
      _publishSnapshot(feedback: 'Select a buildable cell first.');
      return;
    }

    final result = _session.placeTower(position, type);
    if (!result.isAllowed) {
      _publishSnapshot(feedback: _placementMessage(result.failure));
      return;
    }

    final tower = _session.towerAt(position);
    if (tower != null) {
      _addTowerComponent(tower);
    }
    _clearSelection();
    _publishSnapshot();
  }

  void upgradeSelectedTower() {
    final tower = _selectedTower;
    if (tower == null) {
      _publishSnapshot(feedback: 'Select a tower first.');
      return;
    }

    if (!_session.upgradeTower(tower.id)) {
      _publishSnapshot(feedback: _upgradeMessage(tower));
      return;
    }

    final upgradedTower = _session.towerAt(tower.position);
    final component = _towerComponents[tower.id];
    if (upgradedTower != null && component != null) {
      component.updateTower(upgradedTower);
      _selectedTower = upgradedTower;
    }
    _publishSnapshot();
  }

  void specializeSelectedTower(TowerSpecialization specialization) {
    final tower = _selectedTower;
    if (tower == null) {
      _publishSnapshot(feedback: 'Select a tower first.');
      return;
    }

    if (!_session.specializeTower(tower.id, specialization)) {
      _publishSnapshot(feedback: _specializationMessage(tower, specialization));
      return;
    }

    final specializedTower = _session.towerAt(tower.position);
    final component = _towerComponents[tower.id];
    if (specializedTower != null && component != null) {
      component.updateTower(specializedTower);
      _selectedTower = specializedTower;
    }
    _publishSnapshot();
  }

  void startWave() {
    if (!_session.startWave()) {
      _publishSnapshot(feedback: 'Wave cannot start right now.');
      return;
    }

    _autoStartCountdownRemaining = null;
    _resetWaveSpawnState();
    _clearSelection();
    _publishSnapshot();
  }

  void restart() {
    _clearCombatComponents(removeTowers: true);
    _resetWaveSpawnState();
    _nextEnemyId = 1;
    _clearSelection();
    _session.restart();
    _resetPacing();
    _layoutBoardIfReady();
    _publishSnapshot();
  }

  void returnToMap() {
    if (_session.phase == GamePhase.wave) {
      _publishSnapshot(feedback: 'Finish the active wave before returning.');
      return;
    }
    onReturnToMap?.call();
  }

  void togglePause() {
    if (_session.phase == GamePhase.won || _session.phase == GamePhase.lost) {
      return;
    }

    _isPaused = !_isPaused;
    _applyTimeScale();
    _publishSnapshot();
  }

  void setSpeedMultiplier(double multiplier) {
    if (_session.phase == GamePhase.won || _session.phase == GamePhase.lost) {
      return;
    }
    if (!supportedSpeedMultipliers.contains(multiplier)) {
      return;
    }

    _speedMultiplier = multiplier;
    _applyTimeScale();
    _publishSnapshot();
  }

  void toggleAutoStart() {
    if (_session.phase == GamePhase.won || _session.phase == GamePhase.lost) {
      return;
    }

    _autoStartEnabled = !_autoStartEnabled;
    if (!_autoStartEnabled) {
      _autoStartCountdownRemaining = null;
    } else {
      _startAutoStartCountdownIfNeeded();
    }
    _publishSnapshot();
  }

  @override
  void update(double dt) {
    if (_isPaused) {
      processLifecycleEvents();
      _removeInactiveEnemyReferences();
      return;
    }

    super.update(dt);
    _removeInactiveEnemyReferences();

    final scaledDt = dt * _speedMultiplier;
    if (scaledDt > 0 && _tickAutoStartCountdown(scaledDt)) {
      return;
    }

    if (_session.phase != GamePhase.wave) {
      return;
    }

    if (scaledDt > 0) {
      _spawnWaveEnemies(scaledDt);
    }
    _removeInactiveEnemyReferences();
    _finishWaveIfComplete();
  }

  void _layoutBoard(Vector2 gameSize) {
    if (gameSize.x <= 0 || gameSize.y <= 0) {
      return;
    }

    final cellSize = (gameSize.x / BoardLayout.columns)
        .clamp(0, gameSize.y / BoardLayout.rows)
        .toDouble();
    final boardWidth = BoardLayout.columns * cellSize;
    final boardHeight = BoardLayout.rows * cellSize;
    final boardOrigin = Offset(
      (gameSize.x - boardWidth) / 2,
      (gameSize.y - boardHeight) / 2,
    );

    _cellSize = cellSize;
    _boardOrigin = boardOrigin;
    _board?.removeFromParent();
    _board = BoardComponent(
      cellSize: _cellSize,
      pathCells: stage.pathCells,
      selectedCell: _selectedTower?.position ?? _selectedCell,
      spriteSheet: _spriteSheet,
      terrainImage: _terrainImage,
      pathTiles: _pathTiles,
      position: Vector2(_boardOrigin.dx, _boardOrigin.dy),
      priority: 0,
    );
    add(_board!);

    for (final tower in _towerComponents.values) {
      tower.position = _cellCenter(tower.placedTower.position);
      tower.radius = _towerRadius;
    }
  }

  void _addTowerComponent(PlacedTower tower) {
    final component = TowerComponent(
      tower: tower,
      center: _cellCenter(tower.position),
      radius: _towerRadius,
      acquireTarget: _selectTargetForTower,
      launchProjectile: _launchProjectile,
      spriteSheet: _spriteSheet,
      towerVarietySheet: _towerVarietySheet,
      priority: 10,
    );
    _towerComponents[tower.id] = component;
    add(component);
  }

  EnemyComponent? _selectTargetForTower(TowerComponent tower) {
    final candidates = _activeEnemyComponents.values
        .where((enemy) => enemy.isAlive)
        .map((enemy) => enemy.targetCandidate);
    final selected = TowerTargeting.selectTarget(
      tower: TargetPoint(x: tower.position.x, y: tower.position.y),
      range: tower.stats.range,
      candidates: candidates,
    );
    if (selected == null) {
      return null;
    }
    return _activeEnemyComponents[selected.id];
  }

  void _launchProjectile(TowerComponent tower, EnemyComponent target) {
    if (tower.stats.fieldRadius > 0 && tower.stats.fieldDuration > 0) {
      add(
        GravityFieldComponent(
          stats: tower.stats,
          center: target.position,
          enemiesProvider: () => _activeEnemyComponents.values,
          priority: 25,
        ),
      );
      return;
    }

    if (tower.stats.droneCount > 0) {
      _launchDrones(tower);
      return;
    }

    add(
      ProjectileComponent(
        stats: tower.stats,
        target: target,
        startPosition: tower.position,
        enemiesProvider: () => _activeEnemyComponents.values,
        spriteSheet: _spriteSheet,
        towerVarietySheet: _towerVarietySheet,
        priority: 30,
      ),
    );
  }

  void _launchDrones(TowerComponent tower) {
    final active = _activeDronesByTower[tower.placedTower.id] ?? 0;
    final allowed = CombatEffects.allowedDroneLaunches(
      requested: tower.stats.droneCount,
      active: active,
      maxActive: tower.stats.maxActiveDrones,
      sessionActive: _activeDroneCount,
      maxSessionActive: _maxActiveDronesInSession,
    );
    if (allowed <= 0) {
      return;
    }

    _activeDronesByTower[tower.placedTower.id] = active + allowed;
    for (var index = 0; index < allowed; index += 1) {
      add(
        DroneComponent(
          ownerTowerId: tower.placedTower.id,
          stats: tower.stats,
          startPosition: tower.position,
          acquireTarget: _selectNearestEnemyForDrone,
          onExpired: _handleDroneExpired,
          priority: 35,
        ),
      );
    }
  }

  int get _activeDroneCount =>
      _activeDronesByTower.values.fold(0, (total, active) => total + active);

  int get _maxActiveDronesInSession {
    var maxActive = 0;
    for (final tower in _towerComponents.values) {
      maxActive = math.max(maxActive, tower.stats.maxActiveDrones);
    }
    return maxActive;
  }

  EnemyComponent? _selectNearestEnemyForDrone(Vector2 position) {
    EnemyComponent? selected;
    var selectedDistance = double.infinity;

    for (final enemy in _activeEnemyComponents.values) {
      if (!enemy.isAlive) {
        continue;
      }

      final distance = enemy.position.distanceTo(position);
      if (distance < selectedDistance) {
        selected = enemy;
        selectedDistance = distance;
      }
    }

    return selected;
  }

  void _handleDroneExpired(DroneComponent drone) {
    final current = _activeDronesByTower[drone.ownerTowerId] ?? 0;
    _activeDronesByTower[drone.ownerTowerId] = math.max(0, current - 1);
  }

  void _resetWaveSpawnState() {
    _spawnTimer = 0;
    _spawnedCount = 0;
    _activeGroupIndex = 0;
    _spawnedInGroup = 0;
  }

  bool _tickAutoStartCountdown(double dt) {
    final remaining = _autoStartCountdownRemaining;
    if (remaining == null) {
      return false;
    }
    if (_session.phase != GamePhase.build) {
      _autoStartCountdownRemaining = null;
      _publishSnapshot();
      return false;
    }

    final nextRemaining = remaining - dt;
    if (nextRemaining > 0) {
      _autoStartCountdownRemaining = nextRemaining;
      _publishSnapshot();
      return false;
    }

    _autoStartCountdownRemaining = null;
    startWave();
    return true;
  }

  void _startAutoStartCountdownIfNeeded() {
    if (_autoStartEnabled &&
        _autoStartCountdownRemaining == null &&
        _session.phase == GamePhase.build &&
        _session.clearedWaveCount > 0 &&
        _session.activeWave != null) {
      _autoStartCountdownRemaining = autoStartCountdownSeconds;
    }
  }

  void _spawnWaveEnemies(double dt) {
    final wave = _session.activeWave;
    if (wave == null || _spawnedCount >= wave.enemyCount) {
      return;
    }

    _spawnTimer -= dt;
    while (_spawnTimer <= 0 && _spawnedCount < wave.enemyCount) {
      final group = wave.groups[_activeGroupIndex];
      _spawnEnemy(group.enemyStats);
      _spawnedCount += 1;
      _spawnedInGroup += 1;

      if (_spawnedInGroup >= group.enemyCount) {
        _activeGroupIndex += 1;
        _spawnedInGroup = 0;
        if (_activeGroupIndex >= wave.groups.length) {
          _spawnTimer = 0;
          return;
        }
        _spawnTimer += wave.groups[_activeGroupIndex].initialDelay;
      } else {
        _spawnTimer += group.spawnInterval;
      }
    }
  }

  void _spawnEnemy(EnemyStats stats) {
    final enemy = EnemyComponent(
      enemyId: _nextEnemyId,
      stats: stats,
      waypoints: _pathWaypoints(),
      spriteSheet: _spriteSheet,
      towerVarietySheet: _towerVarietySheet,
      onKilled: _handleEnemyKilled,
      onReachedBase: _handleEnemyReachedBase,
      priority: 20,
    );
    _nextEnemyId += 1;
    _activeEnemyComponents[enemy.enemyId] = enemy;
    add(enemy);
  }

  void _handleEnemyKilled(EnemyComponent enemy) {
    _activeEnemyComponents.remove(enemy.enemyId);
    _session.rewardKill(enemy.stats.goldReward);
    _publishSnapshot();
  }

  void _handleEnemyReachedBase(EnemyComponent enemy) {
    _activeEnemyComponents.remove(enemy.enemyId);
    _session.damageBase(enemy.stats.baseDamage);
    if (_session.phase == GamePhase.lost) {
      _clearCombatComponents(removeTowers: false);
      _resetWaveSpawnState();
      _resetPacing();
      _layoutBoardIfReady();
    }
    _publishSnapshot();
  }

  void _finishWaveIfComplete() {
    final wave = _session.activeWave;
    if (wave == null) {
      return;
    }
    if (_spawnedCount < wave.enemyCount || _activeEnemyComponents.isNotEmpty) {
      return;
    }

    _session.finishActiveWave();
    final didWin = _session.phase == GamePhase.won;
    _resetWaveSpawnState();
    if (didWin) {
      _resetPacing();
    } else {
      _startAutoStartCountdownIfNeeded();
    }
    StageCompletion? completion;
    if (didWin) {
      completion = StageCompletion(
        stage: stage,
        result: StageResult.fromVictoryBaseHealth(_session.baseHealth),
      );
    }
    _layoutBoardIfReady();
    _publishSnapshot();
    if (completion != null) {
      onStageWon?.call(completion);
    }
  }

  void _removeInactiveEnemyReferences() {
    _activeEnemyComponents.removeWhere((_, enemy) => enemy.isResolved);
  }

  void _clearCombatComponents({required bool removeTowers}) {
    for (final enemy in _activeEnemyComponents.values.toList()) {
      enemy.removeFromParent();
    }
    for (final projectile
        in children.whereType<ProjectileComponent>().toList()) {
      projectile.removeFromParent();
    }
    for (final drone in children.whereType<DroneComponent>().toList()) {
      drone.removeFromParent();
    }
    for (final field in children.whereType<GravityFieldComponent>().toList()) {
      field.removeFromParent();
    }
    if (removeTowers) {
      for (final tower in _towerComponents.values.toList()) {
        tower.removeFromParent();
      }
      _towerComponents.clear();
    }
    _activeEnemyComponents.clear();
    _activeDronesByTower.clear();
  }

  Vector2 _cellCenter(GridPosition position) {
    final center = BoardLayout.cellCenter(
      position,
      cellSize: _cellSize,
      boardOrigin: _boardOrigin,
    );
    return Vector2(center.dx, center.dy);
  }

  List<Vector2> _pathWaypoints() {
    return stage.pathCells.map(_cellCenter).toList(growable: false);
  }

  void _clearSelection() {
    _selectedCell = null;
    _selectedTower = null;
    _board?.selectedCell = null;
  }

  void _layoutBoardIfReady() {
    if (hasLayout) {
      _layoutBoard(size);
    }
  }

  void _applyTimeScale() {
    timeScale = _isPaused ? 0 : _speedMultiplier;
  }

  void _resetPacing() {
    _isPaused = false;
    _speedMultiplier = defaultSpeedMultiplier;
    _autoStartEnabled = false;
    _autoStartCountdownRemaining = null;
    _applyTimeScale();
  }

  void _publishSnapshot({String? feedback}) {
    stateNotifier.value = _session.snapshot(
      selectedCell: _selectedCell,
      selectedTower: _selectedTower,
      feedback: feedback,
      isPaused: _isPaused,
      speedMultiplier: _speedMultiplier,
      autoStartEnabled: _autoStartEnabled,
      autoStartCountdownRemaining: _autoStartCountdownRemaining,
    );
  }

  String _placementMessage(PlacementFailure? failure) {
    return switch (failure) {
      PlacementFailure.invalidPhase => 'Build towers between waves.',
      PlacementFailure.offBoard => 'Select a cell on the board.',
      PlacementFailure.pathBlocked => 'Cannot build on the enemy path.',
      PlacementFailure.occupied => 'That cell already has a tower.',
      PlacementFailure.insufficientGold => 'Not enough gold for that tower.',
      PlacementFailure.lockedTower => 'That tower unlocks after a later wave.',
      null => 'Cannot place a tower there.',
    };
  }

  String _upgradeMessage(PlacedTower tower) {
    if (_session.phase != GamePhase.build) {
      return 'Upgrade towers between waves.';
    }
    if (!tower.canUpgrade) {
      return 'Choose a specialization or use a maxed tower.';
    }
    return 'Not enough gold to upgrade that tower.';
  }

  String _specializationMessage(
    PlacedTower tower,
    TowerSpecialization specialization,
  ) {
    if (_session.phase != GamePhase.build) {
      return 'Specialize towers between waves.';
    }
    if (specialization.type != tower.type) {
      return 'That specialization belongs to another tower.';
    }
    if (!tower.canSpecialize) {
      return tower.isMaxLevel
          ? 'That tower is already specialized.'
          : 'Upgrade this tower before specializing.';
    }
    return 'Not enough gold to specialize that tower.';
  }

  double get _towerRadius => (_cellSize * 0.28).clamp(8, 18).toDouble();
}
