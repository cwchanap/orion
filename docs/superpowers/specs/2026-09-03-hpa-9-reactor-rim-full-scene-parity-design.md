# HPA-9 Reactor Rim Full-Scene Visual Parity Design

## Decision

Complete the approved Reactor Rim visual language across every product scene in mock artboards **1a–1h** in one HPA-9 implementation pass, building directly on merged HPA-14 / PR #28.

HPA-9 stays scene-local. It does **not** introduce a scene framework, second router, state-management package, graph engine, second token system, global font migration, or new gameplay model. Existing owners remain authoritative:

```text
1a Playable HUD      -> MissionChrome + current mission widgets
1b Stage Briefing    -> extracted StageBriefingSheet, still launched by OrionGamePage
1c Wave Scanner      -> NextWaveScanner + MissionCollapsible
1d Tower Inspector   -> TowerInspector + existing TowerStatScale pipeline
1e Drag to Place     -> TowerBuildRail -> MissionChrome -> OrionGamePage -> OrionDefenseGame -> BoardComponent
1f World Map         -> WorldMapView + SectorMapLayout
1g Tech Tree         -> TechTreeView + CampaignTechTree
1h Mission Report    -> MissionReportPanel + MissionReportContent
```

The mock's 1i System Sheet and 1j Art Requests are reference material, not additional application scenes.

PR #28 is already merged into `main`; HPA-9 targets `main` directly.

## Baseline that must not be rebuilt

PR #28 already supplies:

```text
MissionChrome
MissionSurface
MissionCollapsible
AcquiredRunModuleControl
compact MissionStatusHud
IdleCommandBar / TowerBuildRail / TowerInspector switching
NextWaveScanner
CommandToast
full-size GameWidget inside the mission SafeArea
board-tap forwarding around floating chrome
mock artboards 1a.png ... 1h.png
existing widget fixtures + live captures used as pre-HPA-9 reference
```

HPA-9 extends these seams rather than replacing them.

## Product rule: complete parity without fake product semantics

"Complete visual parity" means every visible region in scenes 1a–1h is accounted for. It does **not** permit inventing data, rules, dependencies, or controls that Orion does not actually have.

Every visible difference ends in exactly one classification:

```text
Exact
Responsive adaptation
Real-only state
Mock-only removed
Intentional deviation
```

No unexplained mismatch is allowed at completion.

Load-bearing examples:

- `CampaignTechUpgrade` is five independent, single-rank purchases. HPA-9 does not add prerequisite semantics merely because 1g resembles a connected graph.
- `MissionReportContent` exposes real outcome information only. HPA-9 does not add score, elapsed time, kills, damage, or R&D analytics merely because 1h shows numeric tiles.
- Orion's board remains the real 8×12 board. HPA-9 does not replace it with per-stage painted board skins.
- visible one-tap `1x / 2x / 3x` speed selection remains even where the static mock is simpler.

## Shared visual language

Reuse `OrionUiTheme` everywhere. `MissionSurface` remains mission-only. Non-mission views use `OrionUiTheme` plus their current Material / `CommandFrame` structure unless actual duplication proves a tiny helper useful during implementation.

Continue the HPA-14 typography choice:

- current Orion sans-serif theme;
- use size, weight, spacing, and hierarchy to approach the mock;
- no Oxanium or other external font dependency;
- font-family difference is an `Intentional deviation`.

## Closed UI-art contract

The previous blanket `assets/` freeze was too strict for complete scene parity. HPA-9 may add **UI-only** art, but the set is closed before scene work begins.

### Approved semantic art roles

| Scene | Art role | Decision |
| --- | --- | --- |
| 1a | board terrain/path | Keep current terrain + path tiles. No per-stage board skin. |
| 1b | stage key art | Add one key-art file per real campaign stage; use a wide center crop in the briefing hero. |
| 1f | stage key art | Reuse the same stage files with a square center crop in map nodes. |
| 1f | world-map backdrop | Add one approved World Map backdrop. |
| 1g | R&D-bay backdrop | Add one approved Tech Tree backdrop. |
| 1h | debrief-hall backdrop | Add one approved Mission Report backdrop. |
| 1h | result banner | Add exactly two result assets: victory and defeat. Medal/rank remains vector/icon UI. |

Normalize approved files under:

```text
assets/images/reactor_rim_ui/stages/<stage-id>.png
assets/images/reactor_rim_ui/results/victory.png
assets/images/reactor_rim_ui/results/defeat.png
assets/images/reactor_rim_ui/backdrops/world-map.png
assets/images/reactor_rim_ui/backdrops/tech-tree-rnd-bay.png
assets/images/reactor_rim_ui/backdrops/mission-report-debrief.png
```

There are exactly seven real campaign stage ids today:

```text
outpost-alpha
nebula-relay
salvage-rift
asteroid-foundry
aurora-gate
void-bastion
singularity-core
```

`outpost-alpha` is the real first campaign stage as well as the common test fixture id; do not create a separate fixture-only stage asset.

### OrionArt extension

Keep one art registry in `lib/game/ui/orion_atlas_sprite.dart`; do not add a parallel public string-path API.

Recommended surface:

```dart
enum OrionStageArtCrop { briefingWide, mapSquare }

enum OrionSceneArt { worldMap, techTree, missionReport }

abstract final class OrionArt {
  static OrionArtDescriptor stage(
    StageDefinition stage, {
    required OrionStageArtCrop crop,
  });

  static OrionArtDescriptor result(StageResult? result);

  static OrionArtDescriptor scene(OrionSceneArt scene);
}
```

`OrionArt.stage` uses one closed `stage.id -> asset` map. The crop changes only `sourceRectFor`:

- `briefingWide`: wide, centered crop for a full-bleed header;
- `mapSquare`: square center crop for the node aperture.

Never stretch the 1024×640-style source image into a square. `sourceRectFor` is the existing hook for preserving composition.

`OrionArt.result` has a closed real-state signature:

- `result == null` -> defeat art;
- `result != null` -> victory art;
- `result.medal` continues to drive the existing medal glyph/color separately.

Do **not** create Clear/Silver/Gold image variants. The mock's medal distinction is vector treatment, not three separate hero images.

### Working-tree art preflight

The external review reports additional untracked PNGs in a local working tree. GitHub cannot verify untracked files, so HPA-9 treats this as a mandatory implementation preflight rather than a repository fact.

Before Task 1 runtime work:

```bash
git status --short assets/images
git ls-files --others --exclude-standard assets/images
```

If candidate `stage_*`, `result_*`, `scene_*`, `board_*`, or backdrop files exist locally:

1. map only approved semantic roles above into `reactor_rim_ui/`;
2. downscale/optimize oversized UI art to the rendered product need without adding a runtime image dependency;
3. delete/reject local board skins and any unmapped scene files from the HPA-9 working tree;
4. never use `git add -A` while unidentified art remains;
5. no implementation task begins with an unexplained untracked PNG under `assets/images/`.

The final scope gate repeats the same check.

## 1a — Playable HUD

### Owner

Extend the merged PR #28 mission composition. No replacement scene or landscape branch.

### Target

The board remains the subject. Status is compact at the rim. Bottom controls read as one coherent dock with a single primary wave action.

Preserve all real HPA-14 behavior:

- base health, stage/wave/phase, credits;
- World Map gating;
- pause/resume;
- direct `1x / 2x / 3x` speed selection;
- auto-start/countdown;
- Start Wave / Start Now / active-wave state;
- selected-cell tower rail;
- selected-tower inspector;
- scanner;
- acquired modules;
- command toast;
- module draft and Mission Report blocking overlays;
- full-size Flame viewport and board tap-through.

HPA-9 only closes remaining visual gaps: spacing, density, art scale, relative emphasis, surface treatment.

Known deviations remain:

```text
real 8×12 board vs synthetic mock board -> Responsive adaptation
visible segmented speed control          -> Intentional deviation
current font family                      -> Intentional deviation
real-only scanner/modules/status states  -> Real-only state
```

## 1b — Stage Briefing

### Navigation decision

Keep the current modal navigation contract. Do **not** convert briefing into a second full-screen route.

The mock is full-bleed. Orion will use a **full-height, scroll-controlled modal bottom sheet with a full-bleed wide hero header**. The sheet may occupy nearly the whole SafeArea, but it still returns `bool?` through `Navigator.pop` and `_showStageBriefing` remains page-owned.

This is a `Responsive adaptation`: visual hierarchy follows the full-screen mock without creating a second navigation model.

### Extraction

Move presentation from private `_StageBriefingSheet` into:

```text
lib/game/ui/stage_briefing_sheet.dart
```

`OrionGamePage` still owns:

- stage selection;
- committed-state facts;
- launching `_startStage(stage)` only after the sheet returns `true`.

No briefing DTO/view-model.

### Exact fact set

The sheet receives `StageDefinition`, committed `StageResult?`, and page-derived primitive runtime facts:

```text
wave count             = stage.waves.length
effective starting HP  = same committed campaign + StageModifierRules path as GameSession.initial
effective start gold   = committed CampaignModifiers.adjustedStartingGold
conditions             = stage modifier titles, or Standard Conditions
best medal/result      = committed StageResult when present
reward                  = existing stage reward when present
```

The page derives effective HP/gold from the same committed run inputs used to create gameplay. The widget does not reproduce game-balance rules.

Medal thresholds may be described only from existing real rules:

- Gold = finish at full starting hull;
- Silver = finish at or above `GameBalance.silverMedalThreshold`;
- Clear = any other victory.

The mock's `≤6 TOWER CAP` tile is `Mock-only removed`; Orion has no such rule.

### Composition

```text
full-bleed wide stage key art
stage identity + main/optional cue
compact fact tiles: Waves / Hull / Start Credits / Conditions
objective / reward / existing medal cue
one Start Mission or Replay Mission action
standard sheet dismiss/back behavior
```

The previous 112dp square boss thumbnail is not the HPA-9 hero treatment.

## 1c — Wave Scanner

Keep `NextWaveScanner` on `MissionCollapsible`.

Close only visual gaps around:

- convoy/group/count hierarchy;
- enemy art prominence;
- trait chips;
- clear bonus;
- recommendations/counters;
- stage modifier treatment;
- collapsed/expanded density.

Preserve unread/read/reset, preview-wave reset, selection collapse, board interception, hit-area release, multi-group information, and Reduced Motion.

No swipe gesture is required for parity. Existing tap + semantics activation remain authoritative.

## 1d — Tower Inspector

Keep `TowerInspector` and its existing stat pipeline.

`TowerStatScale`, `_StatRow`, and `_ProgressionActions` already provide the stat normalization, filled gauges, and L1/L2/L3 behavior. HPA-9 does not rebuild them.

Visual work is:

- make tower art the hero;
- restyle the existing Damage / Fire / Range / secondary gauges;
- keep all six targeting modes;
- present the two real L2 specializations as visual cards that still call `onSpecialize`;
- keep L1 upgrade and L3/max semantics;
- keep sell/refund as accessible tap action, visually subordinate.

The mock's hold-to-salvage implication remains an `Intentional deviation`; sell is not made hold-only.

## 1e — Drag to Place

This is the only behavior-bearing scene in HPA-9. Its correctness and visual presentation are both frozen before implementation.

### Existing authority

`GameSession.validatePlacement(position, type)` remains the only validity authority.

`GameSession.placeTower(position, type)` remains the mutation authority.

The Flutter layer never reimplements path, occupied, phase, module-draft, unlock, or affordability rules.

Preview state stays transient in the Flutter/Flame boundary, not in `GameSnapshot`, and pointer moves do not publish mission snapshots.

### One event family through Flutter

Dock -> Chrome -> Page carries one closed callback:

```dart
sealed class TowerPlacementPreviewEvent {
  const TowerPlacementPreviewEvent();
}

final class TowerPlacementPreviewBegin extends TowerPlacementPreviewEvent {
  const TowerPlacementPreviewBegin(this.type);
  final TowerType type;
}

final class TowerPlacementPreviewUpdate extends TowerPlacementPreviewEvent {
  const TowerPlacementPreviewUpdate(this.globalPosition);
  final Offset globalPosition;
}

final class TowerPlacementPreviewCommit extends TowerPlacementPreviewEvent {
  const TowerPlacementPreviewCommit(this.globalPosition);
  final Offset globalPosition;
}

final class TowerPlacementPreviewCancel extends TowerPlacementPreviewEvent {
  const TowerPlacementPreviewCancel();
}
```

The commit event carries the final pointer location deliberately. An off-board final position must cancel; it must never reuse the last valid preview cell or `_selectedCell`.

`OrionGamePage` reuses `_gameWidgetKey` / the same global->GameWidget-local conversion pattern already used by `_routeTapToBoard`.

No PreviewController.

### Gesture decision

Use **`LongPressDraggable` (or Flutter's equivalent delayed long-press draggable recognizer)** on enabled/unlocked tower cards.

Reason:

- the rail is a real horizontally scrolling `ListView`;
- immediate pan drag would compete with horizontal scrolling;
- long press naturally maps to the mock's `LIFTED` state;
- ordinary tap remains immediate;
- semantics tap remains immediate;
- horizontal swipe continues to scroll the rail and must not begin preview.

The long-press recognizer is the only drag entry path. Do not add a second vertical-only drag path.

### Presentation contract

All five visible 1e preview treatments are in scope:

| Mock element | HPA-9 decision | Owner |
| --- | --- | --- |
| tower ghost follows finger with shadow | **Build** using `LongPressDraggable.feedback` and real `OrionArt.tower(type)` | Flutter tower card/drag feedback |
| cost-delta pill such as `−50 → 360` | **Build** in drag feedback from current rail gold + real Level-1 tower cost; unaffordable state remains explicit | Flutter tower card/drag feedback |
| rail/header changes to `DROP TO BUILD` | **Build** as local transient `TowerBuildRail` presentation state while a long-press drag is active | TowerBuildRail |
| source card reads `LIFTED` | **Build** with `childWhenDragging` / local lifted state | tower card |
| invalid path region receives red wash | **Build** in `BoardComponent` over all path cells while placement preview is active; candidate validity remains separately resolved by `validatePlacement` | Flame BoardComponent |

The selected-cell tower rail remains the only place from which drag can start. The mock's persistent always-available tray is an `Intentional deviation`; HPA-9 does not rebuild mission navigation around a persistent tower palette.

### Preview validity and range

On update:

1. resolve pointer to cell with existing board geometry;
2. if null, clear candidate/range but keep drag active;
3. validate non-null cell through `_session.validatePlacement(cell, type)`;
4. construct a throwaway Level-1 `PlacedTower` at that cell;
5. call `_session.resolveTowerStats(throwaway)`;
6. use the resolved range for the ring;
7. send only presentation fields to `BoardComponent`.

`BoardComponent` owns no placement rule. It may render:

- candidate cell;
- allowed/denied candidate treatment;
- resolved range ring;
- path-region danger wash while drag is active.

While preview is active, preview rendering **replaces** the normal selected-cell paint. Never show the old selection highlight and preview highlight simultaneously.

### Cleanup contract

Extend `_clearSelection()` into the single transient board-interaction cleanup path (rename only if clearer). It clears:

```text
_selectedCell
_selectedTower
BoardComponent.selectedCell
active placement-preview type/cell/result/range
```

Existing callers therefore clear preview automatically on place, sell, start wave, restart, and miss-tap.

Additionally:

- allowed `returnToMap()` calls the same cleanup before navigation;
- module-draft/report input blocking cancels preview;
- long-press drag cancel clears preview;
- invalid commit clears preview without mutation;
- off-board/null final pointer cancels;
- successful commit mutates exactly once through `GameSession.placeTower` and then clears preview.

### Correctness gate

`test/game/orion_defense_game_test.dart` is authoritative. Integration drag is smoke only.

Long Sight regression must **not** calculate the expected value with the resolver under test. Use:

```text
baseRange = GameBalance.towerStats(type, level: 1).range
expected  = baseRange * 1.15
preview range ~= expected
preview range > baseRange
```

Use a fixture where Long Sight is the only range modifier. This fails if preview bypasses the session resolver pipeline.

Task 5 has a mandatory review stop before Task 6 in the same PR.

## 1f — World Map

Keep `WorldMapView`, `SectorMapLayout`, the existing route painter, and campaign callbacks.

Add the approved world-map backdrop and reuse stage key art with the square crop.

Visual target:

- crest/star-chart stage nodes;
- medal/status ring integrated with node;
- existing spatial routes;
- lower-noise header/utility controls;
- explicit locked/available/cleared state without color-only communication.

### Persistent selected-stage bar decision

The source mock contains a persistent selected-stage detail/launch bar. Orion will **not** add it.

Classification: `Intentional deviation`.

Reason: tapping an available stage already opens scene 1b, which is the single authoritative detail + launch surface. A second map-resident selected-stage model would duplicate stage detail, launch behavior, and selection lifecycle; adopting it would make the 1b briefing redundant.

`onStageSelected(stage)` continues to open `StageBriefingSheet` immediately.

## 1g — Tech Tree

Keep the five real, independent `CampaignTechUpgrade` values and existing purchase/persistence callbacks.

Add the approved R&D-bay backdrop with a readability scrim.

Replace the text-heavy row list with a five-node icon field plus one selected-node detail surface. No graph engine and no prerequisite edges.

### Local selection lifecycle

`TechTreeView` becomes stateful for presentation selection only.

Rules:

- initial selection = first `CampaignTechUpgrade.values` entry for deterministic behavior;
- selecting another node changes only local UI state;
- selection survives parent rebuilds while the Tech Tree remains mounted;
- after a successful purchase, the same node remains selected and detail changes to Purchased;
- while save is in flight, the same node remains selected and purchase is disabled;
- if persistence fails and the parent rolls back the purchase, the same node remains selected and detail reflects the rolled-back real state plus existing feedback;
- closing and reopening the Tech Tree creates a fresh view and resets to the deterministic initial node.

No selected upgrade is persisted in campaign state.

Node/detail UI preserves:

- unspent / earned / spent bank;
- purchased / affordable / unaffordable / saving states;
- real effectLabel, description, and cost;
- at least 48dp targets;
- non-color-only states.

A faint decorative constellation may exist only if it does not connect nodes in a way that implies prerequisites.

## 1h — Mission Report

Keep `MissionReportContent` as the data boundary and current action policy.

Use:

1. approved debrief-hall backdrop + dark readability scrim;
2. exactly one victory/defeat result banner from `OrionArt.result(content.result)`;
3. existing vector/icon medal treatment from `content.result.medal` when present;
4. real stage identity and real compact facts;
5. comparison/save state;
6. modules/reward as subordinate sections;
7. existing state-dependent bottom actions.

No separate Clear/Silver/Gold bitmap. No invented numeric analytics.

For saved victory, useful real facts include:

- medal;
- base health result;
- module count;
- save/reward state where appropriate.

For loss, `content.result == null` chooses defeat art and existing loss facts/actions remain authoritative.

Any entrance animation uses existing Reduced Motion plumbing and never delays action availability.

## Evidence contract: evidence lands with each scene

Parity evidence is no longer deferred until the final task.

For **each Task 1–8**, before committing that scene:

1. focused tests are green;
2. capture deterministic `390×844` fixture PNG;
3. reach the same representative state in the real app and capture live `390×844` PNG;
4. add/update that scene's parity row in the PR body;
5. classify every visible difference;
6. only then commit the scene task.

Evidence directory:

```text
docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/
fixture-1a.png ... fixture-1h.png
live-1a.png    ... live-1h.png
```

Source artboards remain the PR #28 copies; do not duplicate them.

### Reproducible capture support

HPA-9 adds two tiny test/developer helpers, not a golden framework:

```text
test/support/reactor_rim_visual_capture.dart
scripts/capture_reactor_rim_ios.sh
```

`reactor_rim_visual_capture.dart` captures a named `RepaintBoundary` to PNG only when `ORION_CAPTURE_DIR` is set; ordinary test runs remain side-effect free.

Each scene test provides one explicit capture case. Example command shape:

```bash
ORION_CAPTURE_DIR=docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9 \
  flutter test test/widget/<scene>_test.dart \
  --plain-name 'capture scene 1x fixture'
```

The live helper is intentionally thin:

```bash
./scripts/capture_reactor_rim_ios.sh \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/live-1x.png
```

It wraps the established booted-iOS-simulator screenshot mechanism; the task lists the real app navigation needed to reach the target state before capture.

No third-party screenshot/golden dependency.

## Responsive/accessibility contract

Use one shared viewport sweep helper rather than multiplying all content assertions by five viewport sizes.

Extend test support with:

```text
product portrait: 390×844
compact portrait smoke: 375×812
landscape smoke: 844×390
```

Mandatory scene-level behavior/content tests run at the product portrait. Each scene owner gets one shared no-overflow/reachable-control sweep across the three sizes above.

Remove `430×932` and `932×430` from the mandatory global matrix. They may be used while debugging but are not release gates.

Run `3.0x` text-scale tests only on high-risk action surfaces:

- Stage Briefing primary action;
- mission primary action / tower rail where already covered;
- Tower Inspector action/card area;
- Tech Tree detail/purchase action;
- Mission Report action row.

Preserve:

- >=48dp touch targets;
- native segmented speed semantics;
- scanner semantics;
- tap placement when drag is added;
- selected/purchased/locked semantics;
- Reduced Motion;
- no state communicated only by color.

## Review checkpoints

### Task 5 hard stop

Task 5 is one focused commit inside the single HPA-9 PR. Do **not** begin Task 6 until review verifies:

- tap vs long-press vs horizontal rail scroll arbitration;
- Long Sight range ring uses resolved range;
- preview replaces selected highlight;
- off-board final position cancels;
- `_clearSelection` owns preview cleanup;
- exactly one tower/gold mutation on valid commit;
- 1e fixture/live parity row is complete.

This achieves the review-isolation benefit without splitting the product ticket into a second PR.

### Task 8 checkpoint

Before final integration, verify 1f/1g/1h are visually close to the mock without adding duplicate stage-detail state, fake Tech Tree prerequisites, or fake report analytics.

## Risks and mitigations

### Horizontal rail scrolling steals the placement drag

Mitigation: LongPressDraggable/delayed recognizer; horizontal swipe must scroll and must not begin preview.

### Preview ring lies after campaign/stage/module modifiers

Mitigation: throwaway L1 `PlacedTower` -> `GameSession.resolveTowerStats`; literal Long Sight multiplier regression.

### Preview and selected-cell paint diverge

Mitigation: preview replaces selected paint while active and `_clearSelection` clears both.

### Off-board release places on the old selected cell

Mitigation: commit carries final global position; null/off-board final position always cancels.

### Local art accidentally ships board skins or huge unused files

Mitigation: Task 0 working-tree inventory, closed semantic art map, no `git add -A`, final `git status` / untracked-PNG gate.

### Stage art is stretched into the wrong aspect ratio

Mitigation: one source file per stage with wide and square `sourceRectFor` crops; no raw stretch.

### Briefing duplicates navigation

Mitigation: keep modal result contract; use full-height sheet + full-bleed hero rather than a new route.

### World Map grows a second stage-detail model

Mitigation: persistent mock detail bar is explicitly an Intentional deviation; scene 1b remains the detail/launch surface.

### Tech Tree selection becomes stale after purchase rollback

Mitigation: selection is local enum identity and survives rebuild; real parent props always determine purchased/affordable state.

### Evidence drift is discovered only at the end

Mitigation: every scene task captures fixture + live evidence and writes its row before commit.

## Non-goals

- no combat/balance changes;
- no board geometry changes;
- no tower/enemy/projectile rule changes;
- no campaign topology/unlock changes;
- no new Tech Tree upgrades, ranks, or prerequisites;
- no new Mission Report analytics;
- no save schema change;
- no scanner recommendation logic change;
- no per-stage board skins;
- no persistent always-on tower tray;
- no persistent World Map selected-stage detail model;
- no global theme/font rewrite;
- no source HTML in the repository;
- no third-party golden framework;
- no generic scene/parity framework;
- no second implementation PR for Task 5.

## Completion definition

HPA-9 is complete when:

1. scenes 1a–1h each have source-artboard -> fixture -> live evidence at `390×844`;
2. each scene's evidence was produced during that scene task, not retrofitted at the end;
3. every visible mismatch is classified;
4. approved UI art is packaged through the closed OrionArt contract and no unmapped local PNG is left to accidentally ship;
5. 1e uses authoritative validation/mutation, resolved range, long-press/scroll-safe gesture arbitration, centralized cleanup, and no off-board fallback;
6. 1f intentionally uses the briefing instead of duplicating a selected-stage bar;
7. 1g keeps five independent purchases and deterministic local selection lifecycle;
8. 1h uses only real result facts and exactly two result images;
9. responsive/accessibility smoke passes at the reduced viewport matrix;
10. focused tests, full `flutter test`, `flutter analyze`, formatting, integration smoke, and `git diff --check` pass.