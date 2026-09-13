# Fifth-review fixes — 12 September 2026

Both findings from the [fifth self-review](2026-09-12-scene-parity-fifth-self-review.md) are resolved in `agent/orion-ui-revamp-foundation`. Implemented directly without subagents; changes remain uncommitted.

- **Inspector keyboard access:** reuse the scanner's native `FocusScope` pattern and autofocus the close button. Tab traversal stays inside the inspector, Enter closes it, and dismissal restores the previous focus. Existing Back handling remains in place.
- **Salvage refunds:** replace fixed dimensions with minimum dimensions and content sizing in `HoldToSalvage`. The compact button includes padding and expands to display the full scaled refund. Its hold duration, cancellation, and phase gating are preserved.

Production changes are confined to `tower_inspector.dart` and `hold_to_salvage.dart`. The three review cases are retained in `test/widget/scene_parity_regression_test.dart`; the focus check now also verifies containment at every Tab step, restoration, and Enter-to-close. No game-state or combat contracts changed.

## Verification

- **937 tests passed** in the full suite; `flutter analyze` is clean.
- **36 focused scene, inspector, and salvage checks passed**, covering the existing hold cancellation and reduced-motion behavior. The strengthened focus restoration/Enter check also passed independently and in the full suite.
- Native Chrome at 360 × 640: place/select a Laser, open its inspector with a 650 ms mouse hold, traverse with 12 Tab and 12 Shift-Tab presses, and press Enter. The sheet closes and the radial becomes available again.
- Real-font captures at normal and 3× text show the complete specialized Laser refund, `+168`. Enlarged text is verified through widget rendering; the native keyboard check uses normal text.

Evidence: `tmp/fifth-review-fixes-evidence/`. The gallery's `fifth-review-fixes` section preserves the failing capture beside the corrected one. These checks close the two named findings and do not claim exhaustive pixel parity or physical-device acceptance. No commits or pushes were made.
