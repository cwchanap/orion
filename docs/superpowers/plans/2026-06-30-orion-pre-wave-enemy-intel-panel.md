# Orion Pre-Wave Enemy Intel Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a build-phase Next Wave intel panel that previews the selected stage's upcoming wave groups, traits, clear bonus, and unlocked counter recommendations.

**Architecture:** Keep preview derivation in the pure model/session layer and expose it through `GameSnapshot.nextWavePreview`. The Flutter UI renders a compact `_NextWavePanel` from snapshot data only, directly under the existing HUD, without reading `OrionDefenseGame` or `GameSession` internals.

**Tech Stack:** Flutter, Flame, Dart `^3.12.0`, `flutter_test`, existing Orion pure rule tests.

---

## File Structure

- Modify `lib/game/models/game_models.dart`
  - Add `WavePreview` and `WavePreviewGroup`.
  - Add `GameBalance.wavePreview(...)` plus private label, trait, and recommendation helpers.
  - Add nullable `GameSnapshot.nextWavePreview`.
- Modify `lib/game/rules/game_session.dart`
  - Populate `nextWavePreview` only during build phase from the selected stage's active wave.
- Modify `lib/game/ui/orion_game_page.dart`
  - Preserve `nextWavePreview` in the manual snapshot copy path.
  - Render `_NextWavePanel` under `_Hud`.
  - Add UI-only trait label helper.
- Modify `test/game/game_balance_test.dart`
  - Cover preview model derivation, labels, traits, fallback labels, and recommendation filtering.
- Modify `test/game/game_session_test.dart`
  - Cover snapshot exposure, active-wave hiding, stage-specific single-group waves, and final-wave zero bonus data.
- Modify `test/widget_test.dart`
  - Cover panel visibility from the mission screen, persistence while selecting a build cell, active-wave hiding, and zero-bonus text omission.

---

### Task 1: Add Pure Wave Preview Derivation

**Files:**
- Modify: `lib/game/models/game_models.dart`
- Test: `test/game/game_balance_test.dart`

- [ ] **Step 1: Write failing preview derivation tests**

Add these tests inside the `GameBalance` group in `test/game/game_balance_test.dart`, near the existing wave tests:

```dart
    test('builds a preview for a multi-group baseline wave', () {
      final preview = GameBalance.wavePreview(
        wave: GameBalance.waves[4],
        waveNumber: 5,
        waveTotal: 8,
        unlockedTowerTypes: const [
          TowerType.laser,
          TowerType.rocket,
          TowerType.cryo,
          TowerType.railgun,
          TowerType.ionChain,
          TowerType.nanite,
          TowerType.gravityWell,
        ],
      );

      expect(preview.waveNumber, 5);
      expect(preview.waveTotal, 8);
      expect(preview.clearBonus, 80);
      expect(
        preview.groups.map(
          (group) => '${group.enemyCount} ${group.label}',
        ),
        ['20 Swarm Drones', '4 Heavy Drones'],
      );
      expect(preview.traits.toList(), [
        EnemyTrait.swarm,
        EnemyTrait.heavy,
      ]);
      expect(preview.recommendedTowerTypes, [
        TowerType.rocket,
        TowerType.cryo,
        TowerType.gravityWell,
      ]);
    });

    test('filters wave preview recommendations to unlocked towers', () {
      final preview = GameBalance.wavePreview(
        wave: GameBalance.waves[4],
        waveNumber: 5,
        waveTotal: 8,
        unlockedTowerTypes: const [TowerType.laser, TowerType.rocket],
      );

      expect(preview.recommendedTowerTypes, [TowerType.rocket]);
    });

    test('labels every approved enemy archetype in wave previews', () {
      const expectedLabels = {
        EnemyArchetype.basicDrone: 'Drones',
        EnemyArchetype.basicEliteDrone: 'Elite Drones',
        EnemyArchetype.armoredDrone: 'Armored Drones',
        EnemyArchetype.shieldedDrone: 'Shielded Drones',
        EnemyArchetype.swarmDrone: 'Swarm Drones',
        EnemyArchetype.regenDrone: 'Regen Drones',
        EnemyArchetype.heavyDrone: 'Heavy Drones',
        EnemyArchetype.armoredHeavyDrone: 'Armored Heavy Drones',
        EnemyArchetype.regenHeavyDrone: 'Regen Heavy Drones',
      };

      for (final entry in expectedLabels.entries) {
        final preview = GameBalance.wavePreview(
          wave: WaveDefinition(
            groups: [
              WaveGroup(
                enemyCount: 1,
                enemyStats: GameBalance.enemyArchetype(entry.key),
              ),
            ],
            clearBonus: 0,
          ),
          waveNumber: 1,
          waveTotal: 1,
          unlockedTowerTypes: const [],
        );

        expect(preview.groups.single.label, entry.value);
      }
    });

    test('uses trait fallback labels for custom enemy stats', () {
      final preview = GameBalance.wavePreview(
        wave: const WaveDefinition(
          groups: [
            WaveGroup(
              enemyCount: 3,
              enemyStats: EnemyStats(
                health: 111,
                speed: 42,
                baseDamage: 2,
                goldReward: 9,
                traits: {EnemyTrait.shielded, EnemyTrait.armored},
                shieldHealth: 10,
                armorReduction: 0.1,
              ),
            ),
          ],
          clearBonus: 12,
        ),
        waveNumber: 1,
        waveTotal: 1,
        unlockedTowerTypes: const [],
      );

      expect(preview.groups.single.label, 'Armored Shielded Drones');
      expect(preview.groups.single.traits.toList(), [
        EnemyTrait.armored,
        EnemyTrait.shielded,
      ]);
      expect(preview.traits.toList(), [
        EnemyTrait.armored,
        EnemyTrait.shielded,
      ]);
      expect(preview.recommendedTowerTypes, isEmpty);
    });

    test('builds an empty wave preview without filler text data', () {
      final preview = GameBalance.wavePreview(
        wave: const WaveDefinition(groups: [], clearBonus: 0),
        waveNumber: 1,
        waveTotal: 1,
        unlockedTowerTypes: const [TowerType.laser],
      );

      expect(preview.groups, isEmpty);
      expect(preview.traits, isEmpty);
      expect(preview.clearBonus, 0);
      expect(preview.recommendedTowerTypes, isEmpty);
    });

    test('wave preview collections cannot be mutated', () {
      final preview = GameBalance.wavePreview(
        wave: GameBalance.waves.first,
        waveNumber: 1,
        waveTotal: 8,
        unlockedTowerTypes: const [TowerType.laser],
      );

      expect(
        () => preview.groups.add(
          WavePreviewGroup(
            enemyCount: 1,
            label: 'Drones',
            traits: const {},
          ),
        ),
        throwsUnsupportedError,
      );
      expect(() => preview.traits.add(EnemyTrait.heavy), throwsUnsupportedError);
      expect(
        () => preview.recommendedTowerTypes.add(TowerType.rocket),
        throwsUnsupportedError,
      );
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
rtk flutter test test/game/game_balance_test.dart
```

Expected: FAIL with errors like `Member not found: 'GameBalance.wavePreview'` and `The method 'WavePreviewGroup' isn't defined`.

- [ ] **Step 3: Add preview DTOs**

In `lib/game/models/game_models.dart`, insert these classes after `WaveDefinition` and before `PlacedTower`:

```dart
class WavePreviewGroup {
  WavePreviewGroup({
    required this.enemyCount,
    required this.label,
    required Set<EnemyTrait> traits,
  }) : traits = Set.unmodifiable(traits);

  final int enemyCount;
  final String label;
  final Set<EnemyTrait> traits;
}

class WavePreview {
  WavePreview({
    required this.waveNumber,
    required this.waveTotal,
    required List<WavePreviewGroup> groups,
    required Set<EnemyTrait> traits,
    required this.clearBonus,
    required List<TowerType> recommendedTowerTypes,
  }) : groups = List.unmodifiable(groups),
       traits = Set.unmodifiable(traits),
       recommendedTowerTypes = List.unmodifiable(recommendedTowerTypes);

  final int waveNumber;
  final int waveTotal;
  final List<WavePreviewGroup> groups;
  final Set<EnemyTrait> traits;
  final int clearBonus;
  final List<TowerType> recommendedTowerTypes;
}
```

- [ ] **Step 4: Add preview builder and helpers**

In `lib/game/models/game_models.dart`, add this public method inside `GameBalance`, near `enemyArchetype(...)`:

```dart
  static WavePreview wavePreview({
    required WaveDefinition wave,
    required int waveNumber,
    required int waveTotal,
    required List<TowerType> unlockedTowerTypes,
  }) {
    final groups = [
      for (final group in wave.groups)
        WavePreviewGroup(
          enemyCount: group.enemyCount,
          label: _enemyLabelForStats(group.enemyStats),
          traits: _orderedTraitsForStats(group.enemyStats),
        ),
    ];
    final traits = _orderedTraitsForWave(wave);

    return WavePreview(
      waveNumber: waveNumber,
      waveTotal: waveTotal,
      groups: groups,
      traits: traits,
      clearBonus: wave.clearBonus,
      recommendedTowerTypes: _recommendedTowerTypes(
        wave,
        unlockedTowerTypes,
      ),
    );
  }
```

Add these private helpers inside `GameBalance`, below `enemyArchetype(...)` and above `towerStats(...)`:

```dart
  static Set<EnemyTrait> _orderedTraitsForWave(WaveDefinition wave) {
    final traits = <EnemyTrait>{};
    for (final trait in EnemyTrait.values) {
      final isPresent = wave.groups.any(
        (group) => group.enemyStats.hasTrait(trait),
      );
      if (isPresent) {
        traits.add(trait);
      }
    }
    return traits;
  }

  static Set<EnemyTrait> _orderedTraitsForStats(EnemyStats stats) {
    final traits = <EnemyTrait>{};
    for (final trait in EnemyTrait.values) {
      if (stats.hasTrait(trait)) {
        traits.add(trait);
      }
    }
    return traits;
  }

  static String _enemyLabelForStats(EnemyStats stats) {
    if (identical(stats, _basicDrone)) {
      return 'Drones';
    }
    if (identical(stats, _basicEliteDrone)) {
      return 'Elite Drones';
    }
    if (identical(stats, _armoredDrone)) {
      return 'Armored Drones';
    }
    if (identical(stats, _shieldedDrone)) {
      return 'Shielded Drones';
    }
    if (identical(stats, _swarmDrone)) {
      return 'Swarm Drones';
    }
    if (identical(stats, _regenDrone)) {
      return 'Regen Drones';
    }
    if (identical(stats, _heavyDrone)) {
      return 'Heavy Drones';
    }
    if (identical(stats, _armoredHeavyDrone)) {
      return 'Armored Heavy Drones';
    }
    if (identical(stats, _regenHeavyDrone)) {
      return 'Regen Heavy Drones';
    }

    final adjectives = [
      for (final trait in EnemyTrait.values)
        if (stats.hasTrait(trait)) _traitAdjective(trait),
    ];
    if (adjectives.isEmpty) {
      return 'Drones';
    }
    return '${adjectives.join(' ')} Drones';
  }

  static String _traitAdjective(EnemyTrait trait) {
    return switch (trait) {
      EnemyTrait.armored => 'Armored',
      EnemyTrait.shielded => 'Shielded',
      EnemyTrait.swarm => 'Swarm',
      EnemyTrait.regen => 'Regen',
      EnemyTrait.heavy => 'Heavy',
    };
  }

  static List<TowerType> _recommendedTowerTypes(
    WaveDefinition wave,
    List<TowerType> unlockedTowerTypes,
  ) {
    final recommendations = <TowerType>[];
    for (final group in wave.groups) {
      for (final trait in EnemyTrait.values) {
        if (!group.enemyStats.hasTrait(trait)) {
          continue;
        }
        for (final towerType in _counterTowersForTrait(trait)) {
          if (!unlockedTowerTypes.contains(towerType)) {
            continue;
          }
          if (recommendations.contains(towerType)) {
            continue;
          }
          recommendations.add(towerType);
          if (recommendations.length == 3) {
            return List.unmodifiable(recommendations);
          }
        }
      }
    }
    return List.unmodifiable(recommendations);
  }

  static List<TowerType> _counterTowersForTrait(EnemyTrait trait) {
    return switch (trait) {
      EnemyTrait.shielded => const [TowerType.ionChain],
      EnemyTrait.armored || EnemyTrait.heavy => const [
        TowerType.rocket,
        TowerType.railgun,
      ],
      EnemyTrait.swarm => const [
        TowerType.rocket,
        TowerType.cryo,
        TowerType.gravityWell,
      ],
      EnemyTrait.regen => const [
        TowerType.laser,
        TowerType.ionChain,
        TowerType.nanite,
      ],
    };
  }
```

- [ ] **Step 5: Run focused model tests**

Run:

```bash
rtk dart format lib/game/models/game_models.dart test/game/game_balance_test.dart
rtk flutter test test/game/game_balance_test.dart
```

Expected: PASS for `test/game/game_balance_test.dart`.

- [ ] **Step 6: Commit Task 1**

Run:

```bash
rtk git add lib/game/models/game_models.dart test/game/game_balance_test.dart
rtk git commit -m "feat: derive Orion wave previews"
```

---

### Task 2: Expose Preview Data Through GameSnapshot

**Files:**
- Modify: `lib/game/models/game_models.dart`
- Modify: `lib/game/rules/game_session.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Test: `test/game/game_session_test.dart`

- [ ] **Step 1: Write failing snapshot tests**

Add these tests in `test/game/game_session_test.dart` near the existing snapshot tests:

```dart
    test('snapshot exposes next wave preview only during build phase', () {
      final session = GameSession.initial();

      final firstPreview = session.snapshot().nextWavePreview;

      expect(firstPreview, isNotNull);
      expect(firstPreview!.waveNumber, 1);
      expect(firstPreview.waveTotal, 8);
      expect(
        firstPreview.groups.map(
          (group) => '${group.enemyCount} ${group.label}',
        ),
        ['8 Drones'],
      );

      expect(session.startWave(), isTrue);
      expect(session.snapshot().nextWavePreview, isNull);

      session.finishActiveWave();
      final secondPreview = session.snapshot().nextWavePreview;

      expect(secondPreview, isNotNull);
      expect(secondPreview!.waveNumber, 2);
      expect(
        secondPreview.groups.map(
          (group) => '${group.enemyCount} ${group.label}',
        ),
        ['8 Drones', '2 Armored Drones'],
      );
      expect(secondPreview.traits.toList(), [EnemyTrait.armored]);
      expect(secondPreview.recommendedTowerTypes, [
        TowerType.rocket,
        TowerType.railgun,
      ]);
    });

    test('snapshot preview uses selected stage single-group waves', () {
      final stage = StageDefinition(
        id: 'preview-stage',
        name: 'Preview Stage',
        mapLabel: 'Preview',
        description: 'Stage for preview tests',
        pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
        waves: const [
          WaveDefinition(
            groups: [
              WaveGroup(
                enemyCount: 3,
                enemyStats: EnemyStats(
                  health: 78,
                  speed: 72,
                  baseDamage: 1,
                  goldReward: 14,
                  traits: {EnemyTrait.regen},
                  regenPerSecond: 2.5,
                ),
              ),
            ],
            clearBonus: 42,
          ),
        ],
        unlockDependencies: [],
        isMainPath: true,
        mainPathOrder: 1,
        mapColumn: 0,
        mapRow: 0,
      );

      final preview = GameSession.initial(stage: stage)
          .snapshot()
          .nextWavePreview;

      expect(preview, isNotNull);
      expect(preview!.waveNumber, 1);
      expect(preview.waveTotal, 1);
      expect(preview.groups.single.enemyCount, 3);
      expect(preview.groups.single.label, 'Regen Drones');
      expect(preview.clearBonus, 42);
      expect(preview.recommendedTowerTypes, [TowerType.laser]);
    });

    test('snapshot preview carries final wave zero clear bonus', () {
      final session = GameSession.initial();

      for (var wave = 0; wave < 7; wave += 1) {
        expect(session.startWave(), isTrue);
        session.finishActiveWave();
      }

      final preview = session.snapshot().nextWavePreview;

      expect(preview, isNotNull);
      expect(preview!.waveNumber, 8);
      expect(preview.waveTotal, 8);
      expect(preview.clearBonus, 0);
    });

    test('snapshot hides next wave preview after win and loss', () {
      final wonSession = GameSession.initial();
      for (var wave = 0; wave < wonSession.stage.waves.length; wave += 1) {
        expect(wonSession.startWave(), isTrue);
        wonSession.finishActiveWave();
      }

      expect(wonSession.phase, GamePhase.won);
      expect(wonSession.snapshot().nextWavePreview, isNull);

      final lostSession = GameSession.initial();
      expect(lostSession.startWave(), isTrue);
      lostSession.damageBase(GameBalance.initialBaseHealth);

      expect(lostSession.phase, GamePhase.lost);
      expect(lostSession.snapshot().nextWavePreview, isNull);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
rtk flutter test test/game/game_session_test.dart
```

Expected: FAIL with `The getter 'nextWavePreview' isn't defined for the type 'GameSnapshot'`.

- [ ] **Step 3: Add `nextWavePreview` to `GameSnapshot`**

In `lib/game/models/game_models.dart`, update the `GameSnapshot` constructor and fields:

```dart
class GameSnapshot {
  GameSnapshot({
    required this.phase,
    required this.gold,
    required this.baseHealth,
    required this.waveNumber,
    required this.waveTotal,
    required this.stageId,
    required this.stageName,
    required this.stageLabel,
    required List<TowerType> unlockedTowerTypes,
    this.nextWavePreview,
    required this.selectedCell,
    required this.selectedTower,
    required this.feedback,
    required this.isPaused,
    required this.speedMultiplier,
    required this.autoStartEnabled,
    required this.autoStartCountdownRemaining,
  }) : unlockedTowerTypes = List.unmodifiable(unlockedTowerTypes);

  final GamePhase phase;
  final int gold;
  final int baseHealth;
  final int waveNumber;
  final int waveTotal;
  final String stageId;
  final String stageName;
  final String stageLabel;
  final List<TowerType> unlockedTowerTypes;
  final WavePreview? nextWavePreview;
  final GridPosition? selectedCell;
  final PlacedTower? selectedTower;
  final String? feedback;
  final bool isPaused;
  final double speedMultiplier;
  final bool autoStartEnabled;
  final double? autoStartCountdownRemaining;

  bool get canStartWave => phase == GamePhase.build;
  bool get isEnded => phase == GamePhase.won || phase == GamePhase.lost;
}
```

- [ ] **Step 4: Populate preview from `GameSession.snapshot()`**

In `lib/game/rules/game_session.dart`, replace the start of `snapshot(...)` with this implementation shape:

```dart
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
          )
        : null;

    return GameSnapshot(
      phase: _phase,
      gold: _gold,
      baseHealth: _baseHealth,
      waveNumber: waveNumber,
      waveTotal: stage.waves.length,
      stageId: stage.id,
      stageName: stage.name,
      stageLabel: stage.mapLabel,
      unlockedTowerTypes: unlockedTypes,
      nextWavePreview: nextWavePreview,
      selectedCell: selectedCell,
      selectedTower: selectedTower,
      feedback: feedback,
      isPaused: isPaused,
      speedMultiplier: speedMultiplier,
      autoStartEnabled: autoStartEnabled,
      autoStartCountdownRemaining: autoStartCountdownRemaining,
    );
  }
```

- [ ] **Step 5: Preserve preview in manual snapshot copy**

In `lib/game/ui/orion_game_page.dart`, update `_showCampaignPersistenceFailure()` so the manual `GameSnapshot(...)` copy includes this argument immediately after `unlockedTowerTypes`:

```dart
        nextWavePreview: snapshot.nextWavePreview,
```

- [ ] **Step 6: Check for other `GameSnapshot` constructor sites**

Run:

```bash
rtk rg -n "GameSnapshot\\(" lib test
```

Expected: every manual `GameSnapshot(...)` call either comes from `GameSession.snapshot()` or explicitly preserves `nextWavePreview`.

- [ ] **Step 7: Run focused session tests**

Run:

```bash
rtk dart format lib/game/models/game_models.dart lib/game/rules/game_session.dart lib/game/ui/orion_game_page.dart test/game/game_session_test.dart
rtk flutter test test/game/game_session_test.dart
```

Expected: PASS for `test/game/game_session_test.dart`.

- [ ] **Step 8: Commit Task 2**

Run:

```bash
rtk git add lib/game/models/game_models.dart lib/game/rules/game_session.dart lib/game/ui/orion_game_page.dart test/game/game_session_test.dart
rtk git commit -m "feat: expose next wave preview in snapshots"
```

---

### Task 3: Render the HUD-Attached Next Wave Panel

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart`
- Test: `test/widget_test.dart`

- [ ] **Step 1: Write failing widget tests for panel visibility**

In `test/widget_test.dart`, update `starts an unlocked stage from the world map` so it also asserts the initial panel:

```dart
    expect(find.text('Next Wave 1/8'), findsOneWidget);
    expect(find.text('8 Drones'), findsOneWidget);
    expect(find.text('Clear bonus 30'), findsOneWidget);
```

Add this new widget test after `mission screen exposes pause speed and auto-start controls`:

```dart
  testWidgets('next wave panel stays visible while planning and hides in wave', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    OrionDefenseGame? game;

    await tester.pumpWidget(
      MaterialApp(
        home: OrionGamePage(onGameCreated: (created) => game = created),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.text('Next Wave 1/8'), findsOneWidget);
    expect(find.text('8 Drones'), findsOneWidget);

    await tester.tapAt(const Offset(225, 275));
    await tester.pumpAndSettle();

    expect(find.text('Build Tower'), findsOneWidget);
    expect(find.text('Next Wave 1/8'), findsOneWidget);
    expect(find.text('8 Drones'), findsOneWidget);

    game!.startWave();
    await tester.pump();

    expect(find.text('Next Wave 1/8'), findsNothing);
    expect(find.text('8 Drones'), findsNothing);
  });
```

- [ ] **Step 2: Run widget tests to verify they fail**

Run:

```bash
rtk flutter test test/widget_test.dart
```

Expected: FAIL because `Next Wave 1/8`, `8 Drones`, and `Clear bonus 30` are not rendered yet.

- [ ] **Step 3: Place panel under the HUD**

In `lib/game/ui/orion_game_page.dart`, replace the existing HUD `Positioned` child:

```dart
                Positioned(
                  left: 12,
                  top: 12,
                  right: 12,
                  child: _Hud(snapshot: snapshot),
                ),
```

with:

```dart
                Positioned(
                  left: 12,
                  top: 12,
                  right: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Hud(snapshot: snapshot),
                      if (snapshot.nextWavePreview != null) ...[
                        const SizedBox(height: 8),
                        _NextWavePanel(preview: snapshot.nextWavePreview!),
                      ],
                    ],
                  ),
                ),
```

- [ ] **Step 4: Add `_NextWavePanel`**

In `lib/game/ui/orion_game_page.dart`, insert this widget after `_Hud` and before `_StatusChip`:

```dart
class _NextWavePanel extends StatelessWidget {
  const _NextWavePanel({required this.preview});

  final WavePreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recommendations = preview.recommendedTowerTypes
        .map(_towerLabel)
        .join(', ');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Next Wave ${preview.waveNumber}/${preview.waveTotal}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (preview.groups.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final group in preview.groups)
                    _StatusChip(label: '${group.enemyCount} ${group.label}'),
                ],
              ),
            ],
            if (preview.traits.isNotEmpty || preview.clearBonus > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final trait in preview.traits)
                    _StatusChip(label: _enemyTraitLabel(trait)),
                  if (preview.clearBonus > 0)
                    _StatusChip(label: 'Clear bonus ${preview.clearBonus}'),
                ],
              ),
            ],
            if (recommendations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Recommended: $recommendations',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Add trait display helper**

In `lib/game/ui/orion_game_page.dart`, add this helper near `_towerLabel(...)`:

```dart
String _enemyTraitLabel(EnemyTrait trait) {
  return switch (trait) {
    EnemyTrait.armored => 'Armored',
    EnemyTrait.shielded => 'Shielded',
    EnemyTrait.swarm => 'Swarm',
    EnemyTrait.regen => 'Regen',
    EnemyTrait.heavy => 'Heavy',
  };
}
```

- [ ] **Step 6: Run focused widget tests**

Run:

```bash
rtk dart format lib/game/ui/orion_game_page.dart test/widget_test.dart
rtk flutter test test/widget_test.dart
```

Expected: PASS for `test/widget_test.dart`.

- [ ] **Step 7: Commit Task 3**

Run:

```bash
rtk git add lib/game/ui/orion_game_page.dart test/widget_test.dart
rtk git commit -m "feat: render Orion next wave panel"
```

---

### Task 4: Cover Zero-Bonus UI Text and Snapshot Copy Behavior

**Files:**
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Add zero-bonus panel text test**

Add this widget test after the panel visibility test in `test/widget_test.dart`:

```dart
  testWidgets('next wave panel omits zero clear bonus text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    OrionDefenseGame? game;

    await tester.pumpWidget(
      MaterialApp(
        home: OrionGamePage(onGameCreated: (created) => game = created),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    final snapshot = game!.stateNotifier.value;
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.build,
      gold: snapshot.gold,
      baseHealth: snapshot.baseHealth,
      waveNumber: 8,
      waveTotal: snapshot.waveTotal,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      nextWavePreview: WavePreview(
        waveNumber: 8,
        waveTotal: snapshot.waveTotal,
        groups: [
          WavePreviewGroup(
            enemyCount: 4,
            label: 'Regen Heavy Drones',
            traits: const {EnemyTrait.regen, EnemyTrait.heavy},
          ),
        ],
        traits: const {EnemyTrait.regen, EnemyTrait.heavy},
        clearBonus: 0,
        recommendedTowerTypes: const [TowerType.laser, TowerType.rocket],
      ),
      selectedCell: snapshot.selectedCell,
      selectedTower: snapshot.selectedTower,
      feedback: snapshot.feedback,
      isPaused: snapshot.isPaused,
      speedMultiplier: snapshot.speedMultiplier,
      autoStartEnabled: snapshot.autoStartEnabled,
      autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
    );
    await tester.pump();

    expect(find.text('Next Wave 8/8'), findsOneWidget);
    expect(find.text('4 Regen Heavy Drones'), findsOneWidget);
    expect(find.text('Clear bonus 0'), findsNothing);
    expect(find.text('Recommended: Laser, Rocket'), findsOneWidget);
  });
```

- [ ] **Step 2: Add persistence-failure preview preservation assertion**

In the existing `stage clear save failure keeps prior progress and shows feedback` widget test, add this assertion after the existing feedback expectation:

```dart
      expect(find.text('Next Wave 1/8'), findsOneWidget);
```

This covers the manual `GameSnapshot(...)` copy in `_showCampaignPersistenceFailure()`.

- [ ] **Step 3: Run focused widget tests**

Run:

```bash
rtk dart format test/widget_test.dart
rtk flutter test test/widget_test.dart
```

Expected: PASS for `test/widget_test.dart`.

- [ ] **Step 4: Commit Task 4**

Run:

```bash
rtk git add test/widget_test.dart
rtk git commit -m "test: cover Orion wave preview panel edges"
```

---

### Task 5: Full Verification and Cleanup

**Files:**
- Verify all touched files.

- [ ] **Step 1: Run full formatter**

Run:

```bash
rtk dart format .
```

Expected: command exits 0. If files change, inspect them with:

```bash
rtk git diff --stat
```

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

- [ ] **Step 4: Review final diff**

Run:

```bash
rtk git status --short
rtk git diff --stat
```

Expected: only intentional HPA-92 implementation files appear. If `dart format .` changed files after Task 4, commit them with:

```bash
rtk git add lib/game/models/game_models.dart lib/game/rules/game_session.dart lib/game/ui/orion_game_page.dart test/game/game_balance_test.dart test/game/game_session_test.dart test/widget_test.dart
rtk git commit -m "chore: format Orion wave preview changes"
```

- [ ] **Step 5: Confirm acceptance criteria**

Check these outcomes against the final code and tests:

- Build phase renders `Next Wave n/8`.
- All `WaveGroup`s in the selected stage's active wave appear.
- Trait chips are distinct and deterministic.
- Clear bonus appears only when positive.
- Recommendations are filtered to unlocked tower types.
- Active wave, won, and lost states hide the panel.
- Existing tower selection, tower building, upgrade, specialization, pacing, and `Start Wave` flows remain covered by the passing test suite.
