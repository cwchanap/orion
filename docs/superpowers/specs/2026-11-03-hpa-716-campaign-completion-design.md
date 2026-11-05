# HPA-716 — Campaign completion and optional-route clarity (design)

**Linear:** https://linear.app/cwchanap/issue/HPA-716  
**Status:** Revised after [PR #47 design review](https://github.com/cwchanap/orion/pull/47#issuecomment-6611270301) and the follow-up code review of the first implementation; docs describe the as-built layout.  
**Scope:** Read-only campaign recommendation and existing world-map presentation.

## Problem and decision

Orion has five main stages and two optional stages. CampaignProgress.isCampaignComplete intentionally treats five main-stage clears as campaign completion, yet the world-map badge currently shows a combined 5/7. The footer prefers an unfinished main stage but falls back to a cleared stage even when an unlocked optional stage remains unfinished.

**Decision:** Clarify main-vs-optional progress in the existing map header and suggest unfinished optional content after the next-main priority. Keep the seven stage nodes and their unlock and reward rules exactly as they are.

This work is independent of [HPA-715 Endless Mode](https://linear.app/cwchanap/issue/HPA-715).

## Player states

| Saved campaign | Visible header | Destination |
| --- | --- | --- |
| Fresh | MAIN 0/5 | Outpost Alpha: NEXT MAIN |
| Alpha and Nebula cleared; optional route unlocked | MAIN 2/5 | Asteroid Foundry: NEXT MAIN |
| Five main cleared, neither optional cleared | CAMPAIGN COMPLETE; MAIN 5/5; OPTIONAL 0/2 | Salvage Rift: OPTIONAL |
| Five main plus Salvage Rift cleared | CAMPAIGN COMPLETE; MAIN 5/5; OPTIONAL 1/2 | Void Bastion: OPTIONAL |
| All seven cleared | ALL SECTORS SECURED; MAIN 5/5; Challenge Badge (optional 2/2 in semantics; redundant visual OPTIONAL badge hidden) | Singularity Core: REPLAY |

The suggested destination never restricts direct stage-node selection. The distinction between **campaign complete** (main route) and **all sectors secured** (all supplied stages) must remain explicit.

Use **OPTIONAL** consistently on the world-map badge, footer qualifier, and existing briefing badge. Do not introduce a new player-facing synonym such as SIDE or SIDE ROUTE.

## Concrete header layout

Use the existing _SectorHeader and _HeaderBadge in lib/game/ui/world_map_view.dart:

1. **Title row:** globe icon, flexible/ellipsized ORION SECTOR title, gold/cyan **MAIN x/5** badge (reusing the existing campaign-complete icon), and violet **OPTIONAL y/2** _HeaderBadge only when the main campaign is complete **and** optional stages remain. Keep the existing earned Challenge Badge star in its current conditional position.
2. **Micro status line below that row:** CAMPAIGN COMPLETE or ALL SECTORS SECURED when appropriate, using the existing feedback-line layout approach. Wrap this decorative status row in `ExcludeSemantics` so a screen reader does not hear the completion announcement twice; only the unified progress `Semantics` summary on the title-row badges announces it. No completion line for a fresh/partial campaign.
3. **Fixed-height feedback slot** below the status line: the header always reserves space for one feedback line, rendering the text only when feedback is present. Feedback appearing or clearing must never resize the header or move the stage nodes (transient text previously shifted the whole plot ~17px and could reset its scroll position). The feedback row keeps its own semantics and the 1.3x scale clamp.
4. **Fixed header, scrolling content:** the title row, badges, status line, feedback slot and utility rail are fixed chrome at the top of the view. Only the region below them — the star chart followed by the destination footer — scrolls vertically, so locked-stage and save/reset feedback and the Codex/Tech Tree/Reset/Settings controls stay on screen at every scroll offset.
5. **Text fitting:** clamp badge text scaling to the existing 1.3x precedent used for dense map labels, while the title is already flexible and ellipsized. Keep each status line short and ensure the title/badges/star do not overflow at 320 logical pixels with system text scale 3x.

The optional badge is hidden at full clear: ALL SECTORS SECURED and the existing Challenge Badge already communicate that result, saving space on narrow screens. The accessibility summary still reports optional 2 of 2. For an empty stage list, retain No stages available and never show any completion claim.

Derive main/optional totals and clear counts from the **supplied stages** and CampaignProgress.isCleared. Keep CampaignProgress.isCampaignComplete(stages) as the authoritative main completion rule. Derive fully secured from a nonempty supplied list with every stage cleared **and** at least one optional stage present (`optionalTotal > 0`); do not reuse hasChallengeBadge as a proxy because that flag only requires optional stages. A campaign supplied with only main stages must show CAMPAIGN COMPLETE at full clear — never ALL SECTORS SECURED — and the unified semantics summary must omit the optional clause rather than announcing "optional 0 of 0".

Keep the Challenge Badge icon and tooltip driven by the existing CampaignModifiers value (not by the new header counters). Wrap the main and optional progress badges in **one** `Semantics` node with a single summary, e.g. “Campaign complete. Main 5 of 5 stages, optional 1 of 2 stages.” Suppress the new micro-status line's default text semantics with `ExcludeSemantics` (but leave the existing feedback message independently accessible). Make non-complete/full-clear summaries accurate, including optional 2 of 2 at full clear; the completion text must not create a second announcement.

**Layout acceptance:** at 320x568 and 568x320 with text scale 3x, the title/header badges, completion status, feedback slot, and utility rail must avoid Flutter overflow and must not overlap the visible portions of tappable stage-node rectangles. The fixed header plus rail stays on screen while the chart scrolls; at these sizes the footer starts below the fold and must be reachable by a real drag anywhere on the chart (no thin scroll strip).

## Scrolling chart region

The first implementation nested the plot's own vertical scroll view inside the whole-sheet scroll view: a drag on the chart never reached the outer scroll, so on short windows the footer was unreachable (at 568x320/3x its action sat 60+ px below the screen edge), the whole map bounced/stretched even with nothing to scroll, and the header scrolled away with its feedback and controls. The as-built structure instead:

- One vertical `SingleChildScrollView` (`primary: false`) sits below the fixed header and contains a `Column` of `[chart, footer]` with `MainAxisAlignment.spaceBetween`, inside a `ConstrainedBox(minHeight: regionHeight)` so the footer still rests at the bottom when content is short.
- The region uses `ClampingScrollPhysics` plus a `ScrollConfiguration` whose behavior draws no overscroll indicator, so edge drags at zero extent are inert instead of bouncing/stretching the whole map.
- The chart keeps its horizontal `SingleChildScrollView` when layout width exceeds the region; vertical and horizontal gestures resolve to different scrollables.
- The chart's plot height is `max(regionHeight - footerReserve, SectorMapLayout.minContentHeight)` — content always exceeds the region when scrolling is needed and never scrolls when it is not. `minContentHeight` (top/bottom insets + node height + the larger of the anchor span and the unanchored-row span) prevents node overlap; there is no intrinsic-height or fixed-height-child trick.
- `SectorMapLayout` fits the stage anchors' own min/max `dy` into the plot's inset frame (normalized t within `plotTopInset..plotTopInset+nodeSpan`) instead of the old fixed `-184` offset, and gives unanchored stages the same fitted frame with row spacing floored at one node height, so they can no longer pile at a single y.

## Read-only stage recommendation

Add one small, deterministic query to lib/game/campaign/campaign_progress.dart:

- CampaignProgress.recommendedStage(Iterable<StageDefinition> stages) returns StageDefinition? without mutating progress, changing unlocks, or touching serialization.
- Prefer the first **unlocked (uncleared) main** stage in supplied order.
- Otherwise prefer the first **unlocked (uncleared) optional** stage in supplied order.
- Otherwise preserve the existing fallback to the **last non-locked** stage for replay.
- Return null if there is no playable stage.

This belongs next to CampaignProgress.isCampaignComplete and statusFor, and can be unit-tested without rendering a whole map. It is a simple query, **not** a new routing service or mutable campaign state.

In _MissionDestination.build, call that query. Derive its display qualifier directly from returned stage and progress status: NEXT MAIN / OPTIONAL / REPLAY (no enum). **Append** the qualifier to the SECTOR NN kicker, e.g. “SECTOR 03 / OPTIONAL”, using `' / '` as a separator. The current `OrionText.micro` does **not** expose `maxLines` or `overflow`; render this kicker as ordinary `Text` with `style: OrionTypography.microLabel(color: theme.systemCyan)` and `overflow: TextOverflow.ellipsis`. The kicker permits **two** lines clamped to the 1.3x dense-map scale (`maxLines: 2`): at 3x system text a single ellipsized line dropped the qualifier — the informative part — inside the ~110px footer column. Two clamped lines keep the whole string painted without letting the footer grow unboundedly; a widget test lays the kicker out with a real `TextPainter` and asserts `didExceedMaxLines` is false. Do not modify the shared typography component just for this usage.

**Accessibility compatibility:** preserve the current Semantics label exactly as “Briefing for [stage name]” because test/widget/scene_parity_regression_test.dart looks it up. Put the new recommended-stage qualifier in Semantics.hint. Keep onStageSelected, its busy gating, artwork, tap target, and existing briefing navigation unchanged.

## Files and exclusions

Implementation changes:

- lib/game/campaign/campaign_progress.dart — pure recommendation query only; no progress-state or save changes
- lib/game/ui/world_map_view.dart — derived counters, fixed header/status UI, reserved feedback slot, single chart+footer scroll region, qualifier/hint, call to query
- lib/game/ui/sector_map_layout.dart — anchor-fit positioning, shared unanchored baseline, `minContentHeight`; stage-node anchors, sizes and routes unchanged
- test/game/campaign_progress_test.dart — small scenario table for the recommendation query
- test/widget/world_map_command_deck_test.dart — visible copy, semantics, busy and compact layout regressions with realistic derived modifiers, non-null feedback, and real fonts; scroll-reachability checks on the real down-axis scrollable

**Read but preserve:** test/widget/scene_parity_regression_test.dart. It relies on the exact existing destination Semantics.label; no change is expected if the label stays stable.

There are **no golden screenshot comparisons** to update: captureReactorRimFixture only writes optional review PNGs when ORION_CAPTURE_DIR is set. Test the actual widget layout/semantics instead.

Do not change OrionDefenseGame, GameSession, the save codec, stage definitions, balance, medals, rewards, tech tree, existing stage nodes, feedback/audio, or settings. No new services, dependencies, persistent flags, art, SFX, or animations.

## Acceptance and regression checks

1. Table-test the read-only recommendation query for fresh, mid-campaign with an optional stage open, main complete with zero/one optional clears, all cleared, and no playable stages. The existing synthetic seven-stage list ends in `side-b`, so its all-clear replay fallback must return `side-b`; add a separate real `OrionCampaign.stages` assertion for `singularity-core` (the production list's final stage).
2. Widget-test each qualifier (NEXT MAIN, OPTIONAL, REPLAY), accessible hint, the unchanged `Briefing for [stage name]` label, and a single non-duplicated campaign-progress announcement.
3. Widget-test main/optional status, header semantics, Challenge Badge presence, and empty-stage behavior.
4. Add automated **320x568 and 568x320 / 3x** widget layout tests. **Load actual fonts first** with `await tester.runAsync(loadRealFonts)` and pass **production-like `CampaignModifiers.fromProgress`** (not a null fixture). Pump both near-full (two header badges) and full-clear (Challenge Badge) states, including **non-null feedback** in at least the longest header scenario. Assert no Flutter layout errors; check header/rail rects only against the **visible portions** of stage-node rects inside the scroll viewport (off-screen rects pass vacuously). Prove a real drag on the chart scrolls the single down-axis scrollable to the bottom extent and reveals a functional, tappable footer that does not cover Outpost Alpha's hit target; then verify the fixed header and utility controls remain on screen.
5. On a common portrait size (390x844), assert the down-axis scrollable reports `maxScrollExtent == 0` and a real drag leaves the position at zero (no wasted scroll); assert a full cycle of transient feedback appearing and clearing never moves a stage node's rect.
6. Verify a main-only supplied stage list clears to CAMPAIGN COMPLETE with no optional clause in semantics. Verify saving/resetting still disables the footer and stage-node interactions. Existing scene-parity, compact-screen, and accessibility tests must still pass.
7. Complete dart format, flutter analyze, flutter test --coverage (Codecov >=90%) and flutter build web --release before marking this single PR ready.

## Out of scope

Endless scores/UX, gameplay balance or progression changes, new rewards, one-time celebration cutscenes, new art/SFX/music, achievements, analytics, online saves, new persistent state, generalized routing frameworks, golden-test infrastructure, or backward-compatibility work for a hobby app.
