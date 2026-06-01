# Orion Sprite Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate one project-owned sprite sheet and use it for Orion's in-game Flame visuals.

**Architecture:** Add a small asset-mapping module that owns the sprite sheet filename, 4x3 cell layout, and game-object-to-sprite mapping. Flame components receive an optional loaded sheet and render sprites when available, keeping their current canvas shapes as fallback rendering. The game loads the image during `onLoad` and passes the sheet through board, tower, enemy, and projectile construction without changing gameplay rules.

**Tech Stack:** Flutter, Flame `Images.load`, Flame `Sprite`, Flutter asset bundle, generated PNG asset, `flutter_test`.

---

### Task 1: Sprite Sheet Mapping API

**Files:**
- Create: `lib/game/assets/game_sprite_sheet.dart`
- Create: `test/game/game_sprite_sheet_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/game/game_sprite_sheet_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_sprite_sheet.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('GameSpriteSheet', () {
    test('maps the 4x3 sprite sheet cells in stable order', () {
      expect(GameSpriteSheet.columns, 4);
      expect(GameSpriteSheet.rows, 3);
      expect(GameSpriteSheet.fileName, 'orion_sprite_sheet.png');
      expect(GameSpriteSheet.assetPath, 'assets/images/orion_sprite_sheet.png');

      final laserRect = GameSpriteSheet.sourceRectFor(
        GameSprite.laserTower,
        imageWidth: 1024,
        imageHeight: 768,
      );
      expect(laserRect.left, 0);
      expect(laserRect.top, 0);
      expect(laserRect.width, 256);
      expect(laserRect.height, 256);

      final finalRect = GameSpriteSheet.sourceRectFor(
        GameSprite.cryoImpact,
        imageWidth: 1024,
        imageHeight: 768,
      );
      expect(finalRect.left, 768);
      expect(finalRect.top, 512);
      expect(finalRect.width, 256);
      expect(finalRect.height, 256);
    });

    test('selects sprites for gameplay object types', () {
      expect(
        GameSpriteSheet.spriteForTower(TowerType.laser),
        GameSprite.laserTower,
      );
      expect(
        GameSpriteSheet.spriteForTower(TowerType.rocket),
        GameSprite.rocketTower,
      );
      expect(
        GameSpriteSheet.spriteForTower(TowerType.cryo),
        GameSprite.cryoTower,
      );

      expect(
        GameSpriteSheet.spriteForProjectile(TowerType.laser),
        GameSprite.laserBolt,
      );
      expect(
        GameSpriteSheet.spriteForProjectile(TowerType.rocket),
        GameSprite.rocketProjectile,
      );
      expect(
        GameSpriteSheet.spriteForProjectile(TowerType.cryo),
        GameSprite.cryoProjectile,
      );

      expect(
        GameSpriteSheet.spriteForEnemy(
          const EnemyStats(
            health: 30,
            speed: 72,
            baseDamage: 1,
            goldReward: 8,
          ),
        ),
        GameSprite.basicDroneEnemy,
      );
      expect(
        GameSpriteSheet.spriteForEnemy(
          const EnemyStats(
            health: 76,
            speed: 84,
            baseDamage: 2,
            goldReward: 11,
          ),
        ),
        GameSprite.heavyDroneEnemy,
      );
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/game_sprite_sheet_test.dart`

Expected: FAIL because `package:orion/game/assets/game_sprite_sheet.dart` does not exist.

- [ ] **Step 3: Implement the mapping module**

Create `lib/game/assets/game_sprite_sheet.dart`:

```dart
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/sprite.dart';

import '../models/game_models.dart';

enum GameSprite {
  laserTower,
  rocketTower,
  cryoTower,
  basicDroneEnemy,
  heavyDroneEnemy,
  laserBolt,
  rocketProjectile,
  cryoProjectile,
  spawnGate,
  baseReactor,
  greenImpact,
  cryoImpact,
}

class GameSpriteSheet {
  GameSpriteSheet._(this._sprites);

  static const String fileName = 'orion_sprite_sheet.png';
  static const String assetPath = 'assets/images/$fileName';
  static const int columns = 4;
  static const int rows = 3;
  static const double heavyEnemyHealthThreshold = 70;

  final Map<GameSprite, Sprite> _sprites;

  static Future<GameSpriteSheet> load(Images images) async {
    final image = await images.load(fileName);
    return GameSpriteSheet.fromImage(image);
  }

  static GameSpriteSheet fromImage(ui.Image image) {
    return GameSpriteSheet._({
      for (final sprite in GameSprite.values)
        sprite: Sprite(
          image,
          srcPosition: Vector2(
            sourceRectFor(
              sprite,
              imageWidth: image.width.toDouble(),
              imageHeight: image.height.toDouble(),
            ).left,
            sourceRectFor(
              sprite,
              imageWidth: image.width.toDouble(),
              imageHeight: image.height.toDouble(),
            ).top,
          ),
          srcSize: Vector2(
            sourceRectFor(
              sprite,
              imageWidth: image.width.toDouble(),
              imageHeight: image.height.toDouble(),
            ).width,
            sourceRectFor(
              sprite,
              imageWidth: image.width.toDouble(),
              imageHeight: image.height.toDouble(),
            ).height,
          ),
        ),
    });
  }

  Sprite sprite(GameSprite sprite) => _sprites[sprite]!;

  static ui.Rect sourceRectFor(
    GameSprite sprite, {
    required double imageWidth,
    required double imageHeight,
  }) {
    final index = sprite.index;
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

  static GameSprite spriteForTower(TowerType type) {
    return switch (type) {
      TowerType.laser => GameSprite.laserTower,
      TowerType.rocket => GameSprite.rocketTower,
      TowerType.cryo => GameSprite.cryoTower,
    };
  }

  static GameSprite spriteForProjectile(TowerType type) {
    return switch (type) {
      TowerType.laser => GameSprite.laserBolt,
      TowerType.rocket => GameSprite.rocketProjectile,
      TowerType.cryo => GameSprite.cryoProjectile,
    };
  }

  static GameSprite spriteForEnemy(EnemyStats stats) {
    if (stats.health >= heavyEnemyHealthThreshold) {
      return GameSprite.heavyDroneEnemy;
    }
    return GameSprite.basicDroneEnemy;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/game/game_sprite_sheet_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/game/assets/game_sprite_sheet.dart test/game/game_sprite_sheet_test.dart
git commit -m "feat: add Orion sprite sheet mapping"
```

### Task 2: Generate and Register Asset

**Files:**
- Create: `assets/images/orion_sprite_sheet.png`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Generate the source sprite sheet**

Use built-in image generation with this prompt:

```text
Use case: stylized-concept
Asset type: 4x3 top-down sprite sheet for a Flutter Flame tower-defense game
Primary request: Create a polished sci-fi sprite sheet for the Orion tower defense MVP.
Canvas and layout: exactly 4 columns by 3 rows, equal-size cells, one centered object per cell, generous padding around every object, consistent top-down camera angle.
Cell order:
Row 1: laser tower, rocket tower, cryo tower, basic drone enemy.
Row 2: heavy armored drone enemy, laser bolt projectile, rocket projectile, cryo shard projectile.
Row 3: blue spawn gate marker, golden base reactor marker, compact green laser impact spark, compact blue cryo impact burst.
Style: readable small-game sprites, crisp silhouettes, soft painted detail, subtle metal panels, compact orbital defense hardware, teal-green laser energy, orange rocket accents, icy blue cryo energy.
Background: perfectly flat solid #00ff00 chroma-key background for removal. The background must be one uniform color with no shadows, gradients, texture, reflections, floor plane, or lighting variation. Do not use #00ff00 anywhere in the sprites.
Avoid: no text, no labels, no watermark, no cast shadows, no contact shadows, no grid lines, no UI frame, no perspective scene.
```

Expected: one generated image containing all 12 sprites on a flat green background.

- [ ] **Step 2: Copy generated source into a temporary project path**

Copy the selected generated image into `tmp/imagegen/orion_sprite_sheet_chroma.png`.

Expected: file exists and can be inspected locally.

- [ ] **Step 3: Remove chroma key into the final asset**

Run:

```bash
python "${CODEX_HOME:-$HOME/.codex}/skills/.system/imagegen/scripts/remove_chroma_key.py" \
  --input tmp/imagegen/orion_sprite_sheet_chroma.png \
  --out assets/images/orion_sprite_sheet.png \
  --auto-key border \
  --soft-matte \
  --transparent-threshold 12 \
  --opaque-threshold 220 \
  --despill
```

Expected: `assets/images/orion_sprite_sheet.png` is a PNG with an alpha channel and transparent corners.

- [ ] **Step 4: Register the asset**

Modify `pubspec.yaml` under `flutter:`:

```yaml
  assets:
    - assets/images/orion_sprite_sheet.png
```

- [ ] **Step 5: Verify the asset is bundled**

Run: `flutter test test/widget_test.dart`

Expected: PASS with no asset bundle errors.

- [ ] **Step 6: Commit**

```bash
git add assets/images/orion_sprite_sheet.png pubspec.yaml
git commit -m "feat: add Orion generated sprite sheet"
```

### Task 3: Use Sprites in Flame Rendering

**Files:**
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `lib/game/components/board_component.dart`
- Modify: `lib/game/components/tower_component.dart`
- Modify: `lib/game/components/enemy_component.dart`
- Modify: `lib/game/components/projectile_component.dart`

- [ ] **Step 1: Update components to accept optional sprite sheets**

In `lib/game/components/board_component.dart`, import the asset mapper:

```dart
import '../assets/game_sprite_sheet.dart';
```

Add a constructor parameter and field:

```dart
BoardComponent({
  required this.cellSize,
  this.selectedCell,
  this.spriteSheet,
  super.position,
  super.priority,
}) : super(...);

final GameSpriteSheet? spriteSheet;
```

Change `_renderMarker` to accept a sprite id and draw the sprite first when available:

```dart
void _renderMarker(
  Canvas canvas,
  GridPosition position,
  Paint paint, {
  required double innerRadiusFactor,
  required GameSprite sprite,
}) {
  final spriteSheet = this.spriteSheet;
  if (spriteSheet != null) {
    final rect = cellRect(position).deflate(cellSize * 0.12);
    spriteSheet.sprite(sprite).renderRect(canvas, rect);
    return;
  }

  final center = cellCenter(position);
  canvas.drawCircle(center, cellSize * 0.38, paint);
  canvas.drawCircle(center, cellSize * innerRadiusFactor, _backgroundPaint);
}
```

In `lib/game/components/tower_component.dart`, import the asset mapper, add `this.spriteSheet` to the constructor, add `final GameSpriteSheet? spriteSheet;`, and render the mapped sprite when present:

```dart
@override
void render(Canvas canvas) {
  final spriteSheet = this.spriteSheet;
  if (spriteSheet == null) {
    super.render(canvas);
  } else {
    spriteSheet
        .sprite(GameSpriteSheet.spriteForTower(placedTower.type))
        .render(
          canvas,
          position: Vector2(radius, radius),
          size: Vector2.all(radius * 2.4),
          anchor: Anchor.center,
        );
  }

  canvas.drawCircle(Offset(radius, radius), radius - 1, _strokePaint);
}
```

In `lib/game/components/enemy_component.dart`, import the asset mapper, add `this.spriteSheet` to the constructor, add `final GameSpriteSheet? spriteSheet;`, and render the mapped enemy sprite when present:

```dart
@override
void render(Canvas canvas) {
  final spriteSheet = this.spriteSheet;
  if (spriteSheet == null) {
    super.render(canvas);
    return;
  }

  spriteSheet
      .sprite(GameSpriteSheet.spriteForEnemy(stats))
      .render(
        canvas,
        position: Vector2(radius, radius),
        size: Vector2.all(radius * 2.4),
        anchor: Anchor.center,
      );
}
```

In `lib/game/components/projectile_component.dart`, import the asset mapper, add `this.spriteSheet` to the constructor, add `final GameSpriteSheet? spriteSheet;`, and render the mapped projectile sprite when present:

```dart
@override
void render(Canvas canvas) {
  final spriteSheet = this.spriteSheet;
  if (spriteSheet == null) {
    super.render(canvas);
    return;
  }

  spriteSheet
      .sprite(GameSpriteSheet.spriteForProjectile(stats.type))
      .render(
        canvas,
        position: Vector2(radius, radius),
        size: Vector2.all(radius * 3),
        anchor: Anchor.center,
      );
}
```

- [ ] **Step 2: Load and pass the sprite sheet in the game**

In `lib/game/orion_defense_game.dart`, import the asset mapper:

```dart
import 'assets/game_sprite_sheet.dart';
```

Add a nullable field:

```dart
GameSpriteSheet? _spriteSheet;
```

Load the sheet in `onLoad` before board layout:

```dart
@override
Future<void> onLoad() async {
  await super.onLoad();
  _spriteSheet = await GameSpriteSheet.load(images);
  _layoutBoard(size);
  _publishSnapshot();
}
```

Pass the sheet to every visual component constructor:

```dart
_board = BoardComponent(
  cellSize: _cellSize,
  selectedCell: _selectedTower?.position ?? _selectedCell,
  spriteSheet: _spriteSheet,
  position: Vector2(_boardOrigin.dx, _boardOrigin.dy),
  priority: 0,
);

final component = TowerComponent(
  tower: tower,
  center: _cellCenter(tower.position),
  radius: _towerRadius,
  spriteSheet: _spriteSheet,
  acquireTarget: _selectTargetForTower,
  launchProjectile: _launchProjectile,
  priority: 10,
);

ProjectileComponent(
  stats: tower.stats,
  target: target,
  startPosition: tower.position,
  spriteSheet: _spriteSheet,
  enemiesProvider: () => _activeEnemyComponents.values,
  priority: 30,
);

EnemyComponent(
  enemyId: _nextEnemyId,
  stats: wave.enemyStats,
  waypoints: _pathWaypoints(),
  spriteSheet: _spriteSheet,
  onKilled: _handleEnemyKilled,
  onReachedBase: _handleEnemyReachedBase,
  priority: 20,
);
```

- [ ] **Step 3: Run focused tests**

Run: `flutter test test/game/game_sprite_sheet_test.dart test/widget_test.dart`

Expected: PASS.

- [ ] **Step 4: Run full verification**

Run:

```bash
dart format lib test
flutter analyze
flutter test
```

Expected: no formatting changes after the final format run, no analyzer issues, and all tests pass.

- [ ] **Step 5: Web smoke test**

Run: `flutter run -d web-server`

Expected: terminal prints a localhost URL. Open it in the in-app browser, place a tower, start a wave, and verify no runtime asset-load errors appear.

- [ ] **Step 6: Commit**

```bash
git add lib/game/orion_defense_game.dart lib/game/components/board_component.dart lib/game/components/tower_component.dart lib/game/components/enemy_component.dart lib/game/components/projectile_component.dart
git commit -m "feat: render Orion gameplay sprites"
```
