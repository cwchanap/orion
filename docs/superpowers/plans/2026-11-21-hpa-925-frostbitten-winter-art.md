# HPA-925 — Frostbitten enemies and winter environment (Implementation Plan)

Date: 2026-11-21  
Linear: https://linear.app/cwchanap/issue/HPA-925/orion-produce-frostbitten-enemy-boss-and-winter-board-art  
Design: [HPA-925 design spec](../specs/2026-11-21-hpa-925-frostbitten-winter-art-design.md)  
Parent: HPA-921 · Follow-on: HPA-926 · Parallel: HPA-927  
Baseline: main @ b3ae929ea56f1be266c5219a1bd218b7197a595c

**One ticket → one PR.** This draft PR contains the spec and plan first. The later agent commits all asset replacements, validation and screenshots **to this same PR**; checkpoints are not separate tickets or PRs. No Dart implementation, asset registry, new Flutter dependency or generated source bundles.

## Checkpoint 0 — Audit the 26 original assets, approved references and tests

1. Sync with latest main and read the design spec, HPA-925/921/926 and HPA-924 final assets. Collect the approved HPA-921 lineup/chibi/mockup attachments as style reference; work in ignored **tmp/**.
2. Inventory **4 sprite atlases + 22 Reactor Rim PNGs** by exact repository path. For each original PNG, record pixel dimensions, mode/alpha, bytes and intended placement/crops. Save an original-contact-sheet snapshot. Do not assume sample dimensions in tests are actual original metadata.
3. Enumerate cell geometry using **GameSpriteSheet (4×3)**, **GameTowerVarietySheet (4×4)**, **GameBossSheet (4×2)** and **GamePathTiles (4×2)**. Save exact baseline pixels for unused tower cells (core slots 0–2, variety slots 0–4) and the empty boss slot 7. Validate the existing board skin's 8:12 aspect and the center-square/center-wide stage crop.
4. Locate the existing test coverage: **test/game/game_sprite_sheet_test.dart**, **game_boss_sheet_test.dart**, **game_path_tiles_test.dart**, **game_board_skin_test.dart**, **test/widget/orion_art_test.dart**, and the scene parity fixtures. No changes to those tests or lib are part of this ticket.

**Gate:** inventory of all 26 paths and reference set complete; before images and baseline image metadata captured.

## Checkpoint 1 — Produce isolated Frostbitten sprites and combat effects

1. Reference-condition generation on approved HPA-921 art and final HPA-924 chibis. Make distinct three-quarter-view Frostbitten walker and brute; generate seven bosses with role-specific silhouettes in the fixed **BossSprite** order (Gatebreaker, Rime Matriarch, Brood Mother, Scrap Colossus, Thawless Warden, Corpse Hauler, Frost Heart). Avoid gore, text, and generic indistinguishable snow monsters.
2. Generate shared projectiles/effects for both combat atlases according to the **index-by-index design table**, not loosely named sheet positions. Check that Haruto/Hikari, Mio/Akane, Rin/Jin and Sayo/Elena can share their indicated cells.
3. Crop, clean alpha and composite each individual sprite to its **original atlas cell**, not a different global grid. Retain the pixel-exact original unused tower cells and transparent boss slot 7; leave enough inner padding so animation sampling never catches a neighbor.
4. Replace in place **orion_sprite_sheet.png**, **orion_tower_variety_sheet.png**, **orion_boss_sheet.png**. Verify full PNG decode, exact original width/height, cell bounds, transparent padding, and 36px/48px side-by-side comparisons against Haruto/Mio chibis.

**Gate:** three gameplay atlases display the correct new visuals with their original grids and no incorrect or reused slot.

## Checkpoint 2 — Produce snow paths and the 22 UI illustrations

1. For **orion_path_tiles.png**, design eight snow-road variants in **GamePathTile** order. Composite at existing cell positions; keep current lane connectors, continuous width, edges and path directions. Validate a local montage of horizontal/vertical/corner/end-cap joins.
2. Replace the five existing **reactor_rim_ui/backdrops/** files in place: title/command center, world map, Camp interior (file still **tech-tree-rnd-bay.png**), mission report and Codex map-room. Leave negative space where current widgets overlay them; no text/branding baked into PNGs.
3. Replace **reactor_rim_ui/boards/nebula.png** with a winter board at its original resolution and 8:12 ratio. Keep paths, placement highlights and characters readable, including the central board area.
4. For each existing stage ID (**outpost-alpha**, **nebula-relay**, **salvage-rift**, **asteroid-foundry**, **aurora-gate**, **void-bastion**, **singularity-core**), replace its **stages/{id}.png** and **crests/{id}.png**. Use HPA-926's proposed place themes but do not rename any path or add visible labels. Preview both center-wide briefing and center-square world-map crop for every stage.
5. Replace **reactor_rim_ui/results/victory.png** and **defeat.png** with warm survival/fading Hearth compositions. Keep original sizing and overlay-safe negative space.
6. Avoid regeneration of already acceptable candidates; prioritize correction of demonstrable crop, alpha, readability or style mismatches. Keep source intermediates in ignored **tmp/**.

**Gate:** all 26 existing PNG target paths updated; 22 UI images fit current dimensions and UI crops; no changes to source code or asset registration.

## Checkpoint 3 — Automated local asset audit and evidence

1. Use **temporary local Pillow/graphics tooling** (not a new committed app dependency) to enumerate the 26 final files and compare against baseline metadata: same filenames, PNG dimensions, grid size, decodability, alpha and expected image variants. Assert unused atlas cell pixel equality and empty final boss cell. Inspect nearby pixel borders for bleed and path tile joins.
2. Compose **two before/after contact sheets**, one for the four sprite atlases (including a 36px enemy vs 48px chibi row) and one for the 22 UI images (show stage square/wide crops). Use current approved references, not invented screenshots. Record model, prompt, reference asset and retouch method per changed group in a short provenance section.
3. Save a concise validation report at **docs/superpowers/validation/2026-11-21-hpa-925-winter-art.md**, and small contact sheets under **docs/superpowers/validation/hpa-925-evidence/**. Do not commit source ZIPs, prompts with secrets, API responses, candidate batches, private absolute paths or a generator script.

**Gate:** mechanical checks of file/slot stability pass and the contact sheets demonstrate visual consistency and small-scale legibility.

## Checkpoint 4 — Final-head test, MCP end-to-end, and screenshot acceptance

1. Run on the **final art head**:
   ~~~bash
   flutter pub get
   flutter analyze
   flutter test
   flutter build web --release
   ~~~
   Verify CI green. Existing loader, widget and campaign tests should pass unchanged. This is not a backend change, so no backend E2E is needed.
2. Run **one MCP-controlled Chrome/browser E2E** against the real game on a single platform: navigate **Title → World Map → Stage Briefing → Stage 1 battle**, deploy the starter Haruto and Mio, and start a wave. Screenshot the actual winter board with both friendly chibi and Frostbitten enemy sprites rendered. Do not count a static mockup alone as the E2E.
3. Capture at **390×844** and (for layout legibility) **320×568**. Compare the art to the approved six-screen mockup on HPA-921 and the HPA-924 final chibi set. Check warm/cold separation, 36px enemy visibility, board contrast, correctly placed Hearth/breach, seamless paths, legible crests and no fallback/broken assets.
4. Use existing deterministic screenshot fixtures or a short additional automated browser route for hard-to-reach bosses, result screens and the remaining backdrops. Compare matching surfaces only: **do not claim HPA-926's future UI/copy retheme has shipped**. Record screenshot filenames, references, observed discrepancies and resolutions in the validation note.
5. Re-check diff and base: only **26 PNG paths**, this spec/plan and scoped validation/evidence files should change. No changes to production Dart, test Dart, pubspec, characters, audio, mechanics, balance or labels. One PR only.

**Gate:** green analyze/test/web build; screenshot-backed MCP E2E at one browser platform; image/cell and mockup comparison documented with no unexplained visual mismatches.

## End-to-end acceptance criteria (all machine/verifiable; no human approval gate)

- [ ] **26 existing PNG files** replaced in place (4 gameplay atlases, 5 backdrops, 1 board, 7 crests, 7 stages, 2 results), retaining exact original filenames and pixel dimensions. No extra runtime art files.
- [ ] Core **4×3**, variety **4×4**, boss **4×2**, path **4×2** atlas contracts unchanged. Original unused tower cells are byte/pixel identical; eighth boss cell remains empty; no cross-cell bleed; all images fully decode.
- [ ] Walker/brute/boss art looks Frostbitten and distinct at **~36px**, visually consistent alongside actual **~48px** HPA-924 chibis. Shared projectile slots serve both related characters; no gore or baked text.
- [ ] Eight snow road tiles join seamlessly. Board keeps units, paths, placements readable. All seven stage illustrations survive both square map and wide briefing crops; five backdrops, seven crests and two results are legible behind current UI.
- [ ] Contact sheets show the **before/after** of every changed asset and an enemy/chibi comparison, with generator/source provenance and objective artifact checks in the committed validation note.
- [ ] **flutter analyze**, **flutter test**, **flutter build web --release** and PR CI succeed on final head with **no Dart or pubspec changes**.
- [ ] MCP browser E2E succeeds from title through stage 1 combat, deploying Haruto/Mio and rendering a Frostbitten enemy; **real screenshots** compared against HPA-921's approved mockup (390×844 plus compact screenshot). Boss/results/remaining scene art is evidenced with deterministic screenshots/contact sheets; no native manual acceptance.
- [ ] All actual implementation/evidence commits go onto **this same HPA-925 PR**; SFX stays in HPA-927 and content/copy integration stays in HPA-926.

## Stop conditions / non-goals

If the ticket-specified generator/model is unavailable or input reference access fails, do not substitute an unapproved generator or fake evidence; record the blocker and retain the draft. Do not update player-visible strings or rename legacy file paths as part of this asset replacement. Human sign-off may occur outside the acceptance process but is **not** a merge/acceptance criterion.
