# Scene parity self review — four findings fixed

Reviewed and fixed the current `agent/orion-ui-revamp-foundation` worktree directly, without subagents. Changes remain uncommitted. All four confirmed findings from the self review are closed by the checks below.

| Finding | Fix | Regression evidence |
| --- | --- | --- |
| P1 Reduced motion shortened the salvage hold | Preserve the controller’s 800 ms confirmation duration regardless of system animation preferences. | The permanent hold test rejects a 250 ms press with animations disabled. The live browser also retained the tower after 250 ms under reduced motion, then refunded 35 credits after a full hold. |
| P2 Compact layout hid the base | Fit the rendered board between the measured HUD/scanner and dock. Apply the inverse transform to taps and drag placement; keep simulation positions, ranges, and movement unchanged. | At 360 × 640 and 390 × 844, all 96 cell centers clear the dock and scanner. Bottom-row placement and enemy inspection use the mapped coordinates. The live compact browser placed a tower on the bottom row and opened its radial and inspector. |
| P2 R&D details overflowed at 3× text | Put selected details inside the existing scroll view with the nodes; reset scroll when the selection changes. | At 360 × 640 with text scale 3, details produce no overflow and the action scrolls above the fixed bank footer. Captures include the detail heading and the scrolled action. |
| P2 Back did not dismiss the inspector | Let the visible inspector consume Back with PopScope and close itself. | Navigator.maybePop is handled and removes the inspector in the mounted game-page test at both portrait sizes. |

## Verification

- `flutter test --no-pub --reporter expanded` — **913 passed**.
- `flutter analyze --no-pub` — **No issues found**.
- `git diff --check` — clean.
- Regression checks live in `test/widget/hold_to_salvage_test.dart`, `test/widget/tech_tree_view_test.dart`, `test/widget_test.dart`, and `test/game/orion_defense_game_test.dart`. Integration helpers now use the game’s displayed cell centers.
- The board transform test independently checks the mapping, verifies unchanged tower combat geometry, and exercises drag placement and enemy inspection.
- The original compact failure remains in `tmp/ui-parity-review/self-review-compact.png`; current compact and large-text evidence are linked from the gallery. Expected-failing scratch tests were replaced by permanent regression tests and archived outside the checkout.
- Fresh local browser checks use the current app at port 8878. The earlier compiler/browser session was restarted after an SDK mismatch; these results come from the clean session.

```sh
flutter test --no-pub --reporter expanded
flutter analyze --no-pub
ORION_CAPTURE_DIR=/tmp/orion-parity flutter test --no-pub --name 'capture scene|compact R&D' --reporter expanded
```

The comparison gallery at `http://127.0.0.1:8879/?review=6` covers all eight supplied app scenes and the regression variants. Closing these four findings does not certify pixel-identical rendering or exhaustive screenshots of every campaign and dialog state. The source/data/art boundaries remain documented in `2026-09-11-remaining-scene-parity.md`.
