# Orion Terrain Background Asset Design

## Goal

Generate and integrate one board-sized terrain background for the Orion tower defense MVP. The asset should add sci-fi battlefield texture beneath the existing grid, path, towers, enemies, projectiles, and selection overlays without changing gameplay rules or board geometry.

## Asset Scope

Create a single portrait PNG:

- Filename: `orion_terrain_background.png`
- Location: `assets/images/`
- Intended shape: 2:3 portrait texture matching the 8 by 12 board ratio
- Visual direction: dark orbital outpost terrain, metal plates, subtle scorched surface variation, faint embedded circuitry, restrained sci-fi floor detail

The image should not contain text, labels, UI, characters, towers, enemies, projectiles, spawn/base symbols, or a baked route. It should stay low-contrast enough that the existing path, grid, selected-cell highlights, sprites, and HUD remain readable.

## Integration Strategy

Register the PNG in `pubspec.yaml`. Add a small terrain asset loader that uses Flame image loading and draws the background across the `BoardComponent` bounds before the existing path rectangles and grid are rendered.

The current flat board color remains the fallback if the terrain image is unavailable or if tests instantiate `BoardComponent` without loaded assets. The integration must not change placement rules, board dimensions, path cells, wave timing, combat behavior, or UI controls.

## Verification

Run formatting, static analysis, and Flutter tests. Then use the running web app to smoke-test that the board background appears behind the existing path/grid, tower placement still works, waves still start, and no runtime asset-load errors appear.
