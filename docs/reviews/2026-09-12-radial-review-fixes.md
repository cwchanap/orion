# Fourth-review radial fixes — 12 September 2026

Both findings from the [fourth self-review](2026-09-12-scene-parity-fourth-self-review.md) are resolved in `agent/orion-ui-revamp-foundation`. Work was completed directly, without subagents. Changes remain uncommitted.

## Changes

- **Board input:** the radial scroll view defers hit testing to its controls. Its automatic desktop scrollbar is disabled because that wrapper also intercepted empty regions. The live browser exposed this second cause after Android widget checks passed; macOS mouse regression checks now reproduce and cover it. Gap taps and selected-tower long presses reach the board again. Touch and wheel scrolling remain available.
- **Dock overlap:** the radial uses the HUD/dock viewport already measured by `MissionChrome`, replacing the fixed bottom reserve. It stays above the real dock at 1×, 1.5×, 2×, and 3× text. Content can scroll on a smaller viewport, and intrinsic width lets longer targeting labels fit after changing modes.

Production edits are confined to `lib/game/ui/mission_chrome.dart`. Regression coverage is in `test/widget/scene_parity_regression_test.dart`. Game state, combat geometry, tower rules, and snapshot contracts are preserved.

## Verification

- **934 tests passed** in the final full suite; `flutter analyze` reports no issues.
- **21 focused scene regressions passed**, including ten new cases: touch and macOS mouse gap taps/long presses, an outside-radial control, bottom-row targeting at four text scales, and an actual scroll gesture at 320 × 568 with 3× text.
- Fresh native Chrome pointer checks at 360 × 640: a gap tap dismisses the selected-tower radial; a 650 ms selected-tower hold opens the inspector; bottom-row targeting changes First to Strongest. Before the change of mode, that control spans y=392–448 above the dock at y=456. Browser console: no errors.
- Final capture runs passed: 43 scene/chrome checks and two scene-1a captures. Captures use real fonts and the mounted Flutter/Flame game.

Logs and native captures are archived under `tmp/review4-fixes-evidence/`. The parity gallery's `radial-review-fixes` section includes corrected images and preserves the original failures in `fourth-review`.

This closes the two named findings. The native run covers desktop mouse input at normal text size; enlarged text and touch input are covered by mounted widget checks. These screenshots support visual review and do not certify pixel-identical parity or physical-device acceptance. No commits or pushes were made.
