# Second and third self-review fixes — 12 September 2026

**Follow-up:** [The fourth self-review](2026-09-12-scene-parity-fourth-self-review.md) found two additional radial regressions in mounted interactions. The results below describe the preceding fix pass.

Implemented directly in `agent/orion-ui-revamp-foundation`, without subagents. All six findings from the second and third self-reviews are resolved. The first review's four fixes remain in place. Nothing was committed or pushed.

## Changes

- **Radial upgrade cost:** content determines button height. The radial measures its content for viewport placement and can scroll within the available space. Real-font checks pass at 100%, 150%, 200%, and 300% text.
- **Retry inspector state:** clear the inspected tower ID before restarting the same stage. Reusing a tower ID in a new attempt no longer opens the previous inspector.
- **Radial targeting:** restored the fourth control and current-mode readout. It cycles the six existing targeting modes through the existing callback, with mutations disabled outside build phase.
- **Scanner keyboard isolation:** a Flutter focus scope moves focus into the expanded scanner, contains Tab traversal, and restores prior focus when closed.
- **Scanner enlarged text:** the header wraps and the horizontal convoy sizes itself to its contents, so the wave and enemy counts remain visible at 3× text on 360 × 640.
- **Map footer:** the destination panel participates in normal column layout. The plot uses the remaining height and scrolls when needed, keeping Alpha's caption clear of the enlarged footer.

Game-state, persistence, balance, and combat contracts remain unchanged.

## Verification

- **924 tests passed** in the full Flutter suite, including 11 new regression checks in `test/widget/scene_parity_regression_test.dart`.
- **Flutter analysis: no issues.** `git diff --check` also passes.
- New checks cover radial text scaling, Retry inspector reset, all six targeting modes and phase gating, scanner focus containment/restoration, and compact scanner/map layout.
- Refreshed fixture captures use real fonts. The compact mission capture confirms the four-way radial fits above the dock.
- Live browser at 360 × 640: opened the scanner, pressed Tab ten times, then Enter; the scanner closed with Wave 1 still in build phase. Placed and selected a Laser, then changed its actual targeting from First to Strongest through the radial.
- Browser evidence and verification logs are retained under `tmp/self-review-fixes-23/`. Gallery: `tmp/ui-parity-review/index.html`, section `review-fixes-23`.

All eight reference scenes remain represented in the gallery. Earlier failure screenshots are retained and explicitly marked historical. This closes the six named findings; it does not certify pixel-identical parity or every possible device/state combination.
