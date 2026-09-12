# Reactor Rim remaining-scene self review

Worktree: `agent/orion-ui-revamp-foundation`. Implemented and reviewed directly, without subagents. Changes are uncommitted.

The local comparison page is `tmp/ui-parity-review/index.html`, served at http://127.0.0.1:8879/. It now covers all eight source scenes, the system sheet and art-request boards, and additional state captures. Source export: `Orion Game UI visual revamp.zip` supplied by the user.

| Scene | Current coverage |
| --- | --- |
| 1a Mission | Full-width HUD and dock, persistent sprite rail, selected-tower radial, range ring |
| 1b Briefing | Portrait art, crest, facts, threats, medal criteria, deploy action |
| 1c Scanner | Full-screen convoy, traits, boss forecast, counters, start action |
| 1d Inspector | Bottom sheet, real stat dials, targeting, specialization art, hold-to-salvage |
| 1e Placement | Green buildable cells, red route, range/cost ghost; allowed and blocked drops |
| 1f Map | Seven authored stage anchors, portrait map art, crests, medals, destination footer |
| 1g R&D | Crystal balance, compact upgrade nodes, details opened on selection |
| 1h Report | Medal, snapshot facts, result art, save status, actions; victory/loss/saving/failure |

## Data and art boundaries

- Preserve `GameSnapshot`, `GameSession`, and `OrionDefenseGame` as the authorities for gameplay. No balance or campaign prerequisite changes.
- The app uses its real 8 × 12 board, eight waves, stage roster, costs, stat units, and medal/save rules. Source demo values are not copied.
- The five R&D upgrades remain independent. Do not draw prerequisite edges that imply nonexistent rules.
- Scanner clear bonus replaces the unsupported timer. Report waves/current credits replace unavailable kills/earned-credit totals. Replay/map remain the actual report navigation actions.
- Existing specialization sprites and native platform icons cover source art-request placeholders. This review does not certify an exact pixel match or every unrelated dialog/state.

## Verification

- Full suite: `flutter test --no-pub --reporter expanded` — 913 passed.
- The full suite includes the selected-range check and the four self-review regressions: reduced-motion hold duration, compact board mapping, 3× R&D details, and inspector Back dismissal.
- `flutter analyze --no-pub` and `git diff --check` — clean.
- Captures: all eight scenes, idle/radial mission, blocked placement, loss/saving/failed reports, compact board before/after, and 3× R&D details/action. Fonts and image decoding are warmed before capture.
- Live browser: map, R&D, briefing/deploy, scanner, placement, upgrade, long-press inspector, canceled short salvage hold, completed salvage hold, and selected-tower range. A fresh pass confirms bottom-row placement at 360 × 640 and canceled/full holds with reduced motion enabled.
- Review findings fixed during this pass: scanner portal hide during a build frame, tooltip competing with salvage hold, omitted group traits, and selected range lost during board replacement. The follow-up self review also fixed all four confirmed issues; see [the finding-by-finding evidence](2026-09-11-scene-parity-self-review.md).

To refresh the primary screenshots using the existing fixtures:

```sh
ORION_CAPTURE_DIR=/tmp/orion-parity flutter test --no-pub --name 'capture scene|compact R&D' --reporter expanded
python3 -m http.server 8879 --bind 127.0.0.1 --directory tmp/ui-parity-review
```

Captures are generated evidence, not pixel golden assertions. The gallery includes starting-state images and distinguishes controlled fixtures from live browser captures.
