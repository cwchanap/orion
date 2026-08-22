import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import 'assets/game_boss_sheet.dart';
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
import 'feedback/game_feedback.dart';
import 'models/game_models.dart';
import 'rules/board_layout.dart';
import 'rules/combat_effects.dart';
import 'rules/enemy_logic.dart';
import 'rules/game_session.dart';
import 'rules/module_offer_picker.dart';
import 'rules/stage_modifier_rules.dart';
import 'rules/tower_targeting.dart';

class StageCompletion {
  const StageCompletion({required this.stage, required this.result});

  final StageDefinition stage;
  final StageResult result;
}

class OrionDefenseGame extends FlameGame with TapCallbacks, HasTimeScale {
  OrionDefenseGame({
    StageDefinition? stage,
    CampaignModifiers campaignModifiers = CampaignModifiers.empty,
    Iterable<RunModuleId>? availableRunModules,
    ModuleOfferPicker? moduleOfferPicker,
    this.onStageWon,
    this.onReturnToMap,
    this.gameFeedback = const NoOpGameFeedback(),
  }) : stage = stage ?? OrionCampaign.stageOne,
       _session = GameSession.initial(
         stage: stage ?? OrionCampaign.stageOne,
         campaignModifiers: campaignModifiers,
         availableRunModules: availableRunModules,
         offerPicker: moduleOfferPicker,
       ) {
    _resetPacing();
  }

  final StageDefinition stage;
  final ValueChanged<StageCompletion>? onStageWon;
  final VoidCallback? onReturnToMap;
  final GameFeedback gameFeedback;
  final GameSession _session;

  CampaignModifiers get campaignModifiers => _session.campaignModifiers;

  @visibleForTesting
  Set<RunModuleId> get availableRunModules => _session.availableRunModules;

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
  GameBossSheet? _bossSheet;
  Image? _terrainImage;
  final Map<int, TowerComponent> _towerComponents = {};
  final Map<int, EnemyComponent> _activeEnemyComponents = {};
  int? _inspectedEnemyId;
  final Map<int, int> _activeDronesByTower = {};

  GameSnapshot get snapshot => stateNotifier.value;
  bool get isPaused => _isPaused;
  double get speedMultiplier => _speedMultiplier;
  bool get autoStartEnabled => _autoStartEnabled;
  double? get autoStartCountdownRemaining => _autoStartCountdownRemaining;
  int? get inspectedEnemyId => _inspectedEnemyId;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _terrainImage = await images.load(GameTerrain.fileName);
    _pathTiles = await GamePathTiles.load(images);
    _spriteSheet = await GameSpriteSheet.load(images);
    _towerVarietySheet = await GameTowerVarietySheet.load(images);
    _bossSheet = await GameBossSheet.load(images);
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
    handleBoardTap(event.canvasPosition.toOffset());
  }

  /// Maps [canvasPosition] (GameWidget-local) to the grid cell it lands on,
  /// or null when it misses the board or hits an enemy-path cell.
  GridPosition? buildableCellAt(Offset canvasPosition) {
    final tappedCell = BoardLayout.cellAt(
      canvasPosition,
      cellSize: _cellSize,
      boardOrigin: _boardOrigin,
    );
    if (tappedCell == null) {
      return null;
    }
    return BoardLayout.isBuildableCell(tappedCell, pathCells: stage.pathCells)
        ? tappedCell
        : null;
  }

  /// Applies the same selection logic as a raw board tap. Lets widget-layer
  /// chrome (e.g. the collapsed next-wave scanner) forward a tap that would
  /// otherwise be swallowed while it hovers over a buildable cell.
  void handleBoardTap(Offset canvasPosition) {
    if (_session.phase == GamePhase.won || _session.phase == GamePhase.lost) {
      return;
    }
    if (_session.pendingRunModuleOffer != null) {
      return;
    }

    if (_session.phase == GamePhase.wave) {
      final enemy = _enemyAt(Vector2(canvasPosition.dx, canvasPosition.dy));
      if (enemy != null) {
        _setInspectedEnemy(enemy.enemyId);
        _publishSnapshot();
        return;
      }
      _setInspectedEnemy(null);
    }

    final tappedCell = BoardLayout.cellAt(
      canvasPosition,
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
      _publishSnapshot(
        feedback: _draftBlockMessage() ?? 'Select a buildable cell first.',
      );
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
    gameFeedback.towerConfirmed();
    _publishSnapshot();
  }

  void upgradeSelectedTower() {
    final tower = _selectedTower;
    if (tower == null) {
      _publishSnapshot(
        feedback: _draftBlockMessage() ?? 'Select a tower first.',
      );
      return;
    }

    if (!_session.upgradeTower(tower.id)) {
      _publishSnapshot(
        feedback: _draftBlockMessage() ?? _upgradeMessage(tower),
      );
      return;
    }

    final upgradedTower = _session.towerAt(tower.position);
    final component = _towerComponents[tower.id];
    if (upgradedTower != null && component != null) {
      component.updateTower(upgradedTower);
      _selectedTower = upgradedTower;
    }
    gameFeedback.towerConfirmed();
    _publishSnapshot();
  }

  void specializeSelectedTower(TowerSpecialization specialization) {
    final tower = _selectedTower;
    if (tower == null) {
      _publishSnapshot(
        feedback: _draftBlockMessage() ?? 'Select a tower first.',
      );
      return;
    }

    if (!_session.specializeTower(tower.id, specialization)) {
      _publishSnapshot(
        feedback:
            _draftBlockMessage() ??
            _specializationMessage(tower, specialization),
      );
      return;
    }

    final specializedTower = _session.towerAt(tower.position);
    final component = _towerComponents[tower.id];
    if (specializedTower != null && component != null) {
      component.updateTower(specializedTower);
      _selectedTower = specializedTower;
    }
    gameFeedback.towerConfirmed();
    _publishSnapshot();
  }

  void sellSelectedTower() {
    final tower = _selectedTower;
    if (tower == null) {
      _publishSnapshot(
        feedback: _draftBlockMessage() ?? 'Select a tower first.',
      );
      return;
    }

    final refund = _session.sellTower(tower.id);
    if (refund == null) {
      _publishSnapshot(
        feedback: _draftBlockMessage() ?? 'Sell towers between waves.',
      );
      return;
    }

    final component = _towerComponents.remove(tower.id);
    component?.removeFromParent();
    for (final drone
        in children
            .whereType<DroneComponent>()
            .where((drone) => drone.ownerTowerId == tower.id)
            .toList()) {
      drone.removeFromParent();
    }
    for (final field
        in children
            .whereType<GravityFieldComponent>()
            .where((field) => field.ownerTowerId == tower.id)
            .toList()) {
      field.removeFromParent();
    }
    _activeDronesByTower.remove(tower.id);
    _clearSelection();
    _publishSnapshot(feedback: 'Sold for $refund gold.');
  }

  void setTargetingMode(TowerTargetingMode mode) {
    final tower = _selectedTower;
    if (tower == null) {
      _publishSnapshot(
        feedback: _draftBlockMessage() ?? 'Select a tower first.',
      );
      return;
    }

    if (!_session.setTargetingMode(tower.id, mode)) {
      _publishSnapshot(
        feedback:
            _draftBlockMessage() ??
            'Targeting can only change during build phase.',
      );
      return;
    }

    final updated = _session.towerAt(tower.position);
    final component = _towerComponents[tower.id];
    if (updated != null && component != null) {
      component.updateTower(updated);
      _selectedTower = updated;
    }
    _publishSnapshot();
  }

  void startWave() {
    if (!_session.startWave()) {
      _publishSnapshot(
        feedback: _draftBlockMessage() ?? 'Wave cannot start right now.',
      );
      return;
    }

    _autoStartCountdownRemaining = null;
    _resetWaveSpawnState();
    _clearSelection();
    _publishSnapshot();
  }

  void selectRunModule(int offerId, RunModuleId moduleId) {
    if (!_session.selectRunModule(offerId: offerId, moduleId: moduleId)) {
      return;
    }

    for (final component in _towerComponents.values) {
      component.updateTower(component.placedTower);
    }
    for (final drone in children.whereType<DroneComponent>()) {
      final ownerTower = _towerComponents[drone.ownerTowerId];
      if (ownerTower != null) {
        drone.updateStats(ownerTower.stats);
      }
    }
    for (final field in children.whereType<GravityFieldComponent>()) {
      final ownerTower = _towerComponents[field.ownerTowerId];
      if (ownerTower != null) {
        field.updateStats(ownerTower.stats);
      }
    }
    _startAutoStartCountdownIfNeeded();
    gameFeedback.moduleSelected();
    _publishSnapshot();
  }

  void restart({
    CampaignModifiers? campaignModifiers,
    Iterable<RunModuleId>? availableRunModules,
  }) {
    _clearCombatComponents(removeTowers: true);
    _resetWaveSpawnState();
    _nextEnemyId = 1;
    _clearSelection();
    _session.restart(
      campaignModifiers: campaignModifiers,
      availableRunModules: availableRunModules,
    );
    _resetPacing();
    _layoutBoardIfReady();
    _publishSnapshot();
  }

  /// Publishes [message] as the current snapshot feedback without mutating
  /// any other game state. Used by the UI to surface campaign-persistence
  /// failures on top of the live game snapshot.
  void overrideFeedback(String message) {
    _publishSnapshot(feedback: message);
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
    final scaledDt = dt * _speedMultiplier;

    super.update(dt);
    _removeInactiveEnemyReferences();

    if (scaledDt > 0 && _tickAutoStartCountdown(scaledDt)) return;
    if (_session.phase != GamePhase.wave) return;

    if (scaledDt > 0) {
      _tickEnemyLogic(scaledDt);
    }
    _removeInactiveEnemyReferences();
    // A reach-base defeat or combat-triggered loss inside _tickEnemyLogic can
    // flip the phase out of wave. Don't spawn or finish-wave after that —
    // _handleEnemyReachedBase already cleaned up combat components and reset
    // spawn state. Spawning here would repopulate the board post-defeat.
    if (_session.phase != GamePhase.wave) return;
    if (scaledDt > 0) {
      _spawnWaveEnemies(scaledDt);
    }
    _finishWaveIfComplete();
  }

  void _tickEnemyLogic(double dt) {
    for (final enemy in _activeEnemyComponents.values.toList()) {
      if (_session.phase != GamePhase.wave) break; // defeat/win ended combat
      if (!_activeEnemyComponents.containsKey(enemy.enemyId)) {
        continue; // cleared this loop
      }
      final logic = enemy.logic;
      if (!logic.isAlive) continue;
      final result = logic.tick(dt);
      enemy.syncRender();
      if (result.overlayDirty) enemy.markOverlayDirty();
      if (result.reachedBase) {
        enemy.resolveReachedBase();
      } else if (result.diedByCorrosion) {
        enemy.resolveKilled();
      } else {
        final bossDef = logic.stats is BossDefinition
            ? logic.stats as BossDefinition
            : null;
        final mechanic = bossDef?.summonMechanic;
        if (mechanic != null) {
          for (var i = 0; i < result.summonsDue; i++) {
            _handleSummonMinions(enemy, mechanic.count);
          }
        }
      }
    }
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
      resolveStats: _session.resolveTowerStats,
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
      mode: tower.placedTower.targetingMode,
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
          ownerTowerId: tower.placedTower.id,
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

  EnemyComponent? _enemyAt(Vector2 canvasPosition) {
    for (final enemy in _activeEnemyComponents.values.toList().reversed) {
      if (!enemy.isAlive || enemy.parent == null) {
        continue;
      }

      final touchRadius = math.max(enemy.radius * 1.8, 24);
      if (enemy.position.distanceTo(canvasPosition) <= touchRadius) {
        return enemy;
      }
    }
    return null;
  }

  void _setInspectedEnemy(int? enemyId) {
    if (_inspectedEnemyId == enemyId) {
      return;
    }

    final previous = _inspectedEnemyId;
    if (previous != null) {
      _activeEnemyComponents[previous]?.setInspected(false);
    }

    _inspectedEnemyId = enemyId;
    if (enemyId != null) {
      _activeEnemyComponents[enemyId]?.setInspected(true);
    }
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
    if (_session.pendingRunModuleOffer != null) {
      _autoStartCountdownRemaining = null;
      return false;
    }

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
        _session.pendingRunModuleOffer == null &&
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
        _spawnTimer += StageModifierRules.nextSpawnDelay(
          stats: group.enemyStats,
          spawnedInGroup: _spawnedInGroup,
          baseSpawnInterval: group.spawnInterval,
          stageModifiers: stage.modifiers,
        );
      }
    }
  }

  List<Offset> _offsetWaypoints(List<Vector2> v) => [
    for (final p in v) Offset(p.x, p.y),
  ];

  EnemyModifierProfile _enemyModifierProfile(EnemyStats stats) {
    return StageModifierRules.enemyProfile(
      stats: stats,
      stageModifiers: stage.modifiers,
    );
  }

  void _spawnEnemy(EnemyStats stats) {
    final bossDef = stats is BossDefinition ? stats : null;
    final waypoints = _pathWaypoints();
    final logic = EnemyLogic(
      enemyId: _nextEnemyId,
      stats: stats,
      waypoints: _offsetWaypoints(waypoints),
      modifierProfile: _enemyModifierProfile(stats),
    );
    final enemy = EnemyComponent(
      enemyId: _nextEnemyId,
      stats: stats,
      logic: logic,
      spriteSheet: _spriteSheet,
      towerVarietySheet: _towerVarietySheet,
      bossSheet: _bossSheet,
      onKilled: _handleEnemyKilled,
      onReachedBase: _handleEnemyReachedBase,
      radius: bossDef == null ? 11 : 20,
      priority: 20,
    );
    _nextEnemyId += 1;
    _activeEnemyComponents[enemy.enemyId] = enemy;
    add(enemy);
  }

  void _handleSummonMinions(EnemyComponent source, int count) {
    // Defensive: the boss may have been resolved (reached base / killed) on
    // the same frame its summon timer expired, or the wave may have ended
    // already. Do not repopulate the board in those cases.
    if (!source.isAlive) return;
    if (_session.phase != GamePhase.wave) return;
    final mechanic = (source.stats as BossDefinition).summonMechanic;
    if (mechanic == null) return;
    final active = _activeEnemyComponents.values
        .where((e) => e.minionOf == source.enemyId && e.isAlive)
        .length;
    final toSpawn = math.max(0, math.min(count, mechanic.maxActive - active));
    for (var i = 0; i < toSpawn; i++) {
      _spawnMinion(source, mechanic.minionStats);
    }
  }

  void _spawnMinion(EnemyComponent boss, EnemyStats stats) {
    final residualOffsets = boss.logic.residualWaypointsFromHere();
    if (residualOffsets.length < 2) return; // boss effectively at base; skip
    final logic = EnemyLogic(
      enemyId: _nextEnemyId,
      stats: stats,
      waypoints: residualOffsets,
      initialCompletedDistance: boss.logic.pathProgress,
      modifierProfile: _enemyModifierProfile(stats),
    );
    final enemy = EnemyComponent(
      enemyId: _nextEnemyId,
      stats: stats,
      logic: logic,
      spriteSheet: _spriteSheet,
      towerVarietySheet: _towerVarietySheet,
      minionOf: boss.enemyId,
      onKilled: _handleEnemyKilled,
      onReachedBase: _handleEnemyReachedBase,
      priority: 20,
    );
    _nextEnemyId += 1;
    _activeEnemyComponents[enemy.enemyId] = enemy;
    add(enemy);
  }

  void _handleEnemyKilled(EnemyComponent enemy) {
    if (_inspectedEnemyId == enemy.enemyId) {
      _setInspectedEnemy(null);
    }
    _activeEnemyComponents.remove(enemy.enemyId);
    _session.rewardKill(
      StageModifierRules.effectiveKillReward(
        stats: enemy.stats,
        stageModifiers: stage.modifiers,
      ),
    );
    if (enemy.stats is BossDefinition) {
      gameFeedback.bossDefeated();
    }
    _publishSnapshot();
  }

  void _handleEnemyReachedBase(EnemyComponent enemy) {
    if (_inspectedEnemyId == enemy.enemyId) {
      _setInspectedEnemy(null);
    }
    _activeEnemyComponents.remove(enemy.enemyId);
    final phaseBeforeDamage = _session.phase;
    _session.damageBase(enemy.stats.baseDamage);
    final didLose =
        phaseBeforeDamage == GamePhase.wave && _session.phase == GamePhase.lost;

    if (didLose) {
      gameFeedback.baseDefeated();
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
    if (didWin) {
      gameFeedback.missionVictory();
    } else {
      gameFeedback.waveCleared();
    }
    final hasPendingDraft = _session.pendingRunModuleOffer != null;
    _resetWaveSpawnState();
    if (didWin) {
      _resetPacing();
    } else if (hasPendingDraft) {
      _autoStartCountdownRemaining = null;
    } else {
      _startAutoStartCountdownIfNeeded();
    }
    StageCompletion? completion;
    if (didWin) {
      completion = StageCompletion(
        stage: stage,
        result: StageResult.fromVictoryBaseHealth(
          _session.baseHealth,
          startingBaseHealth: _session.startingBaseHealth,
        ),
      );
    }
    _layoutBoardIfReady();
    _publishSnapshot();
    if (completion != null) {
      onStageWon?.call(completion);
    }
  }

  void _removeInactiveEnemyReferences() {
    final inspectedEnemyId = _inspectedEnemyId;
    if (inspectedEnemyId != null) {
      final inspectedEnemy = _activeEnemyComponents[inspectedEnemyId];
      if (inspectedEnemy == null || inspectedEnemy.isResolved) {
        _setInspectedEnemy(null);
      }
    }

    _activeEnemyComponents.removeWhere((_, enemy) => enemy.isResolved);
  }

  void _clearCombatComponents({required bool removeTowers}) {
    _setInspectedEnemy(null);
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
      PlacementFailure.pendingModuleDraft => 'Choose a Salvage Module first.',
      PlacementFailure.offBoard => 'Select a cell on the board.',
      PlacementFailure.pathBlocked => 'Cannot build on the enemy path.',
      PlacementFailure.occupied => 'That cell already has a tower.',
      PlacementFailure.insufficientGold => 'Not enough gold for that tower.',
      PlacementFailure.lockedTower => 'That tower unlocks after a later wave.',
      null => 'Cannot place a tower there.',
    };
  }

  String? _draftBlockMessage() => _session.pendingRunModuleOffer == null
      ? null
      : 'Choose a Salvage Module first.';

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
