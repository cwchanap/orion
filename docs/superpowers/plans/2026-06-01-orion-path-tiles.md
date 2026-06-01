# Orion Path Tiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate one path tile atlas and use it to render Orion's fixed enemy route over the terrain background.

**Architecture:** Add a `GamePathTiles` asset module that owns the atlas filename, 4x2 sheet layout, sprite slicing, and deterministic path-cell tile selection from neighboring cells. Register the generated PNG in Flutter's asset bundle, load it through Flame's image cache in `OrionDefenseGame.onLoad`, and pass the loaded atlas to `BoardComponent`. `BoardComponent` draws tile sprites for each `BoardLayout.pathCells` entry and keeps the current gray rectangles as fallback.

**Tech Stack:** Flutter, Flame `Images.load`, Flame `Sprite`, generated PNG atlas, chroma-key removal helper, `flutter_test`.

---

### Task 1: Path Tile Metadata, Slicing, and Selection

**Files:**
- Create: `lib/game/assets/game_path_tiles.dart`
- Create: `test/game/game_path_tiles_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/game/game_path_tiles_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_path_tiles.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/board_layout.dart';

void main() {
  group('GamePathTiles', () {
    test('maps the 4x2 path tile atlas cells in stable order', () {
      expect(GamePathTiles.columns, 4);
      expect(GamePathTiles.rows, 2);
      expect(GamePathTiles.fileName, 'orion_path_tiles.png');
      expect(GamePathTiles.assetPath, 'assets/images/orion_path_tiles.png');

      final horizontalRect = GamePathTiles.sourceRectFor(
        GamePathTile.horizontal,
        imageWidth: 1024,
        imageHeight: 512,
      );
      expect(horizontalRect.left, 0);
      expect(horizontalRect.top, 0);
      expect(horizontalRect.width, 256);
      expect(horizontalRect.height, 256);

      final endRect = GamePathTiles.sourceRectFor(
        GamePathTile.endCap,
        imageWidth: 1024,
        imageHeight: 512,
      );
      expect(endRect.left, 768);
      expect(endRect.top, 256);
      expect(endRect.width, 256);
      expect(endRect.height, 256);
    });

    test('selects route tiles from neighboring path cells', () {
      final pathCells = BoardLayout.pathCells;

      expect(
        GamePathTiles.tileForCell(const GridPosition(0, 1), pathCells),
        GamePathTile.startCap,
      );
      expect(
        GamePathTiles.tileForCell(const GridPosition(1, 1), pathCells),
        GamePathTile.horizontal,
      );
      expect(
        GamePathTiles.tileForCell(const GridPosition(3, 2), pathCells),
        GamePathTile.vertical,
      );
      expect(
        GamePathTiles.tileForCell(const GridPosition(3, 1), pathCells),
        GamePathTile.cornerSouthWest,
      );
      expect(
        GamePathTiles.tileForCell(const GridPosition(3, 4), pathCells),
        GamePathTile.cornerNorthEast,
      );
      expect(
        GamePathTiles.tileForCell(const GridPosition(6, 6), pathCells),
        GamePathTile.cornerNorthWest,
      );
      expect(
        GamePathTiles.tileForCell(const GridPosition(2, 6), pathCells),
        GamePathTile.cornerSouthEast,
      );
      expect(
        GamePathTiles.tileForCell(const GridPosition(7, 10), pathCells),
        GamePathTile.endCap,
      );
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/game_path_tiles_test.dart`

Expected: FAIL because `package:orion/game/assets/game_path_tiles.dart` does not exist.

- [ ] **Step 3: Implement the path tile module**

Create `lib/game/assets/game_path_tiles.dart`:

```dart
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import '../models/game_models.dart';

enum GamePathTile {
  horizontal,
  vertical,
  cornerNorthEast,
  cornerNorthWest,
  cornerSouthEast,
  cornerSouthWest,
  startCap,
  endCap,
}

class GamePathTiles {
  GamePathTiles._(this._sprites);

  static const String fileName = 'orion_path_tiles.png';
  static const String assetPath = 'assets/images/$fileName';
  static const int columns = 4;
  static const int rows = 2;

  final Map<GamePathTile, Sprite> _sprites;

  static Future<GamePathTiles> load(Images images) async {
    final image = await images.load(fileName);
    return GamePathTiles.fromImage(image);
  }

  static GamePathTiles fromImage(ui.Image image) {
    final sprites = <GamePathTile, Sprite>{};
    for (final tile in GamePathTile.values) {
      final sourceRect = sourceRectFor(
        tile,
        imageWidth: image.width.toDouble(),
        imageHeight: image.height.toDouble(),
      );
      sprites[tile] = Sprite(
        image,
        srcPosition: Vector2(sourceRect.left, sourceRect.top),
        srcSize: Vector2(sourceRect.width, sourceRect.height),
      );
    }
    return GamePathTiles._(sprites);
  }

  Sprite sprite(GamePathTile tile) => _sprites[tile]!;

  static ui.Rect sourceRectFor(
    GamePathTile tile, {
    required double imageWidth,
    required double imageHeight,
  }) {
    final index = tile.index;
    final cellWidth = imageWidth / columns;
    final cellHeight = imageHeight / rows;
    final column = index % columns;
    final row = index ~/ columns;
    return ui.Rect.fromLTWH(
      column * cellWidth,
      row * cellHeight,
      cellWidth,
      cellHeight,
    );
  }

  static GamePathTile tileForCell(
    GridPosition position,
    Iterable<GridPosition> pathCells,
  ) {
    final pathSet = pathCells.toSet();
    final hasNorth = pathSet.contains(GridPosition(position.column, position.row - 1));
    final hasEast = pathSet.contains(GridPosition(position.column + 1, position.row));
    final hasSouth = pathSet.contains(GridPosition(position.column, position.row + 1));
    final hasWest = pathSet.contains(GridPosition(position.column - 1, position.row));
    final neighborCount = [hasNorth, hasEast, hasSouth, hasWest]
        .where((hasNeighbor) => hasNeighbor)
        .length;

    if (neighborCount == 1) {
      return position == pathCells.first ? GamePathTile.startCap : GamePathTile.endCap;
    }
    if (hasEast && hasWest) {
      return GamePathTile.horizontal;
    }
    if (hasNorth && hasSouth) {
      return GamePathTile.vertical;
    }
    if (hasNorth && hasEast) {
      return GamePathTile.cornerNorthEast;
    }
    if (hasNorth && hasWest) {
      return GamePathTile.cornerNorthWest;
    }
    if (hasSouth && hasEast) {
      return GamePathTile.cornerSouthEast;
    }
    if (hasSouth && hasWest) {
      return GamePathTile.cornerSouthWest;
    }

    throw StateError('Path cell $position does not map to a supported path tile');
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/game/game_path_tiles_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/game/assets/game_path_tiles.dart test/game/game_path_tiles_test.dart
git commit -m "feat: add Orion path tile mapping"
```

### Task 2: Generate and Register Path Tile Atlas

**Files:**
- Create: `assets/images/orion_path_tiles.png`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Generate source atlas**

Use built-in image generation with this prompt:

```text
Use case: stylized-concept
Asset type: 4x2 top-down path tile atlas for a Flutter Flame tower-defense game
Primary request: Create a sci-fi path tile atlas for Orion, matching the existing dark orbital terrain background.
Canvas and layout: exactly 4 columns by 2 rows, equal-size square cells, one centered path tile per cell, consistent top-down camera angle, generous padding but each tile should fill most of its cell.
Cell order:
Row 1: horizontal straight conduit road, vertical straight conduit road, corner path connecting north and east, corner path connecting north and west.
Row 2: corner path connecting south and east, corner path connecting south and west, start cap tile, end cap tile.
Style: reinforced dark metal route panels, slightly raised sci-fi conduit road, worn industrial surface, subtle edge lighting, restrained blue-gray lights, clear silhouette at small size.
Background: perfectly flat solid #ff00ff chroma-key background for removal. The background must be one uniform color with no shadows, gradients, texture, reflections, floor plane, or lighting variation. Do not use #ff00ff anywhere in the tiles.
Avoid: no text, no labels, no watermark, no towers, no enemies, no projectiles, no base, no spawn gate, no characters, no full board route, no grid lines, no UI frame.
```

Expected: one 4x2 atlas on a flat magenta background.

- [ ] **Step 2: Copy generated source into scratch path**

Copy the selected generated image into `tmp/imagegen/orion_path_tiles_chroma.png`.

Expected: file exists and can be inspected locally.

- [ ] **Step 3: Remove chroma key into final asset**

Run:

```bash
python3 /Users/chanwaichan/.codex/skills/.system/imagegen/scripts/remove_chroma_key.py \
  --input tmp/imagegen/orion_path_tiles_chroma.png \
  --out assets/images/orion_path_tiles.png \
  --auto-key border \
  --soft-matte \
  --transparent-threshold 12 \
  --opaque-threshold 220 \
  --despill
```

Expected: `assets/images/orion_path_tiles.png` is an RGBA PNG with transparent corners.

- [ ] **Step 4: Register the asset**

Modify `pubspec.yaml` under `flutter.assets`:

```yaml
    - assets/images/orion_path_tiles.png
```

- [ ] **Step 5: Verify the asset is bundled**

Run: `flutter test test/widget_test.dart`

Expected: PASS with no asset bundle errors.

- [ ] **Step 6: Commit**

```bash
git add assets/images/orion_path_tiles.png pubspec.yaml
git commit -m "feat: add Orion path tile atlas"
```

### Task 3: Render Path Tiles in Board

**Files:**
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `lib/game/components/board_component.dart`

- [ ] **Step 1: Add path tile support to board**

In `lib/game/components/board_component.dart`, import:

```dart
import '../assets/game_path_tiles.dart';
```

Add constructor parameter and field:

```dart
BoardComponent({
  required this.cellSize,
  this.selectedCell,
  this.spriteSheet,
  this.terrainImage,
  this.pathTiles,
  super.position,
  super.priority,
}) : super(...);

final GamePathTiles? pathTiles;
```

Replace the current path rectangle loop with:

```dart
final pathTiles = this.pathTiles;
for (final pathCell in BoardLayout.pathCells) {
  final rect = cellRect(pathCell).deflate(1);
  if (pathTiles == null) {
    canvas.drawRect(rect, _pathPaint);
  } else {
    final tile = GamePathTiles.tileForCell(pathCell, BoardLayout.pathCells);
    pathTiles.sprite(tile).renderRect(canvas, rect);
  }
}
```

- [ ] **Step 2: Load and pass path tiles**

In `lib/game/orion_defense_game.dart`, import:

```dart
import 'assets/game_path_tiles.dart';
```

Add field:

```dart
GamePathTiles? _pathTiles;
```

Load in `onLoad`:

```dart
_pathTiles = await GamePathTiles.load(images);
```

Pass it into `BoardComponent`:

```dart
pathTiles: _pathTiles,
```

- [ ] **Step 3: Run focused tests**

Run: `flutter test test/game/game_path_tiles_test.dart test/widget_test.dart`

Expected: PASS.

- [ ] **Step 4: Run full verification**

Run:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Expected: formatting check passes, analyzer reports no issues, and all tests pass.

- [ ] **Step 5: Web smoke test**

Restart `flutter run -d web-server`, open the app, verify path tiles render over terrain, place a tower off path, start a wave, and verify no runtime asset-load errors appear.

- [ ] **Step 6: Commit**

```bash
git add lib/game/orion_defense_game.dart lib/game/components/board_component.dart
git commit -m "feat: render Orion path tiles"
```
