# Orion Command Deck UI and HUD Redesign

## Context

Orion already has the complete campaign and mission interaction surfaces needed for a portrait tower-defense game, but the presentation reads as a collection of conventional Material cards, chips, and text buttons. The approved redesign changes that presentation into a cinematic, icon-led command deck while preserving the existing campaign, mission, and persistence behavior.

The redesign targets a polished mobile experience around one core flow:

1. Read the illustrated sector map.
2. Select an available stage.
3. Review its briefing and launch the mission.
4. Read the mission HUD and next-wave threat.
5. Select a build cell and place a tower from an art-led dock.
6. Select the tower and upgrade, specialize, retarget, or sell it.
7. Start the wave.

The approved visual direction is **Cinematic Command Deck**: dark industrial hull surfaces, luminous system colors, large project-owned unit art, framed apertures, reactor rings, and compact labels. It should feel like a game interface, not a dashboard or web application.

## Goal

Make the world map and mission controls more immediately readable, more visually distinctive, and more touch-friendly by making art and icons the primary carriers of information. The playfield remains dominant, essential numbers stay glanceable, and every existing game action remains reachable.

## Scope

In scope:

- Full visual redesign of `WorldMapView` and the existing stage briefing sheet.
- Full visual redesign of the mission HUD, pacing controls, next-wave preview, tower build dock, and selected-tower inspector in `OrionGamePage`.
- Reuse of the project-owned terrain, tower, enemy, effect, and boss sprite sheets in Flutter UI surfaces.
- Shared presentation tokens and reusable command-deck frame, atlas-art, stat, and toast components.
- Command-deck visual integration for `AcquiredRunModuleStrip`, `RunModuleDraftPanel`, `MissionReportPanel`, and the campaign-reset dialog, without changing their content or callbacks.
- Responsive portrait layouts for compact, reference, and large mobile widths.
- Accessibility, reduced-motion behavior, widget tests, and fixed-size local visual QA for the redesigned core flow.

Out of scope:

- Changes to campaign topology, stage unlocks, medals, rewards, blueprints, tech-tree rules, waves, economy, tower balance, placement rules, targeting rules, or combat simulation.
- Changes to `GameSession` ownership or the pure rules/Flame boundary.
- A redesign of the Codex, Tech Tree, feedback settings, module-draft content, or mission-report content. Codex, Tech Tree, and feedback settings remain on the existing `ColorScheme`; the two mission modals and acquired-module strip receive the command-deck surface treatment because they share the redesigned mission stack.
- New remote services, hosted assets, runtime downloads, or cloud dependencies.
- Landscape/tablet-specific layouts, desktop keyboard shortcuts, or controller navigation.
- New fonts or third-party icon packages.

## Design Principles

### Art first, text second

- A tower card is identified first by its tower portrait, then by a short name and cost.
- A stage is identified first by its landmark/boss portrait and route position, then by its short map label.
- Threats use enemy silhouettes and trait icons before prose.
- Text remains for exact values, ambiguous actions, accessibility, and consequential decisions. Decorative paragraphs are removed.

### The playfield owns the center

- Mission overlays stay at the top and bottom edges.
- The idle command dock collapses to the smallest useful state.
- Expanded panels have explicit maximum heights and never become full-screen during active play.
- The next-wave scanner expands into the upper-right corner and can be collapsed by the player.

### State is never color alone

- Locked, unlocked, cleared, selected, affordable, unaffordable, active, and disabled states combine color with icons, rings, opacity, labels, or shape changes.
- Credits, base health, wave progress, tower level, and costs remain numeric.
- Every icon-only action has a tooltip and semantic label.

### Game feel without visual noise

- Frames use solid or near-opaque hull surfaces, chamfered corners, subtle inner highlights, and restrained glow.
- The redesign avoids glassmorphism, generic rounded cards, excessive gradients, tiny sci-fi decoration, and thin fictional-instrumentation lines.
- Bright cyan, gold, violet, green, orange, and red are reserved for meaningful system states.

## Visual System

### Color tokens

Add an `OrionUiTheme` `ThemeExtension` and register it with the existing dark `ThemeData`. Existing screens may continue to use the current `ColorScheme`; redesigned surfaces read the extension directly. `OrionUiTheme.of(context)` supplies the same dark default when the extension is absent so standalone widgets and their existing bare-`MaterialApp` tests remain safe.

| Token | Value | Use |
| --- | --- | --- |
| `voidBlack` | `#05080D` | Screen underlay and deepest negative space |
| `hullBlack` | `#0B1118` | Main opaque command surfaces |
| `panelBlue` | `#111B25` | Raised panels and tower cards |
| `panelRaised` | `#182532` | Selected and emphasized surfaces |
| `frameSteel` | `#2E4658` | Borders, inactive rings, dividers |
| `textPrimary` | `#F4F8FB` | Essential labels and numbers |
| `textMuted` | `#8EA4B5` | Secondary labels and disabled copy |
| `systemCyan` | `#46E6FF` | Active controls, routes, selection, base systems |
| `systemCyanStrong` | `#13B8E6` | Pressed/filled cyan state |
| `creditGold` | `#FFC857` | Credits, rewards, Gold medal, upgrade affordability |
| `systemViolet` | `#A98BFF` | Advanced systems, specializations, gravity/ion identity |
| `naniteGreen` | `#7BE495` | Positive status, regeneration, recovered systems |
| `warningOrange` | `#FF8A3D` | Incoming pressure and low health |
| `dangerRed` | `#FF5D6C` | Destructive actions, errors, critical base health |

Text on command surfaces must meet WCAG AA contrast. Glow is decorative and cannot be the only outline or state indicator.

### Type

Use the platform font already supplied by Flutter. Do not add a font dependency.

- Stage/surface heading: 20–22 sp, weight 700, letter spacing 0.6.
- HUD number: 17–19 sp, weight 700, tabular figures.
- Action label: 12–13 sp, weight 700, letter spacing 0.5.
- Micro label: 10–11 sp, weight 700, letter spacing 0.9, uppercase only for short system labels.
- Body/supporting text: 12–14 sp, weight 400–500.
- No essential copy below 10 sp.

### Geometry and spacing

- Base spacing scale: 4, 8, 12, 16, and 24 dp.
- Minimum interactive target: 48 × 48 dp.
- Small frame radius: 8 dp. Large panel radius: 14 dp.
- Command surfaces use a shared chamfered frame with 8–12 dp clipped corners instead of ordinary pill/card styling.
- Panel outlines are 1 dp with a second low-opacity inner highlight where useful.
- Primary reactor buttons use concentric rings and a 64–72 dp interactive diameter.

### Motion

- Dock state transition: 180 ms ease-out fade/vertical shift.
- Scanner expand/collapse: 180 ms ease-out size/fade.
- Stage-node selection and briefing entrance: 220 ms ease-out.
- Feedback toast: 160 ms entrance, 140 ms exit, visible for 2.4 seconds.
- A subtle pulse may identify an unlocked, uncleared stage, but it must not animate continuously when reduced motion is enabled.
- With `MediaQuery.disableAnimations`, replace all movement and size animation with an immediate state change or a zero-duration fade.

## Local Art System

The first implementation uses only assets already declared in `pubspec.yaml`:

- `orion_terrain_background.png`
- `orion_sprite_sheet.png`
- `orion_tower_variety_sheet.png`
- `orion_path_tiles.png`
- `orion_boss_sheet.png`

No image is downloaded at runtime.

### Reusable atlas widget

Add a presentation-only `OrionAtlasSprite` widget backed by a small immutable art descriptor:

- asset path
- source-rectangle resolver bound to an existing sheet `sourceRectFor` helper
- semantic label
- optional fit, tint, and opacity

The widget resolves the cached asset image, asks the descriptor for the `ui.Rect` computed by the existing `GameSpriteSheet.sourceRectFor`, `GameTowerVarietySheet.sourceRectFor`, or `GameBossSheet.sourceRectFor` helper, and draws that source rectangle into the available box. It performs no row/column arithmetic of its own. The tested loader helpers remain the single owners of grid translation.

Presentation factories provide the supported mappings:

- Tower art uses one exhaustive `TowerType` switch: `GameSpriteSheet.spriteForTower` for Laser, Rocket, and Cryo, and `GameTowerVarietySheet.spriteForTower` for Railgun, Ion Chain, Nanite, Gravity Well, and Drone Bay.
- Stage art derives the final boss sprite from each `StageDefinition`'s final wave and uses the matching `BossSprite` cell in `GameBossSheet`. The campaign validator already guarantees one final boss per stage.
- Preview-group art first matches `WavePreviewGroup.label` exactly against `GameBalance.bosses.name` and uses that boss's `BossSprite`. If no boss name matches, `EnemyTrait.heavy` selects the heavy-drone cell; every other group uses the basic-drone cell. Do not parse adjectives from labels.
- Trait art reuses `shieldIndicator`, `armorIndicator`, and `regenIndicator` from `GameTowerVarietySheet`. Swarm and heavy use the same shape fallbacks already established by `EnemyOverlay`; no new trait art contract is invented.

Unknown tower and boss enum cases are compile-time exhaustive, not runtime fallback states. Only asset load/decode failure falls back to the existing `towerIcon`, stage icon, or generic enemy icon. Locked art is desaturated and darkened by the presentation layer. The source PNGs are never modified.

Flutter's image cache should own UI asset reuse. Precache the terrain, tower sheets, and boss sheet when the corresponding map or mission shell becomes active. Do not decode a new image per card rebuild.

## World Map

### Composition

`WorldMapView` remains the campaign presentation entry point and keeps its existing callbacks and busy-state contract. Its visual structure becomes:

```text
Safe area
└── Sector map stack
    ├── Full-bleed terrain image + dark space treatment
    ├── Painted nebula light, stars, and dependency routes
    ├── Compact sector header
    ├── Seven illustrated stage nodes
    ├── Right utility rail
    ├── Minimal medal legend / campaign badge
    └── Campaign feedback strip when needed
```

The terrain image uses `BoxFit.cover`, a dark navy overlay, and restrained cyan/violet radial light painted above it so it reads as a sector table rather than the in-mission floor. Stars and route glow are vector-painted and deterministic; they are not new state or a new asset.

### Map layout and routes

- Keep the authored `mapColumn` and `mapRow` coordinates as the source of node placement.
- Reserve 52 dp on the right for the utility rail and 12 dp horizontal safe padding.
- Normalize the five map columns and three rows into the remaining `LayoutBuilder` bounds. At 375 dp, the plotting width is `375 - 24 - 52 = 299` dp; placing 56 dp node envelopes between 28 dp edge insets leaves `(299 - 56) / 4 = 60.75` dp between main-path centers, so the five hit targets do not overlap.
- Paint each route from the dependency stage center to the destination center. Main-path routes are solid; optional branches use a short dash pattern.
- A route is bright cyan when its destination is unlocked or cleared, steel when locked, and gold at the destination end when the best result is Gold.
- Routes are visual only and never become independent tap targets.

### Stage nodes

Each stage node has a 48–56 dp art aperture inside a 56 × 80 dp interactive envelope, still above the 48 dp minimum target and narrow enough for all five main-path columns at 375 dp:

- Boss/landmark art fills most of the aperture.
- The short `mapLabel` sits on one line below the art.
- Locked: grayscale art, 35% opacity, steel ring, lock badge, semantic label “{stage}, locked.”
- Unlocked and uncleared: full-color art, cyan double ring, small “available” beacon.
- Cleared: full-color art plus medal ring and medal glyph.
- Clear uses cyan, Silver uses ice/white, and Gold uses `creditGold`.
- Optional stages use a diamond outer frame; main stages use a circular/octagonal frame.
- Reward stages show a small gold or health emblem without repeating the full reward sentence on the node.
- Outpost Alpha keeps a compact blueprint glyph. Its locked/recovered visual state follows committed campaign progress, and its semantics retain the current strings `Blueprint • Locked` and `Blueprint • Recovered`.

The full stage name, status, medal, reward, and Outpost Alpha blueprint state remain available through semantics and in the briefing sheet.

### Header and utility rail

The header contains the compact title “ORION SECTOR,” current campaign completion count, and the challenge badge when earned. The previous large completion and challenge cards become icon-led header badges.

The right rail contains 48 dp icon buttons for:

- Codex
- Tech Tree
- Settings
- Reset Campaign, separated at the bottom and styled as a destructive secondary action

All icons keep the existing callbacks, busy disabling, tooltips, and reset confirmation flow. Labels are exposed to assistive technology even when not visible.

### Stage briefing

Selecting an unlocked stage opens the existing modal briefing flow, redesigned as a 62–78% height command sheet. It remains scrollable on compact portrait devices.

The sheet includes:

- Large cropped boss/landmark art with stage name and main/optional route badge.
- One-line stage description.
- Threat/modifier tiles using icon, short label, and existing accepted description.
- Reward tile when present.
- Best medal and best base-health result when present.
- The committed Outpost Alpha briefing line remains exactly `Blueprint recovered: Relay Calibration`; a fresh Alpha briefing continues to omit that recovered line.
- Primary reactor-style `Launch Mission` action for a fresh stage or `Replay Mission` for a cleared stage.
- Secondary close action.

Locked-stage taps never open the sheet. They keep the existing locked-stage feedback behavior and leave the user on the map.

## Mission Overlay Layout

`OrionGamePage` keeps the current `Scaffold > SafeArea > ValueListenableBuilder<GameSnapshot> > Stack` ownership. `GameWidget` stays `Positioned.fill`; all command-deck widgets are Flutter overlays driven only by `GameSnapshot` and existing callbacks.

Layer order, back to front:

1. `GameWidget`
2. top HUD, pacing strip, acquired-module strip, and next-wave scanner
3. feedback toast and bottom command dock
4. run-module draft overlay
5. mission report/end-state overlay

The module draft and mission report remain modal and must obscure/disable the command deck exactly as they do today.

### Top-overlay hit testing

The current top column is entirely wrapped by `IgnorePointer(ignoring: true)`. The redesign must split that ownership:

- Numeric HUD anchors and the acquired-module strip remain pass-through under `IgnorePointer(ignoring: true)` so board cells beneath them keep receiving taps.
- The pacing strip and scanner are separate interactive siblings outside that wrapper. Their render boxes, not a full-width invisible parent, define the hit-test area.
- The collapsed scanner intentionally consumes only its 48 × 48 dp control area.
- The expanded scanner intentionally consumes its painted area up to 212 × 168 dp in the upper-right corner; this is a documented board dead zone while open.
- Existing widget assertions remain pass-through for numeric HUD content and are inverted only for the pacing/scanner controls.

### Top HUD

Replace the single generic HUD rectangle with three compact anchors in one 52–58 dp row:

- Left: shield-shaped base meter, base icon, current/starting health, and a horizontal health fill.
- Center: stage short label and `wave / total`; the build/wave/paused state appears as a small status beacon rather than a large phase chip.
- Right: credit emblem and current gold using tabular figures.

Health color thresholds are presentation-only:

- above 50%: cyan
- 26–50%: orange
- 0–25%: red

The center stage anchor may truncate a long stage name, but its tooltip and semantics expose the full name.

### Pacing strip

Place a centered compact strip immediately below the HUD:

- Pause/resume icon button.
- 1x, 2x, and 3x segmented controls.
- Auto-start icon toggle.
- When auto-start is counting down, the toggle shows the ceiling of the remaining seconds.

The strip uses the existing `isPaused`, `speedMultiplier`, `autoStartEnabled`, and `autoStartCountdownRemaining` fields and the existing game callbacks. Supported speeds, phase gating, reset behavior, and countdown behavior do not change.

### Next-wave scanner

When `nextWavePreview` is present, show a scanner control anchored below the HUD at the upper right.

Collapsed state:

- 48 dp radar button.
- Next-wave number and aggregate threat count in semantics/tooltip.
- A small warning beacon when the preview contains armored, shielded, regen, or heavy traits.

Expanded state, maximum 212 dp wide and 168 dp high:

- `NEXT {wave}/{total}` header and collapse action.
- Compact group rows with enemy art, count, short label, and trait badges.
- Clear bonus with gold icon.
- Recommended tower portraits when present.
- Environment/modifier icon derived from the existing stage modifiers.

The scanner is expanded on mission entry and whenever a new preview wave appears. The player may collapse it for the rest of that build phase. It is hidden during an active wave, won/lost state, or a modal module draft. Expansion state is widget-local and resets from `nextWavePreview.waveNumber`; it is not added to `GameSnapshot`. Preview portraits use the exact boss-name/heavy/basic mapping defined by the Local Art System, including Swarm Queen as boss art even though that boss does not carry the heavy trait.

## Bottom Command Dock

The bottom dock is one framed command surface whose content is selected from existing snapshot state in this priority order:

1. `selectedTower != null`: tower inspector.
2. `selectedCell != null`: build rail.
3. otherwise: idle/wave command bar.

Use an `AnimatedSwitcher` keyed by those three states. Reduced-motion mode uses zero duration. The dock respects bottom safe-area padding.

### Idle and active-wave state

The compact 72–84 dp command bar contains:

- World Map icon action on the left, preserving the current phase restriction and feedback.
- Minimal phase/status copy in the center.
- A 64–72 dp reactor-style Start Wave button on the right when `canStartWave` is true.

During an active wave, replace the start action with a non-interactive wave-progress reactor. During an auto-start countdown, the reactor displays the remaining second and remains consistent with the existing manual-start cancellation behavior.

### Build rail

When a build cell is selected, show a 128–140 dp dock with a horizontal art rail of all `TowerType.values`:

- Each card is about 64 dp wide with a square tower portrait, one-line short label, and credit icon/cost.
- At 375 dp width, at least four full cards and part or all of a fifth card remain visible; the rest are horizontally scrollable.
- Unlocked and affordable: full color, cyan frame on press.
- Unlocked but unaffordable: art is dimmed and cost is red/gold; it remains tappable so the current “not enough gold” feedback path still works.
- Locked: grayscale art, lock badge, unlock-wave tooltip/semantics, and no placement callback.
- Selected/pressed state uses a double cyan frame and scale no greater than 1.03.

Showing locked towers is a presentation change only. `snapshot.unlockedTowerTypes` remains the source of truth, and the game session remains the final placement authority.

### Selected-tower inspector

The selected-tower dock is capped at 210 dp or 31% of safe viewport height, whichever is smaller. Compact content may scroll inside the dock; the playfield itself does not move.

The inspector contains:

- 68–76 dp tower portrait.
- Tower name, level, and specialization badge.
- Damage, fire rate, and range rows with icon, resolved numeric value, and short bar.
- One type-specific resolved stat where the current UI already exposes it, such as splash, slow duration, corrosion, or drone damage.
- Icon-led targeting selector for the existing targeting modes, with visible short labels where room permits and full tooltips/semantics always.
- Upgrade action at level 1, two specialization choices at level 2, or a max-level badge at level 3.
- A visually separated Sell action with refund value and destructive styling.

All displayed combat values and upgrade/specialization costs come from `snapshot.selectedTowerStats`. The redesign removes the inspector's current second `GameBalance.towerStats` lookup. Sell refund remains sourced from the existing `GameBalance.refundValue(tower)` domain helper because it is not a `TowerStats` field.

Stat-bar fill uses a closed presentation scale per `TowerType`, derived only from `GameBalance.towerStats` for level 1, level 2, and both valid level-3 specializations:

- Damage denominator: maximum base-progression damage.
- Fire denominator: maximum base-progression shots per second (`1 / fireInterval`), so a shorter interval always produces a fuller bar.
- Range denominator: maximum base-progression range.
- Optional type-specific denominator: maximum value for the secondary metric already displayed for that tower type.

Campaign tech, stage modifiers, and run modules are deliberately excluded from these denominators. The runtime numerator is still the resolved `selectedTowerStats` value, may exceed the base-progression scale, and is clamped to a full bar. The exact resolved number always appears beside the bar. The scale catalog is derived from `GameBalance` rather than containing duplicated tuning literals, and tests cover every `TowerType` and both specializations.

Upgrade, specialization, targeting, and sell callbacks remain unchanged. Phase and affordability failures continue to be enforced by the game and surfaced as feedback.

## Feedback Presentation

Mission `snapshot.feedback` moves out of the permanent HUD and into a transient command toast positioned above the bottom dock:

- Maximum two lines and no wider than the safe viewport minus 32 dp.
- Neutral/success feedback uses cyan; affordability warnings use orange; errors use red.
- A transition to a new non-null message latches that string, shows it, and starts or restarts a 2.4-second timer.
- Subsequent null snapshots only re-arm the input so the same string can trigger again later. Null never hides the latched toast and never cancels its timer.
- The timer alone controls exit visibility. A different non-null message replaces the latched copy and restarts the timer; the same non-null message without an intervening null does not continually restart it.
- Latched message, last input, visibility, and timer state are widget-local. No feedback ID or new domain state is required.
- Dispose cancels the timer.

Campaign persistence feedback on the world map remains visible in a compact status strip until replaced or cleared; it must not disappear before the user can read a save failure.

## Responsive Behavior

Reference target: 390 × 844 logical pixels.

The design must remain usable at:

- Compact: 375 × 812.
- Reference: 390 × 844.
- Large portrait: 430 × 932.

Rules:

- All surfaces live inside `SafeArea` and honor device padding.
- No fixed width may exceed the safe viewport.
- The utility rail and stage nodes use computed map bounds rather than screen coordinates.
- Long labels use one-line ellipsis with full tooltip/semantics.
- Build cards scroll horizontally instead of shrinking below the touch target.
- The tower inspector changes from a side-by-side summary/action arrangement to stacked internal rows when the available width is below 400 dp.
- Briefing content scrolls vertically; its primary action remains reachable at 375 × 812 with text scaling at 1.3.
- At text scale 2.0, essential controls may wrap or scroll, but they must not clip, overlap, or become unreachable.

## Accessibility

- Every icon-only control has a `Tooltip` and explicit `Semantics` label, enabled/disabled state, and selected/toggled state where applicable.
- Stage semantics include full name, locked/unlocked/cleared status, medal, and reward.
- Tower-card semantics include tower name, cost, unlock state, affordability, and selected cell placement intent.
- HUD semantics read “Base {current} of {starting},” “Wave {current} of {total},” and “Credits {gold}.”
- Scanner trait icons expose the accepted trait labels, not decorative names.
- Start, upgrade, specialization, sell, reset, and launch retain visible action text because they are consequential actions.
- Focus order follows visual order: HUD status, pacing, scanner, playfield semantics where available, command dock.
- Reduced motion follows the existing app-level behavior tested with `MediaQuery.disableAnimations`.

## Architecture and State Boundaries

The redesign is presentation-only.

- `GameSession` remains unchanged.
- `OrionDefenseGame` remains the mission orchestrator and the only target of UI actions.
- `GameSnapshot` remains the complete mission rendering contract. No field is required for this redesign.
- `CampaignProgress`, `StageDefinition`, `CampaignModifiers`, medals, tech upgrades, rewards, and blueprint state remain the complete world-map contracts.
- Scanner expansion, dock animation, pressed state, and toast timing are Flutter widget-local state.
- Flutter UI never reads mutable game state directly.
- Flame components and board sizing remain unchanged; the overlay redesign must not relayout active-wave paths.
- Numeric HUD hit testing remains pass-through while pacing and scanner hit testing is intentionally interactive only within their painted bounds.

Recommended presentation boundaries:

- `orion_ui_theme.dart`: theme extension, spacing, type, and motion tokens.
- `orion_atlas_sprite.dart`: generic atlas crop and art mapping factories.
- `command_frame.dart`: shared chamfered frame and reactor treatment.
- `command_toast.dart`: transient mission feedback.
- `world_map_view.dart`: sector composition, routes, nodes, and utility rail.
- `orion_game_page.dart`: overlay orchestration and command-dock state.
- `run_module_draft_panel.dart`: command-deck presentation for draft cards and the acquired-module strip.
- `mission_report_panel.dart`: command-deck presentation for end-state content and actions.

Small private widgets may remain colocated until reuse or file size justifies extraction. Do not create a general-purpose component framework beyond these demonstrated needs.

## Busy, Disabled, and Error States

- Existing loading shells remain responsible for initial persistence loads.
- Campaign busy flags disable every map navigation or mutation callback exactly as they do today.
- Disabled controls retain at least 48 dp targets but use steel frames, muted text, and no glow.
- Locked towers and stages cannot invoke gameplay callbacks.
- Unaffordable unlocked towers may invoke placement so the game can provide its current feedback.
- Modal module draft and mission report layers prevent interaction with overlays beneath them.
- Asset load/decode failure falls back to the existing `towerIcon`, stage icon, or generic enemy icon plus semantic label; exhaustive enum mappings do not have an “unknown type” fallback.
- A null `selectedTowerStats` omits stat bars and keeps portrait/name/actions safe rather than throwing.

## Shared Mission and Map Surfaces

- `AcquiredRunModuleStrip` uses compact `OrionUiTheme` hull tokens while remaining non-interactive and pass-through in the top stack.
- `RunModuleDraftPanel` keeps its existing `Positioned.fill` modal ownership, offer copy, affinities, and callbacks. Its scrim, cards, and actions use `OrionUiTheme` and `CommandFrame`.
- `MissionReportPanel` keeps its existing `Positioned.fill` ownership, save-state logic, result copy, rewards, acquired modules, and callbacks. Its report body and actions use the same hull tokens and frames.
- The campaign-reset `AlertDialog` keeps the same confirmation and persistence behavior but uses the command-deck frame and destructive token treatment.
- Codex and Tech Tree remain full-screen replacements on their current `ColorScheme` and are not pulled into this visual slice.

## Performance

- Precache each required sheet once when its map or mission shell becomes active and render through Flutter's shared image cache. A card rebuild must not trigger another asset decode.
- `GameWidget` retains the same game instance across snapshot-driven overlay rebuilds; this is an architecture invariant rather than a request for speculative micro-optimization.

## Delivery Slices and Risks

Deliver the redesign as two independently reviewable PRs. If implementation remains local until final publication, keep the same two branch/commit review gates.

### PR 1: Local theme, art, world map, and briefing

- Add `OrionUiTheme`, `CommandFrame`, source-rect-backed atlas art/factories, and their tests.
- Redesign `WorldMapView`, dependency routes, stage nodes, blueprint glyph, utility rail, campaign feedback strip, stage briefing, and reset dialog.
- Update intentionally changed copy/finders in the same PR, including `Orion Sector Map` → `ORION SECTOR` and fresh-stage `Start Mission` → `Launch Mission`.
- Run focused component/widget tests, full `flutter test`, `flutter analyze`, and screenshot QA at all three portrait sizes before review.

### PR 2: Interactive mission chrome and modal integration

- Split pass-through numeric HUD/acquired modules from interactive pacing/scanner hit-test regions.
- Add the three-anchor HUD, pacing strip, scanner state and preview art mapping, three-state dock, resolved-stat inspector/scales, and latched toast.
- Restyle acquired modules, module draft, and mission report without changing their content or callback contracts.
- Update intentionally retired copy/finders in the same PR, including the old `Gold 150`, `Base 20`, `Wave 1/8`, `Next Wave 1/8`, and `Build Tower` presentation finders. Prefer stable keys and semantics for the new icon-led contracts.
- Run focused component/widget tests, full `flutter test`, `flutter analyze`, and screenshot QA at all three portrait sizes before review.

| Risk | Required mitigation and runnable checkpoint |
| --- | --- |
| Interactive top controls block board taps | Keep HUD/acquired modules under `IgnorePointer`; test that pacing/scanner are interactive and numeric HUD remains pass-through; test the expanded scanner's intentional dead zone. |
| Null snapshots erase a toast immediately | Widget-test that a non-null message remains visible after a null republish and exits only after 2.4 seconds. |
| Atlas UI drifts from Flame crop math | Factories call the existing `sourceRectFor` helpers; test every tower, every boss, boss-name preview matching, heavy/basic fallback, and asset-load fallback. |
| Five map nodes overlap beside the rail at compact width | Pump 375 × 812 and assert distinct 56 dp hit rectangles, in-bounds centers, and successful taps for each main-path node. |
| Blueprint progress disappears in an art-led node | Keep locked/recovered glyph semantics and the committed briefing line; preserve the existing reset regressions. |
| Modal Material cards clash with the command deck | Include acquired strip, module draft, mission report, and reset dialog in their owning PR and test their token/frame use. |
| Text-based widget finders fail for intentional copy changes | Update finders in the same PR as each copy change and replace presentation-only text assertions with keys/semantics where appropriate. |

## Testing Strategy

Preserve the existing behavioral tests and update text/finders only where visible copy intentionally changes. Add focused widget coverage for the new presentation contracts.

### Art and shared components

- Every `TowerType` resolves through the correct existing sheet mapping and `sourceRectFor` helper.
- Every campaign stage resolves to its final `BossDefinition.sprite` through `GameBossSheet.sourceRectFor`.
- A preview group whose label exactly matches each `GameBalance.bosses.name` resolves to that boss; a non-boss heavy group resolves to the heavy drone; another non-boss group resolves to the basic drone.
- Armor, shield, and regen badges resolve to the existing variety-sheet indicator cells; swarm and heavy use the established shape fallbacks.
- An asset load/decode failure renders the icon fallback.
- Atlas cards render without overflow at 64 dp and do not create one asset decode per rebuild.
- Command frames and reactor buttons expose the expected semantic labels and minimum tap bounds.

### World map and briefing

- Seven stage nodes render from the campaign list at compact and large portrait sizes without overflow.
- Locked, unlocked, Clear, Silver, and Gold states expose distinct icon/ring/semantic states.
- Route painting follows `unlockDependencies`, including both optional branches.
- At 375 × 812, all five main-path hit rectangles are distinct, in bounds, and individually tappable beside the 52 dp rail.
- Locked tap shows feedback and does not open a briefing.
- Unlocked tap opens the correct briefing.
- Outpost Alpha exposes `Blueprint • Locked` or `Blueprint • Recovered` semantics from committed progress, reset returns it to locked, and the briefing retains the committed `Blueprint recovered: Relay Calibration` line.
- Briefing retains stage description, modifiers, reward, best result, blueprint state, launch/replay callback, and compact scrolling behavior.
- Busy state disables stage nodes and utility actions.
- Codex, Tech Tree, Settings, and Reset callbacks remain wired.
- Reset confirmation uses command-deck tokens without changing confirmation or persistence behavior.

### Mission HUD and scanner

- HUD shows base current/maximum, credits, stage, phase beacon, and wave progress from a snapshot.
- Low and critical health states use the correct icon/color state without changing the numeric value.
- Pause, 1x/2x/3x, auto-start, and countdown states remain selectable and correctly labeled.
- Numeric HUD and acquired-module content retain an active `IgnorePointer(ignoring: true)` ancestor; pacing and scanner controls do not.
- Tapping through numeric HUD reaches the game layer, while the collapsed scanner consumes only 48 × 48 dp and the expanded scanner consumes its documented painted bounds.
- Scanner expands on a new preview, collapses on tap, resets for the next preview, and hides during waves or modal drafts.
- Preview group counts, traits, clear bonus, recommendations, and environment remain discoverable through visible UI or semantics.

### Command dock

- Idle, selected-cell, and selected-tower snapshots select the correct dock state and priority.
- Build rail shows all tower types, with unlocked, locked, affordable, and unaffordable presentation.
- Locked cards do not invoke placement; unaffordable unlocked cards keep the existing feedback path.
- Horizontal rail and selected-tower inspector do not overflow at 375 × 812, 390 × 844, or 430 × 932.
- Inspector uses `selectedTowerStats` for damage, fire, range, and type-specific values.
- Inspector upgrade/specialization copy and enabled states use `selectedTowerStats.upgradeCost` and `selectedTowerStats.specializationCost`; the old extra base-stat lookup is absent.
- Presentation scales cover every tower type, level 1, level 2, and both level-3 specializations, exclude campaign/stage/run modifiers, normalize fire as shots per second, and clamp resolved values above the base maximum.
- Targeting selection, upgrade, both specialization choices, max state, and sell remain wired.
- Acquired modules, module draft, and mission report use command-deck tokens/frames; the modal overlays remain above and block the dock.

### Feedback, accessibility, and motion

- Mission feedback appears as a toast, remains latched through a null republish, hides only after 2.4 seconds, replaces/restarts for a different message, does not restart for an uninterrupted duplicate, cancels its timer on dispose, and can show the same message again after a null snapshot.
- Campaign save feedback remains readable on the map.
- Icon controls have tooltips and semantic labels.
- Interactive bounds are at least 48 × 48 dp.
- Reduced motion makes sheets, dock changes, scanner changes, toast changes, and node-state changes immediate.
- Text scale 1.3 passes the compact core flow; text scale 2.0 keeps essential actions reachable.

After each delivery PR, complete local simulator screenshot QA at 375 × 812, 390 × 844, and 430 × 932 for that slice's surfaces. PR 1 covers the world map and briefing. PR 2 covers the HUD, scanner collapsed/expanded states, all three dock states, module draft, and mission report. The repository has no golden-test harness today, so the initial implementation should not introduce one solely for this redesign. Behavioral widget assertions remain the automated contract; checked-in goldens can be considered later if the project adopts a stable cross-platform golden pipeline.

Verification commands:

```bash
dart format .
flutter analyze
flutter test
```

## Acceptance Criteria

- The world map reads as an illustrated branching sector rather than a grid of text cards.
- All seven stages use local project-owned art and preserve locked/unlocked/cleared and Clear/Silver/Gold behavior.
- Stage briefings remain complete and launch the same campaign stages with the same modifiers, rewards, results, and blueprint behavior.
- Outpost Alpha retains a compact locked/recovered blueprint glyph and the existing committed blueprint briefing contract.
- The mission playfield remains the dominant surface and is not relaid out by overlay state changes.
- Numeric HUD and acquired-module content remain tap-through; pacing and scanner controls are interactive only inside their visible bounds.
- Base health, credits, stage/wave, pacing, auto-start, and next-wave threat are readable at a glance.
- Selecting a build cell opens an art-led horizontal tower dock using the existing tower sheets.
- All tower types are visible; unlock and affordability states are unambiguous and existing placement rules remain authoritative.
- Selecting a tower exposes its resolved stats, targeting, upgrade/specialization, and sell actions without changing their behavior.
- Inspector combat values and upgrade/specialization costs come from `selectedTowerStats`; bars use the documented modifier-free base-progression scales.
- Mission feedback latches across null snapshot republishes, exits on its timer, and does not consume permanent HUD space; campaign persistence errors remain readable.
- Acquired-module, module-draft, mission-report, and reset-confirmation surfaces use the command-deck tokens without changing their content or callbacks.
- Codex, Tech Tree, Settings, Reset, module draft, mission report, replay, and return-to-map flows continue to work.
- The core flow is polished and usable at 375 × 812, 390 × 844, and 430 × 932 with 48 dp touch targets, accessible semantics, and reduced-motion support.
- No cloud service, hosted image, runtime network request, or new gameplay state is introduced.
