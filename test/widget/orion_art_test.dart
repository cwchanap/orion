import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';

void main() {
  group('OrionArt stage key art', () {
    test('every campaign stage resolves stage art for every crop', () {
      for (final stage in OrionCampaign.stages) {
        for (final crop in OrionStageArtCrop.values) {
          final art = OrionArt.stage(stage, crop: crop);
          expect(
            art.fileName,
            'reactor_rim_ui/stages/${stage.id}.png',
            reason: '${stage.id} $crop',
          );
          final rect = art.sourceRectFor(imageWidth: 1024, imageHeight: 1024);
          expect(rect.left, greaterThanOrEqualTo(0), reason: stage.id);
          expect(rect.top, greaterThanOrEqualTo(0), reason: stage.id);
          expect(rect.right, lessThanOrEqualTo(1024), reason: stage.id);
          expect(rect.bottom, lessThanOrEqualTo(1024), reason: stage.id);
        }
      }
    });

    test('briefingWide and mapSquare share one file per stage', () {
      for (final stage in OrionCampaign.stages) {
        final wide = OrionArt.stage(
          stage,
          crop: OrionStageArtCrop.briefingWide,
        );
        final square = OrionArt.stage(stage, crop: OrionStageArtCrop.mapSquare);
        expect(wide.fileName, square.fileName, reason: stage.id);
      }
    });

    test('mapSquare source rect is square', () {
      const sizes = [(1024.0, 1024.0), (1200.0, 800.0), (700.0, 900.0)];
      for (final stage in OrionCampaign.stages) {
        for (final (width, height) in sizes) {
          final rect = OrionArt.stage(
            stage,
            crop: OrionStageArtCrop.mapSquare,
          ).sourceRectFor(imageWidth: width, imageHeight: height);
          expect(
            rect.width,
            rect.height,
            reason: '${stage.id} at ${width}x$height',
          );
        }
      }
    });

    test('briefingWide source rect is wider than tall', () {
      const sizes = [(1024.0, 1024.0), (1200.0, 800.0), (700.0, 900.0)];
      for (final stage in OrionCampaign.stages) {
        for (final (width, height) in sizes) {
          final rect = OrionArt.stage(
            stage,
            crop: OrionStageArtCrop.briefingWide,
          ).sourceRectFor(imageWidth: width, imageHeight: height);
          expect(
            rect.width,
            greaterThan(rect.height),
            reason: '${stage.id} at ${width}x$height',
          );
        }
      }
    });
  });

  test('OrionArt.result(null) resolves defeat art', () {
    expect(OrionArt.result(null).fileName, 'reactor_rim_ui/results/defeat.png');
  });

  test(
    'OrionArt.result(non-null) resolves victory art regardless of medal',
    () {
      for (final medal in StageMedal.values) {
        final art = OrionArt.result(
          StageResult(medal: medal, bestBaseHealth: 12),
        );
        expect(
          art.fileName,
          'reactor_rim_ui/results/victory.png',
          reason: medal.name,
        );
      }
    },
  );

  test('medal remains a separate real StageResult fact', () {
    final gold = StageResult(medal: StageMedal.gold, bestBaseHealth: 20);
    final clear = StageResult(medal: StageMedal.clear, bestBaseHealth: 4);
    expect(gold.medal, isNot(clear.medal));
    expect(identical(OrionArt.result(gold), OrionArt.result(clear)), isTrue);
  });

  test('all three scene backdrops resolve through OrionArt', () {
    expect(
      OrionArt.scene(OrionSceneArt.worldMap).fileName,
      'reactor_rim_ui/backdrops/world-map.png',
    );
    expect(
      OrionArt.scene(OrionSceneArt.techTree).fileName,
      'reactor_rim_ui/backdrops/tech-tree-rnd-bay.png',
    );
    expect(
      OrionArt.scene(OrionSceneArt.missionReport).fileName,
      'reactor_rim_ui/backdrops/mission-report-debrief.png',
    );
  });

  test(
    'no public parallel resultHeroAssetPath/string-table API is introduced',
    () {
      // Tripwire over all of lib/: stage art stays behind the typed
      // OrionArtDescriptor registry, never a parallel path-string table.
      final offenders = <String>[
        for (final entity in Directory('lib').listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.dart'))
            if (entity.readAsStringSync().contains('resultHeroAssetPath') ||
                RegExp(
                  r'Map<String,\s*String>',
                ).hasMatch(entity.readAsStringSync()))
              entity.path,
      ];
      expect(offenders, isEmpty);
    },
  );

  test('every campaign stage has a crest descriptor', () {
    for (final stage in OrionCampaign.stages) {
      final crest = OrionArt.crestFor(stage);
      expect(crest.fileName, contains('crests/'));
      expect(crest.semanticLabel, isNotEmpty);
    }
  });

  test('commandCenter scene art is registered', () {
    expect(OrionSceneArt.values, contains(OrionSceneArt.commandCenter));
  });
}
