# HPA-716 — Campaign completion and optional-route clarity (implementation plan)

> **One Linear ticket, one PR.** Update the design and plan in this draft PR, then implement and test in **the same PR** after design approval. No separate implementation PR.

**Linear:** https://linear.app/cwchanap/issue/HPA-716  
**Design:** ../specs/2026-11-03-hpa-716-campaign-completion-design.md  
**Review addressed:** https://github.com/cwchanap/orion/pull/47#issuecomment-6611270301  
**Base:** main

## Design choices locked before coding

- Header title row uses the existing flexible ORION SECTOR title and MAIN x/5 badge. When main is complete but optional routes remain, add an existing-style violet OPTIONAL y/2 badge in that row. Keep the earned Challenge Badge icon conditional on the existing CampaignModifiers flag.
- Put CAMPAIGN COMPLETE / ALL SECTORS SECURED on **one short micro line below the row**, ahead of any feedback line. At full clear, suppress the redundant visible OPTIONAL 2/2 badge, but include the optional count in semantics.
- Clamp badge text scaling to the existing 1.3x dense-map precedent. Allow the utility rail to shift down with an extra status line; instead test for no overlap with visible stage-node hit rectangles.
- Keep the scene-parity test's exact destination Semantics.label (e.g. “Briefing for Outpost Alpha”). Put NEXT MAIN / OPTIONAL / REPLAY context in Semantics.hint.
- Keep SECTOR NN and append the qualifier **on the same one-line kicker**, using an ASCII separator and ellipsis where needed. Do not add a second footer text row.
- The recommendation is a **pure, read-only CampaignProgress.recommendedStage(stages) query** using statusFor. No new enum, save field, service or state. No game-rule or persistence changes.
- Use **OPTIONAL** consistently with StageBriefingSheet. Do not introduce SIDE in user-visible copy.
- There are no golden screenshot reference files. Keep existing scene tests; do not add screenshot-updating work.

## Task 1 — Fast unit tests before UI

Extend test/game/campaign_progress_test.dart. Reuse its existing seven-stage synthetic fixtures (five main, two optional) and recordResult or matching test progress setup. Test CampaignProgress.recommendedStage for:

1. Fresh campaign: first main stage.
2. First two main stages cleared; optional A unlocked and third main open: third main wins priority.
3. All five main stages cleared; both optionals open: first optional.
4. First optional cleared: second optional.
5. All seven stages cleared: last non-locked stage (replay).
6. Empty stage input or all supplied stages locked: null.

Then add the small query next to isCampaignComplete/statusFor in lib/game/campaign/campaign_progress.dart:

- Find first unlocked+uncleared main in input order.
- Otherwise first unlocked+uncleared optional in input order.
- Otherwise last not-locked (the current replay fallback).
- Return null when nothing is playable.

Use existing StageProgressStatus.unlocked to distinguish unfinished from cleared; no mutation, serialization, migration, or generalized recommendation engine.

## Task 2 — Present the header accurately

Extend test/widget/world_map_command_deck_test.dart to cover header copy and semantics on at least fresh, main-complete/optional-incomplete, and all-clear inputs. Main and optional counts are from the supplied stage list; completion authority stays CampaignProgress.isCampaignComplete.

In lib/game/ui/world_map_view.dart:

1. Compute mainTotal, mainCleared, optionalTotal, optionalCleared using widget.stages and widget.progress.isCleared; derive fullySecured only if the list is nonempty and every supplied stage is cleared.
2. Pass the simple values to _SectorHeader, including the _EmptySectorMap call with safe zeros/no completion.
3. Reuse the existing icon/badge title row. MAIN x/y is always shown on nonempty maps; add OPTIONAL y/z only after main completion and only while optional stages remain; keep existing Challenge Badge when campaignModifiers.hasChallengeBadge.
4. Insert a single micro status line under the title row when mainComplete, using the feedback-line pattern. Keep the current feedback line and utility rail in their current parent Column, allowing natural downward movement.
5. Clamp _HeaderBadge text scale to the existing 1.3x pattern. Build accurate single-summary semantics (“Campaign complete. Main 5 of 5 stages, optional 1 of 2 stages.”), including the full-clear optional count even when the redundant OPTIONAL badge is hidden.

Do not hard-code five or two in the widget, derive a second completion rule from campaignModifiers, or add new layout components unless the focused test proves necessary.

## Task 3 — Footer recommendation with stable semantics

In _MissionDestination.build:

1. Call progress.recommendedStage(stages) and keep the existing null-stage fallback to SizedBox.shrink.
2. Derive a short qualifier based on stage status and isMainPath: NEXT MAIN / OPTIONAL / REPLAY, with no new enum.
3. Append the qualifier to the current SECTOR NN micro line with a short ASCII separator; keep one line, using ellipsis if cramped.
4. Preserve exactly the current Semantics.label string “Briefing for [stage name]” so test/widget/scene_parity_regression_test.dart still finds it. Add the dynamic context to Semantics.hint instead.
5. Preserve the current surface, stage art, tap target, onStageSelected callback and disabled/busy behavior.

Widget-test each qualifier's visible copy and semantics hint/label, plus the footer's selection callback. Add the busy scenario when an optional stage is selected.

## Task 4 — Reproduce the riskiest layout automatically

In the existing test/widget/world_map_command_deck_test.dart test helpers, ensure header/full-clear fixtures pass **CampaignModifiers.fromProgress(progress, OrionCampaign.stages, CampaignTechTree())** instead of silently defaulting to null. The Challenge Badge must appear when production would show it.

Add one regression widget test at 320x568 and system TextScaler.linear(3), pumping two progress states:

- Main 5/5 with optional 1/2: both MAIN and OPTIONAL badges; this is the longest row without the Challenge Badge.
- All seven stages cleared: ALL SECTORS SECURED and Challenge Badge; the redundant visible OPTIONAL badge is absent.

For both states: assert tester.takeException() is null (including RenderFlex overflow), check the header and utility rail rects against the visible stage-node rects using the existing rect-based test pattern, check that title and status/feedback do not overlap controls, and assert correct semantic summaries.

Keep the existing scene-parity semantics selector unchanged. The optional fixture capture writes only when ORION_CAPTURE_DIR is set; there is **no golden-file comparison or screenshot-reference update** to do.

## Task 5 — Run full regression on this PR

Run:

- flutter test test/game/campaign_progress_test.dart
- flutter test test/widget/world_map_command_deck_test.dart
- flutter test test/widget/scene_parity_regression_test.dart
- dart format --output=none --set-exit-if-changed .
- flutter analyze
- flutter test --coverage
- flutter build web --release

Observe existing Codecov project and patch coverage >=90%. Confirm empty-map behavior, direct stage selection, and saving/resetting still disable actions. If a test exposes an actual overlap, resolve within existing header/footer widgets rather than introducing a new layout service or moving unrelated controls.

Update the checklist/test evidence in this **same draft PR** and only mark ready after review and green checks. HPA-715 remains untouched. No image art, SFX, or music work is required.

## Done when

Clearing the five main missions is unambiguously shown as campaign completion; the map suggests available unfinished optional stages; the seven-stage clear is clearly recognized; replay remains available; stable scene semantics and small-screen layout tests pass. Nothing changes in game logic, save fields, rewards, or assets.
