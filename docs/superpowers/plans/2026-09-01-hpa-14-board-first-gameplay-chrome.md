# HPA-14 Board-First Gameplay Chrome Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle and recompose Orion's in-mission Flutter UI around the approved board-first reference while preserving the full-size Flame viewport and every existing gameplay interaction.

**Architecture:** `OrionGamePage` keeps lifecycle, navigation, persistence, `GameWidget`, module-draft, and Mission Report ownership. `MissionChrome` extracts the current overlay composition without adding state. `MissionSurface` provides the new mission-only visual primitive. `MissionCollapsible` gives next-wave intel and acquired-module details one implementation of collapse/reset/animation/hit-area release. The existing speed `SegmentedButton<double>` remains one-tap and visible.

**Tech Stack:** Dart `^3.12.0`, Flutter `>=3.44.0`, Flame `^1.38.0`, Material 3, `flutter_test`, `integration_test`.

**Spec:** `docs/superpowers/specs/2026-09-01-hpa-14-board-first-gameplay-chrome-design.md`

## Global Constraints

- Continue on `agent/hpa-14-board-first-gameplay-chrome-plan` and PR #28; do not open a second PR.
- Keep `GameSnapshot` / `OrionDefenseGame` as the mission state/action boundary.
- Keep `GameWidget` filling the complete mission `SafeArea`.
- Do not change combat, balance, board geometry, campaign, persistence, rewards, tower/enemy/projectile behavior, or Flame components.
- All intended production changes stay under `lib/game/ui/`.
- Do not modify `OrionDefenseGame.supportedSpeedMultipliers`.
- Portrait is the primary product gate.
- Do not add a dedicated wide branch, wide breakpoint, wide-only dock geometry, or `ORION` branding.
- Landscape uses the same responsive tree; it must avoid overflow/crash and keep controls usable, but HPA-14 does not claim landscape visual parity.
- Reuse `OrionUiTheme`; no second token system or global retheme.
- Keep `CommandFrame` unchanged for non-mission surfaces.
- No font dependency.
- Preserve `_routeTapToBoard(Offset)` and current board-reachability contracts.
- Preserve selected tower > selected cell > idle state priority.
- Preserve all eight tower cards, lock/affordability, L1/L2/L3 progression, six targeting modes, sell/refund, and resolved stats.
- Preserve speed as visible one-tap `1x` / `2x` / `3x` selection using the current `SegmentedButton<double>` interaction.
- Preserve scanner unread/read/reset/collapse/radar-intercept/detail behavior.
- Keep `AcquiredRunModuleStrip` for Mission Report.
- Acquired-module mission details stay in-tree; no Overlay-based menu.
- Preserve command-toast lifecycle and semantics.
- Keep module draft and Mission Report behavior/styling unchanged except compatibility fixes.
- Preserve minimum 48dp touch targets.
- No state-management package, controller/store, overlay registry, slot framework, external asset pipeline, or third-party golden framework.

## Risks

### Portrait layout budget

At the representative `390 × 844` target with `47/34` top/bottom insets, the SafeArea is about `390 × 763`. The 8×12 board is `390 × 585`, leaving roughly `89dp` above and below the centered board. Status, toast, and dock should stay near that budget; overlap is allowed only when non-control overlay space still forwards/passes taps to the board.

### Full-size chrome root

`MissionChrome` may be mounted with `Positioned.fill`, but a bare layout `Stack` must remain non-hit-testing in empty space. One focused page/chrome test pins this. Do not scatter duplicate root-hit-testing rules across later tasks.

### Shared collapse behavior

`MissionCollapsible` has exactly two consumers. Keep its API limited to local expanded state, `collapseRequested`, optional reset token, Reduced Motion transition, and current-child-only switch layout. Scanner-specific radar interception and module-specific content remain in their own widgets.

### ReactorButton cleanup

`ReactorButton` currently carries four tested behaviors: minimum hit target/single invocation, semantics activation, disabled no-tap semantics, and compact-label text-scale safety. Migrate those contracts before deleting the helper.

## Parity / Evidence Contract

The PR proves three things without a large manual screenshot matrix:

1. **Mock → deterministic portrait fixture:** one `390 × 844` build-idle fixture demonstrates the mock's visual hierarchy as a `Responsive adaptation`.
2. **Current gameplay UI → redesign:** widget/page tests prove no value/action/state disappears.
3. **Fixture → live gameplay:** the integration smoke drives the same widgets through a real `OrionDefenseGame` and real taps.

Mandatory visual evidence is only:

```text
source mock
390 × 844 deterministic build-idle fixture
390 × 844 live build-idle gameplay
```

Fixture-only supporting captures are limited to:

```text
selected empty cell / tower rail
selected Level 2 tower / specialization inspector
expanded next-wave scanner
expanded acquired-module details
```

No terminal-state or landscape screenshot matrix is required.

## File Map

### Create

```text
lib/game/ui/mission_surface.dart
lib/game/ui/mission_collapsible.dart
lib/game/ui/mission_chrome.dart
lib/game/ui/acquired_run_module_control.dart

test/widget/mission_surface_test.dart
test/widget/mission_collapsible_test.dart
test/widget/mission_chrome_test.dart
test/widget/acquired_run_module_control_test.dart
```

### Modify

```text
lib/game/ui/orion_game_page.dart
lib/game/ui/mission_command_hud.dart
lib/game/ui/mission_command_dock.dart
lib/game/ui/tower_inspector.dart
lib/game/ui/next_wave_scanner.dart
lib/game/ui/command_toast.dart
lib/game/ui/command_frame.dart          # conditional ReactorButton deletion only

test/widget/mission_command_hud_test.dart
test/widget/mission_command_dock_test.dart
test/widget/tower_inspector_test.dart
test/widget/next_wave_scanner_test.dart
test/widget/command_toast_test.dart
test/widget/orion_ui_theme_test.dart    # conditional ReactorButton test migration/removal
test/widget_test.dart
integration_test/app_smoke_test.dart
```

### No Intended Changes

```text
lib/main.dart
pubspec.yaml
pubspec.lock
lib/game/orion_defense_game.dart
lib/game/models/
lib/game/rules/
lib/game/components/
lib/game/campaign/
lib/game/feedback/
lib/game/ui/world_map_view.dart
lib/game/ui/run_module_draft_panel.dart
lib/game/ui/mission_report_panel.dart
assets/images/
assets/audio/
```

---

## Task 1: Add the mission-only rounded surface

**Files:**
- Create: `lib/game/ui/mission_surface.dart`
- Create: `test/widget/mission_surface_test.dart`

**Interfaces:**
- Consumes: `OrionUiTheme.of(context)`.
- Produces: `MissionSurface` for all later mission restyles.

- [ ] **Step 1: Write the failing primitive tests**

Create `test/widget/mission_surface_test.dart` and assert:

```dart
final decoration = tester
    .widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(const ValueKey('surface')),
        matching: find.byType(DecoratedBox),
      ),
    )
    .decoration as BoxDecoration;

expect(
  decoration.color,
  OrionUiTheme.dark.hullBlack.withValues(alpha: 0.85),
);
expect(decoration.borderRadius, BorderRadius.circular(18));
```

Also assert:

- default border uses `systemCyan` at low opacity and width `1`;
- emphasized mode uses `systemCyanStrong`, width `2`, and one restrained cyan shadow;
- custom radius/padding work;
- the primitive introduces no `GestureDetector`, `InkWell`, or semantics node by itself.

- [ ] **Step 2: Verify RED**

```bash
flutter test test/widget/mission_surface_test.dart
```

Expected: compile failure because `MissionSurface` does not exist.

- [ ] **Step 3: Implement `MissionSurface`**

Use this public boundary:

```dart
class MissionSurface extends StatelessWidget {
  const MissionSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(8),
    this.radius = 18,
    this.emphasized = false,
    this.backgroundColor,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool emphasized;
  final Color? backgroundColor;
  final Color? borderColor;
}
```

Implement with `DecoratedBox`, `BoxDecoration`, `ClipRRect`, and `Padding`. Do not add a painter, controller, animation, or gesture handling.

- [ ] **Step 4: Verify GREEN**

```bash
dart format lib/game/ui/mission_surface.dart test/widget/mission_surface_test.dart
flutter test test/widget/mission_surface_test.dart
flutter analyze
git diff --check
```

- [ ] **Step 5: Commit**

```bash
git add lib/game/ui/mission_surface.dart test/widget/mission_surface_test.dart
git commit -m "feat: add board-first mission surface"
```

---

## Task 2: Extract the shared in-tree collapse invariant and migrate the scanner

**Files:**
- Create: `lib/game/ui/mission_collapsible.dart`
- Create: `test/widget/mission_collapsible_test.dart`
- Modify: `lib/game/ui/next_wave_scanner.dart`
- Modify: `test/widget/next_wave_scanner_test.dart`

**Interfaces:**
- Consumes: `orionMotionDuration(...)`.
- Produces: `MissionCollapsible` for scanner and acquired-module details.

- [ ] **Step 1: Write focused RED tests for the shared invariant**

Create `test/widget/mission_collapsible_test.dart` with a host that renders a full-size tappable background behind the collapsible.

Pin these behaviors:

```text
collapsed trigger toggles expanded
expanded trigger toggles collapsed
collapseRequested closes immediately
collapseRequested disables pointer input
resetToken change closes expanded state
outgoing expanded rectangle is not hit-testable after one transition frame
Reduced Motion makes the switch duration zero
```

For the stale-hit-area test:

1. open the expanded child;
2. record its rectangle;
3. pump with `collapseRequested: true`;
4. pump `1ms`;
5. tap the former expanded rectangle;
6. assert the background receives exactly one tap.

- [ ] **Step 2: Verify RED**

```bash
flutter test test/widget/mission_collapsible_test.dart
```

Expected: compile failure because `MissionCollapsible` does not exist.

- [ ] **Step 3: Implement the narrow shared widget**

Create:

```dart
typedef MissionCollapsibleBuilder = Widget Function(
  BuildContext context,
  VoidCallback toggle,
);

class MissionCollapsible extends StatefulWidget {
  const MissionCollapsible({
    super.key,
    required this.collapseRequested,
    required this.collapsedBuilder,
    required this.expandedBuilder,
    this.resetToken,
    this.onExpandedChanged,
  });

  final bool collapseRequested;
  final Object? resetToken;
  final MissionCollapsibleBuilder collapsedBuilder;
  final MissionCollapsibleBuilder expandedBuilder;
  final ValueChanged<bool>? onExpandedChanged;
}
```

State rules:

```dart
if (oldWidget.resetToken != widget.resetToken ||
    (!oldWidget.collapseRequested && widget.collapseRequested)) {
  _expanded = false;
}
```

Build through:

```dart
IgnorePointer(
  ignoring: widget.collapseRequested,
  child: AnimatedSwitcher(
    duration: orionMotionDuration(
      context,
      const Duration(milliseconds: 180),
    ),
    layoutBuilder: (currentChild, _) =>
        currentChild ?? const SizedBox.shrink(),
    child: /* current collapsed or expanded builder */,
  ),
)
```

Do not add scanner-specific tap interception or unread state.

- [ ] **Step 4: Migrate `NextWaveScanner` to the shared collapse state**

Keep scanner-local:

```text
_hasUnreadPreview
_tapIntercepted
radar-band detection
onCollapsedTapIntercept
preview labels/content
```

Use:

```dart
MissionCollapsible(
  collapseRequested: widget.collapseRequested,
  resetToken: widget.preview.waveNumber,
  onExpandedChanged: (expanded) {
    if (expanded && _hasUnreadPreview) {
      setState(() => _hasUnreadPreview = false);
    }
  },
  collapsedBuilder: ...,
  expandedBuilder: ...,
)
```

Delete scanner-owned `_expanded` and its duplicate current-child-only switch layout.

- [ ] **Step 5: Run the scanner regressions unchanged**

```bash
flutter test test/widget/mission_collapsible_test.dart
flutter test test/widget/next_wave_scanner_test.dart
```

The existing tests for new-preview reset, selection collapse, radar-band interception, expanded hit-area release, trait details, and Reduced Motion must remain green.

- [ ] **Step 6: Verify and commit**

```bash
dart format lib/game/ui/mission_collapsible.dart \
  lib/game/ui/next_wave_scanner.dart \
  test/widget/mission_collapsible_test.dart \
  test/widget/next_wave_scanner_test.dart
flutter analyze
git diff --check
git add lib/game/ui/mission_collapsible.dart \
  lib/game/ui/next_wave_scanner.dart \
  test/widget/mission_collapsible_test.dart \
  test/widget/next_wave_scanner_test.dart
git commit -m "refactor: share mission collapsible behavior"
```

---

## Task 3: Convert the status HUD into compact rounded anchors

**Files:**
- Modify: `lib/game/ui/mission_command_hud.dart`
- Modify: `test/widget/mission_command_hud_test.dart`

**Interfaces:**
- Consumes: `GameSnapshot`, `MissionSurface`.
- Produces: existing `MissionStatusHud({required snapshot})` with new presentation only.

- [ ] **Step 1: Preserve the existing semantic contract**

Keep these exact assertions:

```text
Base 8 of 20
Outpost Alpha. Wave 3 of 8, Build
Outpost Alpha. Wave 1 of 8, Paused
Outpost Alpha. Wave 1 of 8, Wave Active
Credits 150
```

Keep health-color tests at `11/20`, `10/20`, and `5/20`.

- [ ] **Step 2: Add RED layout assertions**

Add keys:

```text
mission-status-hud
mission-status-base
mission-status-stage
mission-status-credits
```

Assert three `MissionSurface` descendants and no `CommandFrame` descendant.

At `390 × 844`, text scale `1.3`, use a long stage name and wave `8/8`; assert all status surfaces remain in the viewport with no exception.

- [ ] **Step 3: Verify RED**

```bash
flutter test test/widget/mission_command_hud_test.dart
```

- [ ] **Step 4: Implement compact anchors**

Replace the fixed outer frame with a `Wrap` of three compact status surfaces. Preserve semantic labels, health thresholds, and existing text-scale caps.

Do not add branding.

- [ ] **Step 5: Verify and commit**

```bash
dart format lib/game/ui/mission_command_hud.dart test/widget/mission_command_hud_test.dart
flutter test test/widget/mission_command_hud_test.dart
flutter analyze
git diff --check
git add lib/game/ui/mission_command_hud.dart test/widget/mission_command_hud_test.dart
git commit -m "feat: compact mission status anchors"
```

---

## Task 4: Move the existing pacing controls into the idle dock before extracting the page composition

This task deliberately keeps the current page-level top/bottom composition. It changes placement and presentation, not speed behavior.

**Files:**
- Modify: `lib/game/ui/mission_command_hud.dart`
- Modify: `lib/game/ui/mission_command_dock.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget/mission_command_hud_test.dart`
- Modify: `test/widget/mission_command_dock_test.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: current `SegmentedButton<double>` callbacks and `GameSnapshot` pacing state.
- Produces: idle dock containing Pause + visible segmented speeds + Auto-start + existing primary action behavior.

- [ ] **Step 1: Rename/refactor the existing pacing strip without changing speed UX**

Rename `MissionPacingStrip` to `MissionPacingControls` if that improves readability after relocation, but keep its interaction model:

```dart
SegmentedButton<double>(
  showSelectedIcon: false,
  segments: const [
    ButtonSegment(value: 1.0, label: Text('1x')),
    ButtonSegment(value: 2.0, label: Text('2x')),
    ButtonSegment(value: 3.0, label: Text('3x')),
  ],
  selected: {snapshot.speedMultiplier},
  onSelectionChanged: canUsePacing
      ? (selection) => onSpeedSelected(selection.single)
      : null,
)
```

Do not introduce a cycle helper and do not modify `orion_defense_game.dart`.

- [ ] **Step 2: Write RED idle-dock tests**

Update the dock contract to receive:

```text
onTogglePause
onSpeedSelected
onToggleAutoStart
```

and move World Map out of the dock contract for the later chrome extraction.

Assert idle state contains:

```text
Pause/Resume
1x
2x
3x
Auto-start
Start Wave or Start Now/current wave action
```

Preserve the existing `_reactorLabel` ordering:

```text
countdown → Start Now
wave → wave progress
otherwise → Start Wave
```

Do not add new won/lost dock labels; Mission Report owns terminal presentation.

- [ ] **Step 3: Pin the four ReactorButton contracts on the replacement mission actions**

Before eventual cleanup, add tests covering the new primary mission action and World Map action:

1. each touch target is at least 48dp and one physical tap invokes the callback once;
2. semantics `tap` invokes the callback once;
3. disabled state has no semantics tap action;
4. long primary labels at text scale `3.0` do not overflow.

These are migrations of the current `orion_ui_theme_test.dart` contracts, not new requirements.

- [ ] **Step 4: Verify RED**

```bash
flutter test test/widget/mission_command_hud_test.dart \
  test/widget/mission_command_dock_test.dart
```

- [ ] **Step 5: Implement the shallow idle dock**

Use one `MissionSurface` containing:

```text
MissionPacingControls
flexible/decorative center spacing
existing primary action
```

Keep selected-cell and selected-tower surfaces unchanged in this task.

Remove the standalone page-level pacing strip and pass pacing callbacks into `MissionCommandDock`.

Keep the existing page top row and `IgnorePointer(AcquiredRunModuleStrip)` unchanged.

- [ ] **Step 6: Migrate the current real-page pacing test in the same commit**

In `test/widget_test.dart`, replace assertions for the old strip with:

```text
new idle pacing controls exist
1x / 2x / 3x all visible
real game changes to 2.0 when 2x is tapped
real game changes directly to 3.0 when 3x is tapped
selection removes idle pacing controls
GameWidget == SafeArea remains true
status + current AcquiredRunModuleStrip remain under IgnorePointer
```

- [ ] **Step 7: Verify GREEN and commit**

```bash
dart format lib/game/ui/mission_command_hud.dart \
  lib/game/ui/mission_command_dock.dart \
  lib/game/ui/orion_game_page.dart \
  test/widget/mission_command_hud_test.dart \
  test/widget/mission_command_dock_test.dart \
  test/widget_test.dart
flutter test test/widget/mission_command_hud_test.dart
flutter test test/widget/mission_command_dock_test.dart
flutter test test/widget_test.dart
flutter analyze
git diff --check
git add lib/game/ui/mission_command_hud.dart \
  lib/game/ui/mission_command_dock.dart \
  lib/game/ui/orion_game_page.dart \
  test/widget/mission_command_hud_test.dart \
  test/widget/mission_command_dock_test.dart \
  test/widget_test.dart
git commit -m "feat: consolidate idle mission controls"
```

---

## Task 5: Extract MissionChrome with one responsive portrait-first composition

**Files:**
- Create: `lib/game/ui/mission_chrome.dart`
- Create: `test/widget/mission_chrome_test.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: `GameSnapshot`, existing callbacks, `MissionStatusHud`, `MissionCommandDock`, `NextWaveScanner`, `CommandToast`, `AcquiredRunModuleStrip`.
- Produces: `MissionChrome` as presentation composition only.

Use this public shape:

```dart
class MissionChrome extends StatelessWidget {
  const MissionChrome({
    super.key,
    required this.snapshot,
    required this.onBoardTapIntercept,
    required this.onWorldMap,
    required this.onStartWave,
    required this.onTogglePause,
    required this.onSpeedSelected,
    required this.onToggleAutoStart,
    required this.onPlaceTower,
    required this.onUpgrade,
    required this.onSpecialize,
    required this.onTargetingChanged,
    required this.onSell,
  });
}
```

- [ ] **Step 1: Write RED composition tests at the product viewport**

At `390 × 844`, assert:

```text
MissionStatusHud exists
World Map exists
AcquiredRunModuleStrip exists only when modules exist
NextWaveScanner exists under its current visibility condition
CommandToast is above MissionCommandDock
idle dock contains Pause + 1x/2x/3x + Auto + primary action
no ORION branding exists
```

- [ ] **Step 2: Pin the single fill-root hit-testing invariant**

Host a tappable background below `MissionChrome`.

Tap a coordinate inside empty chrome/root space but outside every compact control and contextual dock. Assert the background/board intercept receives exactly one tap.

Tap a real control and assert the background does not receive it.

This is the only dedicated root-empty-space test required.

- [ ] **Step 3: Add landscape no-overflow checks without a wide branch**

Pump the same component tree at:

```text
844 × 390
932 × 430
```

Assert:

- no Flutter overflow exception;
- status and controls remain reachable;
- selected-cell and selected-tower docks can scroll/fit as needed.

Do not assert wide-only geometry, branding, or a 900dp dock.

- [ ] **Step 4: Verify RED**

```bash
flutter test test/widget/mission_chrome_test.dart
```

- [ ] **Step 5: Implement the extraction**

Use one `LayoutBuilder` + `Stack`/`Wrap` composition. Let content wrap/constrain based on available size; do not create explicit wide/narrow product branches.

For this task, keep the existing module strip:

```dart
if (snapshot.acquiredRunModules.isNotEmpty)
  IgnorePointer(
    child: AcquiredRunModuleStrip(
      moduleIds: snapshot.acquiredRunModules,
    ),
  )
```

Keep scanner visibility and modifier-title projection exactly as the current page.

- [ ] **Step 6: Replace the inline page overlay bands**

`OrionGamePage` becomes:

```dart
Stack(
  children: [
    Positioned.fill(child: GameWidget(...)),
    Positioned.fill(child: MissionChrome(...)),
    if (pendingOffer) Positioned.fill(child: RunModuleDraftPanel(...)),
    if (lost) Positioned.fill(child: MissionReportPanel(...)),
    if (won) Positioned.fill(child: MissionReportPanel(...)),
  ],
)
```

Keep `_gameWidgetKey` and `_routeTapToBoard` unchanged.

- [ ] **Step 7: Migrate the existing page contracts now**

`test/widget_test.dart` must still prove:

```text
GameWidget == SafeArea
status is pointer-transparent
current acquired-module strip is pointer-transparent
selection replaces idle pacing
speed callbacks reach the real game
board taps pass through empty chrome
module draft/report remain later blocking stack entries
```

- [ ] **Step 8: Verify and commit**

```bash
dart format lib/game/ui/mission_chrome.dart \
  lib/game/ui/orion_game_page.dart \
  test/widget/mission_chrome_test.dart \
  test/widget_test.dart
flutter test test/widget/mission_chrome_test.dart
flutter test test/widget_test.dart
flutter analyze
git diff --check
git add lib/game/ui/mission_chrome.dart \
  lib/game/ui/orion_game_page.dart \
  test/widget/mission_chrome_test.dart \
  test/widget_test.dart
git commit -m "refactor: extract adaptive mission chrome"
```

---

## Task 6: Restyle selected-cell and selected-tower states

**Files:**
- Modify: `lib/game/ui/mission_command_dock.dart`
- Modify: `lib/game/ui/tower_inspector.dart`
- Modify: `test/widget/mission_command_dock_test.dart`
- Modify: `test/widget/tower_inspector_test.dart`
- Modify: `test/widget/mission_chrome_test.dart`

**Interfaces:**
- Consumes: existing tower callbacks and `MissionSurface`.
- Produces: rounded tower rail/inspector with unchanged behavior.

- [ ] **Step 1: Preserve every existing build-rail behavior test**

Keep assertions for:

```text
all eight cards
locked card does not call placement
unlocked unaffordable card still calls authoritative placement callback
active-wave phase blocks placement
375dp fit/peek and horizontal scrolling
text scaling
affordability semantics
```

Add only a presentation assertion that the rail/cards use `MissionSurface` and no mission `CommandFrame`.

- [ ] **Step 2: Preserve every existing inspector behavior test**

Keep:

```text
resolved stats/callbacks
secondary stat
wave-phase disabled mutations
null stats
max-level state
bounded height/internal scroll
all six 48dp targeting actions
upgrade/specialization/sell behavior
```

Add presentation assertions for `MissionSurface` and no mission `CommandFrame`.

- [ ] **Step 3: Add compact portrait geometry coverage**

At `390 × 844`, text scale `1.3`:

- selected cell: tower rail remains reachable and horizontally scrollable;
- selected Level 2 tower: both specialization actions, targeting, sell, and final stat can be reached by internal scroll;
- idle pacing controls are absent in both states.

- [ ] **Step 4: Verify RED**

```bash
flutter test test/widget/mission_command_dock_test.dart \
  test/widget/tower_inspector_test.dart \
  test/widget/mission_chrome_test.dart
```

- [ ] **Step 5: Restyle only**

Replace mission `CommandFrame` shells with `MissionSurface`. Preserve callback/gating/stat logic verbatim.

- [ ] **Step 6: Verify and commit**

```bash
dart format lib/game/ui/mission_command_dock.dart \
  lib/game/ui/tower_inspector.dart \
  test/widget/mission_command_dock_test.dart \
  test/widget/tower_inspector_test.dart \
  test/widget/mission_chrome_test.dart
flutter test test/widget/mission_command_dock_test.dart
flutter test test/widget/tower_inspector_test.dart
flutter test test/widget/mission_chrome_test.dart
flutter analyze
git diff --check
git add lib/game/ui/mission_command_dock.dart \
  lib/game/ui/tower_inspector.dart \
  test/widget/mission_command_dock_test.dart \
  test/widget/tower_inspector_test.dart \
  test/widget/mission_chrome_test.dart
git commit -m "feat: restyle contextual mission controls"
```

---

## Task 7: Add the shared module-details control and finish scanner/toast mission styling

**Files:**
- Create: `lib/game/ui/acquired_run_module_control.dart`
- Create: `test/widget/acquired_run_module_control_test.dart`
- Modify: `lib/game/ui/next_wave_scanner.dart`
- Modify: `lib/game/ui/command_toast.dart`
- Modify: `lib/game/ui/mission_chrome.dart`
- Modify: `test/widget/next_wave_scanner_test.dart`
- Modify: `test/widget/command_toast_test.dart`
- Modify: `test/widget/mission_chrome_test.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: `MissionCollapsible`, `MissionSurface`, `runModuleDefinition(id)`.
- Produces: `AcquiredRunModuleControl(moduleIds:, collapseRequested:)`.

- [ ] **Step 1: Write RED module-control tests**

Create tests for:

```text
empty list → no trigger
three modules → Modules 3 trigger
trigger is at least 48dp
semantics announces acquired module count and button state
opening shows all three title/effect/affinity rows
collapseRequested closes the expansion
module-list content change resets expansion closed
```

Do not duplicate the low-level stale-hit-area regression; assert the module uses `MissionCollapsible`, then rely on Task 2's invariant test.

- [ ] **Step 2: Implement `AcquiredRunModuleControl` in its own file**

Use:

```dart
class AcquiredRunModuleControl extends StatelessWidget {
  const AcquiredRunModuleControl({
    super.key,
    required this.moduleIds,
    required this.collapseRequested,
  });
}
```

Derive a stable reset token from the ordered module IDs:

```dart
final resetToken = Object.hashAll(moduleIds);
```

Build collapsed and expanded surfaces through `MissionCollapsible`. Expanded rows use existing definition fields:

```text
definition.title
definition.effectText
definition.affinity.label
```

No Overlay, menu controller, route, or bottom sheet.

- [ ] **Step 3: Swap the temporary mission module strip**

In `MissionChrome`, replace the pointer-transparent `AcquiredRunModuleStrip` with:

```dart
AcquiredRunModuleControl(
  moduleIds: snapshot.acquiredRunModules,
  collapseRequested:
      snapshot.selectedCell != null || snapshot.selectedTower != null,
)
```

Do not change the report's `AcquiredRunModuleStrip`.

- [ ] **Step 4: Restyle the scanner shell**

Use `MissionSurface` for collapsed and expanded scanner presentation while preserving the shared `MissionCollapsible` behavior and all scanner-local interception/details.

- [ ] **Step 5: Restyle the toast shell**

Replace only the outer mission frame with `MissionSurface`.

Keep every current timer, repeated-message, live-region, tone, line-cap, disposal, and Reduced Motion test.

- [ ] **Step 6: Add representative viewport/overlay tests**

At `390 × 844`:

```text
expanded scanner stays inside viewport
expanded Modules n details stay inside viewport
warning toast remains within viewport
selected cell/tower collapses scanner and modules
```

At `844 × 390` and `932 × 430`, assert no overflow for build idle and one selected state. No visual parity claim.

- [ ] **Step 7: Preserve blocking overlays**

In `test/widget_test.dart`, publish a pending module offer and terminal reports through existing seams. Assert taps at underlying mission-control coordinates do not reach the dock while the draft/report is active.

No report/draft styling changes.

- [ ] **Step 8: Verify and commit**

```bash
dart format lib/game/ui/acquired_run_module_control.dart \
  lib/game/ui/next_wave_scanner.dart \
  lib/game/ui/command_toast.dart \
  lib/game/ui/mission_chrome.dart \
  test/widget/acquired_run_module_control_test.dart \
  test/widget/next_wave_scanner_test.dart \
  test/widget/command_toast_test.dart \
  test/widget/mission_chrome_test.dart \
  test/widget_test.dart
flutter test test/widget/acquired_run_module_control_test.dart
flutter test test/widget/next_wave_scanner_test.dart
flutter test test/widget/command_toast_test.dart
flutter test test/widget/mission_chrome_test.dart
flutter test test/widget_test.dart
flutter analyze
git diff --check
git add lib/game/ui/acquired_run_module_control.dart \
  lib/game/ui/next_wave_scanner.dart \
  lib/game/ui/command_toast.dart \
  lib/game/ui/mission_chrome.dart \
  test/widget/acquired_run_module_control_test.dart \
  test/widget/next_wave_scanner_test.dart \
  test/widget/command_toast_test.dart \
  test/widget/mission_chrome_test.dart \
  test/widget_test.dart
git commit -m "feat: finish mission secondary surfaces"
```

---

## Task 8: Prove live parity, migrate cleanup contracts, and finish the same PR

**Files:**
- Modify: `integration_test/app_smoke_test.dart`
- Modify conditionally: `lib/game/ui/command_frame.dart`
- Modify conditionally: `test/widget/orion_ui_theme_test.dart`
- Update: PR #28 description/evidence.

**Interfaces:**
- Consumes: final mission widget keys/callbacks.
- Produces: live interaction proof and final cleanup only.

- [ ] **Step 1: Update integration finders for the relocated pacing controls**

Replace old `MissionPacingStrip`/standalone pacing assumptions with stable final controls. Keep text finders for `1x`, `2x`, and `3x` because those options remain visible.

- [ ] **Step 2: Preserve board reachability probes**

Keep the existing real-cell probes, including:

```text
(0,0)
(7,0)
row-1 buildable probes already in smoke
```

Add lower buildable `(0,11)` only if it is not already covered by another bottom-chrome probe.

Every probe must reach the real board and open the selected-cell build state.

- [ ] **Step 3: Exercise the real interaction path**

Through actual callbacks/game state:

```text
launch Outpost Alpha
select buildable cell
place Laser
verify real credit change
select placed tower
change targeting to Strongest
return to idle
select 2x directly
select 3x directly
select 1x directly
toggle Auto-start on/off
open/close next-wave scanner
start wave
pause
resume
```

Do not assign synthetic snapshots inside the integration smoke.

- [ ] **Step 4: Run the complete automated gate**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/widget/mission_surface_test.dart
flutter test test/widget/mission_collapsible_test.dart
flutter test test/widget/mission_chrome_test.dart
flutter test test/widget/acquired_run_module_control_test.dart
flutter test test/widget/mission_command_hud_test.dart
flutter test test/widget/mission_command_dock_test.dart
flutter test test/widget/tower_inspector_test.dart
flutter test test/widget/next_wave_scanner_test.dart
flutter test test/widget/command_toast_test.dart
flutter test test/widget_test.dart
flutter test
git diff --check
```

Then run the repository's existing simulator integration smoke command/workflow.

- [ ] **Step 5: Capture only the bounded visual evidence**

Add one PR table:

| Reference | Fixture | Live | Classification | Difference |
| --- | --- | --- | --- | --- |
| source mock | 390×844 build idle | 390×844 build idle | Responsive adaptation | real vertical board, visible gameplay status/speed semantics |

Add fixture-only images for:

```text
selected empty cell
selected Level 2 tower
expanded scanner
expanded Modules n details
```

Do not add a wide/terminal/manual-state screenshot matrix.

- [ ] **Step 6: Migrate ReactorButton contracts before cleanup**

Confirm final tests explicitly cover:

```text
>=48dp touch target
one physical tap invokes once
semantics tap invokes once
disabled semantics has no tap action
long compact primary label at 3.0x text scale does not overflow
```

If any contract is missing, add it to `mission_command_dock_test.dart` or `mission_chrome_test.dart` before deleting anything.

- [ ] **Step 7: Search for ReactorButton usage**

```bash
rg -n "ReactorButton" lib test
```

If production call sites remain, keep `ReactorButton` and its tests.

If the only remaining production occurrence is its definition:

- delete `ReactorButton` from `command_frame.dart`;
- remove the old ReactorButton-specific tests from `orion_ui_theme_test.dart` only after Step 6's replacement tests pass;
- rerun the affected focused tests.

- [ ] **Step 8: Review final scope**

```bash
git diff --stat main...HEAD
git diff --name-only main...HEAD
```

Confirm no changes under:

```text
lib/game/orion_defense_game.dart
lib/game/models/
lib/game/rules/
lib/game/components/
lib/game/campaign/
lib/game/feedback/
assets/images/
assets/audio/
```

- [ ] **Step 9: Commit smoke/cleanup changes**

```bash
git add integration_test/app_smoke_test.dart \
  lib/game/ui/command_frame.dart \
  test/widget/orion_ui_theme_test.dart
git commit -m "test: prove live mission chrome parity"
```

If the two conditional cleanup files were unchanged, stage only `integration_test/app_smoke_test.dart`.

- [ ] **Step 10: Finish on PR #28**

Push all implementation commits to the existing branch. Update PR #28 with:

- implementation summary;
- automated test results;
- simulator smoke result;
- the one mock/fixture/live portrait comparison;
- four fixture-only supporting images;
- intentional deviations.

Mark this same PR ready only after every automated and visual gate above passes.

Do not create another pull request for HPA-14.
