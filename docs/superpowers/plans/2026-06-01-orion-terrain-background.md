# Orion Terrain Background Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate one board-sized terrain PNG and render it behind Orion's existing board path and grid.

**Architecture:** Add a tiny terrain asset metadata module that owns the terrain filename and asset path. Register the generated PNG in Flutter's asset bundle, load it through Flame's image cache in `OrionDefenseGame.onLoad`, and pass the decoded image into `BoardComponent`. `BoardComponent` draws the terrain image first and keeps the existing flat color as fallback.

**Tech Stack:** Flutter, Flame `Images.load`, Flutter asset bundle, generated PNG asset, `flutter_test`.

---

### Task 1: Terrain Asset Metadata

**Files:**
- Create: `lib/game/assets/game_terrain.dart`
- Create: `test/game/game_terrain_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/game/game_terrain_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_terrain.dart';

void main() {
  group('GameTerrain', () {
    test('defines the terrain background asset path', () {
      expect(GameTerrain.fileName, 'orion_terrain_background.png');
      expect(
        GameTerrain.assetPath,
        'assets/images/orion_terrain_background.png',
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/game/game_terrain_test.dart`

Expected: FAIL because `package:orion/game/assets/game_terrain.dart` does not exist.

- [ ] **Step 3: Implement metadata**

Create `lib/game/assets/game_terrain.dart`:

```dart
class GameTerrain {
  const GameTerrain._();

  static const String fileName = 'orion_terrain_background.png';
  static const String assetPath = 'assets/images/$fileName';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/game/game_terrain_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/game/assets/game_terrain.dart test/game/game_terrain_test.dart
git commit -m "feat: add Orion terrain asset metadata"
```

### Task 2: Generate and Register Terrain Asset

**Files:**
- Create: `assets/images/orion_terrain_background.png`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Generate terrain PNG**

Use built-in image generation with this prompt:

```text
Use case: stylized-concept
Asset type: 2:3 portrait board background texture for a Flutter Flame tower-defense game
Primary request: Create a dark sci-fi orbital outpost terrain background for the Orion tower defense board.
Canvas and composition: portrait 2:3 ratio, seamless-feeling single board texture, no grid, no route, no frame, no UI. Keep the image useful as a background under gameplay overlays.
Scene/backdrop: top-down view of an orbital defense platform floor, dark graphite metal panels, subtle scorched patches, faint embedded circuitry, restrained blue-gray floor lighting, small surface seams and wear.
Readability constraints: low-to-medium contrast, no bright focal object, no important detail near edges, enough visual texture to feel like terrain but quiet enough that gray path cells, grid lines, tower sprites, enemy sprites, and selection highlights remain readable on top.
Avoid: no text, no labels, no watermark, no towers, no enemies, no projectiles, no base, no spawn gate, no characters, no baked path, no perspective horizon, no heavy glow, no pure black void.
```

Expected: one portrait terrain image.

- [ ] **Step 2: Copy generated image into project asset path**

Copy the selected generated image to `assets/images/orion_terrain_background.png`.

Expected: file exists and is a normal RGB/RGBA PNG.

- [ ] **Step 3: Register the asset**

Modify `pubspec.yaml` under `flutter.assets`:

```yaml
    - assets/images/orion_terrain_background.png
```

- [ ] **Step 4: Verify the asset is bundled**

Run: `flutter test test/widget_test.dart`

Expected: PASS with no asset bundle errors.

- [ ] **Step 5: Commit**

```bash
git add assets/images/orion_terrain_background.png pubspec.yaml
git commit -m "feat: add Orion terrain background asset"
```

### Task 3: Render Terrain Behind Board

**Files:**
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `lib/game/components/board_component.dart`

- [ ] **Step 1: Add terrain image support to board**

In `lib/game/components/board_component.dart`, keep the existing `dart:ui` import and add an optional field:

```dart
BoardComponent({
  required this.cellSize,
  this.selectedCell,
  this.spriteSheet,
  this.terrainImage,
  super.position,
  super.priority,
}) : super(...);

final Image? terrainImage;
```

Replace the first background draw in `render` with:

```dart
final terrainImage = this.terrainImage;
if (terrainImage == null) {
  canvas.drawRect(Offset.zero & size.toSize(), _backgroundPaint);
} else {
  canvas.drawImageRect(
    terrainImage,
    Rect.fromLTWH(
      0,
      0,
      terrainImage.width.toDouble(),
      terrainImage.height.toDouble(),
    ),
    Offset.zero & size.toSize(),
    Paint(),
  );
}
```

- [ ] **Step 2: Load and pass the terrain image**

In `lib/game/orion_defense_game.dart`, import the metadata module:

```dart
import 'assets/game_terrain.dart';
```

Add a field:

```dart
Image? _terrainImage;
```

Load it in `onLoad` after `await super.onLoad()`:

```dart
_terrainImage = await images.load(GameTerrain.fileName);
```

Pass it into `BoardComponent`:

```dart
terrainImage: _terrainImage,
```

- [ ] **Step 3: Run focused tests**

Run: `flutter test test/game/game_terrain_test.dart test/widget_test.dart`

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

Use `flutter run -d web-server` or hot restart the existing server. Open the app, verify the terrain renders behind the board path/grid, place a tower, start a wave, and verify the terminal shows no runtime asset-load errors.

- [ ] **Step 6: Commit**

```bash
git add lib/game/orion_defense_game.dart lib/game/components/board_component.dart
git commit -m "feat: render Orion terrain background"
```
