# HPA-699 — Arcade Command Deck UI Revamp (Design Spec)

Date: 2026-11-06  
Linear: https://linear.app/cwchanap/issue/HPA-699/orion-revamp-the-game-ui-so-it-looks-like-a-real-game  
Repository: cwchanap/orion  
Status: Proposed, documentation-only draft; implementation belongs in this same PR.

## Outcome and source of truth

Turn Orion's portrait Flutter/Flame UI from translucent utility-style panels into a cohesive, legible arcade command deck. This is a presentation redesign across the entire existing game, not a product-feature, game-balance, campaign-data, or persistence change.

The Linear ticket's eight screen mockups, design-kit image, and attached HTML archive (especially kit.css and board.js) are the visual acceptance reference. Extract exact color/gradient/shadow/spacing values from that archive during implementation; do not guess or re-create approximate CSS values. The **existing game state and actual rules win** wherever visual mock data disagrees with the game.

This spec explicitly supersedes the **visual system** from the older 2026-09-08 UI Revamp Foundation and the blur-tier art direction. Keep useful architecture (ThemeExtension, OrionTypography, current view switch, sprite/backdrop pipeline, snapshot-driven UI); retire its translucent surface tiers and blur-budget tripwires instead of preserving compatibility layers.

## Verified baseline

- The app opens to _ShellView.worldMap in lib/game/ui/orion_game_page.dart; the same page already switches among worldMap, techTree, codex, and stage. No router is needed.
- OrionUiTheme in lib/game/ui/orion_ui_theme.dart is a single ThemeExtension with the current cyan-centric palette. orion_theme_data.dart and orion_typography.dart already provide the theme and local Oxanium/Chakra Petch faces.
- lib/game/ui/orion_surface.dart currently uses OrionSurfaceTier t1–t4 with BackdropFilter. mission_surface.dart and numerous screens consume those tiers.
- WorldMapView owns the sector plot, crest artwork, routes, header, mission destination, and a utility rail containing Codex/R&D/Reset/Settings. Reset is implemented in OrionGamePage; settings currently live in FeedbackSettingsSheet.
- MissionChrome, MissionStatusHud, MissionPacingControls, MissionCommandDock and TowerBuildRail own battle chrome. The tower rail already supports horizontal scrolling and dragging; reuse its input behavior rather than rebuilding placement logic.
- TowerInspector is a scrollable sheet with six targeting modes in a horizontal row, progression previews, and sell callbacks; TowerRadialActions lives in mission_chrome.dart.
- TechTreeView renders five **independently purchasable** upgrades in positioned rows without dependency edges. CampaignTechTree.canPurchase only checks ownership and medal budget.
- CodexView already has a working search field and section navigation (HPA-753); retain those behaviors and scroll/focus fixes.
- BoardComponent draws path, lane, build previews and spawn/base markers; BoardBackdropComponent draws the existing art; EnemyComponent paints sprites and overlays. Existing game geometry and combat authority remain untouched.
- Existing UI regression/capture helpers live under test/widget/ and test/support/reactor_rim_visual_capture.dart.
- HPA-715 Endless Mode **already shipped on `main`** in PR #46 (merged 2026-11-08). Cleared-stage briefings expose the separate Endless run and committed best; HUD/scanner support unbounded waves, and Endless defeat reports have separate save/replay semantics.
- MissionReportPanel's existing return action is **World Map** (`onReturnToMap`), not a next-briefing Continue. FeedbackSettingsSheet keeps sound/music/haptics in a local `_draft`, currently committed only by Done.

## Visual language and design-system boundaries

1. **Semantic colors, one source:** extend OrionUiTheme with the kit's semantic roles: amber = one dominant action per surface, cyan = selection/information, gold = credits, violet = R&D/specializations, green = gains, orange = modifiers, red = danger, bronze/silver/gold = medals. Retain the existing base tokens where correct, with exact new values from kit.css. UI widgets consume theme roles; eliminate raw palette/gradient values in game UI.
2. **Type:** Oxanium for dominant numeric readouts/headlines and Chakra Petch for legible labels and fallback glyphs. Labels must be at least 10 logical pixels in the intended normal-scale layout. Arrow in comparisons must render using a known font containing U+2192 or an icon; never use a missing Oxanium glyph. Preserve real copy for semantics; do not encode all-caps as accessible labels.
3. **Surfaces:** solid framed panels with lit top edges, restrained corner brackets and intentional depth. Remove blur and the translucent tiers; avoid a universal framework of style variants. The existing sprite/backdrop art remains visible behind, not through, the panels.
4. **Actions:** one amber primary action per decision surface; secondary cyan and destructive red. A small shared button applies an offset/lip/shadow press state (90ms when motion is allowed), disabled and loading states, and adequate hit areas. Do not duplicate interaction semantics or overlay a second button on top of an existing callback.
5. **Kit:** a pragmatic handful of reused widgets for button, solid panel/card, chip/tag, stat bar, segmented control, menu tab bar, HUD top bar, medals and modal sheet. Split only where two or more real screens benefit; avoid a generic configuration/DSL/theme engine. Replace old components in place when simpler.
6. **Motion:** use existing orionMotionDuration and reduced-motion preferences. Animations are decorative, not required to perceive state. Maintain 48dp-ish targets for controls and deliberate focus/semantics order.

## Scene contract

### A. Title / menu shell

- Add _ShellView.title and make it the initial post-load view. Text-styled Orion wordmark and existing backdrop art; no new image asset.
- Deterministically choose the first unlocked, uncleared main-path mission as the **title-screen Continue** destination, opening its existing briefing rather than starting combat directly. On first launch this is Outpost Alpha. On full main-path completion, display a completed-state action leading to Sectors rather than a misleading next mission. **Title Continue is unrelated to the Mission Report's World Map action.**
- A single menu shell owns the top resource chips, Settings entry, and bottom Map / R&D / Codex tabs. Title provides direct shortcuts. Keep the current enum-based page switch; no Navigator router, parallel app state or persistent tab cache.
- Move Reset Campaign out of the map's four-icon rail and into Settings, retaining the existing confirmation, saving gates and reset action. No reset icon remains in the sector map. On Reset, return the current sound/music/haptics draft and reset intent to the page, persist changed preferences **before** invoking the existing reset confirmation, and do not open confirmation if that save fails. If confirmation is cancelled, already-saved preferences remain saved; ordinary sheet dismissal without Done/Reset still discards the draft. Avoid a second preference-persistence path.

### B. Sector map and briefing

- Reuse SectorMapLayout and the seven existing stage crests. Visualize cleared / next available / side-route / locked states with gold / cyan pulse / violet / muted lock treatments; medal pips and readable numbered labels; clearer routes.
- Keep world-map scrolling/tap geometry, unlock calculation, campaign-completion copy and destination-card behavior. A mission card shows a clear Deploy action and opens the existing briefing.
- StageBriefingSheet receives a new visual treatment only: identity, difficulty, reward, modifiers, and deployment remain sourced from committed campaign progress, with current tutorial-tip behavior intact. On **cleared stages**, retain the existing Replay Mission / Endless choices, the committed Endless best, and each button's `RunMode` result; locked or uncleared stages must not gain Endless access.

### C. Battle HUD, dock and board

- One framed top status area combines hull, wave and phase label, and credits. Never obscure the playable board with redundant surfaces. For Endless snapshots (`missionWaveTotal == null`), retain an **unbounded** wave readout and accessible Endless label; never render a finite denominator from the stage's scripted wave count.
- One source of pause/speed/auto callbacks is presented near the board; build uses a compact pacing presentation and wave phase may render speed as kit-style segments. Avoid duplicate active controls in HUD and dock.
- Build phase has pre-wave enemy intel beside a prominent Start action and a **single horizontal scrollable row** of all towers, showing cost, unaffordable, and unlock-wave states. Preserve tap, press-drag, selection and guide-anchor mechanics, including first-mission onboarding.
- Wave phase instead emphasizes progress, hostiles remaining, clear bonus, auto and speed states. Do not invent counts; consume GameSnapshot and existing scanner/readout models. Endless scanner previews must continue showing their actual unbounded wave number, enemy composition and **health-scaling copy** from existing preview data; never fall back to finite-stage totals or invented scaling. Preserve Endless auto/pause/speed behavior and its suppression of first-mission tutorial guidance.
- Move the Exit to Map entry into a pause menu. Keep existing save/result guards and current pause/return semantics.
- BoardComponent paints a darker, vignetted field and a readable illuminated route with flow chevrons; enlarge the drawn silhouettes of spawn/core/enemies as the attached board.js prescribes. **Do not alter** BoardLayout, enemy positions, hit areas/radii, targeting, timing, path cells, collisions or any game rules. Check sprite, hit bar, trait overlay and tap alignment after visual scaling.

### D. Tower sheet / radial / report

- Restyle TowerRadialActions, preserving radial activation and interactions. TowerInspector header contains Close and the current Sell action; if selling currently requires a hold gesture, preserve the protection. Six targeting choices are a visible 3-by-2 grid, not a horizontally clipped list.
- Show clear current-to-next stat bars and upgrade/specialization cards with accurately computed values and price/disabled states. The sheet is bounded by available height and scrolls its content, not its footer action offscreen.
- MissionReportPanel uses existing victory/defeat hero art, a clear outcome ribbon, code-drawn medals **only when a medal exists**, stat/reward cards and Replay/**World Map** actions. Preserve committed save-state gating, retry behavior, blueprint copy and campaign progression. **Do not add next-stage navigation here.**
- **Report action/state contract** (the existing `onReturnToMap` invokes `_returnFromMissionReport`, then the map; even a fully completed campaign returns to the map):

  | Report state | Visible actions and destination |
  |---|---|
  | Normal defeat | **Retry** restarts the same mission; **World Map** returns to the sector map. |
  | Mission victory, saving | **Replay Mission** and **World Map** stay disabled until the save settles. |
  | Mission victory, saved | **Replay Mission** restarts the same mission; **World Map** returns to map (not the next briefing). |
  | Mission victory, failed | **Retry Save** retries persistence; **World Map (Unsaved)** returns with the existing unsaved-result warning, while Replay stays unavailable. |
  | Endless defeat, saving | **Replay Endless** and **World Map** are disabled until the best-save settles. |
  | Endless defeat, saved (including zero-wave "No result to save") | **Replay Endless** starts another Endless run; **World Map** returns to map. Show waves **cleared**, prior/saved best and save message; no medals, R&D points or campaign rewards. |
  | Endless defeat, failed | **Retry Save** retries the best save; **World Map (Unsaved)** returns with current best-save failure/retained-best feedback; Replay stays unavailable. |

- Keep text-arrow rendering safe. Do not substitute screenshots or raw mockup numbers for live stats.

### E. R&D, Codex and smaller surfaces

- TechTreeView displays a legible visual network of hex nodes and connector/conduit lines, plus a bottom detail panel with Research action. **Those lines are decorative grouping, not prerequisite edges:** the five upgrades are currently independent, so the UI must not claim that one purchase unlocks another. Preserve point-bank arithmetic and current available/owned/locked-by-budget states. A real dependency tree would require a separate gameplay ticket.
- CodexView presents single-row section tabs, sprite tile grids and details with readable stat bars/specializations. Retain HPA-753 search terms, clear button, per-tab scroll restoration, keyboard focus and empty state.
- Apply the same solid tokens to FeedbackSettingsSheet, CommandToast, first-mission guide, contextual tips, module-draft panel, next-wave scanner, and other remaining UI surfaces. Do not rebuild their logic.

## Integration / exclusions

- **One PR for HPA-699**: this docs-only draft grows into the sole implementation PR after review. Implementation can use multiple logical commits, not multiple pull requests.
- HPA-715 Endless Mode is **already merged on `main`** (PR #46, 2026-11-08). The HPA-699 restyle must preserve its existing briefing, HUD/scanner, wave-health scaling, record-save statuses and medal-free Endless loss report. This is regression preservation, **not** implementing or redesigning Endless rules or persistence. Base implementation on current `main`; keep it in the same HPA-699 PR.
- Do not add art, SFX, packages, navigation infrastructure, campaign data, persistence migrations, rebalance, or orientation/tablet layouts. If a future review establishes that a new logo/medal/board asset is essential, create a **separate art-only ticket** instead of embedding asset generation in this code task.
- Remove obsolete blur widgets, compatibility adapters, palette literals and tests in the same implementation PR. Historical docs remain historical; do not modify them.

## Acceptance and evidence

- Compare every ticket mockup (title, map, build, combat, inspector, report, R&D, Codex) and the remaining sheets against its reference at **390×844**; verify **360×640** for clipping and touch/focus reachability. Safe areas and software keyboard are part of layout.
- Normal label sizing is at least 10 logical pixels, dominant action hierarchy is obvious, all glyphs render, every input remains reachable, and controls reflect real disabled/locked/saving state.
- No BackdropFilter in game UI and no live uses of OrionSurfaceTier. All game UI palette roles resolve via OrionUiTheme / kit primitives; update design-system tripwires to test the **new** rules, not old blur counts.
- Confirm stage selection, cleared-stage Endless launch/best, briefing, build/tower drag, pause/auto/speed, unbounded Endless HUD/scanner/health-scaling copy, tutorial anchors, radial and targeting, settings toggle → Reset (cancel/confirm/save failure), Codex search, R&D purchase, and mission/Endless report replay/map/save gates behave identically. Include a completed-campaign victory still returning to World Map.
- Run dart format, flutter analyze, flutter test, and CI. Capture **before + after** images for every scene, including a cleared-stage Endless briefing, an unbounded Endless HUD/scanner and an Endless defeat report, not just a single happy-path board. The review PR remains a draft until the screenshots and green checks exist.
