# Fourth scene-parity self-review — 12 September 2026

**Resolved:** Both findings below are fixed and verified; see [the fix report](2026-09-12-radial-review-fixes.md). The original review and failing evidence are preserved below.

Reviewed the latest fixes directly in `agent/orion-ui-revamp-foundation`, without subagents. Two radial regressions remain open. Application code is unchanged in this review.

## Findings

### P2 — Transparent radial regions intercept board input

`lib/game/ui/mission_chrome.dart:204–208`

The radial is now inside a `SingleChildScrollView`, whose default hit-test behavior is opaque. Its whole rectangle intercepts pointers, including the visually empty gaps. In the mounted game at 360 × 640, select a Laser at cell (4,5), then tap the visible cell (2,2) in the radial's upper-left gap: selection does not move to (2,2). Long pressing the already-selected tower also fails to open the inspector.

A control case confirms the same mounted board accepts a tap outside the radial, and long pressing the tower after that selection change opens its inspector. The new wrapper is therefore blocking the underlying input path; this is not a test input failure. Preserve pass-through outside real radial controls while retaining scrolling where required.

### P2 — Bottom-row targeting is hidden behind the dock

`lib/game/ui/mission_chrome.dart:348–350`

The new layout assumes a 150 px bottom reserve instead of using the dock height already measured by `MissionChrome`. Select a tower at (4,10) on 360 × 640. At normal text, the targeting button spans y=434–490 while the dock starts at y=456, hiding its bottom 34 px. A tap at the targeting button's center leaves the tower on First.

At 3× text, the dock starts at y=375.2 and the targeting button spans y=397.2–482.2, so it is fully obscured. The same overlap reproduces at 1.5× and 2×. Position and constrain the radial against the measured HUD/dock bounds, and include a bottom-row mounted interaction case in the regression coverage.

## Evidence and verification

18 targeted checks: **12 passed, 6 reproduced the two findings above**.

- The previous 11 permanent regression checks still pass.
- One new positive control verifies board taps and long presses work outside the radial's interception area.
- Two new failures reproduce blocked gap taps and selected-tower long presses.
- Four new failures reproduce bottom-row targeting overlap at 1×, 1.5×, 2×, and 3× text. Targeting remains First after tapping its obscured center in all four cases.
- Captures come from the mounted Flutter/Flame page with real fonts, real placement, and real pointer events. This review does not claim a fresh native browser run or full-suite rerun; the preceding fix pass recorded 924 passing tests.

Reproduction source: `tmp/self-review-4/radial_review_test.dart.txt`. Copy it back to `.dart` in the same directory and run `flutter test --no-pub tmp/self-review-4/radial_review_test.dart test/widget/scene_parity_regression_test.dart --reporter expanded`. Confirmed output is archived as `tmp/self-review-4/confirmed.log`.

Screenshots and the review status are in `tmp/ui-parity-review/index.html`, section `fourth-review`. The earlier six fixes remain implemented, but their isolated tests did not cover these mounted radial interactions. No implementation edits, commits, or pushes were made.
