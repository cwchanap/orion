# Orion Path Tile Asset Design

## Goal

Generate and integrate a path tile asset for the Orion tower defense MVP. The asset should replace the current flat gray path rectangles with readable sci-fi route tiles while preserving the existing `BoardLayout.pathCells` route, path collision rules, placement rules, and combat behavior.

## Asset Scope

Create one compact PNG tile atlas:

- Filename: `orion_path_tiles.png`
- Location: `assets/images/`
- Layout: fixed cell atlas for path segments
- Visual direction: dark sci-fi conduit road, reinforced metal panels, subtle edge lights, worn surface detail, compatible with the current orbital terrain background

The atlas should contain enough tiles to render the current fixed route from adjacency rather than baking a full-board overlay:

- horizontal straight
- vertical straight
- four corners
- spawn/start cap
- base/end cap

The generated art should contain no text, labels, UI, towers, enemies, projectiles, base object, spawn object, grid lines, or full-board route. It should stay readable under the existing grid and clear under moving enemy sprites.

## Integration Strategy

Register the PNG in `pubspec.yaml`. Add a small path tile metadata/atlas loader that slices the image into named path tile sprites. `BoardComponent` should choose the right tile per `BoardLayout.pathCells` entry by inspecting neighboring path cells, draw path tiles over the terrain background, then draw selected-cell overlays, spawn/base sprites, and grid as it does today.

The current gray path rectangles remain as fallback when the path atlas is not loaded. The integration must not change `BoardLayout.pathCells`, path bounds, route continuity, tower placement validation, enemy waypoints, targeting, wave behavior, or economy.

## Verification

Run formatting, static analysis, and Flutter tests. Add focused tests for path tile selection so straight and corner cells map deterministically from neighboring path cells. Then smoke-test the web app: path tiles render over terrain, tower placement still works only off path, a wave starts, enemies follow the same route, and no runtime asset-load errors appear.
