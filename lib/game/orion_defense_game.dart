import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import 'assets/game_path_tiles.dart';
import 'assets/game_sprite_sheet.dart';
import 'assets/game_terrain.dart';
import 'components/board_component.dart';
import 'components/enemy_component.dart';
import 'components/projectile_component.dart';
import 'components/tower_component.dart';
import 'models/game_models.dart';
import 'rules/board_layout.dart';
import 'rules/game_session.dart';
import 'rules/tower_targeting.dart';

class OrionDefenseGame extends FlameGame with TapCallbacks {
  final GameSession _session = GameSession.initial();

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

  GamePathTiles? _pathTiles;
  GameSpriteSheet? _spriteSheet;
  Image? _terrainImage;
  final Map<int, TowerComponent> _towerComponents = {};
  final Map<int, EnemyComponent> _activeEnemyComponents = {};

  GameSnapshot get snapshot => stateNotifier.value;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _terrainImage = await images.load(GameTerrain.fileName);
    _pathTiles = await GamePathTiles.load(images);
    _spriteSheet = await GameSpriteSheet.load(images);
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

  void startWave() {
    if (!_session.startWave()) {
      _publishSnapshot(feedback: 'Wave cannot start right now.');
      return;
    }

    _spawnTimer = 0;
    _spawnedCount = 0;
    _activeGroupIndex = 0;
    _spawnedInGroup = 0;
    _clearSelection();
    _publishSnapshot();
  }

  void restart() {
    _clearCombatComponents(removeTowers: true);
    _spawnTimer = 0;
    _spawnedCount = 0;
    _activeGroupIndex = 0;
    _spawnedInGroup = 0;
    _nextEnemyId = 1;
    _clearSelection();
    _session.restart();
    _layoutBoard(size);
    _publishSnapshot();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _removeInactiveEnemyReferences();

    if (_session.phase != GamePhase.wave) {
      return;
    }

    _spawnWaveEnemies(dt);
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
    add(
      ProjectileComponent(
        stats: tower.stats,
        target: target,
        startPosition: tower.position,
        enemiesProvider: () => _activeEnemyComponents.values,
        spriteSheet: _spriteSheet,
        priority: 30,
      ),
    );
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
      _spawnTimer = 0;
      _spawnedCount = 0;
      _activeGroupIndex = 0;
      _spawnedInGroup = 0;
      _layoutBoard(size);
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
    _spawnTimer = 0;
    _spawnedCount = 0;
    _activeGroupIndex = 0;
    _spawnedInGroup = 0;
    _layoutBoard(size);
    _publishSnapshot();
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
    if (removeTowers) {
      for (final tower in _towerComponents.values.toList()) {
        tower.removeFromParent();
      }
      _towerComponents.clear();
    }
    _activeEnemyComponents.clear();
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
    return BoardLayout.pathCells.map(_cellCenter).toList(growable: false);
  }

  void _clearSelection() {
    _selectedCell = null;
    _selectedTower = null;
    _board?.selectedCell = null;
  }

  void _publishSnapshot({String? feedback}) {
    stateNotifier.value = _session.snapshot(
      selectedCell: _selectedCell,
      selectedTower: _selectedTower,
      feedback: feedback,
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

  double get _towerRadius => (_cellSize * 0.28).clamp(8, 18).toDouble();
}
