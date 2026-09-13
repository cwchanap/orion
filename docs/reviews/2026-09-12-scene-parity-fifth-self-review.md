# Fifth scene-parity self-review — 12 September 2026

**Resolved:** Both findings are fixed; see [the verified fix report](2026-09-12-fifth-review-fixes.md). The original review below is retained as history.

Reviewed the current radial fixes and adjacent mission/inspector interactions directly in `agent/orion-ui-revamp-foundation`, without subagents. **Two P2 findings remain open.** Application code is unchanged in this review.

## P2 — Inspector does not take keyboard focus

`lib/game/ui/orion_game_page.dart:432–446`

The inspector is a `Stack` containing a `ModalBarrier` and the sheet. `PopScope` handles Back, but the composition does not move focus into the sheet or constrain traversal. In the mounted game with the macOS theme, place/select a Laser, open its inspector with a mouse long press, then press Tab twelve times. Focus never enters any inspector control. The underlying Flame `GameWidget` handles key events while focused, so adding a pointer barrier alone does not make this a keyboard modal.

A separate diagnostic also confirms that if Auto already has focus, opening the inspector preserves that focus and Enter enables Auto underneath the sheet. That diagnostic explicitly requested focus and is supplementary evidence; the final reproduction above uses ordinary long-press entry and Tab events without requesting focus.

Give the inspector the same deliberate focus ownership, traversal containment, and focus restoration already used by the scanner. Retain the existing Back behavior.

## P2 — Three-digit salvage refunds clip at enlarged text

`lib/game/ui/hold_to_salvage.dart:107–110`

The compact salvage control still forces a 64 × 56 box with clipping. A legal level-3 specialized Laser refunds 168 credits. At 3× text, its `+168` label wraps inside that box and the icon/label column overflows by **32 px**. The screenshot shows only `+16`; the final digit is hidden. The same state passes at normal text size. This prevents the player from reading the actual refund before committing a sale.

Let the compact control accommodate the full scaled refund, and include a three-digit refund in the radial layout checks. Preserve the hold duration and cancellation behavior.

## Evidence and scope

- **24 targeted checks: 22 passed, 2 failed on the findings above.** All 21 permanent scene regression checks still pass; the normal-text specialized salvage control is the additional passing check.
- Source/current visual comparison covered scenes 1a and 1d, followed by new real-font salvage captures at 360 × 640. Existing gallery captures for other scenes were retained.
- Fresh native Chrome checks confirmed placement, selected-tower radial display, and inspector entry by a 650 ms mouse hold at 360 × 640. The browser did not expose Flutter's internal Auto focus as DOM focus; native confirmation of the keyboard finding is not claimed. The actionable keyboard evidence is the mounted widget reproduction.
- The last full suite remains the preceding fix pass's **934 passing tests** and clean analysis. No fresh full-suite result is claimed for this review.

Final reproduction: `tmp/self-review-5/review_test.dart.txt`. Copy it to `review_test.dart` in that directory and run:

```sh
flutter test --no-pub tmp/self-review-5/review_test.dart test/widget/scene_parity_regression_test.dart --reporter expanded
```

The final log is `tmp/self-review-5/final.log`. The gallery's `fifth-review` section contains the normal/large-text comparison and the live inspector image. Earlier four-review fixes remain implemented. No application edits, commits, or pushes were made.
