# HPA-925 — Frostbitten enemies and winter environment (Design Spec)

Date: 2026-11-21  
Linear: https://linear.app/cwchanap/issue/HPA-925/orion-produce-frostbitten-enemy-boss-and-winter-board-art  
Parent: https://linear.app/cwchanap/issue/HPA-921/orion-pivot-to-last-hearth-an-anime-character-tower-defense  
Downstream integration: HPA-926 (blocked by this ticket and HPA-927)  
Baseline: main @ b3ae929ea56f1be266c5219a1bd218b7197a595c

## Outcome and scope

Deliver **the winter/Frostbitten art as one asset-only PR**, initially opened with this design and its implementation plan. The same PR later receives the generated art and validation evidence. It replaces **26 existing PNG files in place**: four gameplay atlases and 22 Reactor Rim UI images. Existing filenames, grid order, image crop paths, Flutter registration and production loaders are fixed. Pixel dimensions stay fixed for **25 files**; the path atlas is the sole approved dimension correction (1774×887 → 1776×888) to obtain integer tile cells.

This task must not edit **production** Dart, pubspec.yaml, stages/waves/balance, gameplay, copy, character portraits/chibis, sound or music. A small **test-only** asset contract and extraction of existing test helpers into `test/support/` are in scope so the 26 actual PNGs remain validated by CI. HPA-924 owns the 12 final characters (already complete); HPA-927 independently owns SFX; HPA-926 owns renaming, art hookup where needed and overall Last Hearth integration. No new art IDs, sprite registry, generator package, runtime dependency, migrations or platform-specific implementation.

## Verified integration baseline

- The four sprite loaders are **GameSpriteSheet** (4 × 3, currently 1448×1086, 362px cells), **GameTowerVarietySheet** (4 × 4, 1024×1024, 256px cells), **GameBossSheet** (4 × 2, 1024×512, 256px cells, seven occupied boss slots), and **GamePathTiles** (4 × 2, currently 1774×887, **443.5px** cells). They slice by enum/index and actual image dimensions in **lib/game/assets/**. Do not change the loaders. Re-save only the path atlas at **1776×888** (444px square cells, unchanged 2:1 aspect ratio) to avoid fractional atlas boundaries; no hard-coded source image dimensions need changing.
- **GameBoardSkin** uses **reactor_rim_ui/boards/nebula.png** at a fixed 8:12 board ratio (documented 512 × 768). The board is 8 × 12 cells; emphasize paths, units and interaction, not terrain noise.
- **OrionArt** resolves four scene backdrops (`OrionSceneArt`), seven stage images and crests, two result illustrations and a boss atlas. The fifth backdrop, Codex `map-room.png`, loads via an existing direct path in `codex_view.dart`. Stage images are **1024×1024**: the mapSquare crop uses the full square while briefingWide uses the centered **1024×640** band. Compose focal subjects inside **y = 192…832**, leaving the side margin suitable for both surfaces.
- The original 26 paths are all registered by existing **pubspec.yaml** entries, including the five Reactor Rim subdirectories. No registration change is needed. `world-map.png` is **640×640 opaque RGB**; the other four tall backdrops are **512×1110 RGBA**. Maintain these distinct aspect/mode contracts.
- Character art from HPA-924 is already available in **assets/images/characters/{id}/**. Use existing Haruto/Mio chibis for battle scale comparisons; use the approved lineup and six-screen Last Hearth mockup attached to HPA-921 as style/visual references.

## Exact asset replacement inventory

| Directory / file | Count | Visual responsibility |
| --- | ---: | --- |
| assets/images/orion_sprite_sheet.png | 1 | Walkers/brutes, shared projectile effects, snow-wall breach, Orion Hearth |
| assets/images/orion_tower_variety_sheet.png | 1 | Remaining combat projectiles/effects and status indicators |
| assets/images/orion_boss_sheet.png | 1 | Seven named Frostbitten bosses; eighth cell empty |
| assets/images/orion_path_tiles.png | 1 | Eight seamless snow-road/path tile variants; **1776×888** final size (only dimension exception) |
| assets/images/reactor_rim_ui/backdrops/ | 5 | world-map is square RGB (640×640); four tall RGBA (512×1110): command-center, tech-tree-rnd-bay (Camp), mission-report-debrief, map-room |
| assets/images/reactor_rim_ui/boards/nebula.png | 1 | Snowy combat board with quieter build zones |
| assets/images/reactor_rim_ui/crests/ | 7 | One crest per existing stage ID |
| assets/images/reactor_rim_ui/stages/ | 7 | Square 1024×1024 key art per existing stage ID, with focal subject in center 1024×640 band |
| assets/images/reactor_rim_ui/results/ | 2 | victory: warm camp survival; defeat: fading Hearth in winter |
| **Total** | **26** | **Existing filenames and pixel dimensions stay identical** |

Seven existing stage IDs, used for BOTH crests and stages: **outpost-alpha**, **nebula-relay**, **salvage-rift**, **asteroid-foundry**, **aurora-gate**, **void-bastion**, **singularity-core**. Depict the Hokkaido locations from HPA-926's proposed names (Ember Road, Frozen Rail Yard, Sunken Depot, Dead Foundry, Aurora Gate, White Bastion, The Cold Heart) **without changing paths or adding painted-on labels**.

## Sprite-cell contract — never rely on a generated sheet's visual ordering

### orion_sprite_sheet.png — 4 columns × 3 rows, left-to-right/top-to-bottom

| Index | Existing enum slot | Final visual |
| ---: | --- | --- |
| 0–2 | laserTower, rocketTower, cryoTower | **Preserve original pixels:** these still serve as brief visual fallback while character chibi sprites load |
| 3 | basicDroneEnemy | Chibi-proportioned Frostbitten walker |
| 4 | heavyDroneEnemy | Chibi-proportioned Frostbitten brute |
| 5 | laserBolt | Warm light tracer, shared by Haruto and Hikari |
| 6 | rocketProjectile | Small fireball, shared by Mio and Akane |
| 7 | cryoProjectile | Frost shard, shared by Rin and Jin |
| 8 | spawnGate | Breach in snow wall |
| 9 | baseReactor | Orion Hearth with readable warm flame |
| 10 | greenImpact | Warm impact spark |
| 11 | cryoImpact | Frost burst |

### orion_tower_variety_sheet.png — 4 columns × 4 rows

| Index | Existing enum slot | Final visual |
| ---: | --- | --- |
| 0–4 | railgunTower, ionChainTower, naniteTower, gravityWellTower, droneBayTower | **Preserve original pixels:** brief tower fallbacks before character chibis load |
| 5 | railSlug | Streaking arrow / sniper round, legible for Sayo and Elena |
| 6 | ionArc | Lightning arc |
| 7 | naniteCloud | Serum cloud |
| 8 | gravityField | Gravity distortion |
| 9 | drone | Scrap drone |
| 10 | shieldIndicator | Ice shell |
| 11 | armorIndicator | Scrap plating |
| 12 | regenIndicator | Regrowth |
| 13 | corrosionIndicator | Corrosion |
| 14 | clusterBurst | **Style-neutral signature A glyph** (first specialization of *every* combat style); no specific character/fire imagery |
| 15 | prismSplit | **Style-neutral signature B glyph** (second specialization of *every* combat style); no specific character/sunbeam imagery |

### orion_boss_sheet.png — 4 columns × 2 rows

Indices 0–6, in the immutable **BossSprite** order: **relayBreaker** → Gatebreaker; **shieldMatriarch** → Rime Matriarch; **swarmQueen** → Brood Mother; **armoredExcavator** → Scrap Colossus; **regenWarden** → Thawless Warden; **siegeCarrier** → Corpse Hauler; **singularityCore** → The Frost Heart. Keep index 7 empty/transparent. Each boss should read as a distinct Frostbitten chibi-scale silhouette and communicate its existing trait without new mechanics.

### orion_path_tiles.png — 4 columns × 2 rows, 1776×888 final

In **GamePathTile** enum order: horizontal, vertical, cornerNorthEast, cornerNorthWest, cornerSouthEast, cornerSouthWest, startCap, endCap. Match the **current** connector positions and lane width, with consistent snow/ice at all adjoining edges. Keep existing gameplay paths intact.

## Visual art direction and composition

- Source of truth: HPA-921's approved Last Hearth lineup, chibi sheet and six-screen UI mockup; HPA-924's final in-repo character art. Consistent anime, clean cel shading and crisp line art. Enemies/bosses are **eerie, frozen and non-gory**, in three-quarter view, with chibi proportions; the enemy should still clearly differ from a friendly Kindled character.
- Palette: icy whites and blue/cyan for the Frostbitten and Hokkaido landscape; amber/coral/orange for the Hearth, survivors and safe camp interior. Prioritize contrast over decorative detail.
- **Match actual renderer sizes**, not a universal 36px target: ordinary walkers/brutes render at **~38.5px** (`radius=11`, `spriteExtentFactor=1.75`), bosses at **~70px** (`radius=20`), and character chibis at `towerRadius × 4.2`, where `towerRadius = clamp(cellSize × 0.28, 8, 18)` (approximately **57px** for a 390px-wide, 8-column board). Test silhouettes at these sizes beside final HPA-924 chibis; leave transparent padding and avoid cross-cell bleed.
- Warm tracers/fire, cool shards, lightning, serum, gravity, drones and status icons must distinguish mechanics at gameplay scale without text. A slot shared by two characters should read well for both.
- Stage illustrations: visually differentiate seven locations and keep the focal subject within **y=192…832** of the 1024px square; mapSquare shows the full 1024px square, briefingWide shows the center 1024×640 band. Crests stay readable in small map tiles. Respect the square `world-map.png` composition separately from the other four tall backdrops, and leave negative space for overlays.
- The board skin must keep units, path, targeting markers and placement grid visible. Path tiles must form seamless straight segments and corners. Result art must support the current UI labels rather than baking text into images.
- Preserve original PNG dimensions for **25 assets** and keep the four atlas grids and cell indices unchanged; the sole dimension change is `orion_path_tiles.png` **1774×887 → 1776×888** so its 4×2 grid has integer 444px cells. Preserve alpha intent and image crop/placement. Do not bake in renamed stage/boss labels; HPA-926 changes UI copy later.

## Art production approach (no app code)

Use the art-generation method specified in HPA-925 (OpenAI Image API and the issue's model, reference-conditioned on approved images). Work on the owner's machine using existing secured configuration; never log or commit credentials. If the specified generator is unavailable, **do not silently swap providers**; the issue requires approval before the fallback.

Keep scratch source/reference files and multiple candidates in ignored **tmp/**. Generate individual transparent sprite/cell candidates as necessary, then composite at the original atlas cell coordinates instead of trusting the image model to maintain exact enum order. Keep unused cells pixel-identical; leave the final boss cell empty. For larger scene art, crop/reframe to the **current** asset dimensions rather than modifying Dart crop logic. A local, throwaway Pillow/graphics script is sufficient; do not add a production generator or a new CI dependency.

Track source/reference, generator/model/prompt and generation vs retouch in one validation note; no separate duplicated art registry is needed. **Existing signature icon caveat:** `OrionArt._specializations` chooses `clusterBurst` for specialization index 0 and `prismSplit` for index 1 across *all* tower types, including Mio's `clusterRocket` at index 1. Keep both neutral for this asset-only PR. If specific per-character signature glyphs are desired, defer the `OrionArt` mapping change to **HPA-926**, not this art ticket.

## Permanent asset contract (test-only Dart, no production changes)

- Extract reusable PNG decode/IHDR/border helpers from `test/game/character_art_contract_test.dart` to a small `test/support/` helper so the character and new scene tests share the same engine-codec validation without duplicated registries.
- Add `test/game/scene_art_contract_test.dart` **in Checkpoint 0**. It enumerates exactly 26 canonical existing asset paths using the existing stage IDs; asserts file existence and `AssetManifest` inclusion; fully decodes each file via `dart:ui` (disposing each image); verifies PNG dimensions and alpha/color-type expectations by asset role; checks core/variety/boss/path atlas divisibility against loader constants; checks boss slot 7's fully transparent pixels and 1px transparent gutters of **replaced/occupied sprite cells**. Legacy unused tower fallback cells are allowed to remain pixel-identical, not forced through a destructive retouch.
- The **known baseline path-atlas divisibility failure** (1774÷4 = 443.5) and any discovered old gutter issues may make the initial test **red by design**. Record the exact pre-art failures; they become green once the in-place art and 1776×888 path atlas ship. Do not falsely claim the complete contract passes on the original assets.
- The one-off Pillow/graphics script may composite and compare baseline pixels, but it is **not** a separate authoritative pass/fail asset contract. No new production dependency, test platform, CI workflow or runtime art registry.

## Validation and objective acceptance

1. **File and atlas contract:** exactly the 26 existing target paths remain; 25 keep original PNG dimensions and the path atlas is **1776×888**. All four atlas grids keep their indices; unused tower fallback cells remain pixel-identical; generated cell alpha edges do not bleed; boss slot 7 stays fully transparent. The committed `scene_art_contract_test.dart` must fully decode every image via Flutter and verify manifest registration, grid divisibility and transparent gutters.
2. **Visual QA:** an atlas-and-stage-crop contact sheet shows all four atlases, 38.5px walkers/brutes, 70px bosses and actual board-sized character chibis, plus the stage composition band. Compare before/after **real UI fixture captures** produced by the existing `captureReactorRimFixture` harness (using `ORION_CAPTURE_DIR=tmp/hpa-925/before` on baseline and `…/after` on final head). Reuse title, briefing, codex-enemies, mounted-radial and mission-report captures; no new browser route or hand-made 22-image UI contact sheet.
3. **Automated repository checks:** `flutter analyze`, `flutter test` (including the **new** scene art contract), and `flutter build web --release` succeed. No **production** Dart, `pubspec.yaml` or gameplay changes; test-only helper extraction and a new test are explicitly permitted.
4. **MCP-driven E2E and screenshot check:** on a single Chrome/browser platform, navigate the actual app **Title → World Map → Stage Briefing → Battle**, deploy Haruto/Mio, start a wave and capture a scene with Frostbitten beside the chibis. Compare 390×844 and compact 320×568 shots against the HPA-921 approved mockup; use deterministic existing fixture captures to verify boss identity/slot mapping, result panels and other scene art. Do not mistake unchanged pre-HPA-926 copy for art failure.
5. **Scope review:** PR may change the **26 PNGs**, design/plan, **test/game/scene_art_contract_test.dart**, minimal shared helpers in **test/support/**, `test/game/character_art_contract_test.dart` imports/helper refactor and validation/evidence. No SFX, character art redesign or separate PR. **No human approval as an automated acceptance criterion.**

