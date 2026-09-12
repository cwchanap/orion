# Second scene-parity self review

**Resolved on 12 September 2026.** All findings below are historical and now fixed; see [the verified fixes](2026-09-12-scene-parity-review-fixes.md).

Reviewed `agent/orion-ui-revamp-foundation` directly, without subagents. No implementation files changed. Two reproducible bugs and one remaining source-parity gap are open.

## Findings

1. **P2 — Upgrade cost clips at larger text sizes.** In `lib/game/ui/mission_chrome.dart:369–395`, a fixed 64 × 56 button contains a 22 px icon plus an unconstrained scaled text label. The real-font fixture passes at 100% but overflows at 150%, 200%, and 300%; the cost visibly clips at 150%. Let the composition accommodate its content while preserving a readable cost and usable target. Evidence: `tmp/ui-parity-review/radial-text-1.5.png`.
2. **P2 — Retry retains the old inspector identity.** `_restartFromMissionReport` in `lib/game/ui/orion_game_page.dart:915–926` resets the game but leaves `_inspectedTowerId` set. GameSession reuses tower IDs from 1 on restart, so inspecting tower 1, ending the attempt, pressing Retry, and selecting the new tower 1 opens the previous sheet automatically. The new attempt should begin with no inspector selected. The mounted page reproduction publishes the same loss snapshot used by the existing report tests, presses the actual Retry action, places/selects a fresh tower, and observes one unwanted inspector.
3. **P2 — Scene 1a still lacks the reference’s targeting control.** `TowerRadialActions` in `lib/game/ui/mission_chrome.dart:330–442` renders three controls: progression, Inspect, and salvage. The supplied scene 1a has a four-way composition with a bottom targeting icon and current-mode label (FIRST). The current capture omits that region entirely, and current mode is visible only after opening the inspector. Restore the targeting readout/action through the existing snapshot and callback, with progression still gated by Orion’s real L1/L2/L3 rules. This is a source comparison finding, not an automated-test failure or a request to invent gameplay.

## Verification

- New isolated checks: **1 passed, 4 expected failures** — normal-text radial passes; the three larger text sizes expose the same overflow; replay exposes the stale inspector identity.
- Prior-fix checks: **4 passed** — reduced-motion salvage hold, 3× R&D details/action, and the mounted mission at both 390 × 844 and 360 × 640. The two mission cases also exercise Back dismissal.
- The last full suite remains 913 passed from the preceding fix pass. It was not rerun wholesale; these new cases expose gaps in that coverage.
- Current source/reference comparison: scene 1a source and current radial, plus R&D source/current. Existing gallery evidence was retained for unchanged scenes.
- No gameplay, assets, or application code changed during this review. The gallery distinguishes the previous four closed findings from these new open items.

The temporary reproduction is retained as `tmp/self-review-2/second_review_test.dart.txt`, with the logs beside it. It is outside the permanent suite and renamed so it does not pollute application analysis. To reproduce from the worktree:

```sh
cp tmp/self-review-2/second_review_test.dart.txt tmp/self-review-2/second_review_test.dart
ORION_CAPTURE_DIR=/tmp/orion-self-review-2 flutter test --no-pub tmp/self-review-2/second_review_test.dart --reporter expanded
mv tmp/self-review-2/second_review_test.dart tmp/self-review-2/second_review_test.dart.txt
```

Review gallery: `http://127.0.0.1:8879/?review=7#second-review`.
