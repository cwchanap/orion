# HPA-925 — Frostbitten enemies and winter environment (Implementation Plan)

Date: 2026-11-21  
Linear: https://linear.app/cwchanap/issue/HPA-925/orion-produce-frostbitten-enemy-boss-and-winter-board-art  
Design: [HPA-925 design spec](../specs/2026-11-21-hpa-925-frostbitten-winter-art-design.md)  
Parent: HPA-921 · Follow-on: HPA-926 · Parallel: HPA-927  
Baseline: main @ b3ae929ea56f1be266c5219a1bd218b7197a595c  
Review: https://github.com/cwchanap/orion/pull/53#pullrequestreview-6009518738

**One ticket → one PR (#53).** This draft begins with design and plan; add art, a small **test-only** contract, selected screenshots and evidence to this same PR. No production Dart, pubspec, gameplay, sound or character art changes. No new asset registry, runtime dependency, CI job or generator script. Checkpoints are work slices, not extra PRs.

## Review decisions fixed before art production

- **Signature cells 14/15:** `OrionArt._specializations` uses `clusterBurst` for index 0 and `prismSplit` for index 1 **across all combat styles**. Neither is a Mio/Hikari-exclusive combat effect. Generate style-neutral **Signature A/B** inspector glyphs. A future per-character mapping, if desired, belongs in HPA-926.
- **Permanent Flutter test:** existing loader tests use synthetic/blank bitmaps, so add `test/game/scene_art_contract_test.dart` and extract only reusable PNG helpers from HPA-924's `test/game/character_art_contract_test.dart` into `test/support/`. Validate the **real 26 assets**, not only a local Pillow audit.
- **Path atlas:** existing 1774×887 / (4×2) gives fractional **443.5px** tiles. Save it at **1776×888** for integer **444px** cells. This is the **sole dimension exception**; the other 25 PNGs retain original sizes. `GamePathTiles` uses image-derived geometry and needs no Dart change.
- **Visual evidence:** use existing `ORION_CAPTURE_DIR` / `captureReactorRimFixture` screenshots for real UI before/after instead of a hand-built 22-image UI contact sheet or extra browser route. Keep a compact atlas + stage-crop contact sheet.
- **Real scale:** walkers/brutes ≈38.5px, bosses ≈70px, chibi size computed as `towerRadius * 4.2` (roughly 57px when an eight-column board occupies 390px). Do not apply one 36px target to all enemies.
- **Correct source paths/crops:** old tower cells are still brief sprite fallbacks and must remain pixel-identical; `OrionSceneArt` has 4 typed backdrops and `map-room.png` is direct in Codex; `world-map.png` is 640×640 RGB versus four 512×1110 RGBA tall backdrops; stage images are 1024×1024 and the centered wide crop uses **y=192…832**.
## Checkpoint 0 — Audit the 26 original assets, approved references and tests

1. Sync to the PR branch/latest `main`; inspect HPA-925/921/926, approved HPA-921 lineup/mockup, final HPA-924 chibis, and the existing sprite loaders, stages and screenshot fixtures.
2. Inventory **26 existing image paths** and their actual sizes/color type/alpha/bytes, including fixed 25 and the path-atlas exception. Record baseline pixels for core tower cells 0–2, variety tower cells 0–4 and boss empty slot 7. Preserve original previews in ignored `tmp/`.
3. **Before art changes and before adding the new red-first contract**, capture baseline UI fixtures on main with `ORION_CAPTURE_DIR=tmp/hpa-925/before flutter test`. Use existing title, briefing, Codex-enemies, mounted-radial and report captures that are actually emitted by tests. Do not invent extra navigation scripts.
4. Move only reusable test helpers (PNG IHDR, sequential `dart:ui` image decode with disposal, transparent-border check) from `test/game/character_art_contract_test.dart` into `test/support/scene_art_test_helpers.dart`. Keep the character art test green by importing the helper; avoid a new runtime dependency.
5. Add `test/game/scene_art_contract_test.dart` enumerating **all 26 paths** from fixed atlas/UI paths and `OrionCampaign.stages`. Verify file existence, Flutter `AssetManifest` registration, full engine-codec decode, per-role dimensions/color/alpha (world-map stays RGB), atlas width/height divisibility by the **existing loader constants**, boss cell 7 transparent and a **1px alpha gutter on newly generated sprite slots**. Legacy fallback tower cells remain pixel-identical, not forcibly retouched. Use pixel inspection, not IHDR-only assertions.
6. **Red-first exception:** pre-art path atlas 1774×887 fails integer-cell contract; record this expected red and any pre-existing gutter failures. Do not claim baseline tests green when known failures exist. Other checks should remain green; final full test must pass once replacement files are ready.

**Gate:** 26-path inventory, baseline UI captures, reusable test contract and documented initial failures. These edits all stay in PR #53.

## Checkpoint 1 — Produce isolated Frostbitten sprites and combat effects

1. Reference-condition generation on the HPA-921 approvals and final HPA-924 sprites. Make Frostbitten walker/brute and seven distinct chibi-proportioned bosses in current `BossSprite` index order (Gatebreaker, Rime Matriarch, Brood Mother, Scrap Colossus, Thawless Warden, Corpse Hauler, Frost Heart). Avoid gore/text.
2. Create shared projectiles/effects for core/variety sheet slots using the design's exact enum-index table; **index 14 `clusterBurst` and index 15 `prismSplit` are neutral Signature A/B glyphs**, not Mio embers and Hikari sunlight.
3. Composite each generated transparent cell to the existing **4×3, 4×4, 4×2** atlas coordinates; preserve original tower-fallback cells pixel-identically and boss cell 7 fully transparent. Do not trust the image model's sheet order. Prevent alpha bleed into neighboring cells.
4. Replace `orion_sprite_sheet.png` (1448×1086), `orion_tower_variety_sheet.png` (1024×1024) and `orion_boss_sheet.png` (1024×512). Check 38.5px walker/brute, 70px boss and board-sized chibi previews; run the relevant new contract assertions and compare real `fixture-codex-enemies`/`mounted-radial` captures. The path-atlas test may stay red until Checkpoint 2.

**Gate:** three atlas updates satisfy their contract and show correct boss identity/size in existing Codex and battle renderer captures.

## Checkpoint 2 — Produce snow paths and the 22 UI illustrations

1. Replace `orion_path_tiles.png` as an eight-cell snow-road atlas at **1776×888** (4×2 integer cells). Keep GamePathTile index order, edge connectors and lane width; verify a temporary seam montage, engine decode and the permanent atlas divisibility assertion.
2. Replace all five `reactor_rim_ui/backdrops/` PNGs in place: **`world-map.png` square 640×640 RGB**, and `command-center.png`, `tech-tree-rnd-bay.png`, `mission-report-debrief.png`, `map-room.png` each 512×1110 RGBA. Existing 4 typed scene descriptors plus the direct Codex map-room path remain unchanged. Leave overlay-safe negative space; no painted text.
3. Replace `reactor_rim_ui/boards/nebula.png` at original 8:12 / 512×768, keeping paths, placement/targeting markers and chibi-versus-enemy contrast readable.
4. Replace seven `reactor_rim_ui/stages/{id}.png` + seven `crests/{id}.png` using existing stage IDs. Stage images remain 1024×1024; keep focal action in the centered **1024×640** wide-briefing band (**y=192…832**) and also readable at full-square map scale. No renamed file IDs or baked labels.
5. Replace `reactor_rim_ui/results/victory.png`/`defeat.png` at original sizes; preserve text-overlay space. Do not regenerate acceptable candidate art repeatedly.
6. Run appropriate permanent contract tests plus existing title, map, briefing, Codex and mission-report fixture captures after each affected group. Once all 26 files exist, the **entire new contract must be green**, including the previous fractional-path failure.

**Gate:** exactly 26 images replaced, 25 original dimensions retained and sole path atlas resized; real asset tests green; UI fixture surfaces readable.

## Checkpoint 3 — Automated local asset audit and evidence

1. Use throwaway local graphics tooling only for generation/compositing, **unused-cell pixel equality**, a path seam montage and a compact **four-atlas + stage-center-crop contact sheet**. The **committed Flutter scene-art contract** owns final pass/fail on real image size, decode, alpha, manifests and grid correctness; no extra Pillow CI system.
2. Capture matching **before/after UI fixture pairs** from the existing harness: baseline `ORION_CAPTURE_DIR=tmp/hpa-925/before flutter test`, final `ORION_CAPTURE_DIR=tmp/hpa-925/after flutter test`. Include `title-shell-390x844`, `briefing-live-390x844`, `fixture-codex-enemies` (+ compact), `mounted-radial` and mission report only where existing tests emit them. The Codex capture verifies the riskiest boss-index-to-identity mapping in the real renderer.
3. Commit **selected pairs** and the small contact sheet into `docs/superpowers/validation/hpa-925-evidence/`, with `docs/superpowers/validation/2026-11-21-hpa-925-winter-art.md` recording 26 asset sources/model/prompt, old/new dimensions, unused-cell equality, contract results, screenshot references and concrete comparisons to approved HPA-921/HPA-924 art. Keep API secrets, source bundles, many candidates and temp scripts ignored.
4. Do not judge current sci-fi UI labels as art failures; text renaming belongs in HPA-926.

**Gate:** real UI before/after evidence, traceable art provenance and new Flutter asset contract green. No extra browser route.

## Checkpoint 4 — Final-head test, MCP end-to-end, and screenshot acceptance

1. On the final head of **PR #53** run `flutter pub get`, `flutter analyze`, `flutter test test/game/scene_art_contract_test.dart`, `flutter test test/game/character_art_contract_test.dart`, `flutter test`, and `flutter build web --release`. Check GitHub CI. This is art/test-only; no backend E2E is relevant.
2. Run **one MCP-controlled Chrome/browser E2E**, not a manual walkthrough: **Title → World Map → Stage Briefing → Stage 1 battle**, deploy starter Haruto and Mio, start wave 1, and capture actual Frostbitten next to real chibis. Take **390×844** and **320×568** screenshots. A static mockup/contact sheet does not satisfy this E2E.
3. Compare the real screenshots to the approved HPA-921 six-screen mockup and final HPA-924 chibis. Check enemy sizes (ordinary ~38.5px, bosses ~70px through fixtures), path and marker placement, warmth/cold separation, readable board and no broken/fallback art. Use the **existing** deterministic fixture screenshots for boss identity, remaining backdrops and result panels; do not add a new browser route.
4. Confirm diff contains **26 PNGs**, these two docs, one **scene art contract test**, minimal `test/support/` helper and adapted HPA-924 test, plus scoped validation/screenshots. No production Dart, pubspec, stage copy, sound, character art, balance or separate PR. Record required CI checks and MCP screenshot paths in validation note.

**Final gate:** green automated tests/build/CI, documented real MCP E2E and screenshot comparisons on one browser platform, no native or human acceptance criterion.

## End-to-end acceptance criteria (machine-verifiable, no human gate)

- [ ] Exactly **26 existing PNGs** replaced in place (4 atlases, 5 backdrops, board, 7 crests, 7 stages, 2 results). Original paths and grids unchanged; **25 same-size files** and a single `orion_path_tiles.png` resize **1774×887 → 1776×888**.
- [ ] New `scene_art_contract_test.dart` verifies all 26 image paths and Flutter manifest entries, complete `dart:ui` decoding, dimension/mode/alpha checks, integer atlas cells, 1px gutters for new sprite cells and empty boss slot 7. Unused tower fallbacks remain pixel-identical; HPA-924 character art contract still passes after shared-helper extraction.
- [ ] `clusterBurst`/`prismSplit` show two **generic Signature A/B glyphs**, not character-specific effects. Distinct walkers/brutes visible at ~38.5px and seven bosses at ~70px beside final board-sized chibis, without gore/baked text.
- [ ] Eight snow-road tiles join cleanly. Seven stage key images have focal subjects in the centered 1024×640 band; square world-map RGB and four tall RGBA backdrops render correctly. Board, crests and results remain legible behind existing UI.
- [ ] Existing `ORION_CAPTURE_DIR` fixture pairs provide before/after evidence of title/briefing/Codex/battle/report as available; small atlas + stage-crop contact sheet and validation provenance cover all assets, including correct boss identity next to its existing Codex name.
- [ ] Final `flutter analyze`, `flutter test`, `flutter build web --release` and GitHub CI all pass. Production Dart and pubspec untouched; only test-only Dart updates allowed.
- [ ] **MCP-controlled Chrome E2E** runs title → map → briefing → stage 1 wave with Haruto/Mio and visible Frostbitten; real **390×844** and **320×568** screenshots compared to approved HPA-921 mockup and HPA-924 chibis. No manual or native acceptance.
- [ ] All changes/evidence remain in **this PR #53**. HPA-927 owns new SFX; HPA-926 owns all game integration/copy and any future per-character signature art mapping.
## Stop conditions / non-goals

If the ticket-specified generator/model is unavailable or input reference access fails, do not substitute an unapproved generator or fake evidence; record the blocker and retain the draft. Do not update player-visible strings or rename legacy file paths as part of this asset replacement. Human sign-off may occur outside the acceptance process but is **not** a merge/acceptance criterion.
