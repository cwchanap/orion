# HPA-925 — Frostbitten enemies and winter environment (Implementation Plan)

Date: 2026-11-21  
Linear: https://linear.app/cwchanap/issue/HPA-925/orion-produce-frostbitten-enemy-boss-and-winter-board-art  
Design: [HPA-925 design spec](../specs/2026-11-21-hpa-925-frostbitten-winter-art-design.md)  
Parent: HPA-921 · Follow-on: HPA-926 · Parallel: HPA-927  
Baseline: main @ b3ae929ea56f1be266c5219a1bd218b7197a595c  
Reviews: [round 1](https://github.com/cwchanap/orion/pull/53#pullrequestreview-6009518738) · [round 2](https://github.com/cwchanap/orion/pull/53#pullrequestreview-6009761819)

**One ticket → one PR (#53).** This draft begins with design and plan; add art, a small **test-only** contract, selected screenshots and evidence to this same PR. No production Dart, pubspec, gameplay, sound or character art changes. No new asset registry, runtime dependency, CI job or generator script. Checkpoints are work slices, not extra PRs.

## Review decisions fixed before art production

- **Signature cells 14/15:** `OrionArt._specializations` uses `clusterBurst` for index 0 and `prismSplit` for index 1 **across all combat styles**. Neither is a Mio/Hikari-exclusive combat effect. Generate style-neutral **Signature A/B** inspector glyphs. A future per-character mapping, if desired, belongs in HPA-926.
- **Permanent Flutter test:** existing loader tests use synthetic/blank bitmaps, so add `test/game/scene_art_contract_test.dart` and extract only reusable PNG helpers from HPA-924's `test/game/character_art_contract_test.dart` into `test/support/`. Validate the **real 26 assets**, not only a local Pillow audit.
- **Path atlas:** existing 1774×887 / (4×2) gives fractional **443.5px** tiles. Save it at **1776×888** for integer **444px** cells. This is the **sole dimension exception**; the other 25 PNGs retain original sizes. `GamePathTiles` uses image-derived geometry and needs no Dart change.
- **Visual evidence:** use existing `ORION_CAPTURE_DIR` / `captureReactorRimFixture` screenshots for real UI before/after instead of a hand-built 22-image UI contact sheet or extra browser route. Keep a compact atlas + stage-crop contact sheet.
- **Real scale:** walkers/brutes ≈38.5px, bosses ≈70px, chibi size computed as `towerRadius * 4.2` (roughly 57px when an eight-column board occupies 390px). Do not apply one 36px target to all enemies.
- **Correct source paths/crops:** old tower cells are still brief sprite fallbacks and must remain pixel-identical; `OrionSceneArt` has 4 typed backdrops and `map-room.png` is direct in Codex; `world-map.png` is 640×640 RGB versus four 512×1110 RGBA tall backdrops; stage images are 1024×1024 and the centered wide crop uses **y=192…832**.
## Second-review decisions (before art generation)

- **Legacy test coupling:** Two shadow tests in `test/game/board_component_test.dart` assert the old sci-fi spawn/core silhouette and a test in `test/widget/title_screen_test.dart` insists the title backdrop has blue pixels. Use a **synthetic asymmetric sprite** for the former (test shadow behavior) and **palette-independent non-void coverage** for the latter (test actual backdrop presence). These are small test-only changes, not game code.
- **All-seven-boss coverage:** The Codex enemy fixture has *no bosses*; existing `fixture-boss-intel` and `fixture-boss-fight` cover the first boss only. Add a **test-only seven-boss strip** rendering `OrionArt.boss(boss.sprite)` at 70px beside `boss.name` for every `GameBalance.bosses`, captured via existing `ORION_CAPTURE_DIR`. Also capture the existing `world-map-shell-390x844` fixture.
- **Snow paths:** `orion_path_tiles.png` at 1776×888 must have 444px edge-to-edge **midpoint connectors**, verified in a local seam montage. Its cells do **not** need transparent gutters. In-game `BoardComponent` still deflates path cell rectangles by 1px and draws an opaque cyan vector `_renderLane` over tiles; that is an HPA-926 renderer follow-up, not an art failure.
- **Formats and dimensions:** Seven stages 1024×1024 RGB; seven crests 160×160 RGBA; two results 512×256 RGBA; board 512×768 RGBA; world-map 640×640 RGB; four tall backdrops 512×1110 RGBA. Existing UI RGBA surfaces are fully opaque. Contract should allow RGB *or* RGBA on opaque full-bleed art and check decoded alpha 255; three sprite/boss atlases require transparent RGBA, while crests may use alpha silhouettes.
- **Runtime detail:** `greenImpact`, `cryoImpact`, `gravityField` and `drone` atlas cells are not currently rendered: paint them in their assigned slots but do not expect them in battle screenshots. `BoardBackdropComponent` heavily darkens/vignettes/cover-crops `nebula.png`, and Stage Briefing uses it at 50% opacity, so make source board mid-bright and validate actual screenshots. Camp/Flare use a square 640px sprite size for a 512×1110 tall backdrop, distorting it: do **not** compensate by distorting source art; hand off to HPA-926.

## Checkpoint 0 — Audit the 26 original assets, approved references and tests

1. Sync to the PR branch/latest `main`; inspect HPA-925/921/926, approved HPA-921 lineup/mockup, final HPA-924 chibis, and the existing sprite loaders, stages and screenshot fixtures.
2. Inventory **26 existing image paths** and their actual sizes/color type/alpha/bytes, including fixed 25 and the path-atlas exception. Record baseline pixels for core tower cells 0–2, variety tower cells 0–4 and boss empty slot 7. Preserve original previews in ignored `tmp/`.
3. **Before art changes and before adding the new red-first contract**, capture baseline UI fixtures on main with `ORION_CAPTURE_DIR=tmp/hpa-925/before flutter test`. Use existing title, **world-map-shell-390x844**, briefing, **Codex regular-enemies**, **fixture-boss-intel/boss-fight (boss 0)**, mounted-radial and report captures when tests emit them. Do not claim these fixtures cover bosses 1–6 or Camp/Flare. No extra browser route.
4. Move reusable PNG IHDR, engine-codec decode/dispose, transparent-border and first-nonopaque-pixel helpers from `test/game/character_art_contract_test.dart` into `test/support/scene_art_test_helpers.dart`. Keep its existing tests green. Update two **old shadow tests** in `test/game/board_component_test.dart` to use synthetic asymmetrically opaque 4×3 sprites rather than the actual sci-fi asset; update the **title pixel** test in `test/widget/title_screen_test.dart` to assert non-void artwork coverage, not blue dominance. Preserve existing behavioral/render assertions; no production Dart.
5. Add `test/game/scene_art_contract_test.dart` enumerating **26 paths** from existing atlas/UI paths and `OrionCampaign.stages`. Check existence, actual Flutter `AssetManifest`, full `dart:ui` decode, fixed dimensions, **RGBA transparent sprite/boss atlases** and **RGB or RGBA with decoded full opacity** for backdrops/board/stages/results. Crests may have alpha silhouettes. Check atlas divisibility by production loader constants, full transparency of boss cell 7 and a **1px alpha gutter on the three sprite/boss atlases only** (not the path atlas). Legacy fallback cells must be preserved pixel-for-pixel. No new production dependencies.
6. **Red-first exception:** pre-art path atlas 1774×887 fails integer-cell contract; record this expected red. Baseline sprite/boss atlases already have clean 1px gutters. New test must become green after the path resize and art replacements; do not invent other red baseline failures.

**Gate:** 26-path inventory, baseline UI captures, reusable test contract and documented initial failures. These edits all stay in PR #53.

## Checkpoint 1 — Produce isolated Frostbitten sprites and combat effects

1. Reference-condition generation on the HPA-921 approvals and final HPA-924 sprites. Make Frostbitten walker/brute and seven distinct chibi-proportioned bosses in current `BossSprite` index order (Gatebreaker, Rime Matriarch, Brood Mother, Scrap Colossus, Thawless Warden, Corpse Hauler, Frost Heart). Avoid gore/text.
2. Create shared projectiles/effects for core/variety sheet slots using the design's exact enum-index table; **index 14 `clusterBurst` and index 15 `prismSplit` are neutral Signature A/B glyphs**, not Mio embers and Hikari sunlight.
3. Composite each generated transparent cell to the existing **4×3, 4×4, 4×2** atlas coordinates; preserve original tower-fallback cells pixel-identically and boss cell 7 fully transparent. Do not trust the image model's sheet order. Prevent alpha bleed into neighboring cells.
4. Replace `orion_sprite_sheet.png` (1448×1086), `orion_tower_variety_sheet.png` (1024×1024) and `orion_boss_sheet.png` (1024×512). Check 38.5px walker/brute, 70px boss and board-sized chibi previews. Use `fixture-codex-enemies` only for regular enemies and `mounted-radial` for combat; boss-intel/boss-fight show only index 0. Do not gate battle screenshots on the four currently unrendered slots: `greenImpact`, `cryoImpact`, `gravityField`, `drone`. The path-atlas contract may stay red until Checkpoint 2.

5. Add a compact **test-only, all-seven-boss strip capture** (in the new scene-art test or existing widget fixture). Compose `OrionAtlasSprite(art: OrionArt.boss(boss.sprite))` at **70px** with `boss.name` beside it for each `GameBalance.bosses`; assert seven loaded sprite widgets and capture with the existing `ORION_CAPTURE_DIR` helper. This checks all seven runtime atlas index→identity mappings, without a new browser route.

**Gate:** three atlas updates satisfy their contract, regular-enemy/battle and boss-0 fixtures pass, and all seven bosses render correctly in the new strip.

## Checkpoint 2 — Produce snow paths and the 22 UI illustrations

1. Replace `orion_path_tiles.png` at **1776×888** (4×2 integer cells) as eight **444×444 edge-to-edge snow-road tiles with midpoint connectors**. Check source connections via local seam montage and Flutter decoder/grid test; **no path-atlas alpha gutter**. `BoardComponent` still uses `.deflate(1)` and paints the cyan vector lane over the tile: document the runtime limitation for HPA-926 rather than modifying game code.
2. Replace five `reactor_rim_ui/backdrops/` PNGs in place: square world-map **640×640 RGB** and four tall **512×1110 RGBA** images (`command-center`, `tech-tree-rnd-bay`, `mission-report-debrief`, `map-room`). Opaque full-bleed output can be RGB or RGBA. Leave overlay-safe negative space, no text. Camp/Flare currently distort the tall camp backdrop through `Size.square(640)`; **do not pre-distort the PNG**—flag the renderer correction for HPA-926.
3. Replace `reactor_rim_ui/boards/nebula.png` at **512×768** (8:12), using mid-bright snow so paths, placement/targeting and characters remain visible **after** the `BoardBackdropComponent` darkening color matrix, radial vignette, cover crop, and Stage Briefing's 50%-opacity overlay.
4. Replace seven stage PNGs (**1024×1024 opaque; RGB baseline**) and seven crests (**160×160 RGBA source; alpha silhouette allowed**) under existing stage IDs. Keep focal action inside centered **1024×640** wide-briefing band (**y=192…832**) and readable at full-square map scale. No renamed IDs or baked text.
5. Replace `reactor_rim_ui/results/victory.png`/`defeat.png` at **512×256** and keep the full-bleed backdrop opaque, with text-overlay space. Do not regenerate acceptable art repeatedly.
6. Run appropriate permanent contract tests plus existing title, map, briefing, Codex and mission-report fixture captures after each affected group. Once all 26 files exist, the **entire new contract must be green**, including the previous fractional-path failure.

**Gate:** exactly 26 images replaced, 25 original dimensions retained and sole path atlas resized; real asset tests green; UI fixture surfaces readable.

## Checkpoint 3 — Automated local asset audit and evidence

1. Use throwaway local graphics tooling only for generation/compositing, **unused-cell pixel equality**, a path seam montage and a compact **four-atlas + stage-center-crop contact sheet**. The **committed Flutter scene-art contract** owns final pass/fail on real image size, decode, alpha, manifests and grid correctness; no extra Pillow CI system.
2. Capture matching before/after UI fixture pairs: `ORION_CAPTURE_DIR=tmp/hpa-925/before flutter test` (baseline) and `ORION_CAPTURE_DIR=tmp/hpa-925/after flutter test` (final). Include actual emitted title, **world-map-shell-390x844**, briefing, `fixture-codex-enemies` (+compact, **regular enemies**), `fixture-boss-intel`/`fixture-boss-fight` (**boss 0**), `mounted-radial`, report, and the **new seven-boss strip**. Existing fixtures do not capture Camp/Flare. Do not claim Codex shows bosses.
3. Commit **selected pairs** and the small contact sheet into `docs/superpowers/validation/hpa-925-evidence/`, with `docs/superpowers/validation/2026-11-21-hpa-925-winter-art.md` recording 26 asset sources/model/prompt, old/new dimensions, unused-cell equality, contract results, screenshot references and concrete comparisons to approved HPA-921/HPA-924 art. Keep API secrets, source bundles, many candidates and temp scripts ignored.
4. Do not judge sci-fi UI labels, the cyan lane or inset tile gaps as HPA-925 art failures; these remain HPA-926 copy/renderer work. Hand off the Camp/Flare tall-backdrop aspect correction there too.

**Gate:** real UI before/after evidence, traceable art provenance and new Flutter asset contract green. No extra browser route.

## Checkpoint 4 — Final-head test, MCP end-to-end, and screenshot acceptance

1. On the final head of **PR #53** run `flutter pub get`, `flutter analyze`, `flutter test test/game/scene_art_contract_test.dart`, `flutter test test/game/character_art_contract_test.dart`, `flutter test`, and `flutter build web --release`. Check GitHub CI. This is art/test-only; no backend E2E is relevant.
2. Run **one MCP-controlled Chrome/browser E2E**, not a manual walkthrough: **Title → World Map → Stage Briefing → Stage 1 battle**, deploy starter Haruto and Mio, start wave 1, and capture actual Frostbitten next to real chibis. Take **390×844** and **320×568** screenshots. A static mockup/contact sheet does not satisfy this E2E.
3. Compare MCP screenshots against HPA-921 mockup/HPA-924 chibis: ~38.5px ordinary Frostbitten, cold/warm separation, transformed snow board legibility, marker positions and no broken art. **Verify all seven boss mappings via the new strip**, not Codex; use existing boss-0, world map and scene fixtures for other art. The current cyan lane and inset tile gap are a HPA-926 follow-up. No second browser route.
4. Confirm diff contains **26 PNGs**, spec/plan, `scene_art_contract_test.dart` with seven-boss capture, minimal `test/support/` helper, adapted HPA-924 test and two legacy test-only revisions (`test/game/board_component_test.dart`, `test/widget/title_screen_test.dart`), plus scoped validation/screenshots. No production Dart, pubspec, stage copy, SFX, character art, balance or separate PR.

**Final gate:** green automated tests/build/CI, documented real MCP E2E and screenshot comparisons on one browser platform, no native or human acceptance criterion.

## End-to-end acceptance criteria (machine-verifiable, no human gate)

- [ ] Exactly **26 existing PNGs** replaced in place (4 atlases, 5 backdrops, board, 7 crests, 7 stages, 2 results). Original paths and grids unchanged; **25 same-size files** and a single `orion_path_tiles.png` resize **1774×887 → 1776×888**.
- [ ] Permanent `scene_art_contract_test.dart` verifies 26 real image paths, Flutter manifest, complete `dart:ui` decode, dimensions, full opacity for opaque full-bleed UI images (allow RGB/RGBA), integer atlas cells, 1px transparent gutters on **three sprite/boss atlases only**, boss slot 7 alpha==0; HPA-924 test remains green. Legacy shadow and title tests check behavior rather than old sci-fi asset pixels.
- [ ] `clusterBurst`/`prismSplit` show two **generic Signature A/B glyphs**, not character-specific effects. Distinct walkers/brutes visible at ~38.5px and seven bosses at ~70px beside final board-sized chibis, without gore/baked text.
- [ ] Eight **444px source snow-road tiles** join at midpoint connectors in local montage (**no path alpha-gutter test**); cyan lane and tile insets remain HPA-926 runtime work. Seven 1024×1024 stage images have central 1024×640 focal band; seven crests are 160×160; two results are 512×256. World-map and other surfaces remain legible, including board **after** runtime darkening/vignette.
- [ ] Real `ORION_CAPTURE_DIR` fixture pairs show title, **world map**, briefing, Codex **regular enemies**, boss-0 intel/fight, battle/report where emitted. A **new test-only seven-boss strip** renders all seven `OrionArt.boss` descriptors beside each `boss.name` at 70px to verify runtime mapping. A compact atlas/stage-crop sheet plus validation note covers remaining art.
- [ ] Final `flutter analyze`, `flutter test`, `flutter build web --release` and GitHub CI pass. No production Dart or pubspec changes; test-only edits include scene/art helpers, character contract reuse and two old tests decoupled from sci-fi pixels.
- [ ] **MCP-controlled Chrome E2E** runs title → map → briefing → stage 1 wave with Haruto/Mio and visible Frostbitten; real **390×844** and **320×568** screenshots compared to approved HPA-921 mockup and HPA-924 chibis. No manual or native acceptance.
- [ ] All changes/evidence remain in **PR #53**. HPA-927 owns SFX; HPA-926 owns copy, optional per-character glyph mapping, **cyan lane/tile inset** and **Camp/Flare tall-art aspect correction**. Do not distort assets to mask runtime bugs.
## Stop conditions / non-goals

If the ticket-specified generator/model is unavailable or input reference access fails, do not substitute an unapproved generator or fake evidence; record the blocker and retain the draft. Do not update player-visible strings or rename legacy file paths as part of this asset replacement. Human sign-off may occur outside the acceptance process but is **not** a merge/acceptance criterion.
