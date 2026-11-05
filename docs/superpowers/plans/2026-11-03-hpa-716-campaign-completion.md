# HPA-716 — Campaign completion and optional-route clarity (implementation plan)

> **One Linear ticket, one PR.** Update the design and plan in this draft PR, then implement and test in **the same PR** after design approval. No separate implementation PR.

**Linear:** https://linear.app/cwchanap/issue/HPA-716  
**Design:** ../specs/2026-11-03-hpa-716-campaign-completion-design.md  
**Review addressed:** https://github.com/cwchanap/orion/pull/47#issuecomment-6611270301  
**Base:** main

## Design choices locked before coding

- Header title row uses the existing flexible ORION SECTOR title and MAIN x/5 badge. When main is complete but optional routes remain, add an existing-style violet OPTIONAL y/2 badge in that row. Keep the earned Challenge Badge icon conditional on the existing CampaignModifiers flag.
- Put CAMPAIGN COMPLETE / ALL SECTORS SECURED on **one short micro line below the row**, ahead of any feedback line. Wrap that new status line in `ExcludeSemantics` and place **one unified progress summary** on the main/optional badge group to avoid repeating the completion announcement; preserve the existing feedback line's accessibility. At full clear, suppress the redundant visible OPTIONAL 2/2 badge, but include the optional count in progress semantics.
- Clamp badge text scaling to the existing 1.3x dense-map precedent. The header (title, badges, status line, feedback slot) and utility rail are **fixed chrome**; the chart+footer region below them is the only vertical scrollable, so feedback and controls never scroll away. The feedback row occupies a reserved fixed-height slot so transient text never resizes the header or moves stage nodes.
- Keep the scene-parity test's exact destination Semantics.label (e.g. “Briefing for Outpost Alpha”). Put NEXT MAIN / OPTIONAL / REPLAY context in Semantics.hint.
- Keep SECTOR NN and append the qualifier on the same kicker, using `' / '`. `OrionText.micro` lacks overflow/maxLines props, so use an ordinary `Text` with `OrionTypography.microLabel`, `overflow: TextOverflow.ellipsis`, the 1.3x scale clamp, and `maxLines: 2` — a single ellipsized line dropped the qualifier at 3x system text, which a real-`TextPainter` test (`didExceedMaxLines == false`) now guards. Do not extend the shared component. Do not add a second footer row.
- The recommendation is a **pure, read-only CampaignProgress.recommendedStage(stages) query** using statusFor. No new enum, save field, service or state. No game-rule or persistence changes.
- Use **OPTIONAL** consistently with StageBriefingSheet. Do not introduce SIDE in user-visible copy.
- There are no golden screenshot reference files. Keep existing scene tests; do not add screenshot-updating work.

## Task 1 — Fast unit tests before UI

Extend test/game/campaign_progress_test.dart. Reuse its existing seven-stage synthetic fixtures (five main, two optional) and recordResult or matching test progress setup. Test CampaignProgress.recommendedStage for:

1. Fresh campaign: first main stage.
2. First two main stages cleared; optional A unlocked and third main open: third main wins priority.
3. All five main stages cleared; both optionals open: first optional.
4. First optional cleared: second optional.
5. All seven stages cleared: last non-locked stage (replay). **Assert `side-b` for this synthetic fixture**, whose order is five main stages followed by `side-a` and `side-b`; **also assert `singularity-core`** for a separately cleared `OrionCampaign.stages` fixture, whose final stage is the real Singularity Core.
6. Empty stage input or all supplied stages locked: null.

Do not mistakenly assert `stage-5` as the replay result for the synthetic fixture: the function intentionally respects **the last non-locked element in the supplied list**, not the main-path order. Import `OrionCampaign` only for the explicit production-order assertion.

Then add the small query next to isCampaignComplete/statusFor in lib/game/campaign/campaign_progress.dart:

- Find first unlocked+uncleared main in input order.
- Otherwise first unlocked+uncleared optional in input order.
- Otherwise last not-locked (the current replay fallback).
- Return null when nothing is playable.

Use existing StageProgressStatus.unlocked to distinguish unfinished from cleared; no mutation, serialization, migration, or generalized recommendation engine.

## Task 2 — Present the header accurately

Extend test/widget/world_map_command_deck_test.dart to cover header copy and semantics on at least fresh, main-complete/optional-incomplete, and all-clear inputs. Main and optional counts are from the supplied stage list; completion authority stays CampaignProgress.isCampaignComplete.

In lib/game/ui/world_map_view.dart:

1. Compute mainTotal, mainCleared, optionalTotal, optionalCleared using widget.stages and widget.progress.isCleared; derive fullySecured only if the list is nonempty, every supplied stage is cleared, **and** `optionalTotal > 0` (ALL SECTORS SECURED is meaningless on a main-only campaign).
2. Pass the simple values to _SectorHeader, including the _EmptySectorMap call with safe zeros/no completion.
3. Reuse the existing icon/badge title row. MAIN x/y is always shown on nonempty maps; add OPTIONAL y/z only after main completion and only while optional stages remain; keep existing Challenge Badge when campaignModifiers.hasChallengeBadge.
4. Insert a single micro status line under the title row when mainComplete, using the feedback-line pattern **inside `ExcludeSemantics(child: Row(...))`**; the completion line is visual only. Keep the feedback line accessible; render it inside a **reserved fixed-height slot** (one clamped line) so transient feedback never resizes the header or shifts the plot.
5. Clamp _HeaderBadge text scale to the existing 1.3x pattern. Wrap the progress-badge group in **one** Semantics announcing a single accurate summary (“Campaign complete. Main 5 of 5 stages, optional 1 of 2 stages.”), including the full-clear optional count even when the redundant OPTIONAL badge is hidden. When the supplied list has **no** optional stages, omit the optional clause entirely (never "optional 0 of 0") and never show ALL SECTORS SECURED. Suppress default text semantics for the status line so it does not echo the summary. Keep the Challenge Badge's own semantics and feedback semantics as they are.

Do not hard-code five or two in the widget or derive a second completion rule from campaignModifiers.

## Task 3 — Footer recommendation with stable semantics

In _MissionDestination.build:

1. Call progress.recommendedStage(stages) and keep the existing null-stage fallback to SizedBox.shrink.
2. Derive a short qualifier based on stage status and isMainPath: NEXT MAIN / OPTIONAL / REPLAY, with no new enum.
3. Append the qualifier to the current SECTOR NN kicker with the literal `' / '` separator. Replace only this `OrionText.micro` call with a **standard `Text`**, because `OrionText.micro` does not expose `maxLines`/`overflow`. Two clamped lines, not one unclamped: at 3x system text the single line ellipsized the qualifier inside the ~110px column.

   ```dart
   Text(
     'SECTOR ${(stages.indexOf(stage) + 1).toString().padLeft(2, '0')} / $qualifier',
     maxLines: 2,
     overflow: TextOverflow.ellipsis,
     textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
     style: OrionTypography.microLabel(color: theme.systemCyan),
   )
   ```

   Keep the line in the existing footer column; do not add a new row or extend the shared typography API.
4. Preserve exactly the current Semantics.label string “Briefing for [stage name]” so test/widget/scene_parity_regression_test.dart still finds it. Add the dynamic context to Semantics.hint instead.
5. Preserve the current surface, stage art, tap target, onStageSelected callback and disabled/busy behavior.

Widget-test each qualifier's visible copy and semantics hint/label, plus the footer's selection callback. Add the busy scenario when an optional stage is selected.

## Task 4 — Single scrolling region under fixed chrome

Code review of the first implementation found the in-flow header broke the map: the plot's own vertical scroll view inside the whole-sheet scroll view swallowed drags (footer unreachable at 568x320/3x), the whole map overscrolled at zero extent, the header+controls scrolled away, and transient feedback resized the plot. Restructure `WorldMapView.build` and `SectorMapLayout`:

1. The header block (title row, badges, status line, reserved feedback slot) and the utility rail form **fixed chrome** at the top; only the `Expanded` region below scrolls.
2. That region is **one** `SingleChildScrollView` (`primary: false`, `ClampingScrollPhysics`, wrapped in a `ScrollConfiguration` whose behavior draws no overscroll indicator — edge drags at zero extent are inert) containing a `Column` of `[chart, footer]` under `ConstrainedBox(minHeight: regionHeight)` + `MainAxisAlignment.spaceBetween`, so the footer hugs the bottom when content is short and one drag on the chart reaches it when it is not.
3. The chart keeps its conditional horizontal `SingleChildScrollView`. Its height is `max(regionHeight - footerReserve, layout.minContentHeight)` — no intrinsic-height query, no fixed-height-child trick that asserts under `ConstrainedBox`/`LayoutBuilder` children.
4. In `SectorMapLayout`, fit the anchors' own min/max `dy` into the plot box (`plotTopInset..plotTopInset + nodeSpan`, normalized t) instead of the fixed `-184` offset; give unanchored stages the same fitted frame with row spacing floored at one node height so they cannot collapse to a single y; expose `minContentHeight` = insets + node height + max(anchor span, unanchored-row span).

## Task 5 — Reproduce the riskiest layout automatically

In the existing test/widget/world_map_command_deck_test.dart `buildMap` helper, default `campaignModifiers` to **`CampaignModifiers.fromProgress(progress, stages ?? OrionCampaign.stages, CampaignTechTree())`** instead of silently defaulting to null. Explicitly passed modifiers still override that default. The Challenge Badge must appear when production would show it; avoid relying on artificial null-modifier full-clear cases. Add the `tech_tree.dart` import as needed.

Add regression widget tests at **320x568 and 568x320** with **system `TextScaler.linear(3)`**. **Before pumping, call `await tester.runAsync(loadRealFonts)`** (the test file already imports `../support/real_fonts.dart`) so the test uses actual Oxanium/Chakra Petch metrics rather than Flutter's Ahem font. Pump two progress states:

- Main 5/5 with optional 1/2: both MAIN and OPTIONAL badges; this is the longest row without the Challenge Badge. Pass **non-null feedback** (e.g. `'Saving campaign progress…'` as plain test feedback without enabling busy mode) to exercise the status and feedback rows.
- All seven stages cleared: ALL SECTORS SECURED and Challenge Badge; the redundant visible OPTIONAL badge is absent.

For both states: assert `tester.takeException()` is null (including RenderFlex overflow); intersect each stage-node rect with the scroll-viewport rect and check header/rail rects only against those **visible portions** (off-screen rects pass vacuously — the review caught checks that proved nothing below the fold); drive the real down-axis scrollable with an actual `tester.drag` to the bottom extent and assert the destination footer is on screen, clear of Outpost Alpha's hit target, and still fires `onStageSelected`; then assert the fixed header controls remain on screen. Also cover: `maxScrollExtent == 0` plus a zero-effect drag on a common portrait screen, feedback show/clear never moving a node rect, a main-only supplied list (no optional clause, no ALL SECTORS SECURED), and the kicker qualifier actually painting (`TextPainter.didExceedMaxLines`).

Keep the existing scene-parity semantics selector unchanged. The optional fixture capture writes only when ORION_CAPTURE_DIR is set; there is **no golden-file comparison or screenshot-reference update** to do.

## Task 6 — Run full regression on this PR

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
