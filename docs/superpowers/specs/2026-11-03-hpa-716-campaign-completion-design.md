# HPA-716 — Campaign completion and optional-route clarity (design)

**Linear:** https://linear.app/cwchanap/issue/HPA-716  
**Status:** Revised after [PR #47 design review](https://github.com/cwchanap/orion/pull/47#issuecomment-6611270301); docs-first draft, implementation and tests on the **same PR**.  
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
2. **Micro status line below that row:** CAMPAIGN COMPLETE or ALL SECTORS SECURED when appropriate, using the existing feedback-line layout approach. No completion line for a fresh/partial campaign.
3. **Existing feedback line** below the status line when present. The utility rail follows the header in the existing Column, so it is permitted to move down as header lines appear. Do not add a new overlay or move the utility rail to a different parent.
4. **Text fitting:** clamp badge text scaling to the existing 1.3x precedent used for dense map labels, while the title is already flexible and ellipsized. Keep each status line short and ensure the title/badges/star do not overflow at 320 logical pixels with system text scale 3x. Prefer an in-place compact layout adjustment over new layout machinery if a test exposes an overlap.

The optional badge is hidden at full clear: ALL SECTORS SECURED and the existing Challenge Badge already communicate that result, saving space on narrow screens. The accessibility summary still reports optional 2 of 2. For an empty stage list, retain No stages available and never show any completion claim.

Derive main/optional totals and clear counts from the **supplied stages** and CampaignProgress.isCleared. Keep CampaignProgress.isCampaignComplete(stages) as the authoritative main completion rule. Derive fully secured from a nonempty supplied list with every stage cleared; do not reuse hasChallengeBadge as a proxy because that flag only requires optional stages.

Keep the Challenge Badge icon and tooltip driven by the existing CampaignModifiers value (not by the new header counters). Example semantics for main-complete but optional-incomplete: “Campaign complete. Main 5 of 5 stages, optional 1 of 2 stages.” Make the corresponding non-complete/full-clear summaries accurate without duplicate accessibility announcements.

**Layout acceptance:** at 320x568 and text scale 3x, the title/header badges, completion status, and utility rail must avoid Flutter overflow and must not overlap visible tappable stage-node rectangles. A header may grow vertically; “never move the rail” is **not** a valid requirement.

## Read-only stage recommendation

Add one small, deterministic query to lib/game/campaign/campaign_progress.dart:

- CampaignProgress.recommendedStage(Iterable<StageDefinition> stages) returns StageDefinition? without mutating progress, changing unlocks, or touching serialization.
- Prefer the first **unlocked (uncleared) main** stage in supplied order.
- Otherwise prefer the first **unlocked (uncleared) optional** stage in supplied order.
- Otherwise preserve the existing fallback to the **last non-locked** stage for replay.
- Return null if there is no playable stage.

This belongs next to CampaignProgress.isCampaignComplete and statusFor, and can be unit-tested without rendering a whole map. It is a simple query, **not** a new routing service or mutable campaign state.

In _MissionDestination.build, call that query. Derive its display qualifier directly from returned stage and progress status: NEXT MAIN / OPTIONAL / REPLAY (no enum). **Append** the qualifier to the existing one-line SECTOR NN kicker, e.g. “SECTOR 03 / OPTIONAL”, with ellipsis rather than a new row.

**Accessibility compatibility:** preserve the current Semantics label exactly as “Briefing for <stage name>” because test/widget/scene_parity_regression_test.dart looks it up. Put the new recommended-stage qualifier in Semantics.hint. Keep onStageSelected, its busy gating, artwork, tap target, and existing briefing navigation unchanged.

## Files and exclusions

Planned implementation changes:

- lib/game/campaign/campaign_progress.dart — pure recommendation query only; no progress-state or save changes
- lib/game/ui/world_map_view.dart — derived counters, header/status UI, qualifier/hint, call to query
- test/game/campaign_progress_test.dart — small scenario table for the recommendation query
- test/widget/world_map_command_deck_test.dart — visible copy, semantics, busy and compact layout regressions

**Read but preserve:** test/widget/scene_parity_regression_test.dart. It relies on the exact existing destination Semantics.label; no change is expected if the label stays stable.

There are **no golden screenshot comparisons** to update: captureReactorRimFixture only writes optional review PNGs when ORION_CAPTURE_DIR is set. Test the actual widget layout/semantics instead.

Do not change OrionDefenseGame, GameSession, the save codec, stage definitions, balance, medals, rewards, tech tree, existing stage nodes, feedback/audio, or settings. No new services, dependencies, persistent flags, art, SFX, or animations.

## Acceptance and regression checks

1. Table-test the read-only recommendation query for fresh, mid-campaign with an optional stage open, main complete with zero/one optional clears, all cleared, and no playable stages.
2. Widget-test each qualifier (NEXT MAIN, OPTIONAL, REPLAY), accessible hint, and the unchanged Briefing for <stage name> label.
3. Widget-test main/optional status, header semantics, Challenge Badge presence, and empty-stage behavior.
4. Add an automated **320x568 / 3x** widget layout test using **real derived CampaignModifiers.fromProgress** (not a null fixture). Pump both near-full (two header badges) and full-clear (Challenge Badge) states. Assert no Flutter layout errors and that the header and rail do not overlap visible stage-node rectangles. Reuse the current rect/semantics test patterns.
5. Verify saving/resetting still disables the footer and stage-node interactions. Existing scene-parity, compact-screen, and accessibility tests must still pass.
6. Complete dart format, flutter analyze, flutter test --coverage (Codecov >=90%) and flutter build web --release before marking this single PR ready.

## Out of scope

Endless scores/UX, gameplay balance or progression changes, new rewards, one-time celebration cutscenes, new art/SFX/music, achievements, analytics, online saves, new persistent state, generalized routing frameworks, golden-test infrastructure, or backward-compatibility work for a hobby app.
