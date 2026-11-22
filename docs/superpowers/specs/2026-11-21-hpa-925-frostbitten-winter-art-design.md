# HPA-925 — Frostbitten enemies and winter environment (Design Spec)

Date: 2026-11-21  
Linear: https://linear.app/cwchanap/issue/HPA-925/orion-produce-frostbitten-enemy-boss-and-winter-board-art  
Parent: https://linear.app/cwchanap/issue/HPA-921/orion-pivot-to-last-hearth-an-anime-character-tower-defense  
Downstream integration: HPA-926 (blocked by this ticket and HPA-927)  
Baseline: main @ b3ae929ea56f1be266c5219a1bd218b7197a595c

## Outcome and scope

Deliver **the winter/Frostbitten art as one asset-only PR**, initially opened with this design and its implementation plan. The same PR later receives the generated art and validation evidence. It replaces **26 existing PNG files in place**: 4 gameplay atlases and 22 Reactor Rim UI assets. Existing names, pixel dimensions, order, layout, image crops, Flutter asset registration and loaders are the contract.

This task must not edit production Dart, tests, pubspec.yaml, stages/waves/balance, gameplay, copy, character portraits/chibis, sound or music. HPA-924 owns the 12 final characters (already complete); HPA-927 independently owns SFX; HPA-926 owns renaming, art hookup where needed and overall Last Hearth integration. No new art IDs, sprite registry, generator package, runtime dependency, migrations or platform-specific implementation.

## Verified integration baseline

- The four sprite loaders are **GameSpriteSheet** (4 × 3), **GameTowerVarietySheet** (4 × 4), **GameBossSheet** (4 × 2, seven occupied boss cells), and **GamePathTiles** (4 × 2). They slice by enum/index and image dimensions in **lib/game/assets/**. Leave them unchanged.
- **GameBoardSkin** uses **reactor_rim_ui/boards/nebula.png** at a fixed 8:12 board ratio (documented 512 × 768). The board is 8 × 12 cells; emphasize paths, units and interaction, not terrain noise.
- **OrionArt** resolves five scene backdrops, seven stage images and crests, two result illustrations and a boss atlas. Stage art is center-cropped in both **briefingWide** and **mapSquare** contexts. Compose all focal subjects to survive both center crops.
- The original 26 paths are all registered by existing **pubspec.yaml** entries, including the five Reactor Rim subdirectories. No registration change is needed.
- Character art from HPA-924 is already available in **assets/images/characters/{id}/**. Use existing Haruto/Mio chibis for battle scale comparisons; use the approved lineup and six-screen Last Hearth mockup attached to HPA-921 as style/visual references.

## Exact asset replacement inventory

| Directory / file | Count | Visual responsibility |
| --- | ---: | --- |
| assets/images/orion_sprite_sheet.png | 1 | Walkers/brutes, shared projectile effects, snow-wall breach, Orion Hearth |
| assets/images/orion_tower_variety_sheet.png | 1 | Remaining combat projectiles/effects and status indicators |
| assets/images/orion_boss_sheet.png | 1 | Seven named Frostbitten bosses; eighth cell empty |
| assets/images/orion_path_tiles.png | 1 | Eight seamless snow-road/path tile variants |
| assets/images/reactor_rim_ui/backdrops/ | 5 | command-center, world-map, tech-tree-rnd-bay (Camp interior), mission-report-debrief, map-room |
| assets/images/reactor_rim_ui/boards/nebula.png | 1 | Snowy combat board with quieter build zones |
| assets/images/reactor_rim_ui/crests/ | 7 | One crest per existing stage ID |
| assets/images/reactor_rim_ui/stages/ | 7 | One location illustration per existing stage ID |
| assets/images/reactor_rim_ui/results/ | 2 | victory: warm camp survival; defeat: fading Hearth in winter |
| **Total** | **26** | **Existing filenames and pixel dimensions stay identical** |

Seven existing stage IDs, used for BOTH crests and stages: **outpost-alpha**, **nebula-relay**, **salvage-rift**, **asteroid-foundry**, **aurora-gate**, **void-bastion**, **singularity-core**. Depict the Hokkaido locations from HPA-926's proposed names (Ember Road, Frozen Rail Yard, Sunken Depot, Dead Foundry, Aurora Gate, White Bastion, The Cold Heart) **without changing paths or adding painted-on labels**.

## Sprite-cell contract — never rely on a generated sheet's visual ordering

### orion_sprite_sheet.png — 4 columns × 3 rows, left-to-right/top-to-bottom

| Index | Existing enum slot | Final visual |
| ---: | --- | --- |
| 0–2 | laserTower, rocketTower, cryoTower | **Preserve original pixels:** tower atlas cells are no longer displayed |
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
| 0–4 | railgunTower, ionChainTower, naniteTower, gravityWellTower, droneBayTower | **Preserve original pixels:** unused tower cells |
| 5 | railSlug | Streaking arrow / sniper round, legible for Sayo and Elena |
| 6 | ionArc | Lightning arc |
| 7 | naniteCloud | Serum cloud |
| 8 | gravityField | Gravity distortion |
| 9 | drone | Scrap drone |
| 10 | shieldIndicator | Ice shell |
| 11 | armorIndicator | Scrap plating |
| 12 | regenIndicator | Regrowth |
| 13 | corrosionIndicator | Corrosion |
| 14 | clusterBurst | Embers / fire spray for Mio |
| 15 | prismSplit | Sunbeam split for Hikari |

### orion_boss_sheet.png — 4 columns × 2 rows

Indices 0–6, in the immutable **BossSprite** order: **relayBreaker** → Gatebreaker; **shieldMatriarch** → Rime Matriarch; **swarmQueen** → Brood Mother; **armoredExcavator** → Scrap Colossus; **regenWarden** → Thawless Warden; **siegeCarrier** → Corpse Hauler; **singularityCore** → The Frost Heart. Keep index 7 empty/transparent. Each boss should read as a distinct Frostbitten chibi-scale silhouette and communicate its existing trait without new mechanics.

### orion_path_tiles.png — 4 columns × 2 rows

In **GamePathTile** enum order: horizontal, vertical, cornerNorthEast, cornerNorthWest, cornerSouthEast, cornerSouthWest, startCap, endCap. Match the **current** connector positions and lane width, with consistent snow/ice at all adjoining edges. Keep existing gameplay paths intact.

## Visual art direction and composition

- Source of truth: HPA-921's approved Last Hearth lineup, chibi sheet and six-screen UI mockup; HPA-924's final in-repo character art. Consistent anime, clean cel shading and crisp line art. Enemies/bosses are **eerie, frozen and non-gory**, in three-quarter view, with chibi proportions; the enemy should still clearly differ from a friendly Kindled character.
- Palette: icy whites and blue/cyan for the Frostbitten and Hokkaido landscape; amber/coral/orange for the Hearth, survivors and safe camp interior. Prioritize contrast over decorative detail.
- Battle silhouettes must read at approximately **36 logical px** beside the existing approximately **48px chibi character sprites**. Test source alpha edges at small size; leave generous transparent padding within each cell and avoid spill across cell boundaries.
- Warm tracers/fire, cool shards, lightning, serum, gravity, drones and status icons must distinguish mechanics at gameplay scale without text. A slot shared by two characters should read well for both.
- Stage illustrations: visually differentiate the seven proposed locations while keeping main subjects inside both the center-square map crop and center-wide briefing crop. Crests are iconographic and readable in the small world-map tile. The five scene backdrops must leave negative space behind existing overlays.
- The board skin must keep units, path, targeting markers and placement grid visible. Path tiles must form seamless straight segments and corners. Result art must support the current UI labels rather than baking text into images.
- Preserve the exact original PNG dimensions, alpha intent, cell bounds, and image placement/cropping contract. Do not add in-art text or embed renamed stage/boss labels; HPA-926 changes UI copy later.

## Art production approach (no app code)

Use the art-generation method specified in HPA-925 (OpenAI Image API and the issue's model, reference-conditioned on approved images). Work on the owner's machine using existing secured configuration; never log or commit credentials. If the specified generator is unavailable, **do not silently swap providers**; the issue requires approval before the fallback.

Keep scratch source/reference files and multiple candidates in ignored **tmp/**. Generate individual transparent sprite/cell candidates as necessary, then composite at the original atlas cell coordinates instead of trusting the image model to maintain exact enum order. Keep unused cells pixel-identical; leave the final boss cell empty. For larger scene art, crop/reframe to the **current** asset dimensions rather than modifying Dart crop logic. A local, throwaway Pillow/graphics script is sufficient; do not add a production generator or a new CI dependency.

Track source/reference, generator/model/prompt, generation vs retouch, and image dimension/alpha checks in one validation note alongside contact sheets. No separate duplicated art registry is needed.

## Validation and objective acceptance

1. **Asset contract:** exactly the 26 existing target files are replaced; paths/PNG dimensions and four atlas grid layouts are unchanged; unused cells remain pixel-identical, boss cell 7 remains empty. Check every final PNG actually decodes and alpha/cell edges do not bleed.
2. **Visual QA:** before/after contact sheets for all four atlases and 22 UI assets; 36px walker/brute/boss previews side-by-side with final HPA-924 chibis; snow-road seam montage; square and wide crops for seven stages; board screenshot versus HPA-921 mockup. No text baked into artwork.
3. **Automated repository checks:** **flutter analyze**, **flutter test**, **flutter build web --release**, with no production Dart/test/asset-manifest changes. Existing loader, board, stage art and rendering tests must pass.
4. **MCP-driven E2E and screenshot check:** on a single browser platform, navigate the actual app **Title → World Map → Stage Briefing → Battle**, deploy Haruto/Mio, run a wave and capture a scene with Frostbitten next to friendly chibis. Compare screenshots at 390 × 844 (and a compact 320 × 568 where feasible) with HPA-921's approved UI mockup, focusing on art composition and legibility rather than HPA-926's not-yet-renamed copy. Cover boss/results/other scene art through deterministic screenshot fixtures and contact sheets when those states are not reached by the short E2E.
5. **Scope review:** PR changes only the 26 existing PNGs plus this spec/plan, a validation note and tightly scoped screenshot/contact-sheet evidence. No SFX, code, character art rework or separate implementation PR; **no human approval/sign-off criterion**.

This ticket supplies art. HPA-926 later completes the copy/visual integration after HPA-927 finishes its separate audio ticket.
