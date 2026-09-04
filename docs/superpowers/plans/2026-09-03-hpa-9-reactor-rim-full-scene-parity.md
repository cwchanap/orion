# HPA-9 Reactor Rim Full-Scene Visual Parity Implementation Plan

> **For agentic workers:** Use `superpowers:test-driven-development` for runtime work, `superpowers:receiving-code-review` at the Task-5 checkpoint, and `superpowers:verification-before-completion` before any completion claim. Execute scene tasks in order and keep every task green.

**Goal:** Complete mock-to-live visual parity for Reactor Rim scenes 1a–1h while preserving Orion's existing gameplay, campaign, persistence, accessibility, and navigation semantics.

**Baseline:** merged HPA-14 / PR #28 on `main`.

**Architecture:** Keep every scene in its existing owner. Add one narrow, explicitly tested direct-manipulation seam for 1e. Extend `OrionArt` rather than adding a second art registry. No scene framework, graph engine, controller/store, or fake analytics model.

**Spec:** `docs/superpowers/specs/2026-09-03-hpa-9-reactor-rim-full-scene-parity-design.md`

## Global constraints

- One HPA-9 implementation PR. Keep scene-local commits.
- Task 5 is a **hard review stop** inside that PR; do not create a second PR unless the product owner explicitly changes delivery strategy.
- Reuse PR #28's source artboards at `docs/superpowers/specs/assets/evidence/2026-09-01-hpa-14/artboards/1a.png` through `1h.png`.
- Do not add the standalone HTML to the repository.
- Reuse `OrionUiTheme`; no second token system or global theme rewrite.
- No external font dependency.
- Keep `GameWidget` filling the mission `SafeArea`.
- Preserve HPA-14 board-tap forwarding and empty-chrome tap-through.
- Preserve visible direct `1x / 2x / 3x` speed selection.
- Preserve all eight tower types, unlock/affordability behavior, L1/L2/L3, six targeting modes, sell/refund, scanner state, module details, toast behavior, module draft, and report save/loss states.
- Preserve campaign topology, stage unlocks/results, Tech Tree costs/effects/persistence, and navigation.
- `GameSession.validatePlacement(position, type)` stays the placement-validity authority.
- `GameSession.placeTower(position, type)` stays the mutation authority.
- `GameSession.resolveTowerStats(PlacedTower)` is the preview-stat authority.
- Preview state is transient; no pointer-move `GameSnapshot` publication.
- Drag augments tap/semantics placement; it never replaces them.
- No Tech Tree prerequisites or Mission Report analytics.
- Minimum 48dp touch targets, semantics, Reduced Motion, and non-color-only state remain required.
- No third-party screenshot/golden framework.

## Evidence contract

Evidence is produced **with each scene task**, not deferred to the end.

Target directory:

```text
docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/
```

Required outputs:

```text
fixture-1a.png  live-1a.png
fixture-1b.png  live-1b.png
fixture-1c.png  live-1c.png
fixture-1d.png  live-1d.png
fixture-1e.png  live-1e.png
fixture-1f.png  live-1f.png
fixture-1g.png  live-1g.png
fixture-1h.png  live-1h.png
```

Each task completes one PR-body row containing:

```text
source artboard
fixture evidence
live evidence
Exact
Responsive adaptation
Real-only state
Mock-only removed
Intentional deviation
```

No row may leave an unexplained visible mismatch.

## Responsive contract

Use a shared smoke helper rather than repeating all semantic assertions at every width.

Mandatory sizes:

```text
390×844  product portrait + all substantive scene tests
375×812  compact portrait no-overflow/reachability smoke
844×390  landscape no-overflow/reachability smoke
```

`430×932` and `932×430` are no longer mandatory global gates.

Use 3.0× text-scale checks only on highest-risk primary/action surfaces.

---

## Task 0: Preflight UI art and add reusable capture/viewport support

This task runs before any scene implementation. It closes the asset ambiguity and makes parity evidence reproducible from the first scene onward.

### Files

**Create:**

```text
test/widget/orion_art_test.dart
test/support/reactor_rim_visual_capture.dart
scripts/capture_reactor_rim_ios.sh

assets/images/reactor_rim_ui/stages/outpost-alpha.png
assets/images/reactor_rim_ui/stages/nebula-relay.png
assets/images/reactor_rim_ui/stages/salvage-rift.png
assets/images/reactor_rim_ui/stages/asteroid-foundry.png
assets/images/reactor_rim_ui/stages/aurora-gate.png
assets/images/reactor_rim_ui/stages/void-bastion.png
assets/images/reactor_rim_ui/stages/singularity-core.png
assets/images/reactor_rim_ui/results/victory.png
assets/images/reactor_rim_ui/results/defeat.png
assets/images/reactor_rim_ui/backdrops/world-map.png
assets/images/reactor_rim_ui/backdrops/tech-tree-rnd-bay.png
assets/images/reactor_rim_ui/backdrops/mission-report-debrief.png
```

**Modify:**

```text
lib/game/ui/orion_atlas_sprite.dart
pubspec.yaml
test/support/command_deck_fixtures.dart
```

**No intended change:**

```text
pubspec.lock
lib/game/rules/
lib/game/models/
lib/game/campaign/
```

### Step 0.1 — Inventory the real local art before adding anything

Run:

```bash
git status --short assets/images
git ls-files --others --exclude-standard assets/images
find assets/images -maxdepth 2 -type f \( -name 'stage_*.png' -o -name 'result_*.png' -o -name 'scene_*.png' -o -name 'board_*.png' -o -name 'world_map_backdrop.png' \) -print
```

The review reports local candidate art that GitHub cannot see because it is untracked. Verify it in the implementation checkout instead of assuming it exists.

Map only the approved semantic roles from the design spec. If raw candidate names differ, use visual/content inspection to map the role; do not widen the contract.

Reject from HPA-9:

```text
all per-stage board skins
all unmapped scene images
all duplicate/unused result variants
```

Do not use `git add -A` while unidentified files remain.

### Step 0.2 — Normalize approved files

Move/copy only approved UI art into `assets/images/reactor_rim_ui/...`.

If an approved source image is excessively large for a 390×844 mobile UI, downscale/optimize it as an authoring step. Do not add a runtime image-processing dependency.

The stage files are shared by briefing and map; do not produce square and wide duplicate bitmaps.

### Step 0.3 — Write RED art-contract tests

Create `test/widget/orion_art_test.dart` and pin:

```text
OrionCampaign.stages has an OrionArt stage descriptor for every real stage id
briefingWide and mapSquare descriptors use the same file for one stage
mapSquare source rect is square
briefingWide source rect is wider than tall
OrionArt.result(null) resolves defeat art
OrionArt.result(non-null StageResult) resolves victory art regardless of medal
medal remains a separate real StageResult fact
all three scene backdrops resolve through OrionArt
no public parallel resultHeroAssetPath/string-table API is introduced
```

Run:

```bash
flutter test test/widget/orion_art_test.dart
```

Expected: compile/test failure before the new API exists.

### Step 0.4 — Extend the existing OrionArt registry

In `orion_atlas_sprite.dart`:

```dart
enum OrionStageArtCrop { briefingWide, mapSquare }
enum OrionSceneArt { worldMap, techTree, missionReport }
```

Extend `OrionArt.stage(stage, crop: ...)`, `OrionArt.result(StageResult?)`, and `OrionArt.scene(...)` using private closed maps.

Use `sourceRectFor` to center-crop stage art rather than stretching it.

### Step 0.5 — Package only normalized UI directories

In `pubspec.yaml` add:

```yaml
- assets/images/reactor_rim_ui/stages/
- assets/images/reactor_rim_ui/results/
- assets/images/reactor_rim_ui/backdrops/
```

Do not add raw candidate paths outside this directory.

### Step 0.6 — Add shared viewport smoke helper

Extend `test/support/command_deck_fixtures.dart` with reusable viewport constants/helper for:

```text
390×844
375×812
844×390
```

The helper should set/reset `tester.view.physicalSize` and `devicePixelRatio`, and run one caller-supplied pump/assertion per viewport. It is for no-overflow/reachability smoke, not repeated content assertions.

### Step 0.7 — Add deterministic fixture capture helper

Create `test/support/reactor_rim_visual_capture.dart`.

Contract:

- caller wraps the representative scene in a named `RepaintBoundary`;
- helper checks `Platform.environment['ORION_CAPTURE_DIR']`;
- if absent: no file I/O, ordinary tests remain side-effect free;
- if present: `RenderRepaintBoundary.toImage(pixelRatio: 1)` -> PNG -> `<dir>/<filename>`;
- create output directory if needed.

No pixel-comparison assertion and no golden dependency.

### Step 0.8 — Add one live screenshot wrapper

Create executable `scripts/capture_reactor_rim_ios.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
out="$1"
mkdir -p "$(dirname "$out")"
xcrun simctl io booted screenshot "$out"
```

This captures the current booted iOS simulator. Each scene task owns the navigation instructions that put the real app in the representative state before invoking it.

### Step 0.9 — Verify and commit

```bash
dart format lib/game/ui/orion_atlas_sprite.dart test/widget/orion_art_test.dart test/support/command_deck_fixtures.dart test/support/reactor_rim_visual_capture.dart
flutter pub get
flutter test test/widget/orion_art_test.dart
flutter analyze
git diff --check
git status --short assets/images
git ls-files --others --exclude-standard assets/images
```

Before commit, `git ls-files --others --exclude-standard assets/images` must be empty or contain only files explicitly excluded from the HPA-9 checkout and removed before proceeding.

Commit:

```bash
git add lib/game/ui/orion_atlas_sprite.dart pubspec.yaml \
  test/widget/orion_art_test.dart test/support/command_deck_fixtures.dart \
  test/support/reactor_rim_visual_capture.dart scripts/capture_reactor_rim_ios.sh \
  assets/images/reactor_rim_ui
git commit -m "chore: prepare Reactor Rim parity art and capture support"
```

---

## Task 1: Close scene 1a Playable HUD gaps

### Files

Modify only as proven by the visual delta:

```text
lib/game/ui/mission_chrome.dart
lib/game/ui/mission_command_hud.dart
lib/game/ui/mission_command_dock.dart

test/widget/mission_chrome_test.dart
test/widget/mission_command_hud_test.dart
test/widget/mission_command_dock_test.dart
```

### Step 1.1 — Classify the current delta first

Compare:

```text
artboards/1a.png
PR #28 live/fixture baseline
current 390×844 fixture
```

Do not create production work for already-accepted differences:

```text
8×12 board geometry              -> Responsive adaptation
visible 1x/2x/3x                 -> Intentional deviation
font family                      -> Intentional deviation
real scanner/modules/status data -> Real-only state
```

### Step 1.2 — Add RED assertions only for observed gaps

Examples:

```text
status anchors do not collide with top controls
idle dock stays inside bottom SafeArea
primary action remains independent/tappable
selected cell/tower replaces idle controls
empty chrome area still routes board taps
```

Run focused tests and prove at least one assertion for a real observed gap is RED. If there is no remaining gap after classifications, make no unnecessary production edit.

### Step 1.3 — Make minimum presentation changes

Adjust only spacing, density, icon/art size, grouping, and emphasis. Keep PR #28 component boundaries.

### Step 1.4 — Run substantive + shared viewport smoke

```bash
flutter test test/widget/mission_chrome_test.dart
flutter test test/widget/mission_command_hud_test.dart
flutter test test/widget/mission_command_dock_test.dart
flutter test test/widget_test.dart
flutter analyze
git diff --check
```

### Step 1.5 — Capture scene 1a before commit

Fixture:

```bash
ORION_CAPTURE_DIR=docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9 \
  flutter test test/widget/mission_chrome_test.dart \
  --plain-name 'capture scene 1a fixture'
```

Live state:

```text
launch Outpost Alpha
remain in build-idle with no cell/tower selected
scanner/modules collapsed for the representative state
```

Capture:

```bash
./scripts/capture_reactor_rim_ios.sh \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/live-1a.png
```

Write the 1a PR parity row now.

### Step 1.6 — Commit

```bash
git add lib/game/ui/mission_chrome.dart lib/game/ui/mission_command_hud.dart \
  lib/game/ui/mission_command_dock.dart test/widget/mission_chrome_test.dart \
  test/widget/mission_command_hud_test.dart test/widget/mission_command_dock_test.dart \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/fixture-1a.png \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/live-1a.png
git commit -m "feat: finish Reactor Rim playable HUD parity"
```

---

## Task 2: Extract and redesign scene 1b Stage Briefing

### Files

Create:

```text
lib/game/ui/stage_briefing_sheet.dart
test/widget/stage_briefing_sheet_test.dart
```

Modify:

```text
lib/game/ui/orion_game_page.dart
test/widget_test.dart
```

### Step 2.1 — Write RED briefing tests

Pin:

```text
full-bleed wide hero region uses OrionArt.stage(...briefingWide)
stage name + main/optional identity
Waves = stage.waves.length
effective Hull is supplied from real committed run inputs
effective Start Credits is supplied from real committed run inputs
Conditions use real stage modifier titles or Standard Conditions
committed prior medal/result appears when present
reward appears only when real stage reward exists
no TOWER CAP tile/copy exists
one Start Mission / Replay Mission action
primary action Navigator.pop(true)
dismiss path does not start gameplay
390×844 primary composition
shared 375×812 + 844×390 no-overflow/reachability smoke
3.0x text scale keeps primary action reachable
Reduced Motion remains usable
```

Run:

```bash
flutter test test/widget/stage_briefing_sheet_test.dart
```

Expected RED because the extracted widget/full-bleed contract does not exist.

### Step 2.2 — Derive runtime facts at OrionGamePage, not in presentation

Use `_committedCampaignModifiers()` as the source.

Derive:

```dart
final modifiers = _committedCampaignModifiers();
final startingGold = modifiers.adjustedStartingGold;
final startingBaseHealth = StageModifierRules.effectiveStartingBaseHealth(
  campaignAdjustedBaseHealth: modifiers.adjustedStartingBaseHealth,
  stageModifiers: stage.modifiers,
);
```

Pass primitive values into `StageBriefingSheet` along with `StageDefinition` and committed `StageResult?`.

Do not add a briefing DTO.

### Step 2.3 — Keep modal ownership but use full-height/full-bleed composition

`_showStageBriefing` remains `showModalBottomSheet<bool>` with current safe-area/reduced-motion policy.

The extracted sheet uses:

```text
full-width hero at top with no CommandFrame inset around the image
wide stage-art crop
scrim/gradient into content
stage identity + facts
medal/reward/conditions
one launch action
scrollable body if required
```

The difference from the mock's dedicated full screen is recorded as `Responsive adaptation`.

### Step 2.4 — Verify page wiring

Page tests prove:

```text
available stage opens briefing
committed result drives replay state
true result starts the same stage
normal dismiss does not start
```

Run:

```bash
dart format lib/game/ui/stage_briefing_sheet.dart lib/game/ui/orion_game_page.dart test/widget/stage_briefing_sheet_test.dart test/widget_test.dart
flutter test test/widget/stage_briefing_sheet_test.dart
flutter test test/widget_test.dart
flutter analyze
git diff --check
```

### Step 2.5 — Capture scene 1b + parity row

Fixture:

```bash
ORION_CAPTURE_DIR=docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9 \
  flutter test test/widget/stage_briefing_sheet_test.dart \
  --plain-name 'capture scene 1b fixture'
```

Live:

```text
World Map -> tap an available stage -> briefing remains open
```

```bash
./scripts/capture_reactor_rim_ios.sh \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/live-1b.png
```

Write the 1b row, including:

```text
full-screen mock vs full-height sheet -> Responsive adaptation
TOWER CAP                         -> Mock-only removed
```

### Step 2.6 — Commit

```bash
git add lib/game/ui/stage_briefing_sheet.dart lib/game/ui/orion_game_page.dart \
  test/widget/stage_briefing_sheet_test.dart test/widget_test.dart \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/fixture-1b.png \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/live-1b.png
git commit -m "feat: redesign Reactor Rim stage briefing"
```

---

## Task 3: Finish scene 1c Wave Scanner parity

### Files

```text
lib/game/ui/next_wave_scanner.dart
test/widget/next_wave_scanner_test.dart
```

### Step 3.1 — Use one representative multi-group fixture

Include traits, clear bonus, recommendations, and modifiers. Compare directly with 1c before coding.

### Step 3.2 — Add RED structural assertions for actual gaps

Pin:

```text
convoy/group rows stay individually identifiable
count stays adjacent to each group
enemy art remains prominent
trait/recommendation/modifier sections remain discoverable
expanded content is bounded/scrollable
collapsed activation >=48dp
```

Keep all PR #28 unread/read/reset/hit-area tests.

### Step 3.3 — Restyle scanner-owned content only

Continue using `MissionCollapsible` and `MissionSurface`. No new scanner state machine.

### Step 3.4 — Verify

```bash
dart format lib/game/ui/next_wave_scanner.dart test/widget/next_wave_scanner_test.dart
flutter test test/widget/next_wave_scanner_test.dart
flutter test test/widget/mission_collapsible_test.dart
flutter analyze
git diff --check
```

### Step 3.5 — Capture 1c + row

```bash
ORION_CAPTURE_DIR=docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9 \
  flutter test test/widget/next_wave_scanner_test.dart \
  --plain-name 'capture scene 1c fixture'
```

Live:

```text
Outpost Alpha build phase -> expand next-wave scanner on a representative multi-group preview
```

Capture `live-1c.png`, write row, then commit:

```bash
git add lib/game/ui/next_wave_scanner.dart test/widget/next_wave_scanner_test.dart \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/fixture-1c.png \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/live-1c.png
git commit -m "feat: finish Reactor Rim wave scanner parity"
```

---

## Task 4: Finish scene 1d Tower Inspector parity using existing gauges

### Files

Modify:

```text
lib/game/ui/tower_inspector.dart
test/widget/tower_inspector_test.dart
```

Verify no logic change:

```text
lib/game/ui/tower_stat_scale.dart
test/widget/sell_button_test.dart
```

### Step 4.1 — RED tests target hero/card structure, not missing gauges

Representative state: Level-2 tower with both specialization choices.

Pin:

```text
tower art is dominant in header
existing Damage/Fire/Range/secondary semantic values remain
existing gauge fill pipeline remains TowerStatScale-driven
both specialization choices become visual cards and call onSpecialize independently
all six targeting modes remain reachable
sell/refund remains present + subordinate
bounded inspector remains scrollable
```

Do not write a test implying `_StatRow`/fill bars are missing; they already exist.

### Step 4.2 — Restyle only presentation

Increase hero art scale; restyle existing `_StatRow`; wrap L2 choices in art-forward card surfaces while keeping `_ProgressionActions` behavior.

No hold-only sell.

### Step 4.3 — Verify

```bash
dart format lib/game/ui/tower_inspector.dart test/widget/tower_inspector_test.dart
flutter test test/widget/tower_inspector_test.dart
flutter test test/widget/sell_button_test.dart
flutter analyze
git diff --check
```

### Step 4.4 — Capture 1d + row

Fixture command targets a deterministic L2 specialization state. Live state reaches the same through real gameplay/test setup.

Write `fixture-1d.png`, `live-1d.png`, parity row, then commit:

```bash
git add lib/game/ui/tower_inspector.dart test/widget/tower_inspector_test.dart \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/fixture-1d.png \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/live-1d.png
git commit -m "feat: finish Reactor Rim tower inspector parity"
```

---

## Task 5: Add scene 1e long-press drag placement preview

**HARD REVIEW STOP AFTER THIS TASK. DO NOT START TASK 6 UNTIL REVIEWED.**

### Files

Modify:

```text
lib/game/orion_defense_game.dart
lib/game/components/board_component.dart
lib/game/ui/orion_game_page.dart
lib/game/ui/mission_chrome.dart
lib/game/ui/mission_command_dock.dart

test/game/orion_defense_game_test.dart
test/widget/mission_command_dock_test.dart
test/widget/mission_chrome_test.dart
test/widget_test.dart
```

The closed event family may live in `mission_command_dock.dart` and be imported by Chrome/Page; do not create a controller class.

### Step 5.1 — Game RED tests first: validity, range, mutation, cleanup

Add tests before widget drag plumbing.

Pin:

```text
begin preview stores tower type but mutates nothing
update maps GameWidget-local pointer through boardCellAt
valid empty cell -> allowed preview
path -> denied
occupied -> denied
locked -> denied when game API is invoked directly
insufficient gold -> denied
preview itself spends no gold and creates no tower
preview fields replace normal selected-cell render state
null/off-board update clears candidate/range
null/off-board final commit cancels and never uses _selectedCell
valid final commit places exactly one tower and spends exactly one cost
invalid commit places nothing
cancel clears preview
_clearSelection clears preview
startWave/restart/sell/place cleanup cannot leave preview
allowed returnToMap clears preview before callback
```

Long Sight expected range test:

```dart
final baseRange = GameBalance.towerStats(type, level: 1).range;
expect(previewRange, closeTo(baseRange * 1.15, 0.001));
expect(previewRange, greaterThan(baseRange));
```

Use a fixture where Long Sight is the only range modifier. Do **not** compute expected via `resolveTowerStats` in this regression.

Run and confirm RED:

```bash
flutter test test/game/orion_defense_game_test.dart
```

### Step 5.2 — Refactor one position-based placement helper

Keep public tap path:

```dart
void placeTower(TowerType type)
```

Extract the shared mutation body to one private helper such as:

```dart
void _placeTowerAt(GridPosition position, TowerType type)
```

It owns:

```text
_session.placeTower
failure copy
TowerComponent creation
selection/preview cleanup
feedback/haptics/sound
snapshot publication
```

Tap and drag commit call the same helper.

### Step 5.3 — Add transient preview state in OrionDefenseGame

Recommended game-facing methods:

```dart
void beginTowerPlacementPreview(TowerType type);
void updateTowerPlacementPreview(Offset canvasPosition);
void commitTowerPlacementPreview(Offset canvasPosition);
void cancelTowerPlacementPreview();
```

These are presentation seams, not persisted state.

On update:

1. resolve cell;
2. validate through session;
3. create throwaway `PlacedTower(id: -1, type: type, position: cell)`;
4. resolve stats through `_session.resolveTowerStats`;
5. send cell/result/range to BoardComponent;
6. do not publish `GameSnapshot`.

On commit, resolve the **provided final position again**. Null -> cancel. Never commit the last prior cell by fallback.

### Step 5.4 — Make `_clearSelection` own preview cleanup

Extend current cleanup so it clears both selection and preview.

Call it from successful `returnToMap` before `onReturnToMap?.call()`.

Do not clear on a rejected active-wave return; that path keeps gameplay intact and only publishes feedback.

### Step 5.5 — BoardComponent presentation only

Add fields/rendering for:

```text
preview active
candidate cell
candidate allowed/denied
resolved range
path danger wash
```

Rendering order:

```text
terrain/path
if preview active: path danger wash
if preview candidate: candidate validity + optional range ring
else if normal selection: existing selectedCell paint
grid/markers as appropriate
```

No placement logic in BoardComponent.

### Step 5.6 — Add one closed preview event callback through Flutter

Define begin/update/commit/cancel event types.

Add exactly one callback parameter through:

```text
TowerBuildRail / MissionCommandDock
MissionChrome
OrionGamePage
```

`OrionGamePage` switches on the event and reuses `_gameWidgetKey` for coordinate conversion. Begin needs no coordinate. Update/Commit convert `globalPosition` into GameWidget-local before game call.

### Step 5.7 — Use LongPressDraggable, not immediate pan drag

Convert eligible cards (build phase + unlocked; affordability remains authority-driven) to `LongPressDraggable<TowerType>` or equivalent delayed long-press recognizer.

Important: the Flame board is **not** a Flutter `DragTarget`. Do not use `wasAccepted`/`onDragCompleted` as placement authority.

Use callbacks:

```text
onDragStarted -> Begin(type)
onDragUpdate  -> remember/update latest global pointer, emit Update
onDragEnd     -> Commit(last global pointer) if one exists, otherwise Cancel
```

Ignore DragTarget acceptance; game validation decides the result.

Use `feedback` for tower ghost + shadow + cost pill and `childWhenDragging` for `LIFTED` source state.

TowerBuildRail may become stateful **only for local presentation** (`activeDraggedType` / DROP TO BUILD label). No controller.

### Step 5.8 — Freeze the five 1e visual treatments

Implement:

```text
tower ghost follows pointer
shadow under ghost
cost pill: representative affordable state shows −cost -> remaining gold
unaffordable state shows real cost/need without pretending placement is allowed
rail/header reads DROP TO BUILD during long-press drag
source card reads LIFTED
all path cells receive danger wash while preview active
candidate cell separately shows allowed/denied result
allowed candidate shows resolved range ring
```

### Step 5.9 — Gesture-arena widget tests

In `mission_command_dock_test.dart` pin:

```text
normal physical tap -> onPlaceTower exactly once, no preview begin
semantics tap -> onPlaceTower exactly once, no preview begin
short press below long-press threshold -> no preview
horizontal swipe -> ListView scroll offset changes and preview never begins
long press accepted -> Begin exactly once
long-press drag updates -> Update positions stream
end -> Commit exactly once with latest global pointer
cancel/no position -> Cancel
locked card cannot begin preview
unaffordable unlocked card may preview; game authority reports insufficientGold
LIFTED/source state + DROP TO BUILD presentation appear only while dragging
```

Chrome/Page tests pin one event passes through without blocking normal board taps after drag ends.

### Step 5.10 — Verify game authority before integration

```bash
dart format lib/game/orion_defense_game.dart lib/game/components/board_component.dart \
  lib/game/ui/orion_game_page.dart lib/game/ui/mission_chrome.dart \
  lib/game/ui/mission_command_dock.dart test/game/orion_defense_game_test.dart \
  test/widget/mission_command_dock_test.dart test/widget/mission_chrome_test.dart test/widget_test.dart
flutter test test/game/orion_defense_game_test.dart
flutter test test/widget/mission_command_dock_test.dart
flutter test test/widget/mission_chrome_test.dart
flutter test test/widget_test.dart
flutter analyze
git diff --check
```

### Step 5.11 — Capture 1e before the hard review stop

Representative fixture/live state:

```text
selected buildable cell -> rail visible
long-press Laser card
source reads LIFTED
header DROP TO BUILD
finger ghost + cost pill visible
preview over valid cell with range ring
path danger wash visible simultaneously
```

Capture `fixture-1e.png` and `live-1e.png`. Write the 1e parity row.

The live drag is visual/smoke evidence only; the game tests above are correctness authority.

### Step 5.12 — Commit and STOP

```bash
git add lib/game/orion_defense_game.dart lib/game/components/board_component.dart \
  lib/game/ui/orion_game_page.dart lib/game/ui/mission_chrome.dart lib/game/ui/mission_command_dock.dart \
  test/game/orion_defense_game_test.dart test/widget/mission_command_dock_test.dart \
  test/widget/mission_chrome_test.dart test/widget_test.dart \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/fixture-1e.png \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/live-1e.png
git commit -m "feat: add Reactor Rim drag placement preview"
```

**STOP. Request review of Task 5 on this commit before Task 6.**

Required review questions:

```text
Does horizontal rail scrolling remain independent from long-press drag?
Does Long Sight preview use resolved range?
Can any off-board release place on _selectedCell?
Can any selection/navigation path leave stale preview state?
Can any valid drop mutate gold/tower count more than once?
Does the 1e evidence account for all five mock treatments?
```

Do not split this commit into another PR unless explicitly instructed.

---

## Task 6: Redesign scene 1f World Map on existing SectorMapLayout

### Files

```text
lib/game/ui/world_map_view.dart
test/widget/world_map_command_deck_test.dart
test/widget/sector_map_layout_test.dart   # verify unchanged domain geometry
test/widget_test.dart                     # navigation expectations as needed
```

### Step 6.1 — RED presentation tests

Fixture must include cleared + medal, available, locked, and side-stage states.

Pin:

```text
approved world-map backdrop exists behind map with readability scrim
stage node uses OrionArt.stage(...mapSquare), not stretched wide art
crest/status/medal hierarchy exists
each node remains >=48dp semantic action
locked/available/cleared explicit without color only
route painter still uses SectorMapLayout.routes
narrow horizontal scrolling still works
utility actions remain reachable
stage tap calls onStageSelected exactly once
no persistent selected-stage detail/launch bar state is introduced
```

### Step 6.2 — Restyle existing map only

Keep route/layout authority. Add backdrop and restyle `_IllustratedStageNode`/map chrome.

Do not add selected-stage state. `onStageSelected(stage)` still immediately opens Stage Briefing.

### Step 6.3 — Verify

```bash
dart format lib/game/ui/world_map_view.dart test/widget/world_map_command_deck_test.dart test/widget_test.dart
flutter test test/widget/world_map_command_deck_test.dart
flutter test test/widget/sector_map_layout_test.dart
flutter test test/widget_test.dart
flutter analyze
git diff --check
```

### Step 6.4 — Capture 1f + row

Representative live/fixture: map with cleared, available, locked nodes and visible backdrop.

Write the 1f row with explicit:

```text
persistent selected-stage bar -> Intentional deviation; Stage Briefing is the single detail/launch surface
```

Capture and commit:

```bash
git add lib/game/ui/world_map_view.dart test/widget/world_map_command_deck_test.dart test/widget_test.dart \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/fixture-1f.png \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/live-1f.png
git commit -m "feat: redesign Reactor Rim world map"
```

---

## Task 7: Redesign scene 1g Tech Tree with local selection lifecycle

### Files

```text
lib/game/ui/tech_tree_view.dart
test/widget/tech_tree_view_test.dart
test/game/tech_tree_test.dart   # verify domain unchanged
```

### Step 7.1 — RED node + lifecycle tests

Pin:

```text
R&D-bay backdrop + readability scrim
exactly five nodes, one per CampaignTechUpgrade
initial selected node is CampaignTechUpgrade.values.first
selecting another node changes local detail only
selection survives parent rebuild
selection survives successful purchase and detail flips Purchased
selection stays same while saving and purchase is disabled
selection survives failed-save rollback and detail reflects rolled-back real state + feedback
closing/recreating TechTreeView resets selection to first enum
bank still shows real unspent/earned/spent
purchased node cannot repurchase
affordable node calls onPurchase exactly once
unaffordable detail exposes real missing-point reason
no prerequisite semantics/edges
```

### Step 7.2 — Convert TechTreeView to StatefulWidget for presentation only

Store:

```dart
CampaignTechUpgrade _selected = CampaignTechUpgrade.values.first;
```

No persistence, no controller, no model field.

Parent `progress`, `techTree`, `feedback`, and `isSavingProgress` always determine the real node/detail state on rebuild.

### Step 7.3 — Replace list with fixed five-node field + detail

Use local positioning/layout suitable for the tiny fixed catalog. No graph library.

Use backdrop + scrim. Decorative constellation is allowed only if non-semantic and not touching nodes as dependency edges.

### Step 7.4 — Verify

```bash
dart format lib/game/ui/tech_tree_view.dart test/widget/tech_tree_view_test.dart
flutter test test/widget/tech_tree_view_test.dart
flutter test test/game/tech_tree_test.dart
flutter analyze
git diff --check
```

### Step 7.5 — Capture 1g + row

Representative state includes purchased + affordable + unaffordable nodes with one selected detail.

Capture `fixture-1g.png`, `live-1g.png`, write row, then commit:

```bash
git add lib/game/ui/tech_tree_view.dart test/widget/tech_tree_view_test.dart \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/fixture-1g.png \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/live-1g.png
git commit -m "feat: redesign Reactor Rim tech tree"
```

---

## Task 8: Redesign scene 1h Mission Report with two result assets

### Files

```text
lib/game/ui/mission_report_panel.dart
test/widget/mission_report_panel_test.dart
test/game/mission_report_content_test.dart   # verify projection unchanged
test/widget_test.dart                         # page compatibility as needed
```

### Step 8.1 — RED result-first tests

Saved victory fixture:

```text
debrief-hall backdrop + scrim
victory banner selected through OrionArt.result(non-null result)
medal glyph/color still derives from real StageResult.medal
stage identity
base-health result
comparison copy
module content/count
save state
reward when present
current two state-appropriate actions
```

Loss fixture:

```text
OrionArt.result(null) -> defeat banner
Retry + World Map remain
```

Real-only states remain:

```text
saving -> actions disabled
saved -> Replay + World Map
failed -> Retry Save + World Map (Unsaved)
Reduced Motion -> no delayed action availability
```

Do not assert or add score/time/kills/damage/R&D analytics.

### Step 8.2 — Implement backdrop + two-state result hero

Keep `MissionReportContent` unchanged. Use `content.result` directly for victory-vs-defeat art selection and medal treatment.

Restyle existing report body into:

```text
backdrop
result banner + medal/result hero
stage + compact real facts
comparison/save feedback
modules/reward secondary content
action row
```

### Step 8.3 — Verify

```bash
dart format lib/game/ui/mission_report_panel.dart test/widget/mission_report_panel_test.dart test/widget_test.dart
flutter test test/widget/mission_report_panel_test.dart
flutter test test/game/mission_report_content_test.dart
flutter test test/widget_test.dart
flutter analyze
git diff --check
```

### Step 8.4 — Capture 1h + row

Representative capture is saved victory. Automated tests continue to cover loss/saving/failed.

Capture `fixture-1h.png`, `live-1h.png`, write row, then commit:

```bash
git add lib/game/ui/mission_report_panel.dart test/widget/mission_report_panel_test.dart test/widget_test.dart \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/fixture-1h.png \
  docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9/live-1h.png
git commit -m "feat: redesign Reactor Rim mission report"
```

---

## Task 9: Integration smoke, evidence assembly, and final scope gate

All 16 new scene captures already exist before this task. Task 9 does not become the first visual check for any scene.

### Files

```text
integration_test/app_smoke_test.dart
PR body parity matrix
```

No new visual scene architecture should be introduced here.

### Step 9.1 — Extend one real-app smoke journey

Keep existing HPA-14 journey and add/retain representative reachability:

```text
World Map -> available stage
Stage Briefing -> dismiss/start
Mission HUD receives real snapshots
scanner expand/collapse
select empty cell -> build rail
tap placement still works
select another build cell -> long-press drag preview -> cancel
a valid long-press drag/drop places exactly once in smoke
select tower -> inspector -> change targeting
return to map when allowed
Tech Tree open/back and real purchase gating
Mission Report representative action path
```

The drag portion proves wiring only. Task-5 game tests remain correctness authority.

### Step 9.2 — Assemble the eight already-produced parity rows

Verify each row points to:

```text
artboards/1x.png
fixture-1x.png
live-1x.png
```

Check classifications for internal consistency. Do not defer a visual fix into a new row note; if a mismatch is unexplained, return to that scene task and fix it.

### Step 9.3 — Run focused final suite

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/widget/orion_art_test.dart
flutter test test/game/orion_defense_game_test.dart
flutter test test/game/tech_tree_test.dart
flutter test test/game/mission_report_content_test.dart
flutter test test/widget/stage_briefing_sheet_test.dart
flutter test test/widget/mission_chrome_test.dart
flutter test test/widget/mission_command_hud_test.dart
flutter test test/widget/mission_command_dock_test.dart
flutter test test/widget/next_wave_scanner_test.dart
flutter test test/widget/mission_collapsible_test.dart
flutter test test/widget/tower_inspector_test.dart
flutter test test/widget/sell_button_test.dart
flutter test test/widget/world_map_command_deck_test.dart
flutter test test/widget/sector_map_layout_test.dart
flutter test test/widget/tech_tree_view_test.dart
flutter test test/widget/mission_report_panel_test.dart
flutter test test/widget_test.dart
flutter test
```

Run the repository's established native simulator integration command used by PR #28. If direct invocation is still the established command:

```bash
flutter test integration_test/app_smoke_test.dart
```

Record the actual authoritative command/output in the PR.

### Step 9.4 — Asset/scope audit

```bash
git status --short assets/images
git ls-files --others --exclude-standard assets/images
git diff --name-only origin/main...HEAD
git diff --stat origin/main...HEAD
git diff --check
```

Hard requirements:

```text
no untracked/unmapped PNG remains under assets/images
all new HPA-9 UI art is under assets/images/reactor_rim_ui/
no board-skin asset is added
no source HTML is added
no external font is added
no second art registry/string-path table is added
no generic scene/controller/store framework is added
no Tech Tree prerequisite semantics are added
no Mission Report analytics are added
no copied placement validation is added outside GameSession
all 16 HPA-9 capture files exist
```

Suggested checks:

```bash
test -z "$(git ls-files --others --exclude-standard assets/images)"
! git diff --name-only origin/main...HEAD | grep -E '^assets/images/(board_|stage_|scene_|result_|world_map_backdrop)'
find docs/superpowers/specs/assets/evidence/2026-09-03-hpa-9 -maxdepth 1 -type f -name '*.png' | sort
```

The second check intentionally permits only the normalized `reactor_rim_ui/` paths in the HPA-9 diff.

### Step 9.5 — Final verification before ready-for-review

Confirm:

```text
8 source artboards accounted for
8 deterministic fixture captures
8 live captures
8 complete parity rows
Task-5 review checkpoint was completed before campaign-screen work
full suite green
integration green
diff clean
asset working tree clean
```

Only then mark the PR ready.

Commit final integration-only work:

```bash
git add integration_test/app_smoke_test.dart
git commit -m "test: prove Reactor Rim full-scene integration"
```

---

## Implementation order

```text
Task 0  art/capture preflight
Task 1  1a Playable HUD + evidence
Task 2  1b Stage Briefing + evidence
Task 3  1c Wave Scanner + evidence
Task 4  1d Tower Inspector + evidence
Task 5  1e Drag to Place + evidence
        HARD REVIEW STOP
Task 6  1f World Map + evidence
Task 7  1g Tech Tree + evidence
Task 8  1h Mission Report + evidence
Task 9  integration + evidence assembly + final gates
```

## Final definition of done

Do not mark HPA-9/PR ready until:

- all eight scene tasks have their own fixture/live evidence and classifications;
- approved art roles are explicit and packaged through `OrionArt`;
- stage art uses wide/square crops rather than stretching;
- Mission Report uses two result assets plus vector medal, not medal-specific bitmaps;
- 1b preserves modal navigation while achieving a full-height/full-bleed hero composition and drops fake tower-cap data;
- 1e uses long-press drag that does not steal horizontal rail scrolling, resolved range, centralized cleanup, no off-board fallback, and exactly-once placement;
- 1f intentionally routes to briefing rather than duplicating a persistent selected-stage bar;
- 1g local selection lifecycle is deterministic and follows real parent state through purchase/save rollback;
- Tech Tree remains five independent purchases;
- Mission Report uses only real facts;
- the reduced shared viewport sweep, accessibility checks, focused tests, full suite, analysis, formatting, integration, asset audit, and `git diff --check` all pass.