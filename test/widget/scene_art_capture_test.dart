import 'dart:io';

import 'package:flame/flame.dart';
import 'package:flame/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_boss_sheet.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';

import '../support/reactor_rim_visual_capture.dart';
import '../support/real_fonts.dart';

void main() {
  testWidgets('capture each boss through the runtime atlas mapping', (
    tester,
  ) async {
    if (Platform.environment['ORION_CAPTURE_DIR']?.isNotEmpty != true) return;
    await loadRealFonts();
    tester.view.physicalSize = const Size(840, 150);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => Flame.images.load(GameBossSheet.fileName));
    OrionArtDescriptor.resetSpriteCache();
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xff263b4b),
            child: Row(
              children: [
                for (final boss in GameBalance.bosses)
                  Expanded(
                    child: Column(
                      children: [
                        OrionAtlasSprite(
                          art: OrionArt.boss(boss.sprite),
                          size: const Size.square(70),
                        ),
                        Text(
                          boss.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Roboto',
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OrionAtlasSprite), findsNWidgets(7));
    expect(find.byType(SpriteWidget), findsNWidgets(7));
    await tester.runAsync(
      () => captureReactorRimFixture(key, 'all-bosses-70px.png'),
    );
  });
}
