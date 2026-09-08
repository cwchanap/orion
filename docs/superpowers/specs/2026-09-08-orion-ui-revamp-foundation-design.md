# Orion UI Revamp — Foundation Layer (design)

Date: 2026-09-08
Source: Claude Design project `19992866-2fdd-4acd-b094-dccae94bf0f9`, file
`Orion UI Revamp export.dc.html` (scenes 1a–1j; the design system is scene **1i**).
Branch: `agent/orion-ui-revamp-foundation`, stacked on PR #29
(`agent/hpa-9-reactor-rim-full-scene-parity-plan`, head `6e3f878`).

## Why this exists

PR #29 completed a Reactor Rim *parity* pass: eight scenes matched against eight
artboards. The Revamp export is a later and different thing — it adds a **design
system** (scene 1i) that the parity pass never had, and it reverses several
rulings #29 shipped as deliberate deviations.

The reversals, all confirmed as export-wins:

| Element | #29 ruling | Export |
|---|---|---|
| Radial tower actions | Intentional deviation | Asserted (1a, 1d) |
| Hold-to-salvage | Intentional deviation | Asserted (1a, 1d) |
| Oxanium / Chakra Petch | Intentional deviation | Asserted (1i, all scenes) |
| Per-stage board skins | Rejected — "no board skins" | Asserted (`board_nebula`) |
| Persistent tower tray | Mock-only removed | Asserted (1e) |

The export is not itself authoritative about the game. Scene 1b still shows
`≤6 TOWER CAP`; Orion has no tower-cap rule, and #29 removed it for that reason.
**That removal stands.** Where the export contradicts the game's actual rules,
the game wins; where it contradicts a prior *aesthetic* ruling, the export wins.

## Scope

This spec covers the **foundation layer only** — the part of 1i that every scene
depends on, plus the art those scenes will need. It is the first of four planned
pieces:

- **PR A (this spec)** — typography, surface tiers, geometry, motion, art intake.
- **PR B** — in-battle scenes 1a / 1d / 1e (shares the radial + drag machinery).
- **PR C** — mission-loop sheets 1b / 1c.
- **PR D** — between-missions 1f / 1g / 1h.

**No scene layout changes in PR A.** The only edits under `lib/game/ui/` are the
`MissionSurface` adapter swap and the `CommandFrame` retirement. Scenes remain as
#29 shipped them except where dropping the chamfer necessarily alters them.

## Typography

Two OFL faces, vendored to `assets/fonts/` and declared in `pubspec.yaml`:
`Oxanium-ExtraBold.ttf`, `ChakraPetch-Bold.ttf`, `ChakraPetch-Medium.ttf`.

No `google_fonts` dependency: a runtime fetch would break widget tests and
offline builds, and the existing `loadRealFonts` test helper already assumes
local font data.

`OrionTypography`, carried on `OrionUiTheme`, exposes three styles:

| Role | Face | Spec | Used for |
|---|---|---|---|
| `readout` | Oxanium 800 | size-parameterized, default 24 | credits, hull, wave, costs, counts |
| `title` | Oxanium 800 | ~15px, caps, tracked | the single screen title |
| `microLabel` | Chakra Petch 700 | 7–9px, tracking .14–.24em | every label |

The sheet's fourth role — the muted-denominator readout (`03/12`, `20/20`) — is a
composition rather than a face, so it ships as `OrionReadout(value:, denominator:)`.
The widget enforces "never two full-size numbers" structurally: the denominator
renders at ~45% size in `textMuted` and is not overridable.

Two rules are encoded rather than documented:

- `microLabel` cannot resolve to `textPrimary` — it is muted-only by construction.
- All three styles carry the tier text-shadow `0 1px 4px rgba(5,8,13,.9)`, so
  contrast never depends on a surface fill.

The **97** existing `Theme.of(context).textTheme.*` references in the game UI
migrate to these three. Material's `TextTheme` stays populated in `main.dart` for
non-game UI, but the game UI stops reading it.

97 is the largest single mechanical task in PR A and the main driver of its size.
It is migrated file-by-file (20 files under `lib/game/ui/`), each file a separate
commit, so review stays tractable and a bad mapping is revertible in isolation.

## Surface tiers

`OrionSurface(tier:)`. Nearly every color derives from an existing `OrionUiTheme`
token — the export's rgba literals are `hullBlack` / `panelRaised` / `panelBlue` /
`voidBlack` at alpha.

**One exception.** The t3 gradient's bottom stop is `rgba(8,13,19,.94)` = `#080D13`,
which is not in the current palette (it sits between `voidBlack` `#05080D` and
`hullBlack` `#0B1118`, and is also 1i's own card ground). It ships as a single new
token, `sheetBlack`. So 1i's claim that the palette is "unchanged from
orion_ui_theme.dart" is very nearly true but not exactly: it is 14 tokens plus one.

| Tier | Blur | Fill | Border | Role |
|---|---|---|---|---|
| `t1` | 7 | `hullBlack` α.55 | `systemCyan` α.5 | floating control on live art — radial, pacing, toasts, locked nodes |
| `t2` | 6 | `panelRaised` α.66 → `hullBlack` α.76 | `frameSteel` | content card — rail tiles, stat/spec cards, tech plates |
| `t3` | 12 | `panelBlue` α.90 → `#080D13` α.94 | `systemCyan` α.3 | sheet or drawer that covers the scene |
| `t4` | 14 | `voidBlack` α.50 → α.62 | `systemCyan` α.14, top only | the full-width dock shelf |

The blur count is a performance budget, not decoration. 1i caps it at 5–9
`BackdropFilter`s per screen (1a 9 · 1b 8 · 1g/1h 6 · 1c/1d 5 · 1e/1f 3) and
requires blur on the **container**: the eight-tile rail is one blurred row, not
eight. Tier is an enum, so a fifth blur value is unrepresentable rather than
merely discouraged.

Solid primary actions (`WAVE`, `DEPLOY`) stay unblurred by design and do not use
`OrionSurface`.

### Migration

`MissionSurface` becomes a deprecated thin adapter over `OrionSurface(tier: t2)`.
Its 15 call sites therefore keep compiling and convert incrementally, rather than
forcing one 25-site commit alongside the `CommandFrame` removal. The adapter is
deleted in PR D once the last site is gone.

`CommandFrame` gets no adapter: its 10 sites are re-pointed in PR A and the file
is deleted, because leaving a chamfered primitive importable would let scene PRs
reintroduce exactly the geometry 1i forbids.

### Risk: this is the one change that can cost frame budget

The app currently uses **zero** `BackdropFilter`. Making 15 opaque surfaces
translucent is the riskiest part of this spec, and the exposure is the board
during a live wave. Mitigation: measure 1a's 9-blur target on device before the
scene PRs commit to it. If it does not hold, the fallback is tier-selective blur
(t3/t4 only, t1/t2 falling back to opaque fills) — not abandoning translucency.

## Geometry

Radius 14–20 for cards, 50% circles for single-action controls, 22px pills.
Nothing else.

This retires `CommandFrame`: its chamfered `CustomPainter` is precisely what 1i
forbids ("no chamfer, no bevelled plate"). Its 10 call sites move to
`OrionSurface`, and `commandFramePath` plus its tests are **deleted** rather than
left dead — matching the `ReactorButton` handling in `5a27b2a`.

Angular silhouettes remain legal for **icons only** (R&D crystal, credit token,
medal chevron) and never for a surface. That separation is what keeps sprites
reading as objects and chrome reading as glass.

## Motion

Named durations on the theme: lane flow 1.1s linear, idle bob 1.6–3s, hull pulse
2.4s, press feedback 90ms, sheet 220ms. All route through the existing
`orionMotionDuration`, so `MediaQuery.disableAnimationsOf` keeps working
unchanged.

## Art intake

Twelve files pulled from the design project into the existing `reactor_rim_ui/`
layout:

- `crests/` ×7 — one per campaign stage. The export renders five; all seven are
  taken so `singularity-core` and `void-bastion` are not a later gap.
- `boards/` ×3 — `nebula`, `foundry`, `void`.
- `backdrops/command-center.png` — `scene_cic`, the 1c scanner backdrop.

`orion_terrain_mock.png` is **skipped**: nothing in 1a–1h references it and it
reads as a mock leftover.

`OrionSceneArt` gains `commandCenter`. Crests get a `Map<StageId, OrionArtDescriptor>`
alongside the existing stage map, reusing `sourceRectFor` rather than adding a
parallel path API — the constraint `bd294f3` locked in. Files are normalized to
render size with `sips`, as `6e3f878` did, to avoid repeating that cleanup.

**PR A lands the board skins; it does not adopt them.** Whether the board is
actually skinned per stage is a case-by-case ratification against #29's explicit
rejection, and it belongs to PR B where the board is rebuilt.

## Testing

Four tripwires, in the spirit of the existing no-parallel-API scanner:

1. Blur values in `lib/` ⊆ {6, 7, 12, 14}
2. No `commandFramePath` reference survives in `lib/`
3. No game-UI widget reads `Theme.of(context).textTheme`
4. `microLabel` cannot resolve to `textPrimary`

Plus widget tests for the three type roles and four tiers, using the shared
`loadRealFonts` helper from `bd294f3`, extended to load the two new faces.

Existing gates continue to apply: `flutter test` (857 baseline), `flutter analyze`,
`dart format --set-exit-if-changed`.

## Open items deferred to scene PRs

- Board-skin adoption (PR B) — against #29's rejection.
- Radial tower actions and hold-to-salvage (PR B).
- Persistent tower tray (PR B) — against #29's "mock-only removed".
- `≤6 TOWER CAP` (PR C) — **known export error, to be rejected, not implemented.**
