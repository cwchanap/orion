# Orion Command Deck World Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver PR 1 of the Orion Command Deck redesign: shared local UI primitives plus an illustrated, compact, blueprint-safe campaign map and mission briefing.

**Architecture:** Keep campaign state and callbacks unchanged. Add a narrow `OrionUiTheme`, reusable chamfered frame/reactor control, and an atlas widget whose factories delegate crop math to the existing tested sheet loaders. `WorldMapView` remains the campaign projection, while a pure presentation layout helper turns authored map coordinates/dependencies into testable node rectangles and route records.

**Tech Stack:** Dart `^3.12.0`, Flutter, Flame `^1.38.0`, Material 3, `flutter_test`; existing bundled PNG assets only; no new packages.

**Spec:** `docs/superpowers/specs/2026-08-20-orion-ui-hud-redesign-design.md`

## Global Constraints

- This is PR 1 only: shared theme/art primitives, world map, briefing, and reset confirmation.
- Do not change `GameSession`, `GameSnapshot`, `CampaignProgress`, `StageDefinition`, persistence, medals, rewards, blueprint ownership, waves, balance, or combat.
- Use only assets already declared in `pubspec.yaml`; no hosted assets, runtime downloads, new fonts, or icon package.
- Existing sheet `sourceRectFor` helpers own all row/column translation.
- `WorldMapView` keeps its current constructor, callbacks, busy flags, and sticky campaign-feedback contract.
- Five 56 dp main-path hit targets must remain distinct beside a 52 dp rail at 375 × 812.
- Outpost Alpha keeps locked/recovered blueprint state in node semantics and the existing committed briefing line.
- Codex, Tech Tree, and feedback settings stay on their current `ColorScheme`.
- Minimum interactive target is 48 × 48 dp.
- Reduced motion follows `MediaQuery.disableAnimations`.
- No golden-test harness. Use behavioral widget tests plus local screenshot QA at 375 × 812, 390 × 844, and 430 × 932.
- Run strict format, focused tests, `flutter analyze`, and full `flutter test` before the PR review gate.

## Risks

- **Crop drift:** factories must call the loader helpers; no duplicated sheet dimensions in individual widgets.
- **Compact overlap:** geometry is extracted and tested independently before `WorldMapView` is rewritten.
- **Blueprint regression:** node semantics, briefing copy, and reset behavior stay under existing and new widget tests.
- **Copy churn:** update `Orion Sector Map` and `Start Mission` finders in the same task that changes their visible copy.
- **Standalone test themes:** `OrionUiTheme.of(context)` must fall back safely under bare `MaterialApp` tests.

## File Map

### Create

- `lib/game/ui/orion_ui_theme.dart` — command-deck theme extension and reduced-motion duration helper.
- `lib/game/ui/command_frame.dart` — chamfered hull frame and reactor action.
- `lib/game/ui/orion_atlas_sprite.dart` — source-rect-backed local art descriptors, factories, cached painter, and icon fallback.
- `lib/game/ui/sector_map_layout.dart` — pure node geometry and dependency-route projection.
- `test/widget/orion_ui_theme_test.dart` — fallback/extension/frame/tap-bound coverage.
- `test/widget/orion_atlas_sprite_test.dart` — exhaustive tower/boss/preview/trait crop mapping and failure fallback.
- `test/widget/sector_map_layout_test.dart` — compact geometry and route coverage.
- `test/widget/world_map_command_deck_test.dart` — redesigned map states, semantics, callbacks, and busy behavior.

### Modify

- `lib/main.dart` — register `OrionUiTheme.dark` on the existing dark `ThemeData`.
- `lib/game/ui/world_map_view.dart` — illustrated sector stack, routes, nodes, utility rail, blueprint glyph, and sticky feedback.
- `lib/game/ui/orion_game_page.dart` — art-led briefing, launch copy, and command-deck reset dialog.
- `test/widget_test.dart` — briefing/reset/blueprint integration and intentional copy updates.
- `test/widget/codex_view_test.dart` — update only world-map title expectations exercised by the Codex integration.

### No intended changes

- `lib/game/models/game_models.dart`
- `lib/game/rules/game_session.dart`
- `lib/game/orion_defense_game.dart`
- `lib/game/campaign/*`
- `lib/game/ui/codex_view.dart`
- `lib/game/ui/tech_tree_view.dart`
- any PNG or `pubspec.yaml`

---

## Task 1: Add the command-deck theme, frame, and reactor action

**Files:**
- Create: `lib/game/ui/orion_ui_theme.dart`
- Create: `lib/game/ui/command_frame.dart`
- Create: `test/widget/orion_ui_theme_test.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Produces: `OrionUiTheme.dark`, `OrionUiTheme.of(BuildContext)`, and `orionMotionDuration(BuildContext, Duration)`.
- Produces: `CommandFrame` and `ReactorButton` for both implementation plans.
- Consumes: existing Flutter `ThemeData` and `MediaQuery.disableAnimations` only.

- [ ] **Step 1: Write failing theme and component tests**

Create `test/widget/orion_ui_theme_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/command_frame.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

void main() {
  testWidgets('theme lookup falls back under a bare MaterialApp', (tester) async {
    late OrionUiTheme resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            resolved = OrionUiTheme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(resolved, OrionUiTheme.dark);
    expect(resolved.systemCyan, const Color(0xFF46E6FF));
    expect(resolved.creditGold, const Color(0xFFFFC857));
  });

  testWidgets('registered extension wins over the fallback', (tester) async {
    final custom = OrionUiTheme.dark.copyWith(systemCyan: Colors.pink);
    late OrionUiTheme resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [custom]),
        home: Builder(
          builder: (context) {
            resolved = OrionUiTheme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(resolved.systemCyan, Colors.pink);
  });

  testWidgets('reactor action is at least 48dp and invokes once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ReactorButton(
            tooltip: 'Launch Mission',
            label: 'Launch',
            icon: Icons.rocket_launch,
            onPressed: () => taps += 1,
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byTooltip('Launch Mission'));
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));
    await tester.tap(find.byTooltip('Launch Mission'));
    expect(taps, 1);
  });

  testWidgets('reduced motion returns zero duration', (tester) async {
    late Duration resolved;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              resolved = orionMotionDuration(
                context,
                const Duration(milliseconds: 220),
              );
              return const CommandFrame(child: Text('Hull'));
            },
          ),
        ),
      ),
    );

    expect(resolved, Duration.zero);
    expect(find.text('Hull'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the focused test to verify RED**

```bash
rtk flutter test test/widget/orion_ui_theme_test.dart
```

Expected: compile failure because the theme/frame files and types do not exist.

- [ ] **Step 3: Implement the exact theme contract**

Create `lib/game/ui/orion_ui_theme.dart` with these fields and values:

```dart
import 'package:flutter/material.dart';

@immutable
final class OrionUiTheme extends ThemeExtension<OrionUiTheme> {
  const OrionUiTheme({
    required this.voidBlack,
    required this.hullBlack,
    required this.panelBlue,
    required this.panelRaised,
    required this.frameSteel,
    required this.textPrimary,
    required this.textMuted,
    required this.systemCyan,
    required this.systemCyanStrong,
    required this.creditGold,
    required this.systemViolet,
    required this.naniteGreen,
    required this.warningOrange,
    required this.dangerRed,
  });

  static const dark = OrionUiTheme(
    voidBlack: Color(0xFF05080D),
    hullBlack: Color(0xFF0B1118),
    panelBlue: Color(0xFF111B25),
    panelRaised: Color(0xFF182532),
    frameSteel: Color(0xFF2E4658),
    textPrimary: Color(0xFFF4F8FB),
    textMuted: Color(0xFF8EA4B5),
    systemCyan: Color(0xFF46E6FF),
    systemCyanStrong: Color(0xFF13B8E6),
    creditGold: Color(0xFFFFC857),
    systemViolet: Color(0xFFA98BFF),
    naniteGreen: Color(0xFF7BE495),
    warningOrange: Color(0xFFFF8A3D),
    dangerRed: Color(0xFFFF5D6C),
  );

  final Color voidBlack;
  final Color hullBlack;
  final Color panelBlue;
  final Color panelRaised;
  final Color frameSteel;
  final Color textPrimary;
  final Color textMuted;
  final Color systemCyan;
  final Color systemCyanStrong;
  final Color creditGold;
  final Color systemViolet;
  final Color naniteGreen;
  final Color warningOrange;
  final Color dangerRed;

  static OrionUiTheme of(BuildContext context) =>
      Theme.of(context).extension<OrionUiTheme>() ?? dark;

  @override
  OrionUiTheme copyWith({
    Color? voidBlack,
    Color? hullBlack,
    Color? panelBlue,
    Color? panelRaised,
    Color? frameSteel,
    Color? textPrimary,
    Color? textMuted,
    Color? systemCyan,
    Color? systemCyanStrong,
    Color? creditGold,
    Color? systemViolet,
    Color? naniteGreen,
    Color? warningOrange,
    Color? dangerRed,
  }) {
    return OrionUiTheme(
      voidBlack: voidBlack ?? this.voidBlack,
      hullBlack: hullBlack ?? this.hullBlack,
      panelBlue: panelBlue ?? this.panelBlue,
      panelRaised: panelRaised ?? this.panelRaised,
      frameSteel: frameSteel ?? this.frameSteel,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      systemCyan: systemCyan ?? this.systemCyan,
      systemCyanStrong: systemCyanStrong ?? this.systemCyanStrong,
      creditGold: creditGold ?? this.creditGold,
      systemViolet: systemViolet ?? this.systemViolet,
      naniteGreen: naniteGreen ?? this.naniteGreen,
      warningOrange: warningOrange ?? this.warningOrange,
      dangerRed: dangerRed ?? this.dangerRed,
    );
  }

  @override
  OrionUiTheme lerp(covariant OrionUiTheme? other, double t) {
    if (other == null) return this;
    return OrionUiTheme(
      voidBlack: Color.lerp(voidBlack, other.voidBlack, t)!,
      hullBlack: Color.lerp(hullBlack, other.hullBlack, t)!,
      panelBlue: Color.lerp(panelBlue, other.panelBlue, t)!,
      panelRaised: Color.lerp(panelRaised, other.panelRaised, t)!,
      frameSteel: Color.lerp(frameSteel, other.frameSteel, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      systemCyan: Color.lerp(systemCyan, other.systemCyan, t)!,
      systemCyanStrong:
          Color.lerp(systemCyanStrong, other.systemCyanStrong, t)!,
      creditGold: Color.lerp(creditGold, other.creditGold, t)!,
      systemViolet: Color.lerp(systemViolet, other.systemViolet, t)!,
      naniteGreen: Color.lerp(naniteGreen, other.naniteGreen, t)!,
      warningOrange: Color.lerp(warningOrange, other.warningOrange, t)!,
      dangerRed: Color.lerp(dangerRed, other.dangerRed, t)!,
    );
  }
}

Duration orionMotionDuration(BuildContext context, Duration normal) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;
```

- [ ] **Step 4: Implement the shared chamfered frame and reactor action**

Create `lib/game/ui/command_frame.dart`. Use one path function for clip and border:

```dart
Path commandFramePath(Size size, double chamfer) => Path()
  ..moveTo(chamfer, 0)
  ..lineTo(size.width - chamfer, 0)
  ..lineTo(size.width, chamfer)
  ..lineTo(size.width, size.height - chamfer)
  ..lineTo(size.width - chamfer, size.height)
  ..lineTo(chamfer, size.height)
  ..lineTo(0, size.height - chamfer)
  ..lineTo(0, chamfer)
  ..close();
```

`CommandFrame` must accept `child`, `padding`, optional `color`, optional `borderColor`, `emphasized`, and `chamfer`. Paint a solid hull fill plus 1 dp border; do not add blur. `ReactorButton` must accept `tooltip`, `label`, `icon`, `onPressed`, and optional `size` defaulting to 68. Build it from `Tooltip > Semantics(button: true) > SizedBox.square > Material > InkResponse` with two concentric borders and visible label.

- [ ] **Step 5: Register the extension without changing the existing color scheme**

Modify `lib/main.dart`:

```dart
theme: ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF31E6A1),
    brightness: Brightness.dark,
  ),
  extensions: const [OrionUiTheme.dark],
  useMaterial3: true,
),
```

Add the `orion_ui_theme.dart` import. Do not change the current seed or other screens.

- [ ] **Step 6: Run focused tests and commit**

```bash
rtk dart format lib/main.dart lib/game/ui/orion_ui_theme.dart lib/game/ui/command_frame.dart test/widget/orion_ui_theme_test.dart
rtk flutter test test/widget/orion_ui_theme_test.dart
rtk git add lib/main.dart lib/game/ui/orion_ui_theme.dart lib/game/ui/command_frame.dart test/widget/orion_ui_theme_test.dart
rtk git commit -m "feat: add Orion command deck UI primitives"
```

Expected: focused test passes and the commit contains no campaign/gameplay changes.

---

## Task 2: Add loader-owned atlas descriptors and local art rendering

**Files:**
- Create: `lib/game/ui/orion_atlas_sprite.dart`
- Create: `test/widget/orion_atlas_sprite_test.dart`

**Interfaces:**
- Produces: `OrionArtDescriptor`, `OrionArt.tower`, `OrionArt.boss`, `OrionArt.stage`, `OrionArt.previewGroup`, `OrionArt.trait`, and `OrionAtlasSprite`.
- Consumes: `GameSpriteSheet.sourceRectFor`, `GameTowerVarietySheet.sourceRectFor`, `GameBossSheet.sourceRectFor`, their existing enum factories, and Flutter `AssetImage` caching.
- Produces the art API consumed by both PR 1 and PR 2; no caller performs sheet arithmetic.

- [ ] **Step 1: Write exhaustive descriptor tests first**

Create `test/widget/orion_atlas_sprite_test.dart` with these core assertions:

```dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_boss_sheet.dart';
import 'package:orion/game/assets/game_sprite_sheet.dart';
import 'package:orion/game/assets/game_tower_variety_sheet.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';

void main() {
  test('every tower resolves through an existing loader helper', () {
    for (final type in TowerType.values) {
      final art = OrionArt.tower(type);
      final rect = art.sourceRectFor(imageWidth: 400, imageHeight: 400);
      expect(rect.width, greaterThan(0), reason: type.name);
      expect(rect.height, greaterThan(0), reason: type.name);
    }

    expect(
      OrionArt.tower(TowerType.cryo).sourceRectFor(
        imageWidth: 400,
        imageHeight: 300,
      ),
      GameSpriteSheet.sourceRectFor(
        GameSprite.cryoTower,
        imageWidth: 400,
        imageHeight: 300,
      ),
    );
    expect(
      OrionArt.tower(TowerType.droneBay).sourceRectFor(
        imageWidth: 400,
        imageHeight: 400,
      ),
      GameTowerVarietySheet.sourceRectFor(
        GameTowerVarietySprite.droneBayTower,
        imageWidth: 400,
        imageHeight: 400,
      ),
    );
  });

  test('every campaign stage resolves to its authored final boss sprite', () {
    for (final stage in OrionCampaign.stages) {
      final boss = stage.waves.last.groups.last.enemyStats as BossDefinition;
      final art = OrionArt.stage(stage);
      expect(
        art.sourceRectFor(imageWidth: 400, imageHeight: 200),
        GameBossSheet.sourceRectFor(
          boss.sprite,
          imageWidth: 400,
          imageHeight: 200,
        ),
        reason: stage.id,
      );
    }
  });

  test('preview uses exact boss name before heavy/basic fallback', () {
    for (final boss in GameBalance.bosses) {
      final group = WavePreviewGroup(
        enemyCount: 1,
        label: boss.name,
        traits: boss.traits,
      );
      expect(
        OrionArt.previewGroup(group).sourceRectFor(
          imageWidth: 400,
          imageHeight: 200,
        ),
        GameBossSheet.sourceRectFor(
          boss.sprite,
          imageWidth: 400,
          imageHeight: 200,
        ),
        reason: boss.name,
      );
    }

    final queen = WavePreviewGroup(
      enemyCount: 1,
      label: 'Swarm Queen',
      traits: {EnemyTrait.swarm, EnemyTrait.regen},
    );
    final heavy = WavePreviewGroup(
      enemyCount: 4,
      label: 'Heavy Drones',
      traits: {EnemyTrait.heavy},
    );
    final basic = WavePreviewGroup(
      enemyCount: 8,
      label: 'Drones',
      traits: const {},
    );

    expect(OrionArt.previewGroup(queen).assetPath, GameBossSheet.assetPath);
    expect(
      OrionArt.previewGroup(queen).sourceRectFor(
        imageWidth: 400,
        imageHeight: 200,
      ),
      GameBossSheet.sourceRectFor(
        BossSprite.swarmQueen,
        imageWidth: 400,
        imageHeight: 200,
      ),
    );
    expect(OrionArt.previewGroup(heavy).debugName, 'heavy-drone');
    expect(OrionArt.previewGroup(basic).debugName, 'basic-drone');
  });

  test('trait art reuses indicator cells and shape fallbacks', () {
    expect(OrionArt.trait(EnemyTrait.armored), isNotNull);
    expect(OrionArt.trait(EnemyTrait.shielded), isNotNull);
    expect(OrionArt.trait(EnemyTrait.regen), isNotNull);
    expect(OrionArt.trait(EnemyTrait.swarm), isNull);
    expect(OrionArt.trait(EnemyTrait.heavy), isNull);
  });
}
```

Add a widget test that pumps an `OrionAtlasSprite` with an intentionally missing `assetPath`, supplies `fallbackIcon: Icons.broken_image`, pumps to settle, and expects exactly one broken-image icon rather than an empty box.

- [ ] **Step 2: Verify the tests are RED**

```bash
rtk flutter test test/widget/orion_atlas_sprite_test.dart
```

Expected: compile failure because the descriptor/factory/widget do not exist.

- [ ] **Step 3: Implement descriptors that delegate crop math**

Create `lib/game/ui/orion_atlas_sprite.dart` with this public contract:

```dart
typedef OrionSourceRectResolver = ui.Rect Function({
  required double imageWidth,
  required double imageHeight,
});

@immutable
final class OrionArtDescriptor {
  const OrionArtDescriptor({
    required this.assetPath,
    required this.sourceRectFor,
    required this.semanticLabel,
    required this.debugName,
    required this.fallbackIcon,
  });

  final String assetPath;
  final OrionSourceRectResolver sourceRectFor;
  final String semanticLabel;
  final String debugName;
  final IconData fallbackIcon;
}
```

Implement `OrionArt.tower` as an exhaustive `TowerType` switch through the existing `hasTowerSprite`/`spriteForTower` helpers. Implement `boss` through `GameBossSheet.sourceRectFor`. Implement `stage` by validating `stage.waves.last.groups.last.enemyStats is BossDefinition` and delegating to `boss`.

Implement preview selection exactly:

```dart
static OrionArtDescriptor previewGroup(WavePreviewGroup group) {
  for (final boss in GameBalance.bosses) {
    if (boss.name == group.label) return OrionArt.boss(boss.sprite);
  }
  return group.traits.contains(EnemyTrait.heavy)
      ? _gameSprite(GameSprite.heavyDroneEnemy, 'heavy-drone', group.label)
      : _gameSprite(GameSprite.basicDroneEnemy, 'basic-drone', group.label);
}
```

Implement the trait mapping as one exhaustive switch. Armor/shield/regen return variety-sheet descriptors; swarm/heavy return `null` for the shape fallback.

- [ ] **Step 4: Implement cached image resolution and source-rect painting**

`OrionAtlasSprite` is a stateful widget that resolves `AssetImage(widget.art.assetPath)`, listens to its `ImageStream`, and stores one `ImageInfo`. On success, a `CustomPainter` calls:

```dart
final source = art.sourceRectFor(
  imageWidth: image.image.width.toDouble(),
  imageHeight: image.image.height.toDouble(),
);
canvas.drawImageRect(image.image, source, destination, paint);
```

On the image-stream `onError`, render `Icon(widget.art.fallbackIcon, semanticLabel: widget.art.semanticLabel)`. Remove the old listener on `didUpdateWidget` and `dispose`. Wrap the result in `Semantics(image: true, label: widget.art.semanticLabel)` and `ExcludeSemantics` around the fallback icon so the label is announced once.

- [ ] **Step 5: Run focused tests and commit**

```bash
rtk dart format lib/game/ui/orion_atlas_sprite.dart test/widget/orion_atlas_sprite_test.dart
rtk flutter test test/widget/orion_atlas_sprite_test.dart
rtk git add lib/game/ui/orion_atlas_sprite.dart test/widget/orion_atlas_sprite_test.dart
rtk git commit -m "feat: render Orion atlas art in Flutter UI"
```

Expected: all enum/mapping/fallback tests pass without changing the Flame loaders.

---

## Task 3: Extract compact sector geometry and redesign the world map

**Files:**
- Create: `lib/game/ui/sector_map_layout.dart`
- Create: `test/widget/sector_map_layout_test.dart`
- Create: `test/widget/world_map_command_deck_test.dart`
- Modify: `lib/game/ui/world_map_view.dart`

**Interfaces:**
- Consumes: `OrionUiTheme`, `CommandFrame`, `OrionAtlasSprite`, existing stages/progress/callbacks.
- Produces: `SectorMapLayout.nodeRect`, `SectorMapLayout.routes`, and `SectorRoute` for deterministic rendering/tests.
- Preserves: the public `WorldMapView` constructor and sticky `feedback` rendering.

- [ ] **Step 1: Write pure compact-layout and route tests**

Create `test/widget/sector_map_layout_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/ui/sector_map_layout.dart';

void main() {
  test('five main-path hit rectangles are distinct at 375x812', () {
    const size = Size(375, 812);
    final rects = {
      for (final stage in OrionCampaign.mainStages)
        stage.id: SectorMapLayout.nodeRect(stage, size),
    };

    expect(rects.values, hasLength(5));
    for (final rect in rects.values) {
      expect(rect.size, const Size(56, 80));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
      expect(rect.right, lessThanOrEqualTo(375 - 52 - 12));
    }
    final ordered = OrionCampaign.mainStages
        .map((stage) => rects[stage.id]!)
        .toList(growable: false);
    for (var index = 1; index < ordered.length; index += 1) {
      expect(ordered[index - 1].overlaps(ordered[index]), isFalse);
    }
  });

  test('routes are derived from unlock dependencies', () {
    final routes = SectorMapLayout.routes(
      OrionCampaign.stages,
      CampaignProgress(),
    );

    expect(routes, hasLength(6));
    expect(
      routes.map((route) => (route.from.id, route.to.id)).toSet(),
      containsAll({
        ('outpost-alpha', 'nebula-relay'),
        ('nebula-relay', 'salvage-rift'),
        ('nebula-relay', 'asteroid-foundry'),
        ('asteroid-foundry', 'aurora-gate'),
        ('aurora-gate', 'void-bastion'),
        ('aurora-gate', 'singularity-core'),
      }),
    );
    expect(
      routes.where((route) => route.isOptional).map((route) => route.to.id),
      {'salvage-rift', 'void-bastion'},
    );
  });
}
```

- [ ] **Step 2: Write world-map widget tests before changing the view**

Create `test/widget/world_map_command_deck_test.dart` with a local `MaterialApp` harness for `WorldMapView`. Cover:

```dart
CampaignProgress clearedCampaignProgress() => CampaignProgress(
  bestResultsByStageId: {
    for (final stage in OrionCampaign.stages)
      stage.id: const StageResult(
        medal: StageMedal.gold,
        bestBaseHealth: 20,
      ),
  },
);

Widget buildMap({
  required CampaignProgress progress,
  ValueChanged<StageDefinition>? onStageSelected,
  ValueChanged<StageDefinition>? onLockedStageSelected,
  String? feedback,
  bool isSavingProgress = false,
  bool isResetting = false,
  bool isSavingFeedback = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: WorldMapView(
        stages: OrionCampaign.stages,
        progress: progress,
        feedback: feedback,
        isSavingProgress: isSavingProgress,
        isResetting: isResetting,
        isSavingFeedback: isSavingFeedback,
        onStageSelected: onStageSelected ?? (_) {},
        onLockedStageSelected: onLockedStageSelected,
        onResetCampaign: () {},
        onOpenTechTree: () {},
        onOpenCodex: () {},
        onOpenSettings: () {},
      ),
    ),
  );
}
```

```dart
testWidgets('compact map exposes seven art-led stage targets without overlap',
    (tester) async {
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final selected = <String>[];

  await tester.pumpWidget(buildMap(
    progress: clearedCampaignProgress(),
    onStageSelected: (stage) => selected.add(stage.id),
  ));

  expect(find.text('ORION SECTOR'), findsOneWidget);
  for (final stage in OrionCampaign.stages) {
    final finder = find.byKey(ValueKey('sector-stage-${stage.id}'));
    expect(finder, findsOneWidget);
    expect(tester.getSize(finder), const Size(56, 80));
    await tester.tap(finder);
  }
  expect(selected, OrionCampaign.stages.map((stage) => stage.id).toList());
});
```

Also cover:

- fresh Alpha has semantics containing `Blueprint • Locked`;
- cleared Alpha has semantics containing `Blueprint • Recovered`;
- locked nodes call only `onLockedStageSelected`;
- Clear/Silver/Gold nodes expose distinct medal semantics;
- feedback text stays visible until the harness supplies a different/null value;
- Codex, Tech Tree, Settings, and Reset tooltips invoke the existing callbacks;
- `isSavingProgress || isResetting` disables all stage and utility actions.
- `isSavingFeedback` disables Settings only, preserving the current narrower gate.

- [ ] **Step 3: Verify layout and widget tests are RED**

```bash
rtk flutter test test/widget/sector_map_layout_test.dart test/widget/world_map_command_deck_test.dart
```

Expected: compile failures for the new layout types and failures for the retired map UI.

- [ ] **Step 4: Implement pure layout and route projection**

Create `lib/game/ui/sector_map_layout.dart`:

```dart
final class SectorRoute {
  const SectorRoute({
    required this.from,
    required this.to,
    required this.isOptional,
    required this.isActive,
    required this.medal,
  });

  final StageDefinition from;
  final StageDefinition to;
  final bool isOptional;
  final bool isActive;
  final StageMedal? medal;
}

abstract final class SectorMapLayout {
  static const railWidth = 52.0;
  static const horizontalPadding = 12.0;
  static const nodeSize = Size(56, 80);
  static const plotTop = 76.0;
  static const plotBottomInset = 40.0;

  static Rect nodeRect(StageDefinition stage, Size size) {
    final plotWidth = size.width - (horizontalPadding * 2) - railWidth;
    final xStep = (plotWidth - nodeSize.width) / 4;
    final availableHeight =
        size.height - plotTop - plotBottomInset - nodeSize.height;
    final yStep = availableHeight / 2;
    return Rect.fromLTWH(
      horizontalPadding + (stage.mapColumn * xStep),
      plotTop + (stage.mapRow * yStep),
      nodeSize.width,
      nodeSize.height,
    );
  }

  static List<SectorRoute> routes(
    List<StageDefinition> stages,
    CampaignProgress progress,
  ) {
    final byId = {for (final stage in stages) stage.id: stage};
    return [
      for (final to in stages)
        for (final dependency in to.unlockDependencies)
          SectorRoute(
            from: byId[dependency]!,
            to: to,
            isOptional: !to.isMainPath,
            isActive:
                progress.statusFor(to) != StageProgressStatus.locked,
            medal: progress.resultFor(to.id)?.medal,
          ),
    ];
  }
}
```

- [ ] **Step 5: Replace the Material-card map with the sector stack**

Convert `WorldMapView` to `StatefulWidget` only to precache `GameTerrain.assetPath` and `GameBossSheet.assetPath` once from `didChangeDependencies`. Preserve every constructor parameter and guard the cache warm-up per state instance:

```dart
bool _didPrecacheMapArt = false;

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  if (_didPrecacheMapArt) return;
  _didPrecacheMapArt = true;
  precacheImage(const AssetImage(GameTerrain.assetPath), context);
  precacheImage(const AssetImage(GameBossSheet.assetPath), context);
}
```

Build the `SafeArea > LayoutBuilder > Stack`. At the top of the `LayoutBuilder` callback, derive the two values consumed by the stack:

```dart
final uiTheme = OrionUiTheme.of(context);
final nodeRects = {
  for (final stage in widget.stages)
    stage.id: SectorMapLayout.nodeRect(stage, constraints.biggest),
};
```

Then build the stack in this order:

```dart
Positioned.fill(
  child: Image.asset(GameTerrain.assetPath, fit: BoxFit.cover),
),
Positioned.fill(child: ColoredBox(color: uiTheme.voidBlack.withValues(alpha: .64))),
Positioned.fill(
  child: CustomPaint(
    key: const ValueKey('sector-route-layer'),
    painter: _SectorRoutePainter(
      routes: SectorMapLayout.routes(widget.stages, widget.progress),
      nodeRects: nodeRects,
      uiTheme: uiTheme,
    ),
  ),
),
for (final stage in widget.stages)
  Positioned.fromRect(
    rect: SectorMapLayout.nodeRect(stage, constraints.biggest),
    child: _IllustratedStageNode(
      key: ValueKey('sector-stage-${stage.id}'),
      stage: stage,
      status: widget.progress.statusFor(stage),
      result: widget.progress.resultFor(stage.id),
      blueprintRecovered: widget.progress.isCleared(
        OrionCampaign.stageOneId,
      ),
      isBusy: widget.isSavingProgress || widget.isResetting,
      onStageSelected: widget.onStageSelected,
      onLockedStageSelected: widget.onLockedStageSelected,
    ),
  ),
```

Add the compact `ORION SECTOR` header, challenge/completion badges, 52 dp right utility rail, minimal medal legend, and sticky campaign feedback strip. Use `CommandFrame`; do not alter callback/busy logic.

`_IllustratedStageNode` uses `OrionAtlasSprite(art: OrionArt.stage(stage))`, full semantics, main/optional shape, status ring, medal glyph, reward glyph, and the Alpha-only blueprint glyph. Keep visible node copy to `mapLabel`; put full name/status/reward/blueprint in semantics and tooltips.

- [ ] **Step 6: Run focused tests and commit**

```bash
rtk dart format lib/game/ui/sector_map_layout.dart lib/game/ui/world_map_view.dart test/widget/sector_map_layout_test.dart test/widget/world_map_command_deck_test.dart
rtk flutter test test/widget/sector_map_layout_test.dart test/widget/world_map_command_deck_test.dart
rtk git add lib/game/ui/sector_map_layout.dart lib/game/ui/world_map_view.dart test/widget/sector_map_layout_test.dart test/widget/world_map_command_deck_test.dart
rtk git commit -m "feat: redesign Orion sector map"
```

Expected: seven-node geometry, route, state, blueprint, callback, and busy tests pass at compact width.

---

## Task 4: Redesign the stage briefing and reset confirmation

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`
- Modify: `test/widget/codex_view_test.dart`

**Interfaces:**
- Consumes: `OrionUiTheme`, `CommandFrame`, `ReactorButton`, and `OrionArt.stage` from Tasks 1–2.
- Preserves: `_showStageBriefing`, stage launch/replay result, blueprint state, reset persistence, reduced-motion duration, and all campaign callbacks.
- Changes visible copy only: fresh `Start Mission` becomes `Launch Mission`; map title becomes `ORION SECTOR`.

- [ ] **Step 1: Update/add briefing and reset tests first**

In `test/widget_test.dart`, change fresh-stage expectations from `Start Mission` to `Launch Mission`, then add:

```dart
testWidgets('briefing uses stage art and preserves committed blueprint copy',
    (tester) async {
  final store = await storeWithResults({
    OrionCampaign.stageOneId:
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 5),
  });
  await tester.pumpWidget(testGamePage(progressStore: store));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('sector-stage-outpost-alpha')));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
  expect(find.text('Blueprint recovered: Relay Calibration'), findsOneWidget);
  expect(find.text('Replay Mission'), findsOneWidget);
  expect(find.byType(OrionAtlasSprite), findsWidgets);
});

testWidgets('reset confirmation uses command frame and keeps behavior',
    (tester) async {
  final store = await storeWithResults({
    OrionCampaign.stageOneId:
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 5),
  });
  await tester.pumpWidget(testGamePage(progressStore: store));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Reset Campaign'));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('reset-campaign-dialog')), findsOneWidget);
  expect(find.byType(CommandFrame), findsWidgets);
  await tester.tap(find.text('Reset'));
  await tester.pumpAndSettle();
  expect(find.bySemanticsLabel(contains('Blueprint • Locked')), findsOneWidget);
});
```

Use the file's existing page/store helpers rather than introducing a second integration harness. Update `test/widget/codex_view_test.dart` only where it expects the old map title.

- [ ] **Step 2: Run affected tests to verify RED**

```bash
rtk flutter test test/widget_test.dart test/widget/codex_view_test.dart
```

Expected: new art/frame/copy assertions fail against the current briefing/dialog.

- [ ] **Step 3: Restyle `_StageBriefingSheet` without changing its data contract**

Keep the existing `showModalBottomSheet<bool>` flow, scroll behavior, and reduced-motion animation. Give the sheet `key: const ValueKey('stage-briefing')` and a `CommandFrame` body containing:

- `OrionAtlasSprite(art: OrionArt.stage(stage))` in a 112 dp hero aperture;
- stage name and main/optional badge;
- existing description, modifier metadata, reward, best result, and Alpha blueprint copy;
- `ReactorButton`/visible action text with `Launch Mission` for fresh stages and `Replay Mission` for cleared stages;
- existing close behavior.

Do not synthesize blueprint ownership from sheet state. Continue reading committed campaign progress exactly where the existing sheet does.

- [ ] **Step 4: Replace only the reset dialog presentation**

Inside `_confirmResetCampaign`, keep `showDialog<bool>`, single-flight guard, button results, save queue, generation, and feedback unchanged. Replace the `AlertDialog` body with:

```dart
Dialog(
  backgroundColor: Colors.transparent,
  child: CommandFrame(
    key: const ValueKey('reset-campaign-dialog'),
    borderColor: OrionUiTheme.of(context).dangerRed,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Reset Campaign'),
        const SizedBox(height: 8),
        const Text('Clear all campaign progress?'),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reset'),
            ),
          ],
        ),
      ],
    ),
  ),
)
```

- [ ] **Step 5: Run affected tests and commit**

```bash
rtk dart format lib/game/ui/orion_game_page.dart test/widget_test.dart test/widget/codex_view_test.dart
rtk flutter test test/widget_test.dart test/widget/codex_view_test.dart
rtk git add lib/game/ui/orion_game_page.dart test/widget_test.dart test/widget/codex_view_test.dart
rtk git commit -m "feat: redesign Orion mission briefing"
```

Expected: briefing, blueprint, reset, compact scroll, reduced-motion, and Codex-to-map tests pass.

---

## Task 5: PR 1 verification and portrait visual gate

**Files:**
- Verify only; fix failures in the owning task's files and tests.

**Interfaces:**
- Produces: a reviewable PR 1 with shared UI/art APIs stable for the mission-HUD plan.
- Does not begin mission HUD/dock/toast/modal work.

- [ ] **Step 1: Verify no forbidden files changed**

```bash
rtk git diff --name-only origin/main...HEAD
```

Expected: only PR 1 files from this plan. No rules, models, campaign, Flame component, asset, or pubspec changes.

- [ ] **Step 2: Run strict format and focused suites**

```bash
rtk dart format --output=none --set-exit-if-changed lib test
rtk flutter test test/widget/orion_ui_theme_test.dart test/widget/orion_atlas_sprite_test.dart test/widget/sector_map_layout_test.dart test/widget/world_map_command_deck_test.dart test/widget/codex_view_test.dart test/widget_test.dart
```

Expected: formatter exits 0 and all focused tests pass.

- [ ] **Step 3: Run analyzer and full suite**

```bash
rtk flutter analyze
rtk flutter test
```

Expected: no analyzer issues and the complete test suite passes.

- [ ] **Step 4: Perform the three-size local visual check**

At 375 × 812, 390 × 844, and 430 × 932, capture the world map and an open Outpost Alpha briefing to `/tmp/orion-command-deck-pr1/`. At every size verify:

- all seven art apertures render and every route connects the intended nodes;
- five main nodes and the right rail do not overlap;
- locked/unlocked/medal/optional/reward/blueprint states remain distinguishable without reading paragraph copy;
- sticky feedback remains readable;
- briefing art, modifiers, best result, blueprint line, and launch/replay action remain reachable;
- 1.3 text scale does not clip the primary action;
- reduced motion opens the sheet without movement.

- [ ] **Step 5: Commit only visual-gate fixes, if any**

```bash
rtk git add lib/main.dart lib/game/ui/orion_ui_theme.dart lib/game/ui/command_frame.dart lib/game/ui/orion_atlas_sprite.dart lib/game/ui/sector_map_layout.dart lib/game/ui/world_map_view.dart lib/game/ui/orion_game_page.dart test/widget/orion_ui_theme_test.dart test/widget/orion_atlas_sprite_test.dart test/widget/sector_map_layout_test.dart test/widget/world_map_command_deck_test.dart test/widget/codex_view_test.dart test/widget_test.dart
rtk git commit -m "fix: close command deck map visual review"
```

Skip this commit when the visual gate required no source/test changes. PR 1 is ready for review only after Steps 1–4 are green.
