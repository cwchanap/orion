# Orion Command Deck Mission HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver PR 2 of the Orion Command Deck redesign: interactive mission chrome, an art-led three-state command dock, correctly latched feedback, and cohesive mission modal surfaces.

**Architecture:** Build on PR 1's `OrionUiTheme`, `CommandFrame`, and loader-owned `OrionAtlasSprite` APIs. Split the current top overlay into pass-through numeric/module status and narrowly hit-tested pacing/scanner siblings. Extract mission HUD, scanner, dock, inspector scale, and toast widgets so `OrionGamePage` remains the overlay/state orchestrator and all game actions still flow through `OrionDefenseGame`.

**Tech Stack:** Dart `^3.12.0`, Flutter, Flame `^1.38.0`, Material 3, `flutter_test`; PR 1 local art/theme components; no new packages.

**Spec:** `docs/superpowers/specs/2026-08-20-orion-ui-hud-redesign-design.md`

**Dependency:** Implement after the world-map plan/PR so `OrionUiTheme`, `CommandFrame`, `ReactorButton`, `OrionArt`, and `OrionAtlasSprite` are available.

## Global Constraints

- This is PR 2 only: mission HUD, pacing, scanner, dock, inspector, toast, acquired modules, module draft, and mission report.
- Do not change `GameSession`, `GameSnapshot`, `OrionDefenseGame` gameplay ownership, board layout, pacing rules, placement rules, tower balance, campaign persistence, or modal content/callbacks.
- `GameWidget` remains `Positioned.fill` with the same game instance.
- Numeric HUD and acquired modules stay under active `IgnorePointer(ignoring: true)`; pacing and scanner are outside it and consume only painted bounds.
- Expanded scanner's maximum 212 × 168 dp area is an intentional board dead zone; the collapsed scanner consumes only 48 × 48 dp.
- Scanner, toast, and dock animation state are Flutter widget-local; no new snapshot fields.
- Every tower is visible in the build rail. Locked cards never place; unaffordable unlocked cards remain tappable so the game can publish insufficient-gold feedback.
- Inspector numbers and upgrade/specialization costs come from `snapshot.selectedTowerStats`; sell refund keeps `GameBalance.refundValue`.
- Stat-scale denominators derive from unmodified level 1, level 2, and both level-3 specialization values; campaign/stage/run modifiers never enter the denominator.
- Toast visibility latches through null snapshots and exits only on its 2.4-second timer.
- Acquired modules, module draft, and mission report use PR 1 tokens/frames without changing content or callbacks.
- Minimum interactive target is 48 × 48 dp; reduced motion follows `MediaQuery.disableAnimations`.
- No hosted assets, new fonts, new icon package, new goldens, or speculative performance work.
- Run focused tests, full `flutter test`, `flutter analyze`, and three-size local screenshot QA before review.

## Risks

- **Board hit testing:** test pass-through and dead-zone behavior with a real stack before replacing the page overlay.
- **Toast lifetime:** separate last input from latched display and timer state; null only re-arms.
- **Preview identity:** exact boss-name matching must run before heavy/basic fallback.
- **Inspector drift:** keep scale derivation in one pure catalog and keep the inspector free of a second base-stat lookup.
- **Copy-based tests:** retire old HUD/picker presentation finders in the same tasks and replace them with stable keys/semantics.
- **Modal mismatch:** restyle acquired modules, module draft, and mission report before the PR closes.

## File Map

### Create

- `lib/game/ui/mission_command_hud.dart` — three-anchor numeric HUD and interactive pacing strip.
- `lib/game/ui/next_wave_scanner.dart` — local expanded/collapsed preview state and art-led threat content.
- `lib/game/ui/mission_command_dock.dart` — dock priority, idle/wave command bar, and build rail.
- `lib/game/ui/tower_stat_scale.dart` — closed, modifier-free presentation denominators.
- `lib/game/ui/tower_inspector.dart` — selected-tower stats, targeting, progression actions, and sell action.
- `lib/game/ui/command_toast.dart` — latched mission feedback lifecycle.
- `test/widget/mission_command_hud_test.dart`
- `test/widget/next_wave_scanner_test.dart`
- `test/widget/mission_command_dock_test.dart`
- `test/widget/tower_stat_scale_test.dart`
- `test/widget/tower_inspector_test.dart`
- `test/widget/command_toast_test.dart`
- `test/widget/support/command_deck_fixtures.dart` — shared snapshot and preview builders for focused component tests.

### Modify

- `lib/game/ui/orion_game_page.dart` — new mission-stack layering, stable keys, and extracted widgets.
- `lib/game/ui/run_module_draft_panel.dart` — command-deck tokens/frames for acquired and draft surfaces.
- `lib/game/ui/mission_report_panel.dart` — command-deck tokens/frames for end-state surface/actions.
- `test/widget_test.dart` — mission integration, hit testing, retired copy, reduced motion, and modal layering.
- `test/widget/sell_button_test.dart` — inspector integration and resolved-stat/cost expectations.
- `test/widget/run_module_draft_panel_test.dart` — token/frame assertions while retaining callback tests.
- `test/widget/mission_report_panel_test.dart` — token/frame assertions while retaining save/action tests.

### No intended changes

- `lib/game/models/game_models.dart`
- `lib/game/rules/*`
- `lib/game/orion_defense_game.dart`
- `lib/game/components/*`
- `lib/game/campaign/*`
- any assets or `pubspec.yaml`

---

## Task 1: Split top hit testing and add the status HUD/pacing strip

**Files:**
- Create: `lib/game/ui/mission_command_hud.dart`
- Create: `test/widget/mission_command_hud_test.dart`
- Create: `test/widget/support/command_deck_fixtures.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Produces: `MissionStatusHud({required GameSnapshot snapshot})` and `MissionPacingStrip({required GameSnapshot snapshot, required VoidCallback onTogglePause, required ValueChanged<double> onSpeedSelected, required VoidCallback onToggleAutoStart})`.
- Consumes: `OrionUiTheme`, `CommandFrame`, existing `GameSnapshot` pacing fields, and existing game callbacks.
- Preserves: numeric snapshot values and existing pacing enable/disable rules.

- [ ] **Step 1: Add one exact snapshot/preview fixture for focused tests**

Create `test/widget/support/command_deck_fixtures.dart`:

```dart
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
    groups: groups ??
        [
          WavePreviewGroup(
            enemyCount: 8,
            label: 'Drones',
            traits: const {},
          ),
        ],
    traits: traits,
    clearBonus: clearBonus,
    recommendedTowerTypes: recommendedTowerTypes,
  );
}

TowerStats commandDeckTowerStats(
  TowerStats base, {
  double? damage,
  int? upgradeCost,
  int? specializationCost,
}) {
  return TowerStats(
    type: base.type,
    level: base.level,
    specialization: base.specialization,
    cost: base.cost,
    upgradeCost: upgradeCost ?? base.upgradeCost,
    specializationCost: specializationCost ?? base.specializationCost,
    range: base.range,
    damage: damage ?? base.damage,
    fireInterval: base.fireInterval,
    projectileSpeed: base.projectileSpeed,
    splashRadius: base.splashRadius,
    slowMultiplier: base.slowMultiplier,
    slowDuration: base.slowDuration,
    pierceCount: base.pierceCount,
    pierceWidth: base.pierceWidth,
    chainCount: base.chainCount,
    chainRange: base.chainRange,
    chainFalloff: base.chainFalloff,
    corrosionDamagePerSecond: base.corrosionDamagePerSecond,
    corrosionDuration: base.corrosionDuration,
    armorShred: base.armorShred,
    fieldRadius: base.fieldRadius,
    fieldDuration: base.fieldDuration,
    fieldTickInterval: base.fieldTickInterval,
    droneCount: base.droneCount,
    droneLifetime: base.droneLifetime,
    droneDamage: base.droneDamage,
    droneAttackInterval: base.droneAttackInterval,
    maxActiveDrones: base.maxActiveDrones,
    shieldDamageMultiplier: base.shieldDamageMultiplier,
    armorDamageMultiplier: base.armorDamageMultiplier,
    slowedDamageMultiplier: base.slowedDamageMultiplier,
    prismSplitDamageMultiplier: base.prismSplitDamageMultiplier,
    prismSplitRange: base.prismSplitRange,
    clusterBurstCount: base.clusterBurstCount,
    clusterBurstDamageMultiplier: base.clusterBurstDamageMultiplier,
    clusterBurstRadius: base.clusterBurstRadius,
  );
}
```

- [ ] **Step 2: Write HUD value, callback, and hit-test tests first**

Create `test/widget/mission_command_hud_test.dart` with the shared fixture and these tests:

```dart
testWidgets('status HUD exposes exact snapshot values through semantics',
    (tester) async {
  final snapshot = commandDeckSnapshot(
    baseHealth: 8,
    startingBaseHealth: 20,
    gold: 150,
    waveNumber: 3,
    waveTotal: 8,
  );
  await tester.pumpWidget(
    MaterialApp(home: MissionStatusHud(snapshot: snapshot)),
  );

  expect(find.bySemanticsLabel('Base 8 of 20'), findsOneWidget);
  expect(find.bySemanticsLabel('Wave 3 of 8'), findsOneWidget);
  expect(find.bySemanticsLabel('Credits 150'), findsOneWidget);
});

testWidgets('pacing strip invokes existing control callbacks', (tester) async {
  var pauseTaps = 0;
  var autoTaps = 0;
  double? speed;
  await tester.pumpWidget(
    MaterialApp(
      home: MissionPacingStrip(
        snapshot: commandDeckSnapshot(phase: GamePhase.wave),
        onTogglePause: () => pauseTaps += 1,
        onSpeedSelected: (value) => speed = value,
        onToggleAutoStart: () => autoTaps += 1,
      ),
    ),
  );

  await tester.tap(find.byTooltip('Pause'));
  await tester.tap(find.text('2x'));
  await tester.tap(find.byTooltip('Auto-start waves'));
  expect((pauseTaps, speed, autoTaps), (1, 2.0, 1));
});

testWidgets('status passes taps through while pacing consumes them',
    (tester) async {
  var backgroundTaps = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => backgroundTaps += 1,
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: IgnorePointer(
              child: MissionStatusHud(snapshot: commandDeckSnapshot()),
            ),
          ),
          Positioned(
            top: 76,
            left: 0,
            right: 0,
            child: Center(
              child: MissionPacingStrip(
                snapshot: commandDeckSnapshot(phase: GamePhase.wave),
                onTogglePause: () {},
                onSpeedSelected: (_) {},
                onToggleAutoStart: () {},
              ),
            ),
          ),
        ],
      ),
    ),
  );

  await tester.tap(find.byKey(const ValueKey('mission-status-hud')));
  expect(backgroundTaps, 1);
  await tester.tap(find.byTooltip('Pause'));
  expect(backgroundTaps, 1);
});
```

Add threshold assertions for 51% cyan, 50% orange, and 25% red using a keyed base-health fill/icon. Add a countdown case expecting `Auto-start waves, 3 seconds` semantics from `2.2` seconds.

In `test/widget_test.dart`, update the current `_activeIgnorePointerAncestorsOf` checks so the status HUD/acquired strip still have one active ancestor and the pacing strip has none.

- [ ] **Step 3: Run the focused tests to verify RED**

```bash
rtk flutter test test/widget/mission_command_hud_test.dart test/widget_test.dart
```

Expected: compile failure for the new widgets and old IgnorePointer expectations fail.

- [ ] **Step 4: Implement the three status anchors**

Create `lib/game/ui/mission_command_hud.dart`. `MissionStatusHud` is a 52–58 dp `Row` keyed `mission-status-hud`:

- left `Expanded`: shield icon, `current/starting`, and a health fill keyed `base-health-fill`;
- center `Expanded`: `stageLabel`, `waveNumber/waveTotal`, and phase/paused beacon;
- right fixed/expanded: credit icon and gold;
- `Semantics(container: true, label: 'Base ${snapshot.baseHealth} of ${snapshot.startingBaseHealth}')` on the left anchor;
- `Semantics(container: true, label: 'Wave ${snapshot.waveNumber} of ${snapshot.waveTotal}')` on the center anchor;
- `Semantics(container: true, label: 'Credits ${snapshot.gold}')` on the right anchor;
- `Tooltip` for truncated full stage name.

Use this exact threshold helper:

```dart
Color baseHealthColor(GameSnapshot snapshot, OrionUiTheme uiTheme) {
  final fraction = snapshot.startingBaseHealth == 0
      ? 0.0
      : snapshot.baseHealth / snapshot.startingBaseHealth;
  if (fraction > 0.50) return uiTheme.systemCyan;
  if (fraction > 0.25) return uiTheme.warningOrange;
  return uiTheme.dangerRed;
}
```

- [ ] **Step 5: Implement interactive pacing with existing gating**

`MissionPacingStrip` must copy the current enable rules exactly:

```dart
final canUsePacing = !snapshot.isEnded;
final canTogglePause =
    canUsePacing &&
    (snapshot.phase == GamePhase.wave ||
        snapshot.autoStartCountdownRemaining != null ||
        snapshot.isPaused);
```

Use a compact `CommandFrame` around pause/resume, 1x/2x/3x, and auto-start. The countdown is shown in the auto control's visible/semantic state rather than a separate chip. Duration comes from `orionMotionDuration`.

- [ ] **Step 6: Split `_buildStageScaffold` into pass-through and interactive siblings**

In `orion_game_page.dart`, replace the one top `IgnorePointer` column with:

```dart
Positioned(
  left: 12,
  top: 12,
  right: 12,
  child: IgnorePointer(
    ignoring: true,
    child: Column(
      children: [
        MissionStatusHud(snapshot: snapshot),
        const SizedBox(height: 56),
        if (snapshot.acquiredRunModules.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: AcquiredRunModuleStrip(
                moduleIds: snapshot.acquiredRunModules,
              ),
            ),
          ),
      ],
    ),
  ),
),
Positioned(
  top: 76,
  left: 0,
  right: 0,
  child: Center(
    child: MissionPacingStrip(
      snapshot: snapshot,
      onTogglePause: game.togglePause,
      onSpeedSelected: game.setSpeedMultiplier,
      onToggleAutoStart: game.toggleAutoStart,
    ),
  ),
),
```

Do not add a full-width opaque `GestureDetector` or `AbsorbPointer` around the pacing strip. Keep module draft/mission report later in the stack.

In the page state, precache the three UI atlas assets once for that mission-shell lifetime:

```dart
bool _didPrecacheCommandDeckAssets = false;

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  if (_didPrecacheCommandDeckAssets) return;
  _didPrecacheCommandDeckAssets = true;
  for (final assetPath in const [
    GameSpriteSheet.assetPath,
    GameTowerVarietySheet.assetPath,
    GameBossSheet.assetPath,
  ]) {
    precacheImage(AssetImage(assetPath), context);
  }
}
```

This is the only mission-shell performance work in the slice. `OrionAtlasSprite` continues to use Flutter's shared `AssetImage` cache; no card decodes an image during `build`.

- [ ] **Step 7: Run tests and commit**

```bash
rtk dart format lib/game/ui/mission_command_hud.dart lib/game/ui/orion_game_page.dart test/widget/mission_command_hud_test.dart test/widget/support/command_deck_fixtures.dart test/widget_test.dart
rtk flutter test test/widget/mission_command_hud_test.dart test/widget_test.dart
rtk git add lib/game/ui/mission_command_hud.dart lib/game/ui/orion_game_page.dart test/widget/mission_command_hud_test.dart test/widget/support/command_deck_fixtures.dart test/widget_test.dart
rtk git commit -m "feat: add interactive Orion mission HUD"
```

Expected: status stays pass-through, pacing is interactive, and existing pacing behavior remains green.

---

## Task 2: Add the stateful next-wave scanner with closed art mapping

**Files:**
- Create: `lib/game/ui/next_wave_scanner.dart`
- Create: `test/widget/next_wave_scanner_test.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Produces: `NextWaveScanner({required WavePreview preview, required List<String> modifierTitles})` with widget-local expansion keyed by `preview.waveNumber`.
- Consumes: PR 1 `OrionArt.previewGroup`, `OrionArt.trait`, `OrionAtlasSprite`, `CommandFrame`, and existing `WavePreview` fields.
- Parent is responsible for omitting the scanner during waves, ended states, or module drafts.

- [ ] **Step 1: Write scanner lifecycle/content tests first**

Create `test/widget/next_wave_scanner_test.dart`:

```dart
Widget scannerHost(
  WavePreview preview, {
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Align(
        alignment: Alignment.topRight,
        child: NextWaveScanner(
          preview: preview,
          modifierTitles: const ['Standard Conditions'],
        ),
      ),
    ),
  );
}

testWidgets('scanner expands initially, stays collapsed for one preview, and reopens for the next',
    (tester) async {
  final first = commandDeckPreview(waveNumber: 1);
  await tester.pumpWidget(scannerHost(first));
  expect(find.byKey(const ValueKey('next-wave-scanner-expanded')), findsOneWidget);

  await tester.tap(find.byTooltip('Collapse next-wave scanner'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('next-wave-scanner-collapsed')), findsOneWidget);
  expect(
    tester.getSize(find.byKey(const ValueKey('next-wave-scanner-collapsed'))),
    const Size(48, 48),
  );

  await tester.pumpWidget(scannerHost(first));
  expect(find.byKey(const ValueKey('next-wave-scanner-collapsed')), findsOneWidget);

  await tester.pumpWidget(scannerHost(commandDeckPreview(waveNumber: 2)));
  expect(find.byKey(const ValueKey('next-wave-scanner-expanded')), findsOneWidget);
});

testWidgets('Swarm Queen preview uses boss art despite lacking heavy trait',
    (tester) async {
  final bossPreview = commandDeckPreview(
    groups: [
      WavePreviewGroup(
        enemyCount: 1,
        label: 'Swarm Queen',
        traits: {EnemyTrait.swarm, EnemyTrait.regen},
      ),
    ],
  );
  await tester.pumpWidget(scannerHost(bossPreview));

  expect(find.bySemanticsLabel('Swarm Queen'), findsOneWidget);
  expect(find.byKey(const ValueKey('preview-art-boss-swarmQueen')), findsOneWidget);
});
```

Also assert expanded size is no larger than 212 × 168; group counts, trait semantics, clear bonus, recommendations, and modifier titles are discoverable; reduced motion collapses after one pump; the collapsed semantics include next wave and total enemy count.

In `test/widget_test.dart`, change the old always-visible panel test into page-level coverage that the scanner exists in build, is outside `IgnorePointer`, and is absent after `game.startWave()` or while a module draft is active.

- [ ] **Step 2: Run tests to verify RED**

```bash
rtk flutter test test/widget/next_wave_scanner_test.dart test/widget_test.dart
```

Expected: compile failure/new scanner assertions fail.

- [ ] **Step 3: Implement widget-local preview state**

Create `lib/game/ui/next_wave_scanner.dart` as a `StatefulWidget`:

```dart
bool _expanded = true;

@override
void didUpdateWidget(covariant NextWaveScanner oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (oldWidget.preview.waveNumber != widget.preview.waveNumber) {
    _expanded = true;
  }
}
```

Use `AnimatedSwitcher`/`AnimatedSize` with `orionMotionDuration(context, const Duration(milliseconds: 180))`.

Collapsed content is exactly a 48 × 48 radar control keyed `next-wave-scanner-collapsed`. Expanded content is a `CommandFrame` keyed `next-wave-scanner-expanded` and constrained to `maxWidth: 212`, `maxHeight: 168`. The expanded body is scrollable if content exceeds 168 dp.

For each group, render `OrionAtlasSprite(art: OrionArt.previewGroup(group))`, count, short label, and badges. Use `OrionArt.trait` for armor/shield/regen; use the established square/triangle fallback glyph for heavy/swarm. Render recommended tower art with `OrionArt.tower`.

Give each preview portrait `ValueKey('preview-art-${art.debugName}')`; PR 1 defines Swarm Queen's debug name as `boss-swarmQueen`, producing the tested key `preview-art-boss-swarmQueen`.

- [ ] **Step 4: Add the narrowly positioned scanner sibling**

In the stage stack, add after the pacing strip:

```dart
if (snapshot.phase == GamePhase.build &&
    snapshot.nextWavePreview != null &&
    snapshot.pendingRunModuleOffer == null &&
    !snapshot.isEnded)
  Positioned(
    top: 132,
    right: 12,
    child: NextWaveScanner(
      preview: snapshot.nextWavePreview!,
      modifierTitles: snapshot.stageModifiers.isEmpty
          ? [StageModifierMetadata.standardConditions.title]
          : snapshot.stageModifiers
                .map(
                  (modifier) =>
                      StageModifierMetadata.forModifier(modifier).title,
                )
                .toList(growable: false),
    ),
  ),
```

Do not place it under the status `IgnorePointer`. Its own 48 × 48 or 212 × 168 render box defines the intentional dead zone.

- [ ] **Step 5: Run tests and commit**

```bash
rtk dart format lib/game/ui/next_wave_scanner.dart lib/game/ui/orion_game_page.dart test/widget/next_wave_scanner_test.dart test/widget_test.dart
rtk flutter test test/widget/next_wave_scanner_test.dart test/widget_test.dart
rtk git add lib/game/ui/next_wave_scanner.dart lib/game/ui/orion_game_page.dart test/widget/next_wave_scanner_test.dart test/widget_test.dart
rtk git commit -m "feat: add Orion next-wave scanner"
```

Expected: lifecycle, boss mapping, data exposure, hit testing, phase hiding, and reduced-motion tests pass.

---

## Task 3: Add the idle command bar and art-led build rail

**Files:**
- Create: `lib/game/ui/mission_command_dock.dart`
- Create: `test/widget/mission_command_dock_test.dart`

**Interfaces:**
- Produces: `IdleCommandBar({required GameSnapshot snapshot, required VoidCallback onWorldMap, required VoidCallback onStartWave})` and `TowerBuildRail({required GamePhase phase, required int gold, required List<TowerType> unlockedTowerTypes, required ValueChanged<TowerType> onPlaceTower})`.
- Defers `MissionCommandDock` orchestration until Task 4, after `TowerInspector` exists; this task compiles and commits without a temporary selected-tower adapter.
- Preserves existing Start Wave and World Map gating through explicit callbacks and snapshot state.

- [ ] **Step 1: Write idle-bar and tower-card tests first**

Create `test/widget/mission_command_dock_test.dart`:

```dart
Widget railHost({
  int gold = 9999,
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
  ValueChanged<TowerType>? onPlaceTower,
}) {
  return MaterialApp(
    home: Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: 375,
        height: 104,
        child: TowerBuildRail(
          phase: GamePhase.build,
          gold: gold,
          unlockedTowerTypes: unlockedTowerTypes,
          onPlaceTower: onPlaceTower ?? (_) {},
        ),
      ),
    ),
  );
}

testWidgets('build rail shows every tower and preserves lock/affordability callbacks',
    (tester) async {
  final placed = <TowerType>[];
  await tester.pumpWidget(
    MaterialApp(
      home: TowerBuildRail(
        phase: GamePhase.build,
        gold: 0,
        unlockedTowerTypes: const [TowerType.laser],
        onPlaceTower: placed.add,
      ),
    ),
  );

  for (final type in TowerType.values) {
    expect(find.byKey(ValueKey('tower-card-${type.name}')), findsOneWidget);
  }

  await tester.tap(find.byKey(const ValueKey('tower-card-laser')));
  expect(placed, [TowerType.laser]);

  await tester.tap(find.byKey(const ValueKey('tower-card-railgun')));
  expect(placed, [TowerType.laser]);
  expect(
    find.bySemanticsLabel(contains('Railgun, locked until wave')),
    findsOneWidget,
  );
});

testWidgets('five art cards fit or peek at 375dp and the rail scrolls',
    (tester) async {
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(railHost());

  final first = tester.getRect(find.byKey(const ValueKey('tower-card-laser')));
  final fifth = tester.getRect(find.byKey(const ValueKey('tower-card-ionChain')));
  expect(first.width, 64);
  expect(fifth.left, lessThan(375));
  expect(find.byType(Scrollable), findsWidgets);
});
```

Also cover:

- affordable semantics vs unaffordable semantics;
- locked card has no callback even if gold is sufficient;
- active-wave phase prevents every build callback;
- idle World Map and Start Wave actions invoke once and obey snapshot gating;
- reduced motion sets the idle bar's reactor transition duration to zero.

- [ ] **Step 2: Run tests to verify RED**

```bash
rtk flutter test test/widget/mission_command_dock_test.dart test/widget_test.dart
```

Expected: compile failure for the extracted idle/build widgets.

- [ ] **Step 3: Implement the build rail's exact state rules**

Create `lib/game/ui/mission_command_dock.dart`. `TowerBuildRail` iterates all `TowerType.values`, not only unlocked types. For each type:

```dart
final stats = GameBalance.towerStats(type, level: 1);
final unlocked = unlockedTowerTypes.contains(type);
final affordable = gold >= stats.cost;
final canAttempt = phase == GamePhase.build && unlocked;
```

The card is 64 dp wide, uses `OrionAtlasSprite(art: OrionArt.tower(type))`, one-line label, and credit cost. `onTap` is `canAttempt ? () => onPlaceTower(type) : null`; affordability changes styling/semantics only and never removes the callback. Locked cards show unlock wave from `GameBalance.towerUnlockWave(type)` and never call placement.

Use a horizontal `ListView.separated` with 6 dp gaps. Give every card the stable key `tower-card-${type.name}` and semantics containing name, cost, locked/unlocked, affordable/unaffordable, and “place on selected cell.”

- [ ] **Step 4: Implement the standalone idle/wave bar**

`IdleCommandBar` uses the World Map action, minimal phase status, and `ReactorButton` for Start Wave/countdown/wave progress. Its World Map callback is enabled only in `GamePhase.build`; its Start Wave callback is enabled only when `snapshot.canStartWave` is true. Preserve the visible consequential labels `World Map`, `Start Wave`, and `Start Now`, and expose the active wave/countdown state through semantics.

Wrap the bar in `CommandFrame`. Do not add the three-state `MissionCommandDock`, import `TowerInspector`, or modify `OrionGamePage` in this task.

- [ ] **Step 5: Run tests and commit**

```bash
rtk dart format lib/game/ui/mission_command_dock.dart test/widget/mission_command_dock_test.dart
rtk flutter test test/widget/mission_command_dock_test.dart
rtk git add lib/game/ui/mission_command_dock.dart test/widget/mission_command_dock_test.dart
rtk git commit -m "feat: add Orion mission command controls"
```

Expected: callback, lock, affordability, compact-width, idle-action, and reduced-motion tests pass without page integration.

---

## Task 4: Add closed stat scales and the selected-tower inspector

**Files:**
- Create: `lib/game/ui/tower_stat_scale.dart`
- Create: `lib/game/ui/tower_inspector.dart`
- Create: `test/widget/tower_stat_scale_test.dart`
- Create: `test/widget/tower_inspector_test.dart`
- Modify: `lib/game/ui/mission_command_dock.dart`
- Modify: `test/widget/mission_command_dock_test.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget/sell_button_test.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Produces: `TowerStatScale.forType(TowerType)`, normalized core/secondary values, and `TowerInspector`.
- `TowerInspector` consumes `GameSnapshot`, explicit upgrade/specialize/target/sell callbacks, and sell refund; it never resolves base tower stats.
- Produces: callback-driven `MissionCommandDock` orchestration; `OrionGamePage` remains the only adapter from `OrionDefenseGame` methods to UI callbacks.
- Preserves dock priority: selected tower → selected cell → idle/wave.

- [ ] **Step 1: Write stat-scale tests first**

Create `test/widget/tower_stat_scale_test.dart`:

```dart
void main() {
  test('every tower scale covers level 1, level 2, and both specializations', () {
    for (final type in TowerType.values) {
      final scale = TowerStatScale.forType(type);
      final candidates = [
        GameBalance.towerStats(type, level: 1),
        GameBalance.towerStats(type, level: 2),
        for (final specialization in GameBalance.specializationsFor(type))
          GameBalance.towerStats(
            type,
            level: 3,
            specialization: specialization,
          ),
      ];

      expect(candidates, hasLength(4), reason: type.name);
      expect(scale.damageMax, candidates.map((stats) => stats.damage).reduce(max));
      expect(
        scale.shotsPerSecondMax,
        candidates.map((stats) => 1 / stats.fireInterval).reduce(max),
      );
      expect(scale.rangeMax, candidates.map((stats) => stats.range).reduce(max));
    }
  });

  test('resolved modifier values clamp without entering the denominator', () {
    final base = GameBalance.towerStats(TowerType.laser, level: 1);
    final scale = TowerStatScale.forType(TowerType.laser);
    final boosted = base.copyWith(
      damage: scale.damageMax * 2,
      range: scale.rangeMax * 2,
      fireInterval: 1 / (scale.shotsPerSecondMax * 2),
    );

    expect(scale.damageFill(boosted), 1);
    expect(scale.fireFill(boosted), 1);
    expect(scale.rangeFill(boosted), 1);
  });
}
```

Import `dart:math` for `max`. Add secondary-metric assertions for Cryo slow duration, Rocket splash radius, Nanite corrosion DPS, and Drone Bay drone damage; the other four types have no secondary row because the current inspector does not expose one.

- [ ] **Step 2: Write inspector source/callback/compact tests**

Create `test/widget/tower_inspector_test.dart` with a selected-tower snapshot. Include this source/callback regression:

```dart
testWidgets('inspector uses resolved costs and invokes public callbacks',
    (tester) async {
  const tower = PlacedTower(
    id: 7,
    type: TowerType.laser,
    position: GridPosition(2, 3),
  );
  final resolved = commandDeckTowerStats(
    GameBalance.towerStats(TowerType.laser, level: 1),
    damage: 999,
    upgradeCost: 37,
  );
  var upgrades = 0;
  var sells = 0;
  TowerTargetingMode? targeting;

  await tester.pumpWidget(
    MaterialApp(
      home: TowerInspector(
        snapshot: commandDeckSnapshot(
          selectedTower: tower,
          selectedTowerStats: resolved,
        ),
        onUpgrade: () => upgrades++,
        onSpecialize: (_) {},
        onTargetingChanged: (mode) => targeting = mode,
        onSell: () => sells++,
        sellRefund: 41,
      ),
    ),
  );

  expect(find.bySemanticsLabel('Damage 999'), findsOneWidget);
  expect(find.text('Upgrade 37'), findsOneWidget);
  expect(find.text('Sell 41'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('tower-upgrade')));
  await tester.tap(
    find.byKey(const ValueKey('tower-target-strongest')),
  );
  await tester.tap(find.byKey(const ValueKey('tower-sell')));
  expect(upgrades, 1);
  expect(targeting, TowerTargetingMode.strongest);
  expect(sells, 1);
});
```

Also assert:

- displayed damage/fire/range/secondary numbers equal `snapshot.selectedTowerStats`;
- level-1 Upgrade label uses `selectedTowerStats.upgradeCost`;
- level-2 specialization labels use `selectedTowerStats.specializationCost`;
- target-mode selection invokes the chosen mode once;
- sell uses the supplied refund and invokes once;
- null `selectedTowerStats` omits bars and disables progression actions without throwing;
- 375 × 812 stays within the 210 dp/31% inspector cap and scrolls internally when needed;
- level 3 shows Max instead of upgrade/specialization.

Use public `TowerInspector` callbacks rather than grafting fake game state. Give progression, targeting, and sell actions the exact keys used above plus `tower-specialization-${specialization.name}`.

- [ ] **Step 3: Run tests to verify RED**

```bash
rtk flutter test test/widget/tower_stat_scale_test.dart test/widget/tower_inspector_test.dart
```

Expected: compile failure for the new scale/inspector types.

- [ ] **Step 4: Implement the closed scale catalog**

Create `lib/game/ui/tower_stat_scale.dart`:

```dart
enum TowerSecondaryMetric {
  slowDuration,
  splashRadius,
  corrosionDamagePerSecond,
  droneDamage,
}

final class TowerStatScale {
  const TowerStatScale({
    required this.damageMax,
    required this.shotsPerSecondMax,
    required this.rangeMax,
    required this.secondaryMetric,
    required this.secondaryMax,
  });

  final double damageMax;
  final double shotsPerSecondMax;
  final double rangeMax;
  final TowerSecondaryMetric? secondaryMetric;
  final double? secondaryMax;

  static final Map<TowerType, TowerStatScale> _byType = {
    for (final type in TowerType.values) type: _build(type),
  };

  static TowerStatScale forType(TowerType type) => _byType[type]!;

  static TowerStatScale _build(TowerType type) {
    final candidates = [
      GameBalance.towerStats(type, level: 1),
      GameBalance.towerStats(type, level: 2),
      for (final specialization in GameBalance.specializationsFor(type))
        GameBalance.towerStats(
          type,
          level: 3,
          specialization: specialization,
        ),
    ];
    final secondaryMetric = switch (type) {
      TowerType.cryo => TowerSecondaryMetric.slowDuration,
      TowerType.rocket => TowerSecondaryMetric.splashRadius,
      TowerType.nanite => TowerSecondaryMetric.corrosionDamagePerSecond,
      TowerType.droneBay => TowerSecondaryMetric.droneDamage,
      TowerType.laser ||
      TowerType.railgun ||
      TowerType.ionChain ||
      TowerType.gravityWell => null,
    };
    return TowerStatScale(
      damageMax: candidates.map((stats) => stats.damage).reduce(math.max),
      shotsPerSecondMax: candidates
          .map((stats) => 1 / stats.fireInterval)
          .reduce(math.max),
      rangeMax: candidates.map((stats) => stats.range).reduce(math.max),
      secondaryMetric: secondaryMetric,
      secondaryMax: secondaryMetric == null
          ? null
          : candidates
                .map((stats) => secondaryMetric.valueOf(stats))
                .reduce(math.max),
    );
  }

  double damageFill(TowerStats stats) => _fill(stats.damage, damageMax);
  double fireFill(TowerStats stats) =>
      _fill(1 / stats.fireInterval, shotsPerSecondMax);
  double rangeFill(TowerStats stats) => _fill(stats.range, rangeMax);
  double? secondaryFill(TowerStats stats) {
    final metric = secondaryMetric;
    final maximum = secondaryMax;
    return metric == null || maximum == null
        ? null
        : _fill(metric.valueOf(stats), maximum);
  }

  static double _fill(double value, double maximum) =>
      maximum <= 0 ? 0 : (value / maximum).clamp(0, 1).toDouble();
}
```

Import `dart:math` as `math`. Add a `valueOf(TowerStats)` extension on `TowerSecondaryMetric` with an exhaustive switch. This static map is the closed presentation catalog: each denominator is calculated once from the four unmodified balance entries and is never influenced by a runtime snapshot.

- [ ] **Step 5: Implement `TowerInspector` from snapshot-resolved data**

Create `lib/game/ui/tower_inspector.dart` with constructor:

```dart
const TowerInspector({
  super.key,
  required this.snapshot,
  required this.onUpgrade,
  required this.onSpecialize,
  required this.onTargetingChanged,
  required this.onSell,
  required this.sellRefund,
});
```

Read `final tower = snapshot.selectedTower!; final stats = snapshot.selectedTowerStats;`. If `stats == null`, show portrait/name/level, omit stat rows, and disable upgrade/specialization. Otherwise:

- render actual values from `stats` beside bars from `TowerStatScale.forType(tower.type)`;
- read `stats.upgradeCost` and `stats.specializationCost` for action copy and `snapshot.gold` gating;
- render existing targeting modes with short visible labels and full tooltips/semantics;
- use the passed `sellRefund` for the separated destructive action;
- cap height at `math.min(210, MediaQuery.sizeOf(context).height * .31)` and use internal scrolling; import `dart:math` as `math`.

Do not call `GameBalance.towerStats` in this file.

- [ ] **Step 6: Add three-state dock orchestration and integrate the page**

Add `MissionCommandDock` to `mission_command_dock.dart` with this callback-driven constructor:

```dart
const MissionCommandDock({
  super.key,
  required this.snapshot,
  required this.onWorldMap,
  required this.onStartWave,
  required this.onPlaceTower,
  required this.onUpgrade,
  required this.onSpecialize,
  required this.onTargetingChanged,
  required this.onSell,
});
```

Keep this exact selection order and wiring:

```dart
Widget content;
Key contentKey;
if (snapshot.selectedTower != null) {
  contentKey = const ValueKey('command-dock-tower');
  content = TowerInspector(
    snapshot: snapshot,
    onUpgrade: onUpgrade,
    onSpecialize: onSpecialize,
    onTargetingChanged: onTargetingChanged,
    onSell: onSell,
    sellRefund: GameBalance.refundValue(snapshot.selectedTower!),
  );
} else if (snapshot.selectedCell != null) {
  contentKey = const ValueKey('command-dock-build');
  content = TowerBuildRail(
    phase: snapshot.phase,
    gold: snapshot.gold,
    unlockedTowerTypes: snapshot.unlockedTowerTypes,
    onPlaceTower: onPlaceTower,
  );
} else {
  contentKey = const ValueKey('command-dock-idle');
  content = IdleCommandBar(
    snapshot: snapshot,
    onWorldMap: onWorldMap,
    onStartWave: onStartWave,
  );
}
```

Wrap `KeyedSubtree(key: contentKey, child: content)` in `CommandFrame` and `AnimatedSwitcher` using `orionMotionDuration(context, const Duration(milliseconds: 180))`.

In `mission_command_dock_test.dart`, add tests that assert the three keys above in priority order and reduced-motion duration zero with no game fake. In `orion_game_page.dart`, replace `_BottomControls` with:

```dart
MissionCommandDock(
  snapshot: snapshot,
  onWorldMap: game.returnToMap,
  onStartWave: game.startWave,
  onPlaceTower: game.placeTower,
  onUpgrade: game.upgradeSelectedTower,
  onSpecialize: game.specializeSelectedTower,
  onTargetingChanged: game.setTargetingMode,
  onSell: game.sellSelectedTower,
)
```

Update page tests that relied on visible `Build Tower`, `Gold 150`, `Base 20`, or generic button structure to use stable dock/HUD keys and semantic values. Keep exact action-copy assertions for Start Wave, Upgrade, specialization, Sell, and World Map.

Update `sell_button_test.dart` and selected-tower page tests to use the extracted inspector's keys/semantics while retaining all existing resolved-stat and callback regressions.

- [ ] **Step 7: Run tests and commit**

```bash
rtk dart format lib/game/ui/tower_stat_scale.dart lib/game/ui/tower_inspector.dart lib/game/ui/mission_command_dock.dart lib/game/ui/orion_game_page.dart test/widget/tower_stat_scale_test.dart test/widget/tower_inspector_test.dart test/widget/mission_command_dock_test.dart test/widget/sell_button_test.dart test/widget_test.dart
rtk flutter test test/widget/tower_stat_scale_test.dart test/widget/tower_inspector_test.dart test/widget/mission_command_dock_test.dart test/widget/sell_button_test.dart test/widget_test.dart
rtk git add lib/game/ui/tower_stat_scale.dart lib/game/ui/tower_inspector.dart lib/game/ui/mission_command_dock.dart lib/game/ui/orion_game_page.dart test/widget/tower_stat_scale_test.dart test/widget/tower_inspector_test.dart test/widget/mission_command_dock_test.dart test/widget/sell_button_test.dart test/widget_test.dart
rtk git commit -m "feat: redesign Orion tower inspector"
```

Expected: all resolved-value, cost, scale, targeting, progression, sell, null, and compact-height tests pass.

---

## Task 5: Add a toast that latches through null snapshot republishes

**Files:**
- Create: `lib/game/ui/command_toast.dart`
- Create: `test/widget/command_toast_test.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Produces: `CommandToast({required String? feedback, Duration visibleDuration = const Duration(milliseconds: 2400)})`.
- Consumes: optional snapshot feedback only; owns latched text, last input, visibility, and timer locally.
- Parent keeps the widget at one stable key above the dock.

- [ ] **Step 1: Write the complete lifecycle tests first**

Create `test/widget/command_toast_test.dart` with a stable-key host that can be rebuilt with any input, including an uninterrupted duplicate:

```dart
Widget toastHost(String? feedback, {int revision = 0}) {
  return MaterialApp(
    home: Semantics(
      label: 'toast-host-$revision',
      child: CommandToast(
        key: const ValueKey('test-command-toast'),
        feedback: feedback,
      ),
    ),
  );
}

testWidgets('toast stays latched through null and exits only on its timer',
    (tester) async {
  await tester.pumpWidget(toastHost('Not enough gold.'));

  expect(find.text('Not enough gold.'), findsOneWidget);
  await tester.pumpWidget(toastHost(null, revision: 1));
  expect(find.text('Not enough gold.'), findsOneWidget);

  await tester.pump(const Duration(milliseconds: 2399));
  expect(find.text('Not enough gold.'), findsOneWidget);
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 140));
  expect(find.text('Not enough gold.'), findsNothing);
});

testWidgets('null rearms the same text and different text restarts the timer',
    (tester) async {
  await tester.pumpWidget(toastHost('First'));
  await tester.pump(const Duration(seconds: 1));

  await tester.pumpWidget(toastHost('Second', revision: 1));
  await tester.pump(const Duration(milliseconds: 1500));
  expect(find.text('Second'), findsOneWidget);

  await tester.pumpWidget(toastHost(null, revision: 2));
  await tester.pumpWidget(toastHost('Second', revision: 3));
  await tester.pump(const Duration(milliseconds: 2399));
  expect(find.text('Second'), findsOneWidget);
});

testWidgets('uninterrupted duplicate input does not restart the timer',
    (tester) async {
  await tester.pumpWidget(toastHost('Hold'));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(toastHost('Hold', revision: 1));
  await tester.pump(const Duration(milliseconds: 1399));
  expect(find.text('Hold'), findsOneWidget);
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 140));
  expect(find.text('Hold'), findsNothing);
});
```

Also cover a different message replaces copy, disposal with an active timer throws no post-dispose setState, warning/error/neutral tones, maximum two lines, and reduced-motion transition duration zero.

- [ ] **Step 2: Run tests to verify RED**

```bash
rtk flutter test test/widget/command_toast_test.dart
```

Expected: compile failure because `CommandToast` does not exist.

- [ ] **Step 3: Implement separate input/latch/timer state**

Create `lib/game/ui/command_toast.dart`:

```dart
class _CommandToastState extends State<CommandToast> {
  Timer? _timer;
  String? _lastInput;
  String? _latchedMessage;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _accept(widget.feedback, notify: false);
  }

  @override
  void didUpdateWidget(covariant CommandToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    _accept(widget.feedback, notify: true);
  }

  void _accept(String? input, {required bool notify}) {
    if (input == null) {
      _lastInput = null;
      return;
    }
    if (_lastInput == input) return;

    void updateState() {
      _lastInput = input;
      _latchedMessage = input;
      _visible = true;
    }

    if (notify) {
      setState(updateState);
    } else {
      updateState();
    }
    _timer?.cancel();
    _timer = Timer(widget.visibleDuration, () {
      if (!mounted) return;
      setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
```

Render the latched string through `AnimatedSwitcher`, `IgnorePointer`, and `CommandFrame`, with a stable `command-toast` key. Use `duration: orionMotionDuration(context, const Duration(milliseconds: 160))` and `reverseDuration: orionMotionDuration(context, const Duration(milliseconds: 140))`; the tests deliberately pump the 140 ms exit interval after the 2.4-second visibility timer.

Tone mapping is presentation-only:

- danger: lowercase copy contains `failed` or starts with `could not`;
- warning: contains `not enough`, `locked`, or `cannot`;
- neutral: all other feedback.

- [ ] **Step 4: Integrate the toast above the dynamic dock**

Replace the standalone bottom `Positioned` with one stable column:

```dart
Positioned(
  left: 12,
  right: 12,
  bottom: 12,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      CommandToast(
        key: const ValueKey('mission-command-toast'),
        feedback: snapshot.feedback,
      ),
      const SizedBox(height: 8),
      MissionCommandDock(
        snapshot: snapshot,
        onWorldMap: game.returnToMap,
        onStartWave: game.startWave,
        onPlaceTower: game.placeTower,
        onUpgrade: game.upgradeSelectedTower,
        onSpecialize: game.specializeSelectedTower,
        onTargetingChanged: game.setTargetingMode,
        onSell: game.sellSelectedTower,
      ),
    ],
  ),
),
```

Keep module draft and mission report after this position in the stack so they remain modal. Remove persistent mission feedback copy from the status HUD.

- [ ] **Step 5: Add page-level null-republish regression and commit**

In `test/widget_test.dart`, publish a known feedback message, then trigger a null publication (for example a pacing change or countdown tick) and assert the toast remains until 2.4 seconds. Re-publish the same feedback after a null and assert it appears again.

```bash
rtk dart format lib/game/ui/command_toast.dart lib/game/ui/orion_game_page.dart test/widget/command_toast_test.dart test/widget_test.dart
rtk flutter test test/widget/command_toast_test.dart test/widget_test.dart
rtk git add lib/game/ui/command_toast.dart lib/game/ui/orion_game_page.dart test/widget/command_toast_test.dart test/widget_test.dart
rtk git commit -m "feat: add latched Orion mission feedback"
```

Expected: toast lifecycle and page integration tests pass; no snapshot field is added.

---

## Task 6: Integrate acquired modules, module draft, and mission report

**Files:**
- Modify: `lib/game/ui/run_module_draft_panel.dart`
- Modify: `lib/game/ui/mission_report_panel.dart`
- Modify: `test/widget/run_module_draft_panel_test.dart`
- Modify: `test/widget/mission_report_panel_test.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: PR 1 `OrionUiTheme` and `CommandFrame`.
- Preserves: every public constructor, offer/result/save/reward copy, enabled/disabled state, and callback.
- Produces: command-deck visual surfaces that remain `Positioned.fill` modals in `OrionGamePage`.

- [ ] **Step 1: Add frame/token assertions to existing tests**

In `run_module_draft_panel_test.dart`, keep all selection tests and add:

```dart
expect(
  find.byKey(const ValueKey('run-module-draft-frame')),
  findsOneWidget,
);
expect(find.byType(CommandFrame), findsWidgets);
```

In `mission_report_panel_test.dart`, keep every save/action test and add:

```dart
expect(
  find.byKey(const ValueKey('mission-report-frame')),
  findsOneWidget,
);
expect(find.byType(CommandFrame), findsWidgets);
```

Add an `AcquiredRunModuleStrip` case that confirms it uses the command-deck frame, retains full title/effect semantics, and has no tap callback. In `widget_test.dart`, retain the layer assertion that module draft/report content blocks the dock below.

- [ ] **Step 2: Run affected tests to verify RED**

```bash
rtk flutter test test/widget/run_module_draft_panel_test.dart test/widget/mission_report_panel_test.dart test/widget_test.dart
```

Expected: new frame/key assertions fail against the Material-only surfaces.

- [ ] **Step 3: Restyle acquired and draft surfaces without changing content**

In `run_module_draft_panel.dart`:

- keep the full-screen scrim and `SafeArea > SingleChildScrollView`;
- use `OrionUiTheme.voidBlack` for the scrim treatment;
- wrap the offer body in `CommandFrame(key: ValueKey('run-module-draft-frame'))`;
- replace each generic tonal card surface with a pressable `CommandFrame`, preserving title, effect text, affinity, and `onSelected(id)` exactly;
- render each acquired module through a compact `CommandFrame` and preserve title/effect semantics;
- do not add reroll, dismiss, animation, or new module state.

- [ ] **Step 4: Restyle mission report without changing projection/action logic**

In `mission_report_panel.dart`:

- keep full-screen scrim, `SafeArea`, scrolling, save-state rendering, rewards, acquired modules, and action list;
- wrap `_ReportBody` in `CommandFrame(key: ValueKey('mission-report-frame'))`;
- use Gold/cyan/red tokens for win/save/failure states while retaining visible text;
- restyle existing action buttons with command-deck frames/reactor emphasis, but preserve labels, tooltips, disabled states, and callbacks exactly.

- [ ] **Step 5: Run tests and commit**

```bash
rtk dart format lib/game/ui/run_module_draft_panel.dart lib/game/ui/mission_report_panel.dart test/widget/run_module_draft_panel_test.dart test/widget/mission_report_panel_test.dart test/widget_test.dart
rtk flutter test test/widget/run_module_draft_panel_test.dart test/widget/mission_report_panel_test.dart test/widget_test.dart
rtk git add lib/game/ui/run_module_draft_panel.dart lib/game/ui/mission_report_panel.dart test/widget/run_module_draft_panel_test.dart test/widget/mission_report_panel_test.dart test/widget_test.dart
rtk git commit -m "feat: integrate Orion mission modal surfaces"
```

Expected: all existing modal behavior plus new frame/token/layer assertions pass.

---

## Task 7: PR 2 verification and portrait visual gate

**Files:**
- Verify only; fix failures in the owning task's files/tests.

**Interfaces:**
- Produces: a complete, reviewable mission-HUD PR on top of PR 1.
- Preserves the presentation-only boundary and two-PR review history.

- [ ] **Step 1: Verify the diff boundary**

```bash
rtk git diff --name-only origin/main...HEAD
```

Expected: PR 1 plus PR 2 UI/docs/tests only. No game models, rules, orchestrator behavior, Flame components, campaign files, assets, or dependency files.

- [ ] **Step 2: Run strict format and every new focused suite**

```bash
rtk dart format --output=none --set-exit-if-changed lib test
rtk flutter test test/widget/mission_command_hud_test.dart test/widget/next_wave_scanner_test.dart test/widget/mission_command_dock_test.dart test/widget/tower_stat_scale_test.dart test/widget/tower_inspector_test.dart test/widget/command_toast_test.dart test/widget/run_module_draft_panel_test.dart test/widget/mission_report_panel_test.dart test/widget/sell_button_test.dart test/widget_test.dart
```

Expected: formatter and all focused tests pass.

- [ ] **Step 3: Run analyzer and full suite**

```bash
rtk flutter analyze
rtk flutter test
```

Expected: no analyzer issues and the complete suite passes.

- [ ] **Step 4: Perform the three-size local visual check**

At 375 × 812, 390 × 844, and 430 × 932, capture these states to `/tmp/orion-command-deck-pr2/`:

1. idle build HUD with expanded scanner;
2. collapsed scanner;
3. selected-cell build rail showing locked and unaffordable cards;
4. selected level-1 tower;
5. selected level-2 tower with two specializations;
6. active wave HUD/pacing;
7. latched feedback after a null republish;
8. acquired-module strip;
9. run-module draft;
10. victory and loss mission reports.

At every size verify:

- board remains visually dominant and numeric HUD stays readable;
- status/acquired areas remain pass-through and controls consume only visible bounds;
- no scanner/pacing overlap;
- all tower art/cost/lock states are legible and horizontally scrollable;
- inspector stays within its cap and all consequential actions remain reachable;
- toast sits above every dock state and survives null publication;
- modal surfaces fully obscure/block the underlying dock;
- 1.3 text scale does not clip actions and reduced motion changes state immediately.

- [ ] **Step 5: Commit only visual-gate fixes, if any**

```bash
rtk git add lib/game/ui/mission_command_hud.dart lib/game/ui/next_wave_scanner.dart lib/game/ui/mission_command_dock.dart lib/game/ui/tower_stat_scale.dart lib/game/ui/tower_inspector.dart lib/game/ui/command_toast.dart lib/game/ui/run_module_draft_panel.dart lib/game/ui/mission_report_panel.dart lib/game/ui/orion_game_page.dart test/widget/mission_command_hud_test.dart test/widget/next_wave_scanner_test.dart test/widget/mission_command_dock_test.dart test/widget/tower_stat_scale_test.dart test/widget/tower_inspector_test.dart test/widget/command_toast_test.dart test/widget/run_module_draft_panel_test.dart test/widget/mission_report_panel_test.dart test/widget/sell_button_test.dart test/widget/support/command_deck_fixtures.dart test/widget_test.dart
rtk git commit -m "fix: close command deck mission visual review"
```

Skip this commit if the visual gate required no source/test changes. PR 2 is ready for review only after Steps 1–4 are green.
