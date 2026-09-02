# HPA-14 Board-First Gameplay Chrome Redesign Specification

## Decision

Ship one presentation-only redesign of Orion's in-mission Flutter chrome based on the approved board-first visual reference.

The redesign keeps the current gameplay boundary intact:

```text
Flutter mission UI
→ OrionDefenseGame public callbacks
→ GameSession mutation
→ GameSnapshot publication
→ Flutter rebuild
```

`GameSnapshot` remains the only gameplay-state input to mission widgets. `OrionDefenseGame`, combat rules, balance, board geometry, campaign data, persistence, tower behavior, enemy behavior, projectiles, and Flame components do not change.

The change introduces four focused presentation files:

```text
lib/game/ui/mission_surface.dart
lib/game/ui/mission_collapsible.dart
lib/game/ui/mission_chrome.dart
lib/game/ui/acquired_run_module_control.dart
```

`MissionSurface` provides the new rounded/translucent mission language. `MissionCollapsible` owns the small shared expand/collapse and hit-area-release invariant used by next-wave intel and acquired-module details. `MissionChrome` extracts the page's existing mission composition. `AcquiredRunModuleControl` is the mission-only compact module view; the existing `AcquiredRunModuleStrip` stays unchanged for Mission Report.

Do not add a state-management package, controller/store, slot registry, second design-token system, font dependency, orientation lock, external asset pipeline, or third-party golden framework.

## Approved visual reference

The supplied standalone mock is the visual reference. It is preserved in this planning PR as:

```text
docs/superpowers/specs/assets/2026-09-01-hpa-14-board-first-gameplay-chrome.svg
```

The source composition is `1200 × 800` and establishes:

| Element | Mock value |
| --- | --- |
| Background | `#05080D` |
| Grid/route accent | `#46E6FF` |
| Core accent | `#FFC857` |
| Dock | translucent dark rounded surface |
| Utility hierarchy | three compact utility groups |
| Primary hierarchy | one emphasized cyan pill |
| Branding | centered `ORION`, Oxanium-like display treatment |

The mock specifies **visual language and hierarchy**, not Orion's board geometry. Its simplified horizontal route, tower diamonds, and core are not replacement gameplay art.

### Why the mock is not a 1200×800 layout contract

Orion's real board is always 8 columns × 12 rows. The game sizes each cell as:

```dart
min(viewportWidth / 8, viewportHeight / 12)
```

and centers the resulting board.

That means representative layouts are structurally different from the mock:

```text
1200 × 800 → cell 66.7 → board ~533 × 800
844 × 390  → cell 32.5 → board 260 × 390
390 × 844  → cell 48.75 → board 390 × 585
```

A 900dp-wide dock copied literally from the wide mock would be wider than Orion's real 533dp board at 1200×800. A dedicated wide branch would therefore optimize around geometry Orion does not render.

**Decision:** do not build a special wide composition in HPA-14. Do not add `_wideBreakpoint`, `_brandingBreakpoint`, a 900×90 wide-dock contract, or wide-only `ORION` branding. Preserve one portrait-first responsive component tree. Landscape must not crash or overflow and keeps the same controls, but landscape-specific gutter placement is deferred until it is a product requirement.

The mock-to-Flutter visual comparison is performed on the primary portrait product viewport as a **Responsive adaptation**, not an Exact geometry match.

## Product goal

Make the playable board the visual focus while preserving every real action and state already available in Orion.

The idle hierarchy is:

```text
compact status + secondary actions
             ↓
        playable board
             ↓
pause | 1x 2x 3x | auto     Start Wave / Start Now
```

The selected-state hierarchy remains:

```text
selected empty cell → tower rail replaces idle pacing
selected tower      → tower inspector replaces idle pacing
```

This is the existing selected-state pacing rule, not a new gameplay behavior.

## Board and layout budget

`GameWidget` continues to fill the complete mission `SafeArea`:

```dart
Positioned.fill(
  child: KeyedSubtree(
    key: _gameWidgetKey,
    child: GameWidget(game: game),
  ),
)
```

Never reserve Flutter layout space that shrinks the Flame viewport. Enemy movement, projectile movement, and tower range use absolute game units, so changing the viewport changes the apparent combat scale.

### Representative portrait budget

On a `390 × 844` device with representative top/bottom safe-area insets of `47` and `34`, the usable SafeArea is about `390 × 763`.

The 8×12 board becomes:

```text
390 × 585
```

which leaves about:

```text
178dp total vertical free space
~89dp above the centered board
~89dp below the centered board
```

That ~89dp per side is the useful chrome budget before mission UI begins overlapping the board. It is a representative design budget, not a universal inset guarantee.

When chrome overlaps the board, hit targets must stay compact and `_routeTapToBoard(Offset)` remains load-bearing so decorative overlay area cannot make cells unreachable.

## MissionSurface

Create `lib/game/ui/mission_surface.dart`.

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
}
```

Default treatment uses the existing `OrionUiTheme`:

```text
background  = hullBlack at ~85% opacity
border      = systemCyan at ~25% opacity
emphasized  = systemCyanStrong border + one restrained cyan glow
```

It owns no state, gesture handling, animation, controller, or semantics.

Keep `CommandFrame` unchanged for world map, briefing, settings, module draft, Mission Report, and other non-mission surfaces. Do not add a rounded mode to `CommandFrame`.

The new translucent/rounded reference supersedes the older mission-HUD chamfer treatment. This does not authorize a global glassmorphism rewrite.

## MissionCollapsible

Create `lib/game/ui/mission_collapsible.dart` because two mission controls now need the same subtle in-tree collapse contract.

The shared widget owns only:

- local expanded/collapsed state;
- `collapseRequested` forcing the state closed;
- an optional `resetToken` that closes the control when its content identity changes;
- `IgnorePointer(ignoring: collapseRequested)`;
- Reduced Motion duration;
- `AnimatedSwitcher.layoutBuilder` that keeps only the current child so the outgoing expanded rectangle stops hit-testing immediately;
- a toggle callback supplied to the collapsed/expanded builders.

Suggested boundary:

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

Do **not** generalize scanner-specific radar-band interception into this widget. `NextWaveScanner` keeps `_hasUnreadPreview`, `_tapIntercepted`, preview text, radar semantics, and `onCollapsedTapIntercept` itself. The shared widget exists only to give collapse/hit-area release one implementation and one focused regression test.

## MissionChrome

Create `lib/game/ui/mission_chrome.dart` by extracting the current inline composition from `OrionGamePage`.

`MissionChrome` owns composition only:

- compact mission status;
- World Map placement;
- next-wave scanner placement;
- acquired-module placement;
- command toast placement;
- contextual command dock placement;
- responsive wrapping/constraints.

The page keeps:

- campaign and preference loading;
- game creation;
- navigation;
- save state;
- `GameWidget`;
- blocking module draft;
- Mission Report.

The page stack stays:

```text
GameWidget
MissionChrome
RunModuleDraftPanel / MissionReportPanel
```

### Hit testing

`MissionChrome` may be mounted with `Positioned.fill`, but its root is a layout-only `Stack`/`LayoutBuilder`. A bare `RenderStack` does not hit-test empty space itself.

One focused widget/page test must prove empty chrome space still reaches the board. Do not wrap the full root in `Material`, `ColoredBox`, `Listener`, or `GestureDetector`.

That single invariant plus the existing `_routeTapToBoard` regression coverage is sufficient; do not duplicate the same rule throughout every task.

## Mission status

`MissionStatusHud` keeps its current snapshot-only contract and exact semantics:

```text
Base 8 of 20
Outpost Alpha. Wave 3 of 8, Build
Outpost Alpha. Wave 1 of 8, Paused
Credits 150
```

Replace the one large command frame with compact rounded status surfaces for:

1. base health;
2. stage/wave/phase;
3. credits.

Preserve health thresholds:

```text
> 50%  → system cyan
> 25%  → warning orange
≤ 25%  → danger red
```

World Map moves from the large idle command bar to a compact mission action. It remains enabled only when the existing game callback allows returning during build phase.

Do not add the mock's `ORION` wordmark in HPA-14. Branding is deferred with the wide-layout branch; gameplay information has priority.

## Pacing and primary action

Keep the current pacing interaction model. Do **not** replace the speed `SegmentedButton<double>` with a cycle button.

Today the UI already has the three functional utility groups implied by the mock:

1. Pause/Resume.
2. Speed selection (`1x`, `2x`, `3x`).
3. Auto-start.

The speed control keeps:

- all three options visible;
- one-tap access to any speed;
- native segmented selected-state semantics;
- the existing `onSpeedSelected(selection.single)` callback.

`OrionDefenseGame.supportedSpeedMultipliers` stays unchanged. HPA-14 makes no production change outside `lib/game/ui/` for speed ordering.

Restyle the controls and move them into the idle dock. Preserve 48dp minimum touch targets.

The mock's compact utility geometry is an **Intentional deviation** where accessibility or the segmented control needs more space. The three utility groups plus one emphasized primary action is the hierarchy being matched.

### Primary action

Reuse the current idle command behavior rather than inventing a second state policy:

```text
countdown → Start Now
active wave → current wave progress, disabled
ordinary build → Start Wave when canStartWave
```

The existing Mission Report covers terminal won/lost states, so HPA-14 does not need new terminal labels in the underlying dock.

## Contextual dock states

`MissionCommandDock` remains the sole state selector:

```text
selectedTower != null → tower inspector
selectedCell != null  → tower build rail
otherwise             → idle dock
```

### Empty-cell rail

Preserve all existing behavior:

- all eight tower types;
- locked/unlocked state;
- unlock-wave copy;
- real cost;
- affordable/unaffordable state;
- authoritative placement callback;
- build-phase gating;
- horizontal scrolling;
- atlas art;
- semantics;
- current text-scale behavior.

Only presentation changes.

### Tower inspector

Preserve:

- tower art/type/level/specialization;
- six targeting modes;
- Level 1 upgrade;
- both Level 2 specialization choices;
- Level 3 maximum state;
- sell/refund;
- Damage, Fire, Range, and secondary stat;
- build-phase action gating;
- bounded internal scrolling.

Do not force the inspector into the idle dock's shallow height.

## Next-wave scanner

`NextWaveScanner` keeps its scanner-specific contract and delegates only generic expand/collapse layout to `MissionCollapsible`.

Preserve:

- 48dp collapsed target;
- unread/read lifecycle;
- reset when the preview wave changes;
- collapse on cell/tower selection;
- radar-band board interception;
- immediate release of an outgoing expanded hit area;
- multi-group rows;
- mapped trait art;
- unmatched wave-level traits;
- clear bonus;
- recommendations;
- modifiers;
- Reduced Motion.

Restyle collapsed/expanded shells through `MissionSurface`.

## Acquired modules

Keep `AcquiredRunModuleStrip` unchanged for Mission Report and as the temporary pointer-transparent mission presentation while `MissionChrome` is first extracted.

Create a separate mission widget:

```text
lib/game/ui/acquired_run_module_control.dart
```

`AcquiredRunModuleControl` is built on `MissionCollapsible`:

```dart
class AcquiredRunModuleControl extends StatelessWidget {
  const AcquiredRunModuleControl({
    super.key,
    required this.moduleIds,
    required this.collapseRequested,
  });
}
```

Behavior:

- empty list → no control;
- collapsed → compact `Modules n` trigger;
- expanded → in-tree rounded details surface;
- module-list change resets to collapsed;
- cell/tower selection forces collapse;
- no Overlay, `MenuAnchor`, `PopupMenu`, or controller;
- rows are read-only and show existing `runModuleDefinition(id)` data:
  - title;
  - `effectText`;
  - affinity label.

Use a stable content reset token derived from the ordered module IDs, for example:

```dart
Object.hashAll(moduleIds)
```

The module widget lives in its own file; `run_module_draft_panel.dart` remains the draft panel plus report strip.

Because expansion stays inside `MissionChrome`, the later full-screen draft/report stack entries always cover it.

## Command feedback

Keep `CommandToast` behavior unchanged:

- each non-null input is a feedback event;
- identical repeated messages restart the timer;
- null does not clear a live toast;
- replacement text replaces immediately;
- timer disposal is safe;
- live-region semantics remain;
- neutral/warning/danger mapping remains;
- two-line cap remains;
- Reduced Motion removes transitions.

Restyle only its shell and place it immediately above the contextual dock.

Do not replace it with `SnackBar`.

## ReactorButton migration

The current `ReactorButton` tests encode four behavioral contracts that must not disappear if the final mission call sites are removed:

1. minimum 48dp target and one invocation per tap;
2. semantics activation calls the callback;
3. disabled semantics has no tap action;
4. long labels at extreme text scale do not overflow the compact control.

The new World Map and primary mission actions must re-assert those relevant contracts before `ReactorButton` is deleted. Deletion remains conditional on a final repository search finding no remaining call site.

Do not keep dead `ReactorButton` solely to preserve tests; migrate the contracts first, then delete code/tests only if unused.

## Module draft and Mission Report

No visual redesign is authorized for:

- `RunModuleDraftPanel`;
- `MissionReportPanel`;
- saving/saved/failed report states;
- report module list.

They stay after `MissionChrome` in the page `Stack` and continue blocking mission input.

## Parity contract

The feature has three parity questions, but only one manual live visual comparison is required.

### 1. Mock → portrait fixture

At `390 × 844`, compare the source mock's hierarchy against a deterministic Flutter build-idle fixture.

Classification: **Responsive adaptation**.

Required hierarchy:

```text
low-noise dark/cyan mission language
compact status
playable board remains dominant
pause | visible 1x/2x/3x | auto
one emphasized Start Wave action
```

Do not claim exact wide geometry or exact Oxanium typography.

### 2. Current gameplay UI → redesigned UI

Automated widget/page tests prove no existing value/action/state disappears:

- health and health thresholds;
- stage/wave/phase/credits;
- pause and `1x/2x/3x`;
- auto-start/countdown;
- World Map gating;
- eight tower cards and lock/affordability;
- L1/L2/L3 progression;
- six targeting modes;
- sell/refund and stats;
- scanner lifecycle/details;
- acquired-module effect details;
- toast lifecycle/semantics;
- blocking module draft;
- Mission Report states.

### 3. Fixture → live gameplay

The integration smoke—not a manual screenshot matrix—proves the redesigned widgets operate against a real `OrionDefenseGame`, real taps, and real phase transitions.

## Visual evidence budget

Keep evidence lightweight:

### Mandatory three-way comparison

One portrait build-idle row:

```text
source mock
390 × 844 deterministic Flutter build-idle fixture
390 × 844 live build-idle gameplay
```

This is the only required live screenshot pair.

### Fixture-only supporting captures

Capture at most these representative states at `390 × 844`:

```text
selected empty cell / tower rail
selected Level 2 tower / specialization inspector
expanded next-wave scanner
expanded Modules n details
```

Draft/report compatibility is proven by existing automated page tests; manual terminal-state screenshots are optional, not a gate.

### Landscape

Automate no-overflow/usable-control coverage at:

```text
844 × 390
932 × 430
```

No manual landscape parity capture is required. HPA-14 does not claim a landscape-specific redesign.

## Accessibility

Preserve:

- 48dp minimum touch targets;
- native segmented speed semantics;
- exact health/stage/credits semantics;
- disabled action semantics;
- tower-card and tower-inspector semantics;
- scanner semantics;
- module count/details semantics;
- command-toast live region;
- text-scale safety for compact primary actions;
- Reduced Motion through existing helpers.

## Risks

### 1. Chrome can consume board taps

The board fills the SafeArea and chrome may overlap it. Mitigation: layout-only `MissionChrome` root, compact hit targets, preserved `_routeTapToBoard`, and page/integration reachability tests.

### 2. Portrait chrome can exceed the ~89dp gutter budget

Status, toast, or dock growth can overlap the centered board. Mitigation: compact/wrapping status, shallow idle dock, bounded inspector, two-line toast, and explicit `390 × 844` geometry tests. Overlap is acceptable only when board taps outside real control bounds remain reachable.

### 3. Shared collapsible behavior can be over-generalized

`MissionCollapsible` has exactly two consumers. Mitigation: it owns only expanded state/collapse/reset/animation/hit-area release. Scanner-specific radar behavior and module-specific content remain outside.

### 4. Presentation cleanup can accidentally drop established interaction contracts

Mitigation: migrate existing tests rather than replacing them with screenshot assertions. ReactorButton contracts are explicitly re-homed before any cleanup.

## Non-goals

- No combat, balance, wave, board, tower, enemy, projectile, or terrain change.
- No campaign, persistence, reward, progression, or save-schema change.
- No global theme redesign.
- No world-map, briefing, Codex, tech-tree, settings, module-draft, or Mission Report redesign.
- No board-art replacement.
- No wide-layout-specific branch or branding.
- No orientation lock.
- No speed-cycle UX.
- No change to `OrionDefenseGame.supportedSpeedMultipliers`.
- No Overlay-based module menu.
- No generic overlay/slot/controller framework.
- No font dependency.
- No third-party golden framework.

## Acceptance criteria

The implementation is complete when:

1. The `390 × 844` build-idle fixture follows the mock's board-first hierarchy as a documented Responsive adaptation.
2. `GameWidget` still fills the mission `SafeArea`.
3. Portrait remains the primary touch-first experience; landscape has no crash/overflow and keeps usable controls without a dedicated branch.
4. Every existing mission value/action/state listed above remains visible or immediately accessible.
5. Speed remains a visible one-tap `1x/2x/3x` segmented choice.
6. Scanner and module details share one tested collapsible hit-area-release implementation.
7. Empty mission-chrome space does not consume board taps.
8. Selected-cell and selected-tower states replace idle pacing as before.
9. Module draft and Mission Report continue to block mission interaction.
10. ReactorButton is removed only after its relevant behavioral contracts are migrated and no call site remains.
11. One mock/fixture/live portrait comparison plus the small fixture-only evidence set is attached to the PR.
12. Focused tests, `test/widget_test.dart`, integration smoke, full `flutter test`, `flutter analyze`, format, and `git diff --check` pass before the implementation PR is marked ready.
