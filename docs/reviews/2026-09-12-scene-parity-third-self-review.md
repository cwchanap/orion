# Third scene-parity self-review — 12 September 2026

**Resolved on 12 September 2026.** All findings below are historical and now fixed; see [the verified fixes](2026-09-12-scene-parity-review-fixes.md).

Reviewed directly in `agent/orion-ui-revamp-foundation`; no subagents or application edits. This pass examined compact scanner, world-map, briefing, and defeat-report layouts plus keyboard isolation of the full-screen scanner.

## New findings

### P2 — The expanded scanner leaves the obscured Auto control keyboard-active

`lib/game/ui/next_wave_scanner.dart:92–111`

The root overlay uses `BlockSemantics` but does not transfer or contain keyboard focus. Focus the real Auto control in `MissionChrome`, open the scanner, then press Enter: the underlying Auto callback fires once while `WaveScannerScene` is still present. The page wires that callback to `game.toggleAutoStart`, so this can change wave pacing behind the full-screen scene.

Reproduction uses the production `MissionChrome` and its actual pacing control, with a callback counter. Expected 0 activations; actual 1. Use modal focus behavior that transfers focus on opening, confines traversal, and restores focus on closing.

### P2 — Scanner wave and enemy counts clip at 3× text

`lib/game/ui/next_wave_scanner.dart:304–328,344–391`

At 360 × 640 with the real fonts and `TextScaler.linear(3)`, the fixed header row overflows 21 px right. The fixed 148 px convoy row also overflows 13 px below, cutting off the enemy count. The outer vertical scroll view cannot recover content clipped within the convoy row. The same scene passes at 1×, 1.5×, and 2× text.

Allow the header to reflow and size the convoy row for its scaled count text. Evidence: `tmp/ui-parity-review/scanner-text-1.0.png` and `scanner-text-3.0.png`.

### P3 — The enlarged map footer covers Alpha’s caption

`lib/game/ui/world_map_view.dart:164–168`

The map reserves a fixed 150 px below its plot while the destination footer grows with text scale. At 360 × 640 and 3× text, the footer starts at y=465 and Alpha's node ends at y=478, covering the caption by 13 px. The stage circle remains visible and the footer repeats the destination name; this is a visual defect, not a claim that deployment becomes impossible. At 1×, 1.5×, and 2×, the measured rectangles do not overlap.

Reserve the actual footer height in the map layout. Evidence: `tmp/ui-parity-review/map-text-1.0.png` and `map-text-3.0.png`.

## Verification

17 isolated Flutter widget checks: **14 passed; 3 failed as reproductions of the findings above**.

- Four scenes at 360 × 640, using real fonts, each at 1×, 1.5×, 2×, and 3× text.
- Briefing and defeat report pass all four layout checks. These checks do not establish every report state or device combination.
- One keyboard activation check uses the real Auto control beneath the expanded scanner.
- This pass did not rerun the full suite or perform a fresh native browser keyboard check. The preceding fix pass recorded 913 passing tests.

Review checks and their confirmed output are archived under `tmp/self-review-3/` as `scene_review_test.dart.txt`, `scanner_focus_test.dart.txt`, and `confirmed.log`. The scripts retain their original relative imports: copy them back to `.dart` files in that directory and run `flutter test --no-pub tmp/self-review-3/scene_review_test.dart tmp/self-review-3/scanner_focus_test.dart --reporter expanded` to reproduce. Optional `ORION_CAPTURE_DIR` selects the image output directory.

## Previous review status

_Historical — this section records the state when the review ran. All six findings across the second and third reviews were subsequently resolved; see [the verified fixes](2026-09-12-scene-parity-review-fixes.md)._

At review time the second review's three findings were still open: radial upgrade text clipping, stale inspector state after Retry, and the missing bottom targeting control from scene 1a. See [the second self-review](2026-09-12-scene-parity-second-self-review.md). The first review's four fixes were in the working tree; this pass did not modify them.

The gallery covers all eight reference scenes, but visual parity was not complete at that point: six open findings across the second and third reviews, with the changes uncommitted.
