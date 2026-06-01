# Orion Tower Defense MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the generated Flutter counter app with a portrait-first Flame tower-defense MVP where the player places and upgrades towers, starts five waves, wins, loses, and restarts.

**Architecture:** Use a lean Flame-first runtime with pure Dart rule/model classes for deterministic behavior and Flutter widgets for touch-friendly HUD panels. Keep balance, board layout, placement validation, economy, targeting, and wave progression outside rendering components so they can be tested without a running Flame canvas.

**Tech Stack:** Flutter, Dart, Flame, flutter_test, flutter_lints.

---

## File Structure

- Modify: `.gitignore`
  - Keep generated Flutter ignores; no game-specific change is expected.
- Modify: `pubspec.yaml`
  - Add `flame` as the game engine dependency.
- Modify: `pubspec.lock`
  - Updated by `flutter pub add flame`.
- Replace: `lib/main.dart`
  - Bootstrap `MaterialApp`, theme, and `OrionGamePage`.
- Create: `lib/game/models/game_models.dart`
  - Game enums, value types, balance data, snapshot data, and placement results.
- Create: `lib/game/rules/board_layout.dart`
  - Logical grid size, path cells, waypoint conversion, and cell-to-screen helpers.
- Create: `lib/game/rules/game_session.dart`
  - Pure Dart state for gold, base health, phase, tower placement, upgrades, wave start/completion, and restart.
- Create: `lib/game/rules/tower_targeting.dart`
  - Pure Dart target selection by range and closest-to-base progress.
- Create: `lib/game/components/board_component.dart`
  - Flame board, grid, path, placement highlight, and base/spawn rendering.
- Create: `lib/game/components/enemy_component.dart`
  - Enemy movement along waypoints, damage, kill callback, base-reach callback, and slow effects.
- Create: `lib/game/components/projectile_component.dart`
  - Visible projectile travel and safe hit resolution.
- Create: `lib/game/components/tower_component.dart`
  - Tower rendering, cooldowns, targeting, and projectile launch requests.
- Create: `lib/game/orion_defense_game.dart`
  - Flame runtime orchestration, tapping, waves, component spawning, state notifier, and restart.
- Create: `lib/game/ui/orion_game_page.dart`
  - `GameWidget` host plus Flutter HUD, tower picker, upgrade panel, start-wave button, and end-state panel.
- Replace: `test/widget_test.dart`
  - Smoke test for the new game shell.
- Create: `test/game/game_balance_test.dart`
  - Balance, tower stats, wave definitions.
- Create: `test/game/board_layout_test.dart`
  - Board/path invariants.
- Create: `test/game/game_session_test.dart`
  - Placement, economy, upgrades, phases, wave progression, win/loss, restart.
- Create: `test/game/tower_targeting_test.dart`
  - Targeting priority and range filtering.

## Task 0: Commit Generated Flutter Baseline

**Files:**
- Add: `.gitignore`
- Add: `.metadata`
- Add: `README.md`
- Add: `analysis_options.yaml`
- Add: `android/`
- Add: `ios/`
- Add: `lib/main.dart`
- Add: `linux/`
- Add: `macos/`
- Add: `pubspec.lock`
- Add: `pubspec.yaml`
- Add: `test/widget_test.dart`
- Add: `web/`
- Add: `windows/`

- [ ] **Step 1: Confirm generated files are untracked**

Run: `git status --short`

Expected: generated Flutter files are listed as `??`, and the design spec commit already exists.

- [ ] **Step 2: Add the generated Flutter baseline**

Run:

```bash
git add .gitignore .metadata README.md analysis_options.yaml android ios lib linux macos pubspec.lock pubspec.yaml test web windows
```

Expected: the generated Flutter starter files are staged.

- [ ] **Step 3: Commit the generated Flutter baseline**

Run:

```bash
git commit -m "chore: add generated Flutter baseline"
```

Expected: commit succeeds and gives the implementation a clean baseline after the design spec.

## Task 1: Add Flame Dependency

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`

- [ ] **Step 1: Add Flame**

Run:

```bash
flutter pub add flame
```

Expected: `pubspec.yaml` gains a `flame:` dependency and `pubspec.lock` records the resolved version.

- [ ] **Step 2: Verify dependency resolution**

Run:

```bash
rg -n "flame:" pubspec.yaml pubspec.lock
```

Expected: both files contain `flame:` entries.

- [ ] **Step 3: Run the current tests before app replacement**

Run:

```bash
flutter test
```

Expected: the existing counter smoke test passes before the game code is introduced.

- [ ] **Step 4: Commit dependency setup**

Run:

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add Flame dependency"
```

Expected: only dependency files are committed.

## Task 2: Add Game Models and Balance

**Files:**
- Create: `lib/game/models/game_models.dart`
- Create: `test/game/game_balance_test.dart`

- [ ] **Step 1: Write failing balance tests**

Create `test/game/game_balance_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('GameBalance', () {
    test('matches the approved starting economy and base health', () {
      expect(GameBalance.startingGold, 120);
      expect(GameBalance.initialBaseHealth, 20);
    });

    test('defines exactly five waves with escalating pressure', () {
      expect(GameBalance.waves, hasLength(5));
      expect(GameBalance.waves.first.enemyCount, 8);
      expect(GameBalance.waves.first.enemyStats.health, 30);
      expect(GameBalance.waves.first.enemyStats.baseDamage, 1);
      expect(GameBalance.waves.first.enemyStats.goldReward, 8);
      expect(GameBalance.waves.last.enemyCount, 16);
      expect(GameBalance.waves.last.enemyStats.health, 100);
      expect(GameBalance.waves.last.enemyStats.baseDamage, 2);
      expect(GameBalance.waves.last.enemyStats.goldReward, 12);
    });

    test('defines base and upgraded stats for every tower', () {
      for (final type in TowerType.values) {
        final base = GameBalance.towerStats(type, level: 1);
        final upgraded = GameBalance.towerStats(type, level: 2);

        expect(base.cost, greaterThan(0));
        expect(base.upgradeCost, greaterThan(0));
        expect(base.range, greaterThan(0));
        expect(base.damage, greaterThan(0));
        expect(base.fireInterval, greaterThan(0));
        expect(upgraded.damage, greaterThanOrEqualTo(base.damage));
        expect(upgraded.range, greaterThanOrEqualTo(base.range));
      }
    });

    test('rejects unsupported tower levels', () {
      expect(
        () => GameBalance.towerStats(TowerType.laser, level: 0),
        throwsArgumentError,
      );
      expect(
        () => GameBalance.towerStats(TowerType.laser, level: 3),
        throwsArgumentError,
      );
    });
  });
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
flutter test test/game/game_balance_test.dart
```

Expected: fail because `package:orion/game/models/game_models.dart` does not exist.

- [ ] **Step 3: Add game model and balance code**

Create `lib/game/models/game_models.dart`:

```dart
import 'dart:math' as math;

enum GamePhase { build, wave, won, lost }

enum TowerType { laser, rocket, cryo }

enum PlacementFailure { offBoard, pathBlocked, occupied, insufficientGold }

class GridPosition {
  const GridPosition(this.column, this.row);

  final int column;
  final int row;

  double distanceTo(GridPosition other) {
    final dx = column - other.column;
    final dy = row - other.row;
    return math.sqrt((dx * dx) + (dy * dy));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is GridPosition &&
            runtimeType == other.runtimeType &&
            column == other.column &&
            row == other.row;
  }

  @override
  int get hashCode => Object.hash(column, row);

  @override
  String toString() => 'GridPosition(column: $column, row: $row)';
}

class PlacementResult {
  const PlacementResult._({required this.isAllowed, this.failure});

  const PlacementResult.allowed()
      : this._(isAllowed: true);

  const PlacementResult.denied(PlacementFailure failure)
      : this._(isAllowed: false, failure: failure);

  final bool isAllowed;
  final PlacementFailure? failure;
}

class TowerStats {
  const TowerStats({
    required this.type,
    required this.level,
    required this.cost,
    required this.upgradeCost,
    required this.range,
    required this.damage,
    required this.fireInterval,
    required this.projectileSpeed,
    required this.splashRadius,
    required this.slowMultiplier,
    required this.slowDuration,
  });

  final TowerType type;
  final int level;
  final int cost;
  final int upgradeCost;
  final double range;
  final double damage;
  final double fireInterval;
  final double projectileSpeed;
  final double splashRadius;
  final double slowMultiplier;
  final double slowDuration;

  bool get canUpgrade => level == 1;
}

class EnemyStats {
  const EnemyStats({
    required this.health,
    required this.speed,
    required this.baseDamage,
    required this.goldReward,
  });

  final double health;
  final double speed;
  final int baseDamage;
  final int goldReward;
}

class WaveDefinition {
  const WaveDefinition({
    required this.enemyCount,
    required this.enemyStats,
    this.spawnInterval = 0.9,
  });

  final int enemyCount;
  final EnemyStats enemyStats;
  final double spawnInterval;
}

class PlacedTower {
  const PlacedTower({
    required this.id,
    required this.type,
    required this.position,
    this.level = 1,
  });

  final int id;
  final TowerType type;
  final GridPosition position;
  final int level;

  PlacedTower upgraded() {
    if (level >= 2) {
      throw StateError('Tower is already upgraded');
    }
    return PlacedTower(id: id, type: type, position: position, level: level + 1);
  }
}

class GameSnapshot {
  const GameSnapshot({
    required this.phase,
    required this.gold,
    required this.baseHealth,
    required this.waveNumber,
    required this.selectedCell,
    required this.selectedTower,
    required this.feedback,
  });

  final GamePhase phase;
  final int gold;
  final int baseHealth;
  final int waveNumber;
  final GridPosition? selectedCell;
  final PlacedTower? selectedTower;
  final String? feedback;

  bool get canStartWave => phase == GamePhase.build;
  bool get isEnded => phase == GamePhase.won || phase == GamePhase.lost;
}

class GameBalance {
  static const int startingGold = 120;
  static const int initialBaseHealth = 20;

  static const List<WaveDefinition> waves = [
    WaveDefinition(
      enemyCount: 8,
      enemyStats: EnemyStats(
        health: 30,
        speed: 72,
        baseDamage: 1,
        goldReward: 8,
      ),
    ),
    WaveDefinition(
      enemyCount: 10,
      enemyStats: EnemyStats(
        health: 42,
        speed: 76,
        baseDamage: 1,
        goldReward: 9,
      ),
    ),
    WaveDefinition(
      enemyCount: 12,
      enemyStats: EnemyStats(
        health: 58,
        speed: 80,
        baseDamage: 1,
        goldReward: 10,
      ),
    ),
    WaveDefinition(
      enemyCount: 14,
      enemyStats: EnemyStats(
        health: 76,
        speed: 84,
        baseDamage: 2,
        goldReward: 11,
      ),
    ),
    WaveDefinition(
      enemyCount: 16,
      enemyStats: EnemyStats(
        health: 100,
        speed: 88,
        baseDamage: 2,
        goldReward: 12,
      ),
    ),
  ];

  static TowerStats towerStats(TowerType type, {required int level}) {
    if (level != 1 && level != 2) {
      throw ArgumentError.value(level, 'level', 'Tower level must be 1 or 2');
    }

    return switch ((type, level)) {
      (TowerType.laser, 1) => const TowerStats(
          type: TowerType.laser,
          level: 1,
          cost: 50,
          upgradeCost: 70,
          range: 145,
          damage: 12,
          fireInterval: 0.42,
          projectileSpeed: 420,
          splashRadius: 0,
          slowMultiplier: 1,
          slowDuration: 0,
        ),
      (TowerType.laser, 2) => const TowerStats(
          type: TowerType.laser,
          level: 2,
          cost: 50,
          upgradeCost: 70,
          range: 160,
          damage: 18,
          fireInterval: 0.34,
          projectileSpeed: 460,
          splashRadius: 0,
          slowMultiplier: 1,
          slowDuration: 0,
        ),
      (TowerType.rocket, 1) => const TowerStats(
          type: TowerType.rocket,
          level: 1,
          cost: 80,
          upgradeCost: 100,
          range: 165,
          damage: 26,
          fireInterval: 1.15,
          projectileSpeed: 300,
          splashRadius: 58,
          slowMultiplier: 1,
          slowDuration: 0,
        ),
      (TowerType.rocket, 2) => const TowerStats(
          type: TowerType.rocket,
          level: 2,
          cost: 80,
          upgradeCost: 100,
          range: 180,
          damage: 40,
          fireInterval: 1.0,
          projectileSpeed: 330,
          splashRadius: 72,
          slowMultiplier: 1,
          slowDuration: 0,
        ),
      (TowerType.cryo, 1) => const TowerStats(
          type: TowerType.cryo,
          level: 1,
          cost: 70,
          upgradeCost: 90,
          range: 135,
          damage: 5,
          fireInterval: 0.85,
          projectileSpeed: 360,
          splashRadius: 0,
          slowMultiplier: 0.62,
          slowDuration: 1.4,
        ),
      (TowerType.cryo, 2) => const TowerStats(
          type: TowerType.cryo,
          level: 2,
          cost: 70,
          upgradeCost: 90,
          range: 150,
          damage: 8,
          fireInterval: 0.72,
          projectileSpeed: 390,
          splashRadius: 0,
          slowMultiplier: 0.48,
          slowDuration: 2.0,
        ),
    };
  }
}
```

- [ ] **Step 4: Run balance tests**

Run:

```bash
flutter test test/game/game_balance_test.dart
```

Expected: all tests in `game_balance_test.dart` pass.

- [ ] **Step 5: Commit models and balance**

Run:

```bash
git add lib/game/models/game_models.dart test/game/game_balance_test.dart
git commit -m "feat: add tower defense models and balance"
```

Expected: commit succeeds with the new model file and balance test.

## Task 3: Add Board Layout Rules

**Files:**
- Create: `lib/game/rules/board_layout.dart`
- Create: `test/game/board_layout_test.dart`

- [ ] **Step 1: Write failing board layout tests**

Create `test/game/board_layout_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/board_layout.dart';

void main() {
  group('BoardLayout', () {
    test('uses a portrait-friendly 8 by 12 grid', () {
      expect(BoardLayout.columns, 8);
      expect(BoardLayout.rows, 12);
    });

    test('recognizes in-bounds and out-of-bounds cells', () {
      expect(BoardLayout.isInBounds(const GridPosition(0, 0)), isTrue);
      expect(BoardLayout.isInBounds(const GridPosition(7, 11)), isTrue);
      expect(BoardLayout.isInBounds(const GridPosition(-1, 0)), isFalse);
      expect(BoardLayout.isInBounds(const GridPosition(8, 0)), isFalse);
      expect(BoardLayout.isInBounds(const GridPosition(0, 12)), isFalse);
    });

    test('defines a continuous fixed path from spawn to base', () {
      expect(BoardLayout.pathCells.first, const GridPosition(0, 1));
      expect(BoardLayout.pathCells.last, const GridPosition(7, 10));

      for (var index = 1; index < BoardLayout.pathCells.length; index += 1) {
        final previous = BoardLayout.pathCells[index - 1];
        final current = BoardLayout.pathCells[index];
        expect(previous.distanceTo(current), 1);
      }
    });

    test('distinguishes path and buildable cells', () {
      expect(BoardLayout.isPathCell(const GridPosition(3, 4)), isTrue);
      expect(BoardLayout.isBuildableCell(const GridPosition(3, 4)), isFalse);
      expect(BoardLayout.isBuildableCell(const GridPosition(0, 0)), isTrue);
      expect(BoardLayout.isBuildableCell(const GridPosition(7, 11)), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run the failing board layout test**

Run:

```bash
flutter test test/game/board_layout_test.dart
```

Expected: fail because `BoardLayout` does not exist.

- [ ] **Step 3: Add board layout rules**

Create `lib/game/rules/board_layout.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../models/game_models.dart';

class BoardLayout {
  static const int columns = 8;
  static const int rows = 12;

  static const List<GridPosition> pathCells = [
    GridPosition(0, 1),
    GridPosition(1, 1),
    GridPosition(2, 1),
    GridPosition(3, 1),
    GridPosition(3, 2),
    GridPosition(3, 3),
    GridPosition(3, 4),
    GridPosition(4, 4),
    GridPosition(5, 4),
    GridPosition(6, 4),
    GridPosition(6, 5),
    GridPosition(6, 6),
    GridPosition(5, 6),
    GridPosition(4, 6),
    GridPosition(3, 6),
    GridPosition(2, 6),
    GridPosition(2, 7),
    GridPosition(2, 8),
    GridPosition(2, 9),
    GridPosition(3, 9),
    GridPosition(4, 9),
    GridPosition(5, 9),
    GridPosition(6, 9),
    GridPosition(7, 9),
    GridPosition(7, 10),
  ];

  static bool isInBounds(GridPosition position) {
    return position.column >= 0 &&
        position.column < columns &&
        position.row >= 0 &&
        position.row < rows;
  }

  static bool isPathCell(GridPosition position) {
    return pathCells.contains(position);
  }

  static bool isBuildableCell(GridPosition position) {
    return isInBounds(position) && !isPathCell(position);
  }

  static Offset cellCenter(
    GridPosition position, {
    required double cellSize,
    required Offset boardOrigin,
  }) {
    return Offset(
      boardOrigin.dx + (position.column + 0.5) * cellSize,
      boardOrigin.dy + (position.row + 0.5) * cellSize,
    );
  }

  static GridPosition? cellAt(
    Offset point, {
    required double cellSize,
    required Offset boardOrigin,
  }) {
    final local = point - boardOrigin;
    final column = local.dx ~/ cellSize;
    final row = local.dy ~/ cellSize;
    final position = GridPosition(column, row);
    return isInBounds(position) ? position : null;
  }
}
```

- [ ] **Step 4: Run board layout tests**

Run:

```bash
flutter test test/game/board_layout_test.dart
```

Expected: all board layout tests pass.

- [ ] **Step 5: Commit board layout rules**

Run:

```bash
git add lib/game/rules/board_layout.dart test/game/board_layout_test.dart
git commit -m "feat: add tower defense board layout"
```

Expected: commit succeeds with board layout code and tests.

## Task 4: Add Pure Game Session Rules

**Files:**
- Create: `lib/game/rules/game_session.dart`
- Create: `test/game/game_session_test.dart`

- [ ] **Step 1: Write failing session tests**

Create `test/game/game_session_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/game_session.dart';

void main() {
  group('GameSession', () {
    test('starts in build phase with approved economy', () {
      final session = GameSession.initial();

      expect(session.phase, GamePhase.build);
      expect(session.gold, 120);
      expect(session.baseHealth, 20);
      expect(session.waveIndex, 0);
      expect(session.towers, isEmpty);
    });

    test('validates invalid placements without spending gold', () {
      final session = GameSession.initial();

      expect(
        session.validatePlacement(const GridPosition(-1, 0), TowerType.laser).failure,
        PlacementFailure.offBoard,
      );
      expect(
        session.validatePlacement(const GridPosition(0, 1), TowerType.laser).failure,
        PlacementFailure.pathBlocked,
      );

      session.placeTower(const GridPosition(0, 0), TowerType.laser);
      expect(
        session.validatePlacement(const GridPosition(0, 0), TowerType.cryo).failure,
        PlacementFailure.occupied,
      );
      expect(session.gold, 70);
    });

    test('places towers and spends gold', () {
      final session = GameSession.initial();

      final result = session.placeTower(const GridPosition(0, 0), TowerType.rocket);

      expect(result.isAllowed, isTrue);
      expect(session.gold, 40);
      expect(session.towers.single.type, TowerType.rocket);
      expect(session.towers.single.level, 1);
    });

    test('denies purchase when gold is insufficient', () {
      final session = GameSession.initial(gold: 40);

      final result = session.placeTower(const GridPosition(0, 0), TowerType.laser);

      expect(result.isAllowed, isFalse);
      expect(result.failure, PlacementFailure.insufficientGold);
      expect(session.gold, 40);
      expect(session.towers, isEmpty);
    });

    test('upgrades a tower once and spends gold', () {
      final session = GameSession.initial(gold: 200);
      session.placeTower(const GridPosition(0, 0), TowerType.cryo);
      final tower = session.towers.single;

      final upgraded = session.upgradeTower(tower.id);

      expect(upgraded, isTrue);
      expect(session.towers.single.level, 2);
      expect(session.gold, 40);
      expect(session.upgradeTower(tower.id), isFalse);
    });

    test('starts waves only from build phase', () {
      final session = GameSession.initial();

      expect(session.startWave(), isTrue);
      expect(session.phase, GamePhase.wave);
      expect(session.startWave(), isFalse);
    });

    test('progresses through five waves and wins after the final clear', () {
      final session = GameSession.initial();

      for (var wave = 0; wave < 5; wave += 1) {
        expect(session.startWave(), isTrue);
        session.finishActiveWave();
      }

      expect(session.phase, GamePhase.won);
      expect(session.waveIndex, 5);
    });

    test('loses when base health reaches zero and clamps health', () {
      final session = GameSession.initial(baseHealth: 2);

      session.damageBase(5);

      expect(session.baseHealth, 0);
      expect(session.phase, GamePhase.lost);
    });

    test('restart returns a clean initial state', () {
      final session = GameSession.initial();
      session.placeTower(const GridPosition(0, 0), TowerType.laser);
      session.startWave();
      session.damageBase(20);

      session.restart();

      expect(session.phase, GamePhase.build);
      expect(session.gold, 120);
      expect(session.baseHealth, 20);
      expect(session.waveIndex, 0);
      expect(session.towers, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the failing session tests**

Run:

```bash
flutter test test/game/game_session_test.dart
```

Expected: fail because `GameSession` does not exist.

- [ ] **Step 3: Add session rules**

Create `lib/game/rules/game_session.dart`:

```dart
import '../models/game_models.dart';
import 'board_layout.dart';

class GameSession {
  GameSession.initial({
    int? gold,
    int? baseHealth,
  })  : _gold = gold ?? GameBalance.startingGold,
        _baseHealth = baseHealth ?? GameBalance.initialBaseHealth;

  final Map<GridPosition, PlacedTower> _towersByPosition = {};
  int _nextTowerId = 1;
  int _gold;
  int _baseHealth;
  int _waveIndex = 0;
  GamePhase _phase = GamePhase.build;

  int get gold => _gold;
  int get baseHealth => _baseHealth;
  int get waveIndex => _waveIndex;
  GamePhase get phase => _phase;
  List<PlacedTower> get towers => List.unmodifiable(_towersByPosition.values);
  WaveDefinition? get activeWave {
    if (_waveIndex >= GameBalance.waves.length) {
      return null;
    }
    return GameBalance.waves[_waveIndex];
  }

  GameSnapshot snapshot({
    GridPosition? selectedCell,
    PlacedTower? selectedTower,
    String? feedback,
  }) {
    return GameSnapshot(
      phase: _phase,
      gold: _gold,
      baseHealth: _baseHealth,
      waveNumber: (_waveIndex + 1).clamp(1, GameBalance.waves.length).toInt(),
      selectedCell: selectedCell,
      selectedTower: selectedTower,
      feedback: feedback,
    );
  }

  PlacementResult validatePlacement(GridPosition position, TowerType type) {
    if (!BoardLayout.isInBounds(position)) {
      return const PlacementResult.denied(PlacementFailure.offBoard);
    }
    if (BoardLayout.isPathCell(position)) {
      return const PlacementResult.denied(PlacementFailure.pathBlocked);
    }
    if (_towersByPosition.containsKey(position)) {
      return const PlacementResult.denied(PlacementFailure.occupied);
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
    final entry = _findTowerEntry(towerId);
    if (entry == null) {
      return false;
    }

    final tower = entry.value;
    if (tower.level >= 2) {
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

  bool startWave() {
    if (_phase != GamePhase.build || _waveIndex >= GameBalance.waves.length) {
      return false;
    }
    _phase = GamePhase.wave;
    return true;
  }

  void finishActiveWave() {
    if (_phase != GamePhase.wave) {
      return;
    }

    _waveIndex += 1;
    _phase = _waveIndex >= GameBalance.waves.length ? GamePhase.won : GamePhase.build;
  }

  void rewardKill(int goldReward) {
    if (_phase == GamePhase.lost || _phase == GamePhase.won) {
      return;
    }
    _gold += goldReward;
  }

  void damageBase(int amount) {
    if (_phase == GamePhase.lost || _phase == GamePhase.won) {
      return;
    }
    _baseHealth = (_baseHealth - amount)
        .clamp(0, GameBalance.initialBaseHealth)
        .toInt();
    if (_baseHealth == 0) {
      _phase = GamePhase.lost;
    }
  }

  PlacedTower? towerAt(GridPosition position) => _towersByPosition[position];

  void restart() {
    _towersByPosition.clear();
    _nextTowerId = 1;
    _gold = GameBalance.startingGold;
    _baseHealth = GameBalance.initialBaseHealth;
    _waveIndex = 0;
    _phase = GamePhase.build;
  }

  MapEntry<GridPosition, PlacedTower>? _findTowerEntry(int towerId) {
    for (final entry in _towersByPosition.entries) {
      if (entry.value.id == towerId) {
        return entry;
      }
    }
    return null;
  }
}
```

- [ ] **Step 4: Run session tests**

Run:

```bash
flutter test test/game/game_session_test.dart
```

Expected: all session tests pass.

- [ ] **Step 5: Commit session rules**

Run:

```bash
git add lib/game/rules/game_session.dart test/game/game_session_test.dart
git commit -m "feat: add tower defense session rules"
```

Expected: commit succeeds with session logic and tests.

## Task 5: Add Targeting Rules

**Files:**
- Create: `lib/game/rules/tower_targeting.dart`
- Create: `test/game/tower_targeting_test.dart`

- [ ] **Step 1: Write failing targeting tests**

Create `test/game/tower_targeting_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/rules/tower_targeting.dart';

void main() {
  group('TowerTargeting', () {
    test('selects the in-range enemy closest to the base', () {
      const tower = TargetPoint(x: 0, y: 0);
      const candidates = [
        TargetCandidate(id: 1, x: 20, y: 0, pathProgress: 0.2, isAlive: true),
        TargetCandidate(id: 2, x: 70, y: 0, pathProgress: 0.9, isAlive: true),
        TargetCandidate(id: 3, x: 30, y: 0, pathProgress: 0.5, isAlive: true),
      ];

      final target = TowerTargeting.selectTarget(
        tower: tower,
        range: 80,
        candidates: candidates,
      );

      expect(target?.id, 2);
    });

    test('ignores enemies outside range or already dead', () {
      const target = TowerTargeting.selectTarget(
        tower: TargetPoint(x: 0, y: 0),
        range: 40,
        candidates: [
          TargetCandidate(id: 1, x: 100, y: 0, pathProgress: 0.9, isAlive: true),
          TargetCandidate(id: 2, x: 10, y: 0, pathProgress: 0.8, isAlive: false),
        ],
      );

      expect(target, isNull);
    });
  });
}
```

- [ ] **Step 2: Run the failing targeting tests**

Run:

```bash
flutter test test/game/tower_targeting_test.dart
```

Expected: fail because `TowerTargeting` does not exist.

- [ ] **Step 3: Add targeting rules**

Create `lib/game/rules/tower_targeting.dart`:

```dart
class TargetPoint {
  const TargetPoint({required this.x, required this.y});

  final double x;
  final double y;
}

class TargetCandidate {
  const TargetCandidate({
    required this.id,
    required this.x,
    required this.y,
    required this.pathProgress,
    required this.isAlive,
  });

  final int id;
  final double x;
  final double y;
  final double pathProgress;
  final bool isAlive;
}

class TowerTargeting {
  static TargetCandidate? selectTarget({
    required TargetPoint tower,
    required double range,
    required Iterable<TargetCandidate> candidates,
  }) {
    final rangeSquared = range * range;
    TargetCandidate? selected;

    for (final candidate in candidates) {
      if (!candidate.isAlive) {
        continue;
      }

      final dx = candidate.x - tower.x;
      final dy = candidate.y - tower.y;
      final distanceSquared = (dx * dx) + (dy * dy);
      if (distanceSquared > rangeSquared) {
        continue;
      }

      if (selected == null || candidate.pathProgress > selected.pathProgress) {
        selected = candidate;
      }
    }

    return selected;
  }
}
```

- [ ] **Step 4: Run targeting tests**

Run:

```bash
flutter test test/game/tower_targeting_test.dart
```

Expected: all targeting tests pass.

- [ ] **Step 5: Run all pure rule tests**

Run:

```bash
flutter test test/game
```

Expected: all tests under `test/game` pass.

- [ ] **Step 6: Commit targeting rules**

Run:

```bash
git add lib/game/rules/tower_targeting.dart test/game/tower_targeting_test.dart
git commit -m "feat: add tower targeting rules"
```

Expected: commit succeeds with targeting logic and tests.

## Task 6: Add Flame Board and Combat Components

**Files:**
- Create: `lib/game/components/board_component.dart`
- Create: `lib/game/components/enemy_component.dart`
- Create: `lib/game/components/projectile_component.dart`
- Create: `lib/game/components/tower_component.dart`

- [ ] **Step 1: Create board component**

Create `lib/game/components/board_component.dart`:

```dart
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../rules/board_layout.dart';

class BoardComponent extends PositionComponent {
  BoardComponent({
    required this.cellSize,
    required this.boardOrigin,
    required this.selectedCell,
  }) : super(
          position: Vector2(boardOrigin.dx, boardOrigin.dy),
          size: Vector2(
            BoardLayout.columns * cellSize,
            BoardLayout.rows * cellSize,
          ),
        );

  final double cellSize;
  final Offset boardOrigin;
  GridPosition? selectedCell;

  @override
  void render(Canvas canvas) {
    final boardRect = Offset.zero & Size(size.x, size.y);
    final background = Paint()..color = const Color(0xFF08111F);
    canvas.drawRect(boardRect, background);

    final gridPaint = Paint()
      ..color = const Color(0xFF1E385A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var column = 0; column <= BoardLayout.columns; column += 1) {
      final x = column * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), gridPaint);
    }
    for (var row = 0; row <= BoardLayout.rows; row += 1) {
      final y = row * cellSize;
      canvas.drawLine(Offset(0, y), Offset(size.x, y), gridPaint);
    }

    final pathPaint = Paint()..color = const Color(0xFF2E5E8F);
    for (final cell in BoardLayout.pathCells) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            cell.column * cellSize + 2,
            cell.row * cellSize + 2,
            cellSize - 4,
            cellSize - 4,
          ),
          const Radius.circular(6),
        ),
        pathPaint,
      );
    }

    final selected = selectedCell;
    if (selected != null) {
      final paint = Paint()
        ..color = BoardLayout.isBuildableCell(selected)
            ? const Color(0x6631E6A1)
            : const Color(0x66FF5A6A);
      canvas.drawRect(
        Rect.fromLTWH(
          selected.column * cellSize,
          selected.row * cellSize,
          cellSize,
          cellSize,
        ),
        paint,
      );
    }

    final spawnPaint = Paint()..color = const Color(0xFF31E6A1);
    final basePaint = Paint()..color = const Color(0xFFFFC857);
    canvas.drawCircle(
      Offset(cellSize * 0.5, cellSize * 1.5),
      cellSize * 0.24,
      spawnPaint,
    );
    canvas.drawCircle(
      Offset(cellSize * 7.5, cellSize * 10.5),
      cellSize * 0.28,
      basePaint,
    );
  }
}
```

- [ ] **Step 2: Create enemy component**

Create `lib/game/components/enemy_component.dart`:

```dart
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../rules/tower_targeting.dart';

class EnemyComponent extends CircleComponent {
  EnemyComponent({
    required this.enemyId,
    required this.stats,
    required this.waypoints,
    required this.onKilled,
    required this.onReachedBase,
  })  : health = stats.health,
        super(
          radius: 10,
          anchor: Anchor.center,
          paint: Paint()..color = const Color(0xFFFF5A6A),
        ) {
    position = waypoints.first.clone();
  }

  final int enemyId;
  final EnemyStats stats;
  final List<Vector2> waypoints;
  final void Function(EnemyComponent enemy) onKilled;
  final void Function(EnemyComponent enemy) onReachedBase;

  double health;
  int _waypointIndex = 1;
  double _slowRemaining = 0;
  double _slowMultiplier = 1;
  bool _resolved = false;

  bool get isAlive => !_resolved && health > 0;
  double get pathProgress {
    final base = (_waypointIndex - 1).clamp(0, waypoints.length - 1).toDouble();
    return base / (waypoints.length - 1);
  }

  TargetCandidate get targetCandidate {
    return TargetCandidate(
      id: enemyId,
      x: position.x,
      y: position.y,
      pathProgress: pathProgress,
      isAlive: isAlive,
    );
  }

  void applyDamage(double amount) {
    if (!isAlive) {
      return;
    }
    health -= amount;
    if (health <= 0) {
      _resolved = true;
      onKilled(this);
      removeFromParent();
    }
  }

  void applySlow({
    required double multiplier,
    required double duration,
  }) {
    if (!isAlive || duration <= 0 || multiplier >= 1) {
      return;
    }
    _slowMultiplier = math.min(_slowMultiplier, multiplier);
    _slowRemaining = math.max(_slowRemaining, duration);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isAlive || waypoints.length < 2) {
      return;
    }

    if (_slowRemaining > 0) {
      _slowRemaining -= dt;
      if (_slowRemaining <= 0) {
        _slowMultiplier = 1;
      }
    }

    final target = waypoints[_waypointIndex];
    final direction = target - position;
    final distance = direction.length;
    final travel = stats.speed * _slowMultiplier * dt;

    if (distance <= travel) {
      position = target.clone();
      _waypointIndex += 1;
      if (_waypointIndex >= waypoints.length) {
        _resolved = true;
        onReachedBase(this);
        removeFromParent();
      }
      return;
    }

    position += direction.normalized() * travel;
  }
}
```

- [ ] **Step 3: Create projectile component**

Create `lib/game/components/projectile_component.dart`:

```dart
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../models/game_models.dart';
import 'enemy_component.dart';

class ProjectileComponent extends CircleComponent {
  ProjectileComponent({
    required this.stats,
    required this.target,
    required Vector2 start,
    required this.enemiesProvider,
  }) : super(
          radius: stats.type == TowerType.rocket ? 5 : 3,
          anchor: Anchor.center,
          position: start,
          paint: Paint()
            ..color = switch (stats.type) {
              TowerType.laser => const Color(0xFF31E6A1),
              TowerType.rocket => const Color(0xFFFFC857),
              TowerType.cryo => const Color(0xFF73D2FF),
            },
        );

  final TowerStats stats;
  final EnemyComponent target;
  final Iterable<EnemyComponent> Function() enemiesProvider;

  @override
  void update(double dt) {
    super.update(dt);
    if (!target.isAlive || target.isRemoving) {
      removeFromParent();
      return;
    }

    final direction = target.position - position;
    final distance = direction.length;
    final travel = stats.projectileSpeed * dt;
    if (distance <= travel) {
      _resolveHit();
      removeFromParent();
      return;
    }
    position += direction.normalized() * travel;
  }

  void _resolveHit() {
    if (stats.splashRadius > 0) {
      for (final enemy in enemiesProvider()) {
        if (!enemy.isAlive) {
          continue;
        }
        if (enemy.position.distanceTo(target.position) <= stats.splashRadius) {
          enemy.applyDamage(stats.damage);
        }
      }
      return;
    }

    target.applyDamage(stats.damage);
    if (stats.slowDuration > 0) {
      target.applySlow(
        multiplier: stats.slowMultiplier,
        duration: stats.slowDuration,
      );
    }
  }
}
```

- [ ] **Step 4: Create tower component**

Create `lib/game/components/tower_component.dart`:

```dart
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../rules/tower_targeting.dart';
import 'enemy_component.dart';

class TowerComponent extends CircleComponent {
  TowerComponent({
    required this.tower,
    required this.center,
    required this.acquireTarget,
    required this.fireProjectile,
  }) : super(
          radius: tower.level == 1 ? 13 : 16,
          anchor: Anchor.center,
          position: center,
          paint: Paint()
            ..color = switch (tower.type) {
              TowerType.laser => const Color(0xFF31E6A1),
              TowerType.rocket => const Color(0xFFFFC857),
              TowerType.cryo => const Color(0xFF73D2FF),
            },
        );

  PlacedTower tower;
  final Vector2 center;
  final EnemyComponent? Function(TargetPoint point, double range) acquireTarget;
  final void Function(TowerComponent tower, EnemyComponent target) fireProjectile;
  double _cooldown = 0;

  TowerStats get stats => GameBalance.towerStats(tower.type, level: tower.level);

  void updateTower(PlacedTower updated) {
    tower = updated;
    radius = updated.level == 1 ? 13 : 16;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _cooldown -= dt;
    if (_cooldown > 0) {
      return;
    }

    final target = acquireTarget(
      TargetPoint(x: position.x, y: position.y),
      stats.range,
    );
    if (target == null) {
      return;
    }

    fireProjectile(this, target);
    _cooldown = stats.fireInterval;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final stroke = Paint()
      ..color = const Color(0x55FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset.zero, radius, stroke);
  }
}
```

- [ ] **Step 5: Format component files**

Run:

```bash
dart format lib/game/components
```

Expected: formatter updates or confirms the component files.

- [ ] **Step 6: Run analyzer for component API issues**

Run:

```bash
flutter analyze
```

Expected: analyzer prints `No issues found!`.

- [ ] **Step 7: Commit components**

Run:

```bash
git add lib/game/components
git commit -m "feat: add tower defense Flame components"
```

Expected: commit succeeds with board, enemy, projectile, and tower components.

## Task 7: Add Flame Runtime

**Files:**
- Create: `lib/game/orion_defense_game.dart`

- [ ] **Step 1: Create the Flame game runtime**

Create `lib/game/orion_defense_game.dart`:

```dart
import 'dart:async';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import 'components/board_component.dart';
import 'components/enemy_component.dart';
import 'components/projectile_component.dart';
import 'components/tower_component.dart';
import 'models/game_models.dart';
import 'rules/board_layout.dart';
import 'rules/game_session.dart';
import 'rules/tower_targeting.dart';

class OrionDefenseGame extends FlameGame with TapCallbacks {
  OrionDefenseGame() {
    stateNotifier = ValueNotifier<GameSnapshot>(
      _session.snapshot(),
    );
  }

  final GameSession _session = GameSession.initial();
  late final ValueNotifier<GameSnapshot> stateNotifier;
  final Map<int, TowerComponent> _towerComponents = {};
  final List<EnemyComponent> _enemies = [];

  BoardComponent? _board;
  GridPosition? _selectedCell;
  PlacedTower? _selectedTower;
  double _cellSize = 40;
  Offset _boardOrigin = Offset.zero;
  double _spawnTimer = 0;
  int _spawnedInWave = 0;
  int _nextEnemyId = 1;

  GameSnapshot get snapshot => _session.snapshot(
        selectedCell: _selectedCell,
        selectedTower: _selectedTower,
      );

  @override
  FutureOr<void> onLoad() {
    _layoutBoard();
    _publish();
    return super.onLoad();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _layoutBoard();
  }

  void _layoutBoard() {
    if (size.x <= 0 || size.y <= 0) {
      return;
    }

    final availableWidth = size.x - 24;
    final availableHeight = size.y - 170;
    _cellSize = (availableWidth / BoardLayout.columns)
        .clamp(24, availableHeight / BoardLayout.rows)
        .toDouble();
    final boardWidth = BoardLayout.columns * _cellSize;
    _boardOrigin = Offset((size.x - boardWidth) / 2, 96);

    final existing = _board;
    if (existing != null) {
      existing.removeFromParent();
    }

    _board = BoardComponent(
      cellSize: _cellSize,
      boardOrigin: _boardOrigin,
      selectedCell: _selectedCell,
    );
    add(_board!);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (_session.phase == GamePhase.won || _session.phase == GamePhase.lost) {
      return;
    }

    final cell = BoardLayout.cellAt(
      Offset(event.localPosition.x, event.localPosition.y),
      cellSize: _cellSize,
      boardOrigin: _boardOrigin,
    );
    if (cell == null) {
      _clearSelection();
      return;
    }

    final tower = _session.towerAt(cell);
    _selectedCell = tower == null ? cell : null;
    _selectedTower = tower;
    _board?.selectedCell = cell;
    _publish();
  }

  void placeTower(TowerType type) {
    final cell = _selectedCell;
    if (cell == null) {
      return;
    }

    final result = _session.placeTower(cell, type);
    if (!result.isAllowed) {
      _publish(feedback: _placementMessage(result.failure));
      return;
    }

    final tower = _session.towerAt(cell)!;
    final center = _cellCenter(cell);
    final component = TowerComponent(
      tower: tower,
      center: center,
      acquireTarget: _acquireTarget,
      fireProjectile: _fireProjectile,
    );
    _towerComponents[tower.id] = component;
    add(component);
    _clearSelection();
  }

  void upgradeSelectedTower() {
    final tower = _selectedTower;
    if (tower == null) {
      return;
    }

    final upgraded = _session.upgradeTower(tower.id);
    if (!upgraded) {
      _publish(feedback: 'Not enough gold or tower already upgraded');
      return;
    }

    final updated = _session.towers.firstWhere((candidate) => candidate.id == tower.id);
    _selectedTower = updated;
    _towerComponents[tower.id]?.updateTower(updated);
    _publish();
  }

  void startWave() {
    if (!_session.startWave()) {
      return;
    }
    _spawnTimer = 0;
    _spawnedInWave = 0;
    _clearSelection();
  }

  void restart() {
    for (final enemy in List<EnemyComponent>.from(_enemies)) {
      enemy.removeFromParent();
    }
    for (final tower in _towerComponents.values) {
      tower.removeFromParent();
    }
    for (final projectile in List<ProjectileComponent>.from(
      children.whereType<ProjectileComponent>(),
    )) {
      projectile.removeFromParent();
    }

    _enemies.clear();
    _towerComponents.clear();
    _selectedCell = null;
    _selectedTower = null;
    _spawnTimer = 0;
    _spawnedInWave = 0;
    _nextEnemyId = 1;
    _session.restart();
    _board?.selectedCell = null;
    _publish();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_session.phase != GamePhase.wave) {
      return;
    }

    final wave = _session.activeWave;
    if (wave == null) {
      return;
    }

    _spawnTimer -= dt;
    if (_spawnedInWave < wave.enemyCount && _spawnTimer <= 0) {
      _spawnEnemy(wave.enemyStats);
      _spawnedInWave += 1;
      _spawnTimer = wave.spawnInterval;
    }

    _enemies.removeWhere((enemy) => enemy.isRemoving || !enemy.isAlive);
    if (_spawnedInWave >= wave.enemyCount && _enemies.isEmpty) {
      _session.finishActiveWave();
      _publish();
    }
  }

  EnemyComponent? _acquireTarget(TargetPoint point, double range) {
    final target = TowerTargeting.selectTarget(
      tower: point,
      range: range,
      candidates: _enemies.map((enemy) => enemy.targetCandidate),
    );
    if (target == null) {
      return null;
    }
    for (final enemy in _enemies) {
      if (enemy.enemyId == target.id && enemy.isAlive) {
        return enemy;
      }
    }
    return null;
  }

  void _fireProjectile(TowerComponent tower, EnemyComponent target) {
    add(
      ProjectileComponent(
        stats: tower.stats,
        target: target,
        start: tower.position.clone(),
        enemiesProvider: () => _enemies,
      ),
    );
  }

  void _spawnEnemy(EnemyStats stats) {
    final enemy = EnemyComponent(
      enemyId: _nextEnemyId,
      stats: stats,
      waypoints: _pathWaypoints(),
      onKilled: (enemy) {
        _session.rewardKill(enemy.stats.goldReward);
        _publish();
      },
      onReachedBase: (enemy) {
        _session.damageBase(enemy.stats.baseDamage);
        _publish();
      },
    );
    _nextEnemyId += 1;
    _enemies.add(enemy);
    add(enemy);
  }

  List<Vector2> _pathWaypoints() {
    return [
      for (final cell in BoardLayout.pathCells) _cellCenter(cell),
    ];
  }

  Vector2 _cellCenter(GridPosition cell) {
    final center = BoardLayout.cellCenter(
      cell,
      cellSize: _cellSize,
      boardOrigin: _boardOrigin,
    );
    return Vector2(center.dx, center.dy);
  }

  void _clearSelection() {
    _selectedCell = null;
    _selectedTower = null;
    _board?.selectedCell = null;
    _publish();
  }

  void _publish({String? feedback}) {
    stateNotifier.value = _session.snapshot(
      selectedCell: _selectedCell,
      selectedTower: _selectedTower,
      feedback: feedback,
    );
  }

  String _placementMessage(PlacementFailure? failure) {
    return switch (failure) {
      PlacementFailure.offBoard => 'Outside the grid',
      PlacementFailure.pathBlocked => 'Cannot build on the route',
      PlacementFailure.occupied => 'Cell already has a tower',
      PlacementFailure.insufficientGold => 'Not enough gold',
      null => 'Cannot place tower',
    };
  }
}
```

- [ ] **Step 2: Run analyzer**

Run:

```bash
flutter analyze
```

Expected: analyzer succeeds after resolving any installed Flame API differences in tap events or child iteration.

- [ ] **Step 3: Commit runtime**

Run:

```bash
git add lib/game/orion_defense_game.dart
git commit -m "feat: add Orion defense Flame runtime"
```

Expected: commit succeeds with the Flame runtime.

## Task 8: Add Flutter UI Shell and Replace Counter App

**Files:**
- Replace: `lib/main.dart`
- Create: `lib/game/ui/orion_game_page.dart`
- Replace: `test/widget_test.dart`

- [ ] **Step 1: Replace widget test with game shell smoke test**

Replace `test/widget_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/main.dart';

void main() {
  testWidgets('boots into the Orion tower defense shell', (tester) async {
    await tester.pumpWidget(const OrionApp());
    await tester.pump();

    expect(find.text('Orion'), findsOneWidget);
    expect(find.textContaining('Gold'), findsOneWidget);
    expect(find.textContaining('Base'), findsOneWidget);
    expect(find.textContaining('Wave'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the failing widget test**

Run:

```bash
flutter test test/widget_test.dart
```

Expected: fail because `OrionApp` does not exist and the counter app is still present.

- [ ] **Step 3: Replace main app bootstrap**

Replace `lib/main.dart`:

```dart
import 'package:flutter/material.dart';

import 'game/ui/orion_game_page.dart';

void main() {
  runApp(const OrionApp());
}

class OrionApp extends StatelessWidget {
  const OrionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Orion',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF31E6A1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const OrionGamePage(),
    );
  }
}
```

- [ ] **Step 4: Add game page and overlays**

Create `lib/game/ui/orion_game_page.dart`:

```dart
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../orion_defense_game.dart';

class OrionGamePage extends StatefulWidget {
  const OrionGamePage({super.key});

  @override
  State<OrionGamePage> createState() => _OrionGamePageState();
}

class _OrionGamePageState extends State<OrionGamePage> {
  late final OrionDefenseGame _game;

  @override
  void initState() {
    super.initState();
    _game = OrionDefenseGame();
  }

  @override
  void dispose() {
    _game.stateNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050B14),
      body: SafeArea(
        child: ValueListenableBuilder<GameSnapshot>(
          valueListenable: _game.stateNotifier,
          builder: (context, snapshot, _) {
            return Stack(
              children: [
                Positioned.fill(child: GameWidget(game: _game)),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 8,
                  child: _Hud(snapshot: snapshot),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _BottomControls(game: _game, snapshot: snapshot),
                ),
                if (snapshot.isEnded)
                  Positioned.fill(
                    child: _EndStatePanel(game: _game, snapshot: snapshot),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.snapshot});

  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Orion',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 8,
          children: [
            _HudChip(label: 'Base', value: '${snapshot.baseHealth}'),
            _HudChip(label: 'Gold', value: '${snapshot.gold}'),
            _HudChip(label: 'Wave', value: '${snapshot.waveNumber}/5'),
            _HudChip(label: 'Phase', value: snapshot.phase.name.toUpperCase()),
          ],
        ),
        if (snapshot.feedback != null) ...[
          const SizedBox(height: 8),
          Text(
            snapshot.feedback!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFFC857)),
          ),
        ],
      ],
    );
  }
}

class _HudChip extends StatelessWidget {
  const _HudChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC0D1B2A),
        border: Border.all(color: const Color(0xFF1E385A)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label $value'),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({required this.game, required this.snapshot});

  final OrionDefenseGame game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.selectedTower != null) {
      return _UpgradePanel(game: game, tower: snapshot.selectedTower!);
    }
    if (snapshot.selectedCell != null) {
      return _TowerPicker(game: game);
    }
    return FilledButton(
      onPressed: snapshot.canStartWave ? game.startWave : null,
      child: const Text('Start Wave'),
    );
  }
}

class _TowerPicker extends StatelessWidget {
  const _TowerPicker({required this.game});

  final OrionDefenseGame game;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: () => game.placeTower(TowerType.laser),
            child: const Text('Laser 50'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: () => game.placeTower(TowerType.rocket),
            child: const Text('Rocket 80'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: () => game.placeTower(TowerType.cryo),
            child: const Text('Cryo 70'),
          ),
        ),
      ],
    );
  }
}

class _UpgradePanel extends StatelessWidget {
  const _UpgradePanel({required this.game, required this.tower});

  final OrionDefenseGame game;
  final PlacedTower tower;

  @override
  Widget build(BuildContext context) {
    final stats = GameBalance.towerStats(tower.type, level: tower.level);
    return FilledButton(
      onPressed: tower.level == 1 ? game.upgradeSelectedTower : null,
      child: Text(
        tower.level == 1
            ? 'Upgrade ${tower.type.name} ${stats.upgradeCost}'
            : '${tower.type.name} fully upgraded',
      ),
    );
  }
}

class _EndStatePanel extends StatelessWidget {
  const _EndStatePanel({required this.game, required this.snapshot});

  final OrionDefenseGame game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final won = snapshot.phase == GamePhase.won;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xAA050B14)),
      child: Center(
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1B2A),
            border: Border.all(color: const Color(0xFF31E6A1)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                won ? 'Outpost secured' : 'Base destroyed',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: game.restart,
                child: const Text('Restart'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run widget test**

Run:

```bash
flutter test test/widget_test.dart
```

Expected: the app shell smoke test passes.

- [ ] **Step 6: Commit UI shell**

Run:

```bash
git add lib/main.dart lib/game/ui/orion_game_page.dart test/widget_test.dart
git commit -m "feat: add Orion defense UI shell"
```

Expected: commit succeeds with the Flutter shell and smoke test.

## Task 9: Full Verification and Runtime Smoke

**Files:**
- Verify: all Dart source and test files touched by earlier tasks.

- [ ] **Step 1: Format all Dart files**

Run:

```bash
dart format lib test
```

Expected: formatter completes without syntax errors.

- [ ] **Step 2: Run analyzer**

Run:

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run all tests**

Run:

```bash
flutter test
```

Expected: all widget and rule tests pass.

- [ ] **Step 4: Launch web server smoke target**

Run:

```bash
flutter run -d web-server
```

Expected: Flutter starts a local web server and prints a URL. Open the URL in the in-app browser or another browser and verify:

- Board appears in portrait layout.
- HUD shows Orion, base, gold, wave, and phase.
- Tapping an open off-path cell shows tower buttons.
- Tapping a path cell does not spend gold.
- Placing a tower spends gold and draws the tower.
- Start Wave spawns enemies.
- Towers shoot enemies.
- Kills award gold.
- Tapping a tower opens the upgrade action.
- Clearing wave 5 shows the win panel.
- Letting enough enemies through shows the loss panel.
- Restart returns to initial state.

- [ ] **Step 5: Commit final verification fixes**

If Step 1, Step 2, Step 3, or Step 4 required edits, run:

```bash
git add lib test pubspec.yaml pubspec.lock
git commit -m "fix: polish Orion defense MVP verification"
```

Expected: final fixes are committed. If no edits were required, skip this commit and record that verification passed without changes.

## Self-Review Notes

- Spec coverage: the plan covers five manual waves, simple gold economy, fixed route, grid off-path placement, three towers, one upgrade level, win/loss, restart, deterministic tests, and local runtime verification.
- Scope check: dynamic pathfinding, assets, audio, multiple maps, save/load, leaderboards, desktop-specific keyboard controls, and advanced upgrade trees are excluded from the implementation tasks.
- Type consistency: `TowerType`, `TowerStats`, `EnemyStats`, `WaveDefinition`, `GamePhase`, `PlacementResult`, `GridPosition`, `PlacedTower`, and `GameSnapshot` are defined before later tasks reference them.
