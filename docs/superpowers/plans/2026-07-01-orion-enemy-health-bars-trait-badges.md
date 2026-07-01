# Orion Enemy Health Bars And Trait Badges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add compact in-combat enemy health, shield, trait, and effect overlays with touch inspection while preserving Orion's existing combat rules.

**Architecture:** Keep this as a Flame rendering feature. Add a focused enemy overlay helper that derives display state and renders bars/badges from `EnemyComponent` runtime state, then let `OrionDefenseGame` own the inspected enemy ID and tap hit-testing.

**Tech Stack:** Dart 3.12, Flutter, Flame 1.37, `flutter_test`.

---

## File Structure

- Create `lib/game/components/enemy_overlay.dart`
  - Owns `EnemyOverlayBadge`, `EnemyOverlayData`, `EnemyOverlayState`, and `EnemyOverlayRenderer`.
  - Contains deterministic health/shield ratio logic, notable/expanded decisions, badge ordering, badge capping, and Canvas rendering.
- Modify `lib/game/components/enemy_component.dart`
  - Imports the overlay helper and tower variety sheet.
  - Stores optional `GameTowerVarietySheet`.
  - Exposes `isInspected`, `overlayState`, and `setInspected()`.
  - Delegates overlay drawing after the enemy body is rendered.
- Modify `lib/game/orion_defense_game.dart`
  - Passes `_towerVarietySheet` to enemies.
  - Tracks `int? _inspectedEnemyId`.
  - Hit-tests enemies before board cells during waves.
  - Clears inspection when enemies resolve or combat components are cleared.
- Modify `test/game/enemy_component_test.dart`
  - Adds display-state coverage for ratios, notable behavior, badge ordering, capping, and resolved suppression.
- Modify `test/game/orion_defense_game_test.dart`
  - Adds tap-inspection coverage against active `EnemyComponent`s.

---

### Task 1: Enemy Overlay Display State

**Files:**
- Create: `lib/game/components/enemy_overlay.dart`
- Modify: `test/game/enemy_component_test.dart`

- [ ] **Step 1: Write failing display-state tests**

Add this import to `test/game/enemy_component_test.dart`:

```dart
import 'package:orion/game/components/enemy_overlay.dart';
```

Add this group inside the existing top-level `group('EnemyComponent', () { ... })`, after the current armor test:

```dart
    group('EnemyOverlayState', () {
      test('full-health traitless enemies do not render normal overlays', () {
        final state = EnemyOverlayState.fromData(
          const EnemyOverlayData(
            isResolved: false,
            isInspected: false,
            health: 100,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: {},
            isSlowed: false,
            isCorroded: false,
          ),
        );

        expect(state.shouldRender, isFalse);
        expect(state.showHealthBar, isFalse);
        expect(state.showShieldBar, isFalse);
        expect(state.badges, isEmpty);
      });

      test('damaged enemies expose clamped health ratio', () {
        final damaged = EnemyOverlayState.fromData(
          const EnemyOverlayData(
            isResolved: false,
            isInspected: false,
            health: 25,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: {},
            isSlowed: false,
            isCorroded: false,
          ),
        );
        final overhealed = EnemyOverlayState.fromData(
          const EnemyOverlayData(
            isResolved: false,
            isInspected: false,
            health: 125,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: {},
            isSlowed: false,
            isCorroded: false,
          ),
        );

        expect(damaged.shouldRender, isTrue);
        expect(damaged.healthRatio, 0.25);
        expect(damaged.showHealthBar, isTrue);
        expect(overhealed.healthRatio, 1);
      });

      test('shielded enemies expose shield state separately from health', () {
        final state = EnemyOverlayState.fromData(
          const EnemyOverlayData(
            isResolved: false,
            isInspected: false,
            health: 100,
            maxHealth: 100,
            shield: 10,
            maxShield: 40,
            traits: {EnemyTrait.shielded},
            isSlowed: false,
            isCorroded: false,
          ),
        );

        expect(state.shouldRender, isTrue);
        expect(state.healthRatio, 1);
        expect(state.shieldRatio, 0.25);
        expect(state.showHealthBar, isTrue);
        expect(state.showShieldBar, isTrue);
        expect(state.badges, [EnemyOverlayBadge.shielded]);
      });

      test('resolved enemies suppress overlays even when inspected', () {
        final state = EnemyOverlayState.fromData(
          const EnemyOverlayData(
            isResolved: true,
            isInspected: true,
            health: 25,
            maxHealth: 100,
            shield: 10,
            maxShield: 40,
            traits: {EnemyTrait.armored, EnemyTrait.regen},
            isSlowed: true,
            isCorroded: true,
          ),
        );

        expect(state.shouldRender, isFalse);
        expect(state.isExpanded, isFalse);
        expect(state.showHealthBar, isFalse);
        expect(state.showShieldBar, isFalse);
        expect(state.badges, isEmpty);
      });

      test('inspected enemies expand even when not otherwise notable', () {
        final state = EnemyOverlayState.fromData(
          const EnemyOverlayData(
            isResolved: false,
            isInspected: true,
            health: 100,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: {},
            isSlowed: false,
            isCorroded: false,
          ),
        );

        expect(state.shouldRender, isTrue);
        expect(state.isExpanded, isTrue);
        expect(state.showHealthBar, isTrue);
        expect(state.showShieldBar, isFalse);
      });

      test('badges are ordered and capped by overlay mode', () {
        const data = EnemyOverlayData(
          isResolved: false,
          health: 50,
          maxHealth: 100,
          shield: 10,
          maxShield: 40,
          traits: {
            EnemyTrait.shielded,
            EnemyTrait.armored,
            EnemyTrait.regen,
            EnemyTrait.heavy,
            EnemyTrait.swarm,
          },
          isSlowed: true,
          isCorroded: true,
        );

        final normal = EnemyOverlayState.fromData(
          data.copyWith(isInspected: false),
        );
        final expanded = EnemyOverlayState.fromData(
          data.copyWith(isInspected: true),
        );

        expect(normal.badges, [
          EnemyOverlayBadge.corroded,
          EnemyOverlayBadge.slowed,
        ]);
        expect(expanded.badges, [
          EnemyOverlayBadge.corroded,
          EnemyOverlayBadge.slowed,
          EnemyOverlayBadge.shielded,
          EnemyOverlayBadge.armored,
        ]);
      });

      test('corroded regen enemies keep both badges in priority order', () {
        final state = EnemyOverlayState.fromData(
          const EnemyOverlayData(
            isResolved: false,
            isInspected: true,
            health: 80,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: {EnemyTrait.regen},
            isSlowed: false,
            isCorroded: true,
          ),
        );

        expect(state.badges, [
          EnemyOverlayBadge.corroded,
          EnemyOverlayBadge.regen,
        ]);
      });

      test('swarm-only enemies are not automatically notable', () {
        final normal = EnemyOverlayState.fromData(
          const EnemyOverlayData(
            isResolved: false,
            isInspected: false,
            health: 100,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: {EnemyTrait.swarm},
            isSlowed: false,
            isCorroded: false,
          ),
        );
        final inspected = EnemyOverlayState.fromData(
          const EnemyOverlayData(
            isResolved: false,
            isInspected: true,
            health: 100,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: {EnemyTrait.swarm},
            isSlowed: false,
            isCorroded: false,
          ),
        );

        expect(normal.shouldRender, isFalse);
        expect(normal.badges, isEmpty);
        expect(inspected.shouldRender, isTrue);
        expect(inspected.badges, [EnemyOverlayBadge.swarm]);
      });
    });
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
rtk flutter test test/game/enemy_component_test.dart --name EnemyOverlayState
```

Expected: FAIL because `package:orion/game/components/enemy_overlay.dart` does not exist.

- [ ] **Step 3: Create the display-state helper**

Create `lib/game/components/enemy_overlay.dart` with this initial content:

```dart
import '../models/game_models.dart';

enum EnemyOverlayBadge { corroded, slowed, shielded, armored, regen, heavy, swarm }

class EnemyOverlayData {
  const EnemyOverlayData({
    required this.isResolved,
    this.isInspected = false,
    required this.health,
    required this.maxHealth,
    required this.shield,
    required this.maxShield,
    required this.traits,
    required this.isSlowed,
    required this.isCorroded,
  });

  final bool isResolved;
  final bool isInspected;
  final double health;
  final double maxHealth;
  final double shield;
  final double maxShield;
  final Set<EnemyTrait> traits;
  final bool isSlowed;
  final bool isCorroded;

  EnemyOverlayData copyWith({
    bool? isResolved,
    bool? isInspected,
    double? health,
    double? maxHealth,
    double? shield,
    double? maxShield,
    Set<EnemyTrait>? traits,
    bool? isSlowed,
    bool? isCorroded,
  }) {
    return EnemyOverlayData(
      isResolved: isResolved ?? this.isResolved,
      isInspected: isInspected ?? this.isInspected,
      health: health ?? this.health,
      maxHealth: maxHealth ?? this.maxHealth,
      shield: shield ?? this.shield,
      maxShield: maxShield ?? this.maxShield,
      traits: traits ?? this.traits,
      isSlowed: isSlowed ?? this.isSlowed,
      isCorroded: isCorroded ?? this.isCorroded,
    );
  }
}

class EnemyOverlayState {
  const EnemyOverlayState({
    required this.shouldRender,
    required this.isExpanded,
    required this.healthRatio,
    required this.shieldRatio,
    required this.showHealthBar,
    required this.showShieldBar,
    required this.badges,
  });

  static const int normalBadgeLimit = 2;
  static const int expandedBadgeLimit = 4;

  final bool shouldRender;
  final bool isExpanded;
  final double healthRatio;
  final double shieldRatio;
  final bool showHealthBar;
  final bool showShieldBar;
  final List<EnemyOverlayBadge> badges;

  factory EnemyOverlayState.fromData(EnemyOverlayData data) {
    if (data.isResolved) {
      return const EnemyOverlayState(
        shouldRender: false,
        isExpanded: false,
        healthRatio: 0,
        shieldRatio: 0,
        showHealthBar: false,
        showShieldBar: false,
        badges: [],
      );
    }

    final healthRatio = _ratio(data.health, data.maxHealth);
    final shieldRatio = _ratio(data.shield, data.maxShield);
    final hasShieldState = data.maxShield > 0 || data.shield > 0;
    final isDamaged = healthRatio < 1;
    final hasHighSignalTrait =
        data.traits.contains(EnemyTrait.armored) ||
        data.traits.contains(EnemyTrait.shielded) ||
        data.traits.contains(EnemyTrait.regen) ||
        data.traits.contains(EnemyTrait.heavy);
    final isNotable =
        isDamaged ||
        hasShieldState ||
        hasHighSignalTrait ||
        data.isSlowed ||
        data.isCorroded;
    final shouldRender = data.isInspected || isNotable;
    final allBadges = shouldRender
        ? _orderedBadges(
            traits: data.traits,
            hasShieldState: hasShieldState,
            isSlowed: data.isSlowed,
            isCorroded: data.isCorroded,
          )
        : const <EnemyOverlayBadge>[];
    final badgeLimit = data.isInspected ? expandedBadgeLimit : normalBadgeLimit;

    return EnemyOverlayState(
      shouldRender: shouldRender,
      isExpanded: data.isInspected,
      healthRatio: healthRatio,
      shieldRatio: shieldRatio,
      showHealthBar: shouldRender && (data.isInspected || isDamaged || hasShieldState),
      showShieldBar: shouldRender && hasShieldState,
      badges: List.unmodifiable(allBadges.take(badgeLimit)),
    );
  }

  static double _ratio(double value, double maxValue) {
    if (maxValue <= 0) {
      return 0;
    }
    return (value / maxValue).clamp(0, 1).toDouble();
  }

  static List<EnemyOverlayBadge> _orderedBadges({
    required Set<EnemyTrait> traits,
    required bool hasShieldState,
    required bool isSlowed,
    required bool isCorroded,
  }) {
    return [
      if (isCorroded) EnemyOverlayBadge.corroded,
      if (isSlowed) EnemyOverlayBadge.slowed,
      if (hasShieldState || traits.contains(EnemyTrait.shielded))
        EnemyOverlayBadge.shielded,
      if (traits.contains(EnemyTrait.armored)) EnemyOverlayBadge.armored,
      if (traits.contains(EnemyTrait.regen)) EnemyOverlayBadge.regen,
      if (traits.contains(EnemyTrait.heavy)) EnemyOverlayBadge.heavy,
      if (traits.contains(EnemyTrait.swarm)) EnemyOverlayBadge.swarm,
    ];
  }
}
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
rtk flutter test test/game/enemy_component_test.dart --name EnemyOverlayState
```

Expected: PASS for the `EnemyOverlayState` tests.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
rtk git add lib/game/components/enemy_overlay.dart test/game/enemy_component_test.dart
rtk git commit -m "test: cover enemy overlay display state"
```

Expected: commit succeeds with only the overlay helper and enemy component test changes.

---

### Task 2: Enemy Overlay Rendering And Component Integration

**Files:**
- Modify: `lib/game/components/enemy_overlay.dart`
- Modify: `lib/game/components/enemy_component.dart`
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `test/game/enemy_component_test.dart`

- [ ] **Step 1: Write failing component integration tests**

Add these tests inside `group('EnemyComponent', () { ... })` in `test/game/enemy_component_test.dart`, after the `EnemyOverlayState` group:

```dart
    test('component overlay state reflects runtime health shield and effects', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
          shieldHealth: 40,
          traits: {EnemyTrait.shielded, EnemyTrait.regen},
          regenPerSecond: 10,
        ),
        waypoints: [Vector2(0, 0), Vector2(1000, 0)],
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      enemy.applyDamage(30);
      enemy.applySlow(multiplier: 0.5, duration: 2);
      enemy.applyCorrosion(damagePerSecond: 5, duration: 2, armorShred: 0.1);

      final state = enemy.overlayState;

      expect(state.shouldRender, isTrue);
      expect(state.healthRatio, 1);
      expect(state.shieldRatio, 0.25);
      expect(state.showHealthBar, isTrue);
      expect(state.showShieldBar, isTrue);
      expect(state.badges, [
        EnemyOverlayBadge.corroded,
        EnemyOverlayBadge.slowed,
      ]);
    });

    test('component inspection expands the overlay state', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
        ),
        waypoints: [Vector2(0, 0), Vector2(1000, 0)],
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      expect(enemy.isInspected, isFalse);
      expect(enemy.overlayState.shouldRender, isFalse);

      enemy.setInspected(true);

      expect(enemy.isInspected, isTrue);
      expect(enemy.overlayState.shouldRender, isTrue);
      expect(enemy.overlayState.isExpanded, isTrue);
      expect(enemy.overlayState.showHealthBar, isTrue);
    });
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
rtk flutter test test/game/enemy_component_test.dart
```

Expected: FAIL because `EnemyComponent.overlayState`, `EnemyComponent.isInspected`, and `EnemyComponent.setInspected()` do not exist.

- [ ] **Step 3: Add the renderer to the overlay helper**

Replace `lib/game/components/enemy_overlay.dart` with this complete file:

```dart
import 'dart:ui';

import 'package:flame/components.dart';

import '../assets/game_tower_variety_sheet.dart';
import '../models/game_models.dart';

enum EnemyOverlayBadge { corroded, slowed, shielded, armored, regen, heavy, swarm }

class EnemyOverlayData {
  const EnemyOverlayData({
    required this.isResolved,
    this.isInspected = false,
    required this.health,
    required this.maxHealth,
    required this.shield,
    required this.maxShield,
    required this.traits,
    required this.isSlowed,
    required this.isCorroded,
  });

  final bool isResolved;
  final bool isInspected;
  final double health;
  final double maxHealth;
  final double shield;
  final double maxShield;
  final Set<EnemyTrait> traits;
  final bool isSlowed;
  final bool isCorroded;

  EnemyOverlayData copyWith({
    bool? isResolved,
    bool? isInspected,
    double? health,
    double? maxHealth,
    double? shield,
    double? maxShield,
    Set<EnemyTrait>? traits,
    bool? isSlowed,
    bool? isCorroded,
  }) {
    return EnemyOverlayData(
      isResolved: isResolved ?? this.isResolved,
      isInspected: isInspected ?? this.isInspected,
      health: health ?? this.health,
      maxHealth: maxHealth ?? this.maxHealth,
      shield: shield ?? this.shield,
      maxShield: maxShield ?? this.maxShield,
      traits: traits ?? this.traits,
      isSlowed: isSlowed ?? this.isSlowed,
      isCorroded: isCorroded ?? this.isCorroded,
    );
  }
}

class EnemyOverlayState {
  const EnemyOverlayState({
    required this.shouldRender,
    required this.isExpanded,
    required this.healthRatio,
    required this.shieldRatio,
    required this.showHealthBar,
    required this.showShieldBar,
    required this.badges,
  });

  static const int normalBadgeLimit = 2;
  static const int expandedBadgeLimit = 4;

  final bool shouldRender;
  final bool isExpanded;
  final double healthRatio;
  final double shieldRatio;
  final bool showHealthBar;
  final bool showShieldBar;
  final List<EnemyOverlayBadge> badges;

  factory EnemyOverlayState.fromData(EnemyOverlayData data) {
    if (data.isResolved) {
      return const EnemyOverlayState(
        shouldRender: false,
        isExpanded: false,
        healthRatio: 0,
        shieldRatio: 0,
        showHealthBar: false,
        showShieldBar: false,
        badges: [],
      );
    }

    final healthRatio = _ratio(data.health, data.maxHealth);
    final shieldRatio = _ratio(data.shield, data.maxShield);
    final hasShieldState = data.maxShield > 0 || data.shield > 0;
    final isDamaged = healthRatio < 1;
    final hasHighSignalTrait =
        data.traits.contains(EnemyTrait.armored) ||
        data.traits.contains(EnemyTrait.shielded) ||
        data.traits.contains(EnemyTrait.regen) ||
        data.traits.contains(EnemyTrait.heavy);
    final isNotable =
        isDamaged ||
        hasShieldState ||
        hasHighSignalTrait ||
        data.isSlowed ||
        data.isCorroded;
    final shouldRender = data.isInspected || isNotable;
    final allBadges = shouldRender
        ? _orderedBadges(
            traits: data.traits,
            hasShieldState: hasShieldState,
            isSlowed: data.isSlowed,
            isCorroded: data.isCorroded,
          )
        : const <EnemyOverlayBadge>[];
    final badgeLimit = data.isInspected ? expandedBadgeLimit : normalBadgeLimit;

    return EnemyOverlayState(
      shouldRender: shouldRender,
      isExpanded: data.isInspected,
      healthRatio: healthRatio,
      shieldRatio: shieldRatio,
      showHealthBar:
          shouldRender && (data.isInspected || isDamaged || hasShieldState),
      showShieldBar: shouldRender && hasShieldState,
      badges: List.unmodifiable(allBadges.take(badgeLimit)),
    );
  }

  static double _ratio(double value, double maxValue) {
    if (maxValue <= 0) {
      return 0;
    }
    return (value / maxValue).clamp(0, 1).toDouble();
  }

  static List<EnemyOverlayBadge> _orderedBadges({
    required Set<EnemyTrait> traits,
    required bool hasShieldState,
    required bool isSlowed,
    required bool isCorroded,
  }) {
    return [
      if (isCorroded) EnemyOverlayBadge.corroded,
      if (isSlowed) EnemyOverlayBadge.slowed,
      if (hasShieldState || traits.contains(EnemyTrait.shielded))
        EnemyOverlayBadge.shielded,
      if (traits.contains(EnemyTrait.armored)) EnemyOverlayBadge.armored,
      if (traits.contains(EnemyTrait.regen)) EnemyOverlayBadge.regen,
      if (traits.contains(EnemyTrait.heavy)) EnemyOverlayBadge.heavy,
      if (traits.contains(EnemyTrait.swarm)) EnemyOverlayBadge.swarm,
    ];
  }
}

class EnemyOverlayRenderer {
  EnemyOverlayRenderer();

  final Paint _barBackgroundPaint = Paint()..color = const Color(0xCC101624);
  final Paint _healthPaint = Paint()..color = const Color(0xFFE35D6A);
  final Paint _shieldPaint = Paint()..color = const Color(0xFF6EC6FF);
  final Paint _badgeBackgroundPaint = Paint()..color = const Color(0xD9141B2B);
  final Paint _badgeStrokePaint = Paint()
    ..color = const Color(0xCCFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  void render(
    Canvas canvas, {
    required EnemyOverlayState state,
    required double radius,
    GameTowerVarietySheet? towerVarietySheet,
  }) {
    if (!state.shouldRender) {
      return;
    }

    final centerX = radius;
    var top = -radius * (state.isExpanded ? 0.92 : 0.72);

    if (state.badges.isNotEmpty) {
      _renderBadges(
        canvas,
        badges: state.badges,
        centerX: centerX,
        y: top,
        size: state.isExpanded ? 9 : 7,
        towerVarietySheet: towerVarietySheet,
      );
      top += state.isExpanded ? 11 : 9;
    }

    if (state.showHealthBar) {
      _renderBar(
        canvas,
        centerX: centerX,
        y: top,
        width: radius * (state.isExpanded ? 2.8 : 2.25),
        height: state.isExpanded ? 4 : 3,
        ratio: state.healthRatio,
        fillPaint: _healthPaint,
      );
      top += state.isExpanded ? 5 : 4;
    }

    if (state.showShieldBar) {
      _renderBar(
        canvas,
        centerX: centerX,
        y: top,
        width: radius * (state.isExpanded ? 2.8 : 2.25),
        height: 2.5,
        ratio: state.shieldRatio,
        fillPaint: _shieldPaint,
      );
    }
  }

  void _renderBar(
    Canvas canvas, {
    required double centerX,
    required double y,
    required double width,
    required double height,
    required double ratio,
    required Paint fillPaint,
  }) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(centerX - (width / 2), y, width, height),
      Radius.circular(height / 2),
    );
    canvas.drawRRect(rect, _barBackgroundPaint);

    if (ratio <= 0) {
      return;
    }

    final fillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(centerX - (width / 2), y, width * ratio, height),
      Radius.circular(height / 2),
    );
    canvas.drawRRect(fillRect, fillPaint);
  }

  void _renderBadges(
    Canvas canvas, {
    required List<EnemyOverlayBadge> badges,
    required double centerX,
    required double y,
    required double size,
    required GameTowerVarietySheet? towerVarietySheet,
  }) {
    const gap = 2.0;
    final totalWidth = (badges.length * size) + ((badges.length - 1) * gap);
    var x = centerX - (totalWidth / 2);

    for (final badge in badges) {
      final rect = Rect.fromLTWH(x, y, size, size);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        _badgeBackgroundPaint,
      );

      final sprite = _spriteForBadge(towerVarietySheet, badge);
      if (sprite == null) {
        _renderFallbackBadge(canvas, rect, badge);
      } else {
        sprite.render(
          canvas,
          position: Vector2(rect.left, rect.top),
          size: Vector2.all(size),
        );
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        _badgeStrokePaint,
      );
      x += size + gap;
    }
  }

  Sprite? _spriteForBadge(
    GameTowerVarietySheet? towerVarietySheet,
    EnemyOverlayBadge badge,
  ) {
    if (towerVarietySheet == null) {
      return null;
    }

    final sprite = switch (badge) {
      EnemyOverlayBadge.shielded => GameTowerVarietySprite.shieldIndicator,
      EnemyOverlayBadge.armored => GameTowerVarietySprite.armorIndicator,
      EnemyOverlayBadge.regen => GameTowerVarietySprite.regenIndicator,
      EnemyOverlayBadge.corroded => GameTowerVarietySprite.corrosionIndicator,
      EnemyOverlayBadge.slowed => null,
      EnemyOverlayBadge.heavy => null,
      EnemyOverlayBadge.swarm => null,
    };

    if (sprite == null) {
      return null;
    }
    return towerVarietySheet.sprite(sprite);
  }

  void _renderFallbackBadge(
    Canvas canvas,
    Rect rect,
    EnemyOverlayBadge badge,
  ) {
    final paint = Paint()..color = _fallbackColor(badge);
    final center = rect.center;
    final insetRect = rect.deflate(rect.width * 0.22);

    switch (badge) {
      case EnemyOverlayBadge.slowed:
        canvas.drawCircle(center, insetRect.width / 2, paint);
        canvas.drawLine(
          Offset(insetRect.left, insetRect.bottom),
          Offset(insetRect.right, insetRect.top),
          _badgeStrokePaint,
        );
        return;
      case EnemyOverlayBadge.heavy:
        canvas.drawRRect(
          RRect.fromRectAndRadius(insetRect, const Radius.circular(1.5)),
          paint,
        );
        return;
      case EnemyOverlayBadge.swarm:
        canvas.drawCircle(
          Offset(center.dx - rect.width * 0.16, center.dy),
          rect.width * 0.13,
          paint,
        );
        canvas.drawCircle(center, rect.width * 0.13, paint);
        canvas.drawCircle(
          Offset(center.dx + rect.width * 0.16, center.dy),
          rect.width * 0.13,
          paint,
        );
        return;
      case EnemyOverlayBadge.corroded:
      case EnemyOverlayBadge.shielded:
      case EnemyOverlayBadge.armored:
      case EnemyOverlayBadge.regen:
        canvas.drawCircle(center, insetRect.width / 2, paint);
        return;
    }
  }

  Color _fallbackColor(EnemyOverlayBadge badge) {
    return switch (badge) {
      EnemyOverlayBadge.corroded => const Color(0xFF67D46E),
      EnemyOverlayBadge.slowed => const Color(0xFF78D8FF),
      EnemyOverlayBadge.shielded => const Color(0xFF6EC6FF),
      EnemyOverlayBadge.armored => const Color(0xFFC9D6E8),
      EnemyOverlayBadge.regen => const Color(0xFF67D46E),
      EnemyOverlayBadge.heavy => const Color(0xFFFFB84D),
      EnemyOverlayBadge.swarm => const Color(0xFFFFD166),
    };
  }
}
```

- [ ] **Step 4: Integrate overlay state and rendering into `EnemyComponent`**

Modify `lib/game/components/enemy_component.dart`.

Add this import:

```dart
import '../assets/game_tower_variety_sheet.dart';
import 'enemy_overlay.dart';
```

Update the constructor parameters:

```dart
    this.spriteSheet,
    this.towerVarietySheet,
    double radius = 11,
```

Add these fields near the existing `spriteSheet` field:

```dart
  final GameTowerVarietySheet? towerVarietySheet;
  bool _isInspected = false;

  static final EnemyOverlayRenderer _overlayRenderer = EnemyOverlayRenderer();
```

Add these getters and method near the existing `isAlive` getters:

```dart
  bool get isInspected => _isInspected;

  EnemyOverlayState get overlayState {
    return EnemyOverlayState.fromData(
      EnemyOverlayData(
        isResolved: isResolved,
        isInspected: isInspected,
        health: health,
        maxHealth: maxHealth,
        shield: shield,
        maxShield: stats.shieldHealth,
        traits: stats.traits,
        isSlowed: isSlowed,
        isCorroded: isCorroded,
      ),
    );
  }

  void setInspected(bool value) {
    _isInspected = value;
  }
```

Replace the current `render()` method with:

```dart
  @override
  void render(Canvas canvas) {
    final spriteSheet = this.spriteSheet;
    if (spriteSheet == null) {
      super.render(canvas);
    } else {
      spriteSheet
          .sprite(GameSpriteSheet.spriteForEnemy(stats))
          .render(
            canvas,
            position: Vector2(radius, radius),
            size: Vector2.all(radius * 2.4),
            anchor: Anchor.center,
          );
    }

    _overlayRenderer.render(
      canvas,
      state: overlayState,
      radius: radius,
      towerVarietySheet: towerVarietySheet,
    );
  }
```

- [ ] **Step 5: Pass the tower variety sheet into enemies**

In `lib/game/orion_defense_game.dart`, update `_spawnEnemy()`:

```dart
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
```

- [ ] **Step 6: Run focused tests and verify they pass**

Run:

```bash
rtk flutter test test/game/enemy_component_test.dart
```

Expected: PASS for all `EnemyComponent` tests.

- [ ] **Step 7: Run analyzer to catch render/import issues**

Run:

```bash
rtk flutter analyze
```

Expected: no analyzer issues.

- [ ] **Step 8: Commit Task 2**

Run:

```bash
rtk git add lib/game/components/enemy_overlay.dart lib/game/components/enemy_component.dart lib/game/orion_defense_game.dart test/game/enemy_component_test.dart
rtk git commit -m "feat: render compact enemy combat overlays"
```

Expected: commit succeeds with overlay rendering and component integration.

---

### Task 3: Touch Inspection In `OrionDefenseGame`

**Files:**
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `test/game/orion_defense_game_test.dart`

- [ ] **Step 1: Write failing tap-inspection tests**

Add this import at the top of `test/game/orion_defense_game_test.dart`:

```dart
import 'dart:ui';
```

Add these tests inside `group('OrionDefenseGame', () { ... })`, after the paused-wave movement test:

```dart
    test('tapping an active enemy marks it inspected', () {
      final game = OrionDefenseGame(stage: _twoEnemyImmediateSpawnStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.05);
      game.processLifecycleEvents();

      final enemies = game.children.whereType<EnemyComponent>().toList();
      expect(enemies, hasLength(2));
      enemies[0].position = Vector2(120, 200);
      enemies[1].position = Vector2(420, 200);

      _tapPoint(game, enemies[0].position);

      expect(game.inspectedEnemyId, enemies[0].enemyId);
      expect(enemies[0].isInspected, isTrue);
      expect(enemies[1].isInspected, isFalse);
      expect(enemies[0].overlayState.isExpanded, isTrue);
    });

    test('tapping another active enemy switches inspection', () {
      final game = OrionDefenseGame(stage: _twoEnemyImmediateSpawnStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.05);
      game.processLifecycleEvents();

      final enemies = game.children.whereType<EnemyComponent>().toList();
      enemies[0].position = Vector2(120, 200);
      enemies[1].position = Vector2(420, 200);

      _tapPoint(game, enemies[0].position);
      _tapPoint(game, enemies[1].position);

      expect(game.inspectedEnemyId, enemies[1].enemyId);
      expect(enemies[0].isInspected, isFalse);
      expect(enemies[1].isInspected, isTrue);
    });

    test('tapping away from enemies clears inspection', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01);
      game.processLifecycleEvents();

      final enemy = game.children.whereType<EnemyComponent>().single;
      enemy.position = Vector2(120, 200);

      _tapPoint(game, enemy.position);
      _tapPoint(game, Vector2(700, 1100));

      expect(game.inspectedEnemyId, isNull);
      expect(enemy.isInspected, isFalse);
    });

    test('resolving the inspected enemy clears inspection', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01);
      game.processLifecycleEvents();

      final enemy = game.children.whereType<EnemyComponent>().single;
      enemy.position = Vector2(120, 200);
      _tapPoint(game, enemy.position);

      enemy.applyDamage(1000);
      game.processLifecycleEvents();

      expect(game.inspectedEnemyId, isNull);
      expect(enemy.isResolved, isTrue);
    });
```

Add this helper stage near the existing private stage helpers:

```dart
StageDefinition _twoEnemyImmediateSpawnStage() {
  return StageDefinition(
    id: 'two-enemy-immediate-spawn-stage',
    name: 'Two Enemy Immediate Spawn Stage',
    mapLabel: 'Immediate',
    description: 'Stage with two enemies for inspection tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: const [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 2,
            spawnInterval: 0.01,
            enemyStats: EnemyStats(
              health: 100,
              speed: 0,
              baseDamage: 1,
              goldReward: 0,
            ),
          ),
        ],
        clearBonus: 0,
      ),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}
```

Add this tap helper near `_tapCell()`:

```dart
void _tapPoint(OrionDefenseGame game, Vector2 point) {
  game.onTapDown(
    TapDownEvent(
      1,
      game,
      TapDownDetails(globalPosition: Offset(point.x, point.y)),
    ),
  );
}
```

- [ ] **Step 2: Run the focused game tests and verify they fail**

Run:

```bash
rtk flutter test test/game/orion_defense_game_test.dart --name inspect
```

Expected: FAIL because `OrionDefenseGame.inspectedEnemyId` and enemy tap inspection do not exist.

- [ ] **Step 3: Add inspection state to `OrionDefenseGame`**

In `lib/game/orion_defense_game.dart`, add this field near `_activeEnemyComponents`:

```dart
  int? _inspectedEnemyId;
```

Add this getter near the existing pacing getters:

```dart
  int? get inspectedEnemyId => _inspectedEnemyId;
```

At the start of `onTapDown()`, after the ended-state guard and before `BoardLayout.cellAt(...)`, add:

```dart
    if (_session.phase == GamePhase.wave) {
      final enemy = _enemyAt(event.canvasPosition);
      if (enemy != null) {
        _setInspectedEnemy(enemy.enemyId);
        _publishSnapshot();
        return;
      }
      _setInspectedEnemy(null);
    }
```

Add these helpers near `_selectNearestEnemyForDrone()`:

```dart
  EnemyComponent? _enemyAt(Vector2 canvasPosition) {
    for (final enemy in _activeEnemyComponents.values.toList().reversed) {
      if (!enemy.isAlive || !enemy.isMounted) {
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
```

- [ ] **Step 4: Clear inspection on enemy resolution and combat cleanup**

In `_handleEnemyKilled()`, add the inspection clear before `_publishSnapshot()`:

```dart
  void _handleEnemyKilled(EnemyComponent enemy) {
    if (_inspectedEnemyId == enemy.enemyId) {
      _setInspectedEnemy(null);
    }
    _activeEnemyComponents.remove(enemy.enemyId);
    _session.rewardKill(enemy.stats.goldReward);
    _publishSnapshot();
  }
```

In `_handleEnemyReachedBase()`, add the inspection clear before removing the active enemy:

```dart
  void _handleEnemyReachedBase(EnemyComponent enemy) {
    if (_inspectedEnemyId == enemy.enemyId) {
      _setInspectedEnemy(null);
    }
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
```

Replace `_removeInactiveEnemyReferences()` with:

```dart
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
```

At the top of `_clearCombatComponents({required bool removeTowers})`, add:

```dart
    _setInspectedEnemy(null);
```

- [ ] **Step 5: Run focused game tests and verify they pass**

Run:

```bash
rtk flutter test test/game/orion_defense_game_test.dart --name inspect
```

Expected: PASS for the inspection tests.

- [ ] **Step 6: Run the full game test file**

Run:

```bash
rtk flutter test test/game/orion_defense_game_test.dart
```

Expected: PASS for all `OrionDefenseGame` tests.

- [ ] **Step 7: Commit Task 3**

Run:

```bash
rtk git add lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
rtk git commit -m "feat: inspect enemies during active waves"
```

Expected: commit succeeds with tap inspection behavior and tests.

---

### Task 4: Final Verification

**Files:**
- Verify all modified Dart files.

- [ ] **Step 1: Format the code**

Run:

```bash
rtk dart format .
```

Expected: formatter completes. If it changes files, inspect the diff before continuing.

- [ ] **Step 2: Run analyzer**

Run:

```bash
rtk flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run full test suite**

Run:

```bash
rtk flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Inspect final diff**

Run:

```bash
rtk git status --short
rtk git diff --stat HEAD
```

Expected: only intentional code/test files are modified since the last task commit, or the worktree is clean if every task committed cleanly after formatting.

- [ ] **Step 5: Commit any formatter-only changes**

If Step 1 changed formatting after Task 3, run:

```bash
rtk git add lib/game/components/enemy_overlay.dart lib/game/components/enemy_component.dart lib/game/orion_defense_game.dart test/game/enemy_component_test.dart test/game/orion_defense_game_test.dart
rtk git commit -m "style: format enemy overlay changes"
```

Expected: commit succeeds if there were formatter changes. If there were no formatter changes, skip this step.
