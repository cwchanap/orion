import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/ui/orion_primary_button.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/orion_typography.dart';
import 'package:orion/game/ui/mission_report_content.dart';
import 'package:orion/game/ui/mission_report_panel.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/orion_finders.dart';
import '../support/command_deck_fixtures.dart';
import '../support/reactor_rim_visual_capture.dart';
import '../support/real_fonts.dart';
import '../widget_test.dart' as fixtures;

void main() {
  testWidgets('saving victory shows save copy and disables both exits', (
    tester,
  ) async {
    // Catches a production panel that exposes replay/map before save truth is
    // resolved, which could discard an improving result. Callbacks are provided
    // so the test verifies the panel actively disables otherwise available
    // exits — not merely that no callback was supplied.
    var replayed = false;
    var returned = false;
    await _pumpPanel(
      tester,
      _victoryContent(MissionSaveState.saving),
      onReplay: () => replayed = true,
      onReturnToMap: () => returned = true,
    );

    expect(find.text('Saving result…'), findsOneWidget);
    expect(find.text('Replay Mission'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);

    final replayButton = tester.widget<TextButton>(
      find.descendant(
        of: find.byTooltip('Replay Mission'),
        matching: find.byType(TextButton),
      ),
    );
    final mapButton = tester.widget<TextButton>(
      find.descendant(
        of: find.byTooltip('World Map'),
        matching: find.byType(TextButton),
      ),
    );
    expect(replayButton.onPressed, isNull);
    expect(mapButton.onPressed, isNull);
    expect(replayed, isFalse);
    expect(returned, isFalse);
  });

  testWidgets('saved victory enables replay and world map actions', (
    tester,
  ) async {
    // Catches a production panel that leaves actions disabled after persistence
    // succeeds, preventing the player from continuing the campaign.
    var replayed = false;
    var returned = false;
    await _pumpPanel(
      tester,
      _victoryContent(MissionSaveState.saved),
      onReplay: () => replayed = true,
      onReturnToMap: () => returned = true,
    );

    expect(find.text('Saved.'), findsOneWidget);
    expect(find.text('Replay Mission'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);

    await tester.tap(find.byTooltip('Replay Mission'));
    await tester.tap(find.byTooltip('World Map'));
    expect(replayed, isTrue);
    expect(returned, isTrue);
  });

  testWidgets('failed victory offers retry save and unsaved map only', (
    tester,
  ) async {
    // Catches a production panel that presents a failed write as replayable or
    // silently labels the map exit as if the result had been committed.
    var retried = false;
    var returned = false;
    await _pumpPanel(
      tester,
      _victoryContent(MissionSaveState.failed),
      onRetrySave: () => retried = true,
      onReturnToMap: () => returned = true,
    );

    expect(find.text('Save failed — progress unchanged.'), findsOneWidget);
    expect(find.text('Retry Save'), findsOneWidget);
    expect(find.text('World Map (Unsaved)'), findsOneWidget);
    expect(find.text('Replay Mission'), findsNothing);

    await tester.tap(find.byTooltip('Retry Save'));
    await tester.tap(find.byTooltip('World Map (Unsaved)'));
    expect(retried, isTrue);
    expect(returned, isTrue);
  });

  testWidgets(
    'failed-save actions survive 3x text at 360x640 (Task 4 triage)',
    (tester) async {
      await tester.runAsync(loadRealFonts);
      final collect = _collectLayoutErrors();
      var retried = false;
      var returned = false;
      await _pumpScaledReport(
        tester,
        _victoryContent(MissionSaveState.failed),
        const Size(360, 640),
        capture: 'task6-fix1-failed-360-3x.png',
        onRetrySave: () => retried = true,
        onReturnToMap: () => returned = true,
      );
      collect.restore();
      _expectNoOverflow(collect.errors);
      _expectWholeStageName(tester);
      _expectWholeMedalCriteria(tester);
      _expectWholeStats(tester, ['HULL', 'WAVES', 'CREDITS', 'PENDING']);
      _expectWholeStats(tester, ['20/20', '8/8', '120', '+3']);
      expect(find.text('Save failed — progress unchanged.'), findsOneWidget);
      await _expectAction(tester, const Size(360, 640), 'Retry Save', true);
      await _expectAction(
        tester,
        const Size(360, 640),
        'World Map (Unsaved)',
        true,
      );
      expect(retried, isTrue);
      expect(returned, isTrue);
    },
  );

  group('tall-text report surfaces (fix round 1)', () {
    for (final size in const [Size(360, 640), Size(390, 844)]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('failed victory stays whole at 3x text, $label', (
        tester,
      ) async {
        await tester.runAsync(loadRealFonts);
        final collect = _collectLayoutErrors();
        var retried = false;
        var returned = false;
        await _pumpScaledReport(
          tester,
          _victoryContent(MissionSaveState.failed),
          size,
          capture: 'task6-fix1-failed-$label-3x.png',
          onRetrySave: () => retried = true,
          onReturnToMap: () => returned = true,
        );
        collect.restore();
        _expectNoOverflow(collect.errors);
        _expectWholeStageName(tester);
        _expectWholeMedalCriteria(tester);
        _expectWholeStats(tester, const [
          'HULL',
          'WAVES',
          'CREDITS',
          'PENDING',
        ]);
        _expectWholeStats(tester, const ['20/20', '8/8', '120', '+3']);
        expect(find.text('Save failed — progress unchanged.'), findsOneWidget);
        await _expectAction(tester, size, 'Retry Save', true);
        await _expectAction(tester, size, 'World Map (Unsaved)', true);
        expect(retried, isTrue);
        expect(returned, isTrue);
      });

      testWidgets('saved victory keeps whole labels and enabled exits '
          'at 3x text, $label', (tester) async {
        await tester.runAsync(loadRealFonts);
        final collect = _collectLayoutErrors();
        var replayed = false;
        var returned = false;
        await _pumpScaledReport(
          tester,
          _victoryContent(MissionSaveState.saved),
          size,
          capture: 'task6-fix1-saved-$label-3x.png',
          onReplay: () => replayed = true,
          onReturnToMap: () => returned = true,
        );
        collect.restore();
        _expectNoOverflow(collect.errors);
        _expectWholeStageName(tester);
        _expectWholeWords(tester, 'SECTOR SECURED');
        _expectWholeWords(tester, 'VICTORY');
        _expectWholeMedalCriteria(tester);
        _expectWholeStats(tester, const ['HULL', 'WAVES', 'CREDITS', 'R&D']);
        _expectWholeStats(tester, const ['20/20', '8/8', '120', '+3']);
        expect(find.text('Saved.'), findsOneWidget);
        expect(find.text('New first-clear result'), findsOneWidget);
        await _expectAction(tester, size, 'Replay Mission', true);
        await _expectAction(tester, size, 'World Map', true);
        expect(replayed, isTrue);
        expect(returned, isTrue);
      });

      testWidgets('defeat keeps whole labels and exits at 3x text, $label', (
        tester,
      ) async {
        await tester.runAsync(loadRealFonts);
        final collect = _collectLayoutErrors();
        var retried = false;
        var returned = false;
        await _pumpScaledReport(
          tester,
          _lossContent(),
          size,
          capture: 'task6-fix1-loss-$label-3x.png',
          onReplay: () => retried = true,
          onReturnToMap: () => returned = true,
        );
        collect.restore();
        _expectNoOverflow(collect.errors);
        _expectWholeStageName(tester);
        _expectWholeWords(tester, 'MISSION FAILED');
        _expectWholeStats(tester, const [
          'HULL',
          'WAVES',
          'CREDITS',
          'PENDING',
        ]);
        _expectWholeStats(tester, const ['0/20', '5/8', '120', '+0']);
        _expectWholeWords(tester, 'MISSION DETAILS');
        await _expectAction(tester, size, 'Retry', true);
        await _expectAction(tester, size, 'World Map', true);
        expect(retried, isTrue);
        expect(returned, isTrue);
      });
    }

    testWidgets('saving victory keeps gated exits whole at 3x text, 360x640', (
      tester,
    ) async {
      await tester.runAsync(loadRealFonts);
      final collect = _collectLayoutErrors();
      await _pumpScaledReport(
        tester,
        _victoryContent(MissionSaveState.saving),
        const Size(360, 640),
        capture: 'task6-fix1-saving-360x640-3x.png',
        onReplay: () {},
        onReturnToMap: () {},
      );
      collect.restore();
      _expectNoOverflow(collect.errors);
      _expectWholeStageName(tester);
      _expectWholeMedalCriteria(tester);
      expect(find.text('Saving result…'), findsOneWidget);
      await _expectAction(
        tester,
        const Size(360, 640),
        'Replay Mission',
        false,
      );
      await _expectAction(tester, const Size(360, 640), 'World Map', false);
    });

    testWidgets('endless saved report keeps whole exits at 3x text, 360x640', (
      tester,
    ) async {
      await tester.runAsync(loadRealFonts);
      final collect = _collectLayoutErrors();
      var replayed = false;
      var returned = false;
      await _pumpScaledReport(
        tester,
        _endlessContent(MissionSaveState.saved, priorBest: 5, savedBest: 8),
        const Size(360, 640),
        capture: 'task6-fix1-endless-saved-360x640-3x.png',
        onReplay: () => replayed = true,
        onReturnToMap: () => returned = true,
      );
      collect.restore();
      _expectNoOverflow(collect.errors);
      _expectWholeStageName(tester);
      _expectWholeWords(tester, 'ENDLESS RUN OVER');
      _expectWholeStats(tester, const ['HULL', 'WAVES', 'CREDITS']);
      _expectWholeStats(tester, const ['0/20', '8', '120']);
      expect(find.text('Saved.'), findsOneWidget);
      expect(find.text('New best! Previous: 5 waves'), findsOneWidget);
      await _expectAction(tester, const Size(360, 640), 'Replay Endless', true);
      await _expectAction(tester, const Size(360, 640), 'World Map', true);
      expect(replayed, isTrue);
      expect(returned, isTrue);
    });

    for (final (name, content) in [
      ('failed', _victoryContent(MissionSaveState.failed)),
      ('saved', _victoryContent(MissionSaveState.saved)),
      ('loss', _lossContent()),
    ]) {
      testWidgets('$name report stays whole at compact 1x, 360x640', (
        tester,
      ) async {
        await tester.runAsync(loadRealFonts);
        final collect = _collectLayoutErrors();
        await _pumpScaledReport(
          tester,
          content,
          const Size(360, 640),
          textScale: 1,
          capture: 'task6-fix1-$name-360x640-1x.png',
          onReplay: () {},
          onReturnToMap: () {},
          onRetrySave: () {},
        );
        collect.restore();
        _expectNoOverflow(collect.errors);
        _expectWholeStageName(tester);
      });
    }
  });

  group('painted title enlargement (fix round 2)', () {
    for (final stage in const [
      'Outpost Alpha',
      'Asteroid Foundry',
      'Singularity Core',
    ]) {
      for (final size in const [Size(360, 640), Size(390, 844)]) {
        final label = '${size.width.toInt()}x${size.height.toInt()}';
        final slug = stage.toLowerCase().replaceAll(' ', '-');
        testWidgets('$stage title honours 3x scale with whole words, '
            '$label', (tester) async {
          await tester.runAsync(loadRealFonts);
          final boundary = GlobalKey();
          final collect = _collectLayoutErrors();
          final content = _victoryContent(
            MissionSaveState.saved,
            stageName: stage,
          );
          await _pumpScaledReport(
            tester,
            content,
            size,
            textScale: 1,
            boundary: boundary,
            onReplay: () {},
            onReturnToMap: () {},
          );
          final at1 = _paintedTitleWords(tester, stage);
          await _pumpScaledReport(
            tester,
            content,
            size,
            textScale: 3,
            boundary: boundary,
            capture: 'task6-fix2-title-$slug-$label-3x.png',
            onReplay: () {},
            onReturnToMap: () {},
          );
          final at3 = _paintedTitleWords(tester, stage);
          collect.restore();
          _expectNoOverflow(collect.errors);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.label == stage,
            ),
            findsOneWidget,
            reason: 'exactly one accessible stage title',
          );
          final contentWidth = size.width - 40;
          for (final word in stage.toUpperCase().split(' ')) {
            final rects1 = at1[word]!;
            final rects3 = at3[word]!;
            expect(
              rects3.map((rect) => rect.top).toSet().length,
              1,
              reason: '"$word" splits across painted lines',
            );
            final bounds1 = _unionRects(rects1);
            final bounds3 = _unionRects(rects3);
            expect(
              bounds3.left >= -0.5 && bounds3.right <= size.width + 0.5,
              isTrue,
              reason: '"$word" clips painted horizontal bounds: $bounds3',
            );
            expect(
              bounds3.height,
              greaterThanOrEqualTo(bounds1.height - 0.5),
              reason: '"$word" paints smaller at 3x than at 1x',
            );
            if (_wordFitsAtScale(word, contentWidth, 3)) {
              expect(
                bounds3.height,
                greaterThanOrEqualTo(bounds1.height * 1.8),
                reason: '"$word" fits at 3x yet is not substantially enlarged',
              );
            }
          }
          expect(
            _unionRects(at3.values.expand((rects) => rects)).height,
            greaterThanOrEqualTo(
              _unionRects(at1.values.expand((rects) => rects)).height * 1.6,
            ),
            reason: 'painted title height does not grow substantially at 3x',
          );
          await tester.ensureVisible(find.text('MISSION DETAILS'));
          await tester.pumpAndSettle();
          final footer = tester.getRect(
            find.ancestor(
              of: find.text('World Map'),
              matching: find.byType(OrionPrimaryButton),
            ),
          );
          expect(
            footer.top >= 0 && footer.bottom <= size.height,
            isTrue,
            reason: 'pinned footer left the viewport after scrolling',
          );
        });
      }
    }
  });

  testWidgets('3x scrolled details captures for failed and saved states', (
    tester,
  ) async {
    await tester.runAsync(loadRealFonts);
    for (final (name, content) in [
      ('failed', _victoryContent(MissionSaveState.failed)),
      ('saved', _victoryContent(MissionSaveState.saved)),
    ]) {
      final collect = _collectLayoutErrors();
      final boundary = GlobalKey();
      await _pumpScaledReport(
        tester,
        content,
        const Size(360, 640),
        boundary: boundary,
        capture: 'task6-fix2-$name-360x640-3x-top.png',
        onReplay: () {},
        onReturnToMap: () {},
        onRetrySave: () {},
      );
      await tester.ensureVisible(find.text('WAVES'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => captureReactorRimFixture(
          boundary,
          'task6-fix2-$name-360x640-3x-stats.png',
        ),
      );
      await tester.ensureVisible(find.text('MISSION DETAILS'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => captureReactorRimFixture(
          boundary,
          'task6-fix2-$name-360x640-3x-scrolled.png',
        ),
      );
      collect.restore();
      _expectNoOverflow(collect.errors);
      final footer = tester.getRect(
        find.ancestor(
          of: find.text(name == 'failed' ? 'World Map (Unsaved)' : 'World Map'),
          matching: find.byType(OrionPrimaryButton),
        ),
      );
      expect(
        footer.top >= 0 && footer.bottom <= 640,
        isTrue,
        reason: '$name pinned footer left the viewport after scrolling',
      );
    }
  });

  testWidgets('loss offers retry and world map actions', (tester) async {
    // Catches a production panel that omits a recovery path after a lost run.
    var retried = false;
    var returned = false;
    await _pumpPanel(
      tester,
      _lossContent(),
      onReplay: () => retried = true,
      onReturnToMap: () => returned = true,
    );

    expect(find.text('MISSION FAILED'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);

    await tester.tap(find.byTooltip('Retry'));
    await tester.tap(find.byTooltip('World Map'));
    expect(retried, isTrue);
    expect(returned, isTrue);
  });

  testWidgets('module IDs reuse acquired strip title and effect copy', (
    tester,
  ) async {
    // Catches a production panel that forks module rendering and drifts from
    // the existing in-run title/effect text.
    await _pumpPanel(
      tester,
      _victoryContent(
        MissionSaveState.saved,
        moduleIds: const [RunModuleId.heavyCaliber],
      ),
    );

    final definition = runModuleDefinition(RunModuleId.heavyCaliber);
    await _openDetails(tester);
    expect(find.textContaining(definition.title), findsOneWidget);
    expect(find.textContaining(definition.effectText), findsOneWidget);
  });

  testWidgets('empty module IDs show the projected empty-state copy', (
    tester,
  ) async {
    // Catches a production panel that invents a second empty-state string or
    // leaves the Salvage Modules section blank.
    await _pumpPanel(tester, _victoryContent(MissionSaveState.saved));

    await _openDetails(tester);
    expect(find.text('No Salvage Modules acquired'), findsOneWidget);
  });

  testWidgets('optional reward fact renders its title and detail', (
    tester,
  ) async {
    // Catches a production panel that drops the typed reward seam needed by
    // the follow-up reward slice.
    await _pumpPanel(
      tester,
      _victoryContent(
        MissionSaveState.saved,
        reward: const MissionRewardFact(
          title: 'Blueprint fragment',
          detail: 'Unlocks a new blueprint after saving.',
        ),
      ),
    );

    await _openDetails(tester);
    expect(find.text('Blueprint fragment'), findsOneWidget);
    expect(find.text('Unlocks a new blueprint after saving.'), findsOneWidget);
  });

  testWidgets(
    'null saveState victory fails closed with both actions disabled',
    (tester) async {
      // Catches a production panel that fails open for an unknown/null victory
      // save state, enabling Replay/World Map before persistence is resolved.
      // The production page only renders a victory report after
      // _missionSaveState != null, so null is not normally reachable. Still,
      // failing closed is the safe default: treat null like saving so a future
      // integration mistake cannot silently permit leaving with an uncommitted
      // result.
      var replayed = false;
      var returned = false;
      await _pumpPanel(
        tester,
        _victoryContentNullSaveState(),
        onReplay: () => replayed = true,
        onReturnToMap: () => returned = true,
      );

      expect(find.text('Replay Mission'), findsOneWidget);
      expect(find.text('World Map'), findsOneWidget);

      final replayButton = tester.widget<TextButton>(
        find.descendant(
          of: find.byTooltip('Replay Mission'),
          matching: find.byType(TextButton),
        ),
      );
      final mapButton = tester.widget<TextButton>(
        find.descendant(
          of: find.byTooltip('World Map'),
          matching: find.byType(TextButton),
        ),
      );
      expect(replayButton.onPressed, isNull);
      expect(mapButton.onPressed, isNull);
      expect(replayed, isFalse);
      expect(returned, isFalse);
    },
  );

  testWidgets('null saveState victory shows the info save-status icon', (
    tester,
  ) async {
    // Catches a production _SaveStateRow that drops the null-state icon case.
    await _pumpPanel(tester, _victoryContentNullSaveState());

    expect(find.bySemanticsLabel('Save status'), findsOneWidget);
  });

  testWidgets('three module IDs fit the 360 by 640 surface without overflow', (
    tester,
  ) async {
    // Catches a production layout that lets the report body push fixed actions
    // off-screen or overflow instead of scrolling its content.
    await _pumpPanel(
      tester,
      _victoryContent(
        MissionSaveState.saved,
        moduleIds: const [
          RunModuleId.heavyCaliber,
          RunModuleId.overclockRelay,
          RunModuleId.longSight,
        ],
      ),
    );

    expect(find.text('Replay Mission'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);

    // Verify the action buttons are physically reachable within the viewport,
    // not merely present in the widget tree.
    final replayRect = tester.getRect(
      find.descendant(
        of: find.byTooltip('Replay Mission'),
        matching: find.byType(TextButton),
      ),
    );
    final mapRect = tester.getRect(
      find.descendant(
        of: find.byTooltip('World Map'),
        matching: find.byType(TextButton),
      ),
    );
    expect(replayRect.top, greaterThanOrEqualTo(0));
    expect(replayRect.bottom, lessThanOrEqualTo(640));
    expect(mapRect.top, greaterThanOrEqualTo(0));
    expect(mapRect.bottom, lessThanOrEqualTo(640));

    expect(tester.takeException(), isNull);
  });

  testWidgets('saved victory fixture: debrief backdrop, victory banner, '
      'medal glyphs, real facts', (tester) async {
    // Scene 1h restyle pin: the report reads as a debrief over the approved
    // backdrop, with exactly ONE result banner selected through
    // OrionArt.result(content.result), medal treatment derived from the real
    // StageResult.medal (vector glyphs, no per-medal bitmaps), and the real
    // stage facts. No score/time/kills/damage/R&D analytics exist here.
    await _pumpPanel(
      tester,
      _victoryContent(
        MissionSaveState.saved,
        moduleIds: const [RunModuleId.heavyCaliber],
        reward: const MissionRewardFact(
          title: 'Blueprint fragment',
          detail: 'Unlocks a new blueprint after saving.',
        ),
      ),
      onReplay: () {},
      onReturnToMap: () {},
    );

    // Debrief-hall backdrop + readability scrim, art cover-fit under the scrim.
    await _openDetails(tester);
    expect(
      find.byKey(const ValueKey('mission-report-backdrop')),
      findsOneWidget,
    );
    final backdropArt = find.descendant(
      of: find.byKey(const ValueKey('mission-report-backdrop')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.key == const ValueKey('mission-report-backdrop-art'),
      ),
    );
    expect(backdropArt, findsOneWidget);
    final backdropStack = tester.widget<Stack>(
      find.ancestor(of: backdropArt, matching: find.byType(Stack)).first,
    );
    final layerKeys = [
      for (final child in backdropStack.children)
        (child is Positioned ? child.child : child).key,
    ];
    final artIndex = layerKeys.indexOf(
      const ValueKey('mission-report-backdrop-art'),
    );
    final scrimIndex = layerKeys.indexOf(
      const ValueKey('mission-report-scrim'),
    );
    expect(artIndex, greaterThanOrEqualTo(0));
    expect(scrimIndex, greaterThan(artIndex));

    // Exactly ONE victory banner via OrionArt.result(non-null result); the
    // defeat art must never appear next to it.
    expect(
      find.byKey(const ValueKey('mission-report-result-art')),
      findsOneWidget,
    );
    expect(_resultArt('reactor_rim_ui/results/victory.png'), findsOneWidget);
    expect(_resultArt('reactor_rim_ui/results/defeat.png'), findsNothing);

    expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
    expect(find.text('SECTOR SECURED'), findsOneWidget);
    expect(findOrionTitle('Outpost Alpha'), findsOneWidget);
    expect(find.text('Gold medal • Base 20/20'), findsOneWidget);
    expect(find.text('New first-clear result'), findsOneWidget);
    expect(find.text('Saved.'), findsOneWidget);

    // Module content/count and reward as subordinate sections.
    expect(find.textContaining('Heavy Caliber'), findsOneWidget);
    expect(
      find.textContaining(runModuleDefinition(RunModuleId.heavyCaliber).title),
      findsOneWidget,
    );
    expect(find.text('Blueprint fragment'), findsOneWidget);

    // Current state-appropriate actions.
    expect(find.text('Replay Mission'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);
  });

  testWidgets('loss shows the defeat banner and keeps Retry + World Map', (
    tester,
  ) async {
    // OrionArt.result(null) must resolve the defeat banner; a loss has no
    // StageResult, so no medal treatment may appear.
    var retried = false;
    var returned = false;
    await _pumpPanel(
      tester,
      _lossContent(),
      onReplay: () => retried = true,
      onReturnToMap: () => returned = true,
    );

    await _openDetails(tester);
    expect(
      find.byKey(const ValueKey('mission-report-result-art')),
      findsOneWidget,
    );
    expect(_resultArt('reactor_rim_ui/results/defeat.png'), findsOneWidget);
    expect(_resultArt('reactor_rim_ui/results/victory.png'), findsNothing);
    expect(find.byIcon(Icons.workspace_premium), findsNothing);
    expect(find.text('MISSION FAILED'), findsOneWidget);
    expect(findOrionTitle('Outpost Alpha'), findsOneWidget);
    expect(find.text('Reached Wave 5/8'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);

    await tester.tap(find.byTooltip('Retry'));
    await tester.tap(find.byTooltip('World Map'));
    expect(retried, isTrue);
    expect(returned, isTrue);
  });

  group('endless defeat report', () {
    testWidgets(
      'shows ENDLESS RUN OVER and never mission-failed copy or semantics',
      (tester) async {
        await _pumpPanel(tester, _endlessContent(MissionSaveState.saved));

        expect(find.text('ENDLESS RUN OVER'), findsOneWidget);
        expect(find.text('MISSION FAILED'), findsNothing);

        final handle = tester.ensureSemantics();
        try {
          expect(find.bySemanticsLabel('Endless Run Over'), findsOneWidget);
          // The decorative result graphic announces the endless outcome,
          // not a mission failure.
          expect(find.bySemanticsLabel('Endless run over'), findsOneWidget);
          expect(find.bySemanticsLabel('Mission Failed'), findsNothing);
          expect(find.bySemanticsLabel('Mission failed'), findsNothing);
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets('WAVES stat reads wavesCleared, not the attempted wave', (
      tester,
    ) async {
      // Defeat during wave 9: eight clears are the score.
      await _pumpPanel(
        tester,
        _endlessContent(MissionSaveState.saved, waveNumber: 9, wavesCleared: 8),
      );
      expect(find.text('8'), findsOneWidget);
      expect(find.text('9'), findsNothing);
      expect(find.textContaining('/8'), findsNothing);

      // Defeat during wave 1: zero clears.
      await _pumpPanel(
        tester,
        _endlessContent(MissionSaveState.saved, waveNumber: 1, wavesCleared: 0),
      );
      expect(find.text('0'), findsOneWidget);
      expect(find.text('0/20'), findsOneWidget);
    });

    testWidgets('omits the R&D tile and any medal reward', (tester) async {
      await _pumpPanel(tester, _endlessContent(MissionSaveState.saved));

      expect(find.text('R&D'), findsNothing);
      expect(find.text('PENDING'), findsNothing);
      expect(find.textContaining('R&D'), findsNothing);
      expect(find.byIcon(Icons.pentagon), findsNothing);

      // The suppression is endless-scoped: an ordinary mission loss keeps
      // its PENDING tile.
      await _pumpPanel(tester, _lossContent());
      expect(find.text('PENDING'), findsOneWidget);
      expect(find.bySemanticsLabel('Save status'), findsNothing);
    });

    testWidgets('saved state shows comparison, save row, and both exits', (
      tester,
    ) async {
      var replayed = false;
      var returned = false;
      await _pumpPanel(
        tester,
        _endlessContent(MissionSaveState.saved, priorBest: 5, savedBest: 8),
        onReplay: () => replayed = true,
        onReturnToMap: () => returned = true,
      );

      expect(find.text('Saved.'), findsOneWidget);
      expect(find.text('New best! Previous: 5 waves'), findsOneWidget);
      expect(find.bySemanticsLabel('Save status'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      // The replay action launches another endless run, so it is labeled
      // 'Replay Endless' — 'Replay Mission' belongs to the finite mission.
      expect(find.text('Replay Endless'), findsOneWidget);
      expect(find.text('Replay Mission'), findsNothing);
      expect(find.text('World Map'), findsOneWidget);

      await tester.tap(find.byTooltip('Replay Endless'));
      await tester.tap(find.byTooltip('World Map'));
      expect(replayed, isTrue);
      expect(returned, isTrue);
    });

    testWidgets(
      'zero-wave endless defeat pairs No result to save with info icon',
      (tester) async {
        await _pumpPanel(
          tester,
          _endlessContent(
            MissionSaveState.saved,
            waveNumber: 1,
            wavesCleared: 0,
            priorBest: null,
            savedBest: null,
          ),
        );

        expect(find.text('No result to save.'), findsOneWidget);
        expect(find.byIcon(Icons.info_outline), findsOneWidget);
        expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      },
    );

    testWidgets('saving keeps replay and return disabled', (tester) async {
      await _pumpPanel(
        tester,
        _endlessContent(MissionSaveState.saving),
        onReplay: () {},
        onReturnToMap: () {},
      );

      expect(find.text('Saving result…'), findsOneWidget);
      final replayButton = tester.widget<TextButton>(
        find.descendant(
          of: find.byTooltip('Replay Endless'),
          matching: find.byType(TextButton),
        ),
      );
      final mapButton = tester.widget<TextButton>(
        find.descendant(
          of: find.byTooltip('World Map'),
          matching: find.byType(TextButton),
        ),
      );
      expect(replayButton.onPressed, isNull);
      expect(mapButton.onPressed, isNull);
    });

    testWidgets('failed offers Retry Save and the unsaved map exit', (
      tester,
    ) async {
      var retried = false;
      var returned = false;
      await _pumpPanel(
        tester,
        _endlessContent(MissionSaveState.failed, savedBest: 5),
        onRetrySave: () => retried = true,
        onReturnToMap: () => returned = true,
      );

      expect(find.text('Save failed — best 5 waves kept.'), findsOneWidget);
      expect(find.text('Retry Save'), findsOneWidget);
      expect(find.text('World Map (Unsaved)'), findsOneWidget);
      expect(find.text('Replay Mission'), findsNothing);
      expect(find.text('Replay Endless'), findsNothing);

      await tester.tap(find.byTooltip('Retry Save'));
      await tester.tap(find.byTooltip('World Map (Unsaved)'));
      expect(retried, isTrue);
      expect(returned, isTrue);
    });
  });

  testWidgets('Reduced Motion leaves saved-victory actions immediately '
      'available', (tester) async {
    // No entrance animation may delay action availability: with animations
    // disabled the Replay action fires on the very first frame, with no
    // settling pumps in between.
    var replayed = false;
    await _pumpPanel(
      tester,
      _victoryContent(MissionSaveState.saved),
      onReplay: () => replayed = true,
      disableAnimations: true,
    );

    await tester.tap(find.byTooltip('Replay Mission'));
    expect(replayed, isTrue);
  });

  testWidgets('capture scene 1h fixture', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Representative scene 1h state: saved victory — debrief backdrop + scrim,
    // victory result banner, gold medal glyphs, real stage facts, module strip
    // + reward, Replay/World Map actions. Real Roboto + Material icons so the
    // evidence shows true text metrics.
    await loadRealFonts();
    // The memo can hold a pending future from an earlier cold-cache test
    // in this process; clear it so this fixture's warmed cache is used.
    OrionArtDescriptor.resetSpriteCache();
    // Image decode is real async engine work that cannot complete under the
    // test FakeAsync zone; pre-warm the Flame cache (keyed by file name, the
    // same keys the OrionArt descriptors use) so the art renders.
    await tester.runAsync(() async {
      await Flame.images.load(
        'reactor_rim_ui/backdrops/mission-report-debrief.png',
      );
      await Flame.images.load('reactor_rim_ui/results/victory.png');
      await Flame.images.load('orion_tower_variety_sheet.png');
    });

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          // The product app hides this banner; a fixture host must too, or the
          // parity evidence carries a stripe the shipped game never shows.
          debugShowCheckedModeBanner: false,
          theme: orionThemeData,
          home: Scaffold(
            body: MissionReportPanel(
              content: _victoryContent(
                MissionSaveState.saved,
                moduleIds: const [
                  RunModuleId.heavyCaliber,
                  RunModuleId.overclockRelay,
                ],
                reward: const MissionRewardFact(
                  title: 'Blueprint fragment',
                  detail: 'Unlocks a new blueprint after saving.',
                ),
              ),
              onReplay: () {},
              onReturnToMap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mission-report-backdrop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mission-report-backdrop-art')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mission-report-scrim')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mission-report-result-art')),
      findsOneWidget,
    );
    expect(_resultArt('reactor_rim_ui/results/victory.png'), findsOneWidget);
    expect(find.text('SECTOR SECURED'), findsOneWidget);
    expect(findOrionTitle('Outpost Alpha'), findsOneWidget);
    expect(find.text('New first-clear result'), findsOneWidget);
    expect(find.text('Saved.'), findsOneWidget);
    expect(find.text('Replay Mission'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);

    await tester.runAsync(
      () => warmSceneImages(tester.element(find.byType(MissionReportPanel)), [
        'reactor_rim_ui/backdrops/mission-report-debrief.png',
        'reactor_rim_ui/results/victory.png',
      ]),
    );
    await tester.pump();
    // No-op unless ORION_CAPTURE_DIR is set. runAsync: PNG encoding is
    // real async engine work and deadlocks the FakeAsync zone otherwise.
    await tester.runAsync(
      () => captureReactorRimFixture(boundaryKey, 'fixture-1h.png'),
    );
    for (final variant in {
      'loss': _lossContent(),
      'saving': _victoryContent(MissionSaveState.saving),
      'failed': _victoryContent(MissionSaveState.failed),
    }.entries) {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: orionThemeData,
            home: Scaffold(
              body: MissionReportPanel(
                content: variant.value,
                onReplay: () {},
                onReturnToMap: () {},
                onRetrySave: () {},
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => warmSceneImages(tester.element(find.byType(MissionReportPanel)), [
          'reactor_rim_ui/backdrops/mission-report-debrief.png',
          'reactor_rim_ui/results/defeat.png',
          'reactor_rim_ui/results/victory.png',
        ]),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () => captureReactorRimFixture(
          boundaryKey,
          'fixture-1h-${variant.key}.png',
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });

  group('command-deck report hierarchy (HPA-699)', () {
    testWidgets('result art spans the hero behind the stage heading', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        _victoryContent(MissionSaveState.saved),
        size: const Size(390, 844),
      );
      final art = tester.getRect(
        find.byKey(const ValueKey('mission-report-result-art')),
      );
      final title = tester.getRect(findOrionTitle('Outpost Alpha'));
      expect(art.top, 0);
      expect(art.width, 390);
      expect(art.height, greaterThanOrEqualTo(300));
      expect(art.contains(title.center), isTrue);
    });

    testWidgets('the victory ribbon has notched ends', (tester) async {
      await _pumpPanel(tester, _victoryContent(MissionSaveState.saved));
      final ribbon = find.ancestor(
        of: findOrionTitle('Victory'),
        matching: find.byType(ClipPath),
      );
      expect(ribbon, findsOneWidget);
      final clip = tester.widget<ClipPath>(ribbon);
      final size = tester.getSize(ribbon);
      final path = clip.clipper!.getClip(size);
      expect(path.contains(Offset(1, size.height / 2)), isFalse);
      expect(path.contains(Offset(size.width / 2, size.height / 2)), isTrue);
    });

    Finder criterion(String label) => find.textContaining(
      RegExp(RegExp.escape(label), caseSensitive: false),
      findRichText: true,
    );

    testWidgets('victory medals show distinct criteria glyphs', (tester) async {
      await _pumpPanel(tester, _victoryContent(MissionSaveState.saved));
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
    });

    testWidgets('victory carries an outcome ribbon and all three medal '
        'criteria', (tester) async {
      await _pumpPanel(tester, _victoryContent(MissionSaveState.saved));

      expect(find.text('VICTORY'), findsOneWidget);
      for (final label in ['Cleared', '10+ hull', 'No leaks']) {
        expect(criterion(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('a clear-only victory still shows all three medal criteria', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        projectVictoryReport(
          snapshot: _syntheticSnapshot(),
          result: const StageResult(medal: StageMedal.clear, bestBaseHealth: 8),
          priorSavedResult: null,
          saveState: MissionSaveState.saved,
        ),
      );

      for (final label in ['Cleared', '10+ hull', 'No leaks']) {
        expect(criterion(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('defeat reports render no medal treatment', (tester) async {
      for (final content in [
        _lossContent(),
        _endlessContent(MissionSaveState.saved),
      ]) {
        await _pumpPanel(tester, content);
        expect(find.text('×'), findsNothing);
        for (final label in ['Cleared', '10+ hull', 'No leaks']) {
          expect(
            criterion(label),
            findsNothing,
            reason:
                '$label (${content.snapshot.isEndless ? 'endless' : 'mission'})',
          );
        }
      }
    });

    testWidgets('a reward fact renders in the report body, not only in '
        'details', (tester) async {
      await _pumpPanel(
        tester,
        _victoryContent(
          MissionSaveState.saved,
          reward: const MissionRewardFact(
            title: 'Blueprint fragment',
            detail: 'Unlocks a new blueprint after saving.',
          ),
        ),
      );

      expect(find.text('Blueprint fragment'), findsOneWidget);
      expect(
        find.text('Unlocks a new blueprint after saving.'),
        findsOneWidget,
      );
    });

    testWidgets('an endless report never surfaces rewards even when content '
        'carries one', (tester) async {
      final content = MissionReportContent(
        snapshot: _syntheticSnapshot(
          phase: GamePhase.lost,
          baseHealth: 0,
          missionWaveTotal: null,
          wavesCleared: 4,
        ),
        stageId: 'outpost-alpha',
        stageName: 'Outpost Alpha',
        didWin: false,
        outcomeText: 'Survived 4 waves',
        moduleIds: const [],
        saveState: MissionSaveState.saved,
        saveText: 'Saved.',
        reward: const MissionRewardFact(
          title: 'Blueprint fragment',
          detail: 'Unlocks a new blueprint after saving.',
        ),
        nextOpportunityText:
            'Replay for a better result or continue on the World Map.',
      );
      await _pumpPanel(tester, content);
      await _openDetails(tester);

      expect(find.text('Blueprint fragment'), findsNothing);
    });

    testWidgets('report actions are shared OrionPrimaryButtons', (
      tester,
    ) async {
      Future<void> expectShared(String label, {bool? primary}) async {
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byType(OrionPrimaryButton),
        );
        expect(button, findsOneWidget, reason: label);
        final widget = tester.widget<OrionPrimaryButton>(button);
        if (primary == true) {
          expect(widget.variant, OrionButtonVariant.primary, reason: label);
        } else if (primary == false) {
          expect(
            widget.variant,
            isNot(OrionButtonVariant.primary),
            reason: label,
          );
        }
      }

      await _pumpPanel(
        tester,
        _victoryContent(MissionSaveState.saved),
        onReplay: () {},
        onReturnToMap: () {},
      );
      await expectShared('World Map', primary: true);
      await expectShared('Replay Mission', primary: false);

      await _pumpPanel(
        tester,
        _lossContent(),
        onReplay: () {},
        onReturnToMap: () {},
      );
      await expectShared('Retry', primary: false);
      await expectShared('World Map', primary: true);

      await _pumpPanel(
        tester,
        _victoryContent(MissionSaveState.failed),
        onRetrySave: () {},
        onReturnToMap: () {},
      );
      await expectShared('Retry Save', primary: false);
      await expectShared('World Map (Unsaved)');

      await _pumpPanel(
        tester,
        _endlessContent(MissionSaveState.saved),
        onReplay: () {},
        onReturnToMap: () {},
      );
      await expectShared('Replay Endless', primary: false);
    });

    testWidgets('saving keeps both shared actions disabled', (tester) async {
      await _pumpPanel(
        tester,
        _victoryContent(MissionSaveState.saving),
        onReplay: () {},
        onReturnToMap: () {},
      );

      for (final label in ['Replay Mission', 'World Map']) {
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byType(OrionPrimaryButton),
        );
        expect(button, findsOneWidget, reason: label);
        expect(
          tester.widget<OrionPrimaryButton>(button).onPressed,
          isNull,
          reason: label,
        );
      }
    });

    testWidgets('no report state exposes a Continue or next-stage action', (
      tester,
    ) async {
      for (final content in [
        _victoryContent(MissionSaveState.saving),
        _victoryContent(MissionSaveState.saved),
        _victoryContent(MissionSaveState.failed),
        _lossContent(),
        _endlessContent(MissionSaveState.saving),
        _endlessContent(MissionSaveState.saved),
        _endlessContent(MissionSaveState.failed),
        _endlessContent(
          MissionSaveState.saved,
          waveNumber: 1,
          wavesCleared: 0,
          priorBest: null,
          savedBest: null,
        ),
      ]) {
        await _pumpPanel(tester, content);
        expect(find.text('Continue'), findsNothing);
        expect(find.text('Next'), findsNothing);
      }
    });

    testWidgets('zero-wave endless defeat keeps both exits enabled', (
      tester,
    ) async {
      var replayed = false;
      var returned = false;
      await _pumpPanel(
        tester,
        _endlessContent(
          MissionSaveState.saved,
          waveNumber: 1,
          wavesCleared: 0,
          priorBest: null,
          savedBest: null,
        ),
        onReplay: () => replayed = true,
        onReturnToMap: () => returned = true,
      );

      expect(find.text('0'), findsOneWidget);
      expect(find.text('No result to save.'), findsOneWidget);
      expect(find.text('Replay Endless'), findsOneWidget);
      expect(find.text('World Map'), findsOneWidget);

      await tester.tap(find.text('Replay Endless'));
      await tester.tap(find.text('World Map'));
      expect(replayed, isTrue);
      expect(returned, isTrue);
    });

    testWidgets('an ordinary victory World Map exits to the sector map, '
        'never a briefing', (tester) async {
      SharedPreferences.setMockInitialValues({});
      OrionDefenseGame? game;
      await tester.pumpWidget(
        fixtures.testGamePage(onGameCreated: (created) => game = created),
      );
      await tester.pumpAndSettle();
      await fixtures.startStageFromBriefing(tester);
      await fixtures.publishVictory(
        tester,
        game!,
        result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );
      await tester.pumpAndSettle();

      expect(find.text('Continue'), findsNothing);
      await tester.tap(find.byTooltip('World Map'));
      await tester.pumpAndSettle();
      expect(find.text('ORION SECTOR'), findsOneWidget);
      expect(find.byKey(const ValueKey('stage-briefing')), findsNothing);
    });

    testWidgets('a completed-campaign victory World Map exits to the sector '
        'map', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await fixtures.storeWithResults({
        for (final stage in OrionCampaign.stages)
          stage.id: const StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 1,
          ),
      });
      OrionDefenseGame? game;
      await tester.pumpWidget(
        fixtures.testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();
      await fixtures.startStageFromBriefing(
        tester,
        mapLabel: 'Core',
        actionLabel: 'Replay Mission',
      );
      await fixtures.publishVictory(
        tester,
        game!,
        result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );
      await tester.pumpAndSettle();

      expect(find.text('Continue'), findsNothing);
      await tester.tap(find.byTooltip('World Map'));
      await tester.pumpAndSettle();
      expect(find.text('ORION SECTOR'), findsOneWidget);
      expect(find.byKey(const ValueKey('stage-briefing')), findsNothing);
    });

    group('rewards panel save-state copy (fix round 1)', () {
      Finder rewardsCard(WidgetTester tester) {
        final title = find.text('REWARDS');
        expect(title, findsOneWidget);
        final card = tester
            .widgetList<OrionSurface>(
              find.ancestor(of: title, matching: find.byType(OrionSurface)),
            )
            .singleWhere((surface) => surface.role == OrionSurfaceRole.card);
        return find.byWidget(card);
      }

      testWidgets(
        'saving victory qualifies projected R&D as pending, not spendable',
        (tester) async {
          await _pumpPanel(
            tester,
            _victoryContent(MissionSaveState.saving),
            onReplay: () {},
            onReturnToMap: () {},
          );
          expect(find.text('Saving result…'), findsOneWidget);

          final panel = rewardsCard(tester);
          expect(
            find.descendant(of: panel, matching: find.text('+3 R&D')),
            findsOneWidget,
            reason: 'projected medal points still render while pending',
          );
          expect(
            find.descendant(
              of: panel,
              matching: find.text('Spend it in the R&D lab'),
            ),
            findsNothing,
            reason: 'uncommitted points must not read as spendable',
          );
          expect(
            find.descendant(
              of: panel,
              matching: find.textContaining(
                RegExp('pending', caseSensitive: false),
              ),
            ),
            findsWidgets,
            reason: 'the rewards panel must qualify the points as pending',
          );

          for (final label in ['Replay Mission', 'World Map']) {
            final button = find.ancestor(
              of: find.text(label),
              matching: find.byType(OrionPrimaryButton),
            );
            expect(
              tester.widget<OrionPrimaryButton>(button).onPressed,
              isNull,
              reason: label,
            );
          }
        },
      );

      testWidgets('failed victory qualifies projected R&D as not awarded', (
        tester,
      ) async {
        await _pumpPanel(
          tester,
          _victoryContent(MissionSaveState.failed),
          onRetrySave: () {},
          onReturnToMap: () {},
        );
        expect(find.text('Save failed — progress unchanged.'), findsOneWidget);
        expect(find.text('Retry Save'), findsOneWidget);
        expect(find.text('World Map (Unsaved)'), findsOneWidget);
        expect(find.text('Replay Mission'), findsNothing);

        final panel = rewardsCard(tester);
        expect(
          find.descendant(of: panel, matching: find.text('+3 R&D')),
          findsOneWidget,
          reason: 'projected medal points still render when unawarded',
        );
        expect(
          find.descendant(
            of: panel,
            matching: find.text('Spend it in the R&D lab'),
          ),
          findsNothing,
          reason: 'points are not awarded when the save failed',
        );
        expect(
          find.descendant(
            of: panel,
            matching: find.textContaining(
              RegExp(
                'unawarded|not awarded|not committed',
                caseSensitive: false,
              ),
            ),
          ),
          findsWidgets,
          reason:
              'the rewards panel must qualify the points as not '
              'awarded',
        );
      });

      testWidgets('saved victory keeps spendable R&D wording', (tester) async {
        await _pumpPanel(tester, _victoryContent(MissionSaveState.saved));
        expect(find.text('Saved.'), findsOneWidget);

        final panel = rewardsCard(tester);
        expect(
          find.descendant(of: panel, matching: find.text('+3 R&D')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: panel,
            matching: find.text('Spend it in the R&D lab'),
          ),
          findsOneWidget,
        );
      });

      testWidgets(
        'retained best awards no additional R&D but keeps reward copy',
        (tester) async {
          await _pumpPanel(
            tester,
            projectVictoryReport(
              snapshot: _syntheticSnapshot(),
              result: const StageResult(
                medal: StageMedal.gold,
                bestBaseHealth: 20,
              ),
              priorSavedResult: const StageResult(
                medal: StageMedal.gold,
                bestBaseHealth: 20,
              ),
              saveState: MissionSaveState.saved,
              reward: const MissionRewardFact(
                title: 'Blueprint fragment',
                detail: 'Unlocks a new blueprint after saving.',
              ),
            ),
          );
          expect(
            find.text('Saved best retained: Gold • 20 base health'),
            findsOneWidget,
          );
          expect(find.text('Best result already saved.'), findsOneWidget);

          final panel = rewardsCard(tester);
          expect(
            find.descendant(
              of: panel,
              matching: find.textContaining(RegExp(r'\+\d+ R&D')),
            ),
            findsNothing,
            reason: 'a retained result awards zero additional points',
          );
          expect(
            find.descendant(
              of: panel,
              matching: find.text('Blueprint fragment'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: panel,
              matching: find.text('Unlocks a new blueprint after saving.'),
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets('reward copy stays identical across save states', (
        tester,
      ) async {
        for (final state in MissionSaveState.values) {
          await _pumpPanel(
            tester,
            _victoryContent(
              state,
              reward: const MissionRewardFact(
                title: 'Blueprint fragment',
                detail: 'Unlocks a new blueprint after saving.',
              ),
            ),
          );
          final panel = rewardsCard(tester);
          expect(
            find.descendant(
              of: panel,
              matching: find.text('Blueprint fragment'),
            ),
            findsOneWidget,
            reason: state.name,
          );
          expect(
            find.descendant(
              of: panel,
              matching: find.text('Unlocks a new blueprint after saving.'),
            ),
            findsOneWidget,
            reason: state.name,
          );
        }
      });
    });
  });
}

Finder _resultArt(String fileName) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName == 'assets/images/$fileName',
);

Future<void> _pumpPanel(
  WidgetTester tester,
  MissionReportContent content, {
  Size size = const Size(360, 640),
  VoidCallback? onReplay,
  VoidCallback? onReturnToMap,
  VoidCallback? onRetrySave,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        home: Scaffold(
          body: MissionReportPanel(
            content: content,
            onReplay: onReplay,
            onReturnToMap: onReturnToMap,
            onRetrySave: onRetrySave,
          ),
        ),
      ),
    ),
  );

  expect(find.byType(OrionSurface), findsWidgets);
}

GameSnapshot _syntheticSnapshot({
  List<RunModuleId> modules = const [],
  int baseHealth = 20,
  int waveNumber = 8,
  int? missionWaveTotal = 8,
  int wavesCleared = 0,
  GamePhase phase = GamePhase.won,
  String stageName = 'Outpost Alpha',
}) {
  return commandDeckSnapshot(
    phase: phase,
    gold: 120,
    baseHealth: baseHealth,
    startingBaseHealth: 20,
    waveNumber: waveNumber,
    missionWaveTotal: missionWaveTotal,
    wavesCleared: wavesCleared,
    stageId: 'outpost-alpha',
    stageName: stageName,
    stageLabel: 'Alpha',
    unlockedTowerTypes: const [TowerType.laser, TowerType.cryo],
    acquiredRunModules: modules,
  );
}

MissionReportContent _victoryContent(
  MissionSaveState saveState, {
  List<RunModuleId> moduleIds = const [],
  MissionRewardFact? reward,
  String stageName = 'Outpost Alpha',
}) {
  return projectVictoryReport(
    snapshot: _syntheticSnapshot(modules: moduleIds, stageName: stageName),
    result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    priorSavedResult: null,
    saveState: saveState,
    reward: reward,
  );
}

MissionReportContent _victoryContentNullSaveState() {
  return MissionReportContent(
    snapshot: _syntheticSnapshot(),
    stageId: 'outpost-alpha',
    stageName: 'Outpost Alpha',
    didWin: true,
    outcomeText: 'Gold medal • Base 20/20',
    comparisonText: 'New first-clear result',
    moduleIds: const [],
    emptyModulesText: 'No Salvage Modules acquired',
    saveState: null,
    saveText: 'Save status pending.',
    nextOpportunityText:
        'Replay for a better result or continue on the World Map.',
  );
}

MissionReportContent _lossContent() {
  return projectLossReport(
    snapshot: _syntheticSnapshot(
      phase: GamePhase.lost,
      baseHealth: 0,
      waveNumber: 5,
    ),
  );
}

MissionReportContent _endlessContent(
  MissionSaveState saveState, {
  int waveNumber = 9,
  int wavesCleared = 8,
  int? priorBest = 5,
  int? savedBest,
  List<RunModuleId> moduleIds = const [],
}) {
  return projectEndlessReport(
    snapshot: _syntheticSnapshot(
      phase: GamePhase.lost,
      baseHealth: 0,
      waveNumber: waveNumber,
      missionWaveTotal: null,
      wavesCleared: wavesCleared,
      modules: moduleIds,
    ),
    priorBest: priorBest,
    savedBest: savedBest,
    saveState: saveState,
  );
}

Future<void> _openDetails(WidgetTester tester) async {
  final details = find.text('MISSION DETAILS');
  await tester.ensureVisible(details);
  await tester.tap(details);
  await tester.pumpAndSettle();
}

({List<FlutterErrorDetails> errors, void Function() restore})
_collectLayoutErrors() {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  void restore() => FlutterError.onError = previous;
  addTearDown(restore);
  return (errors: errors, restore: restore);
}

void _expectNoOverflow(List<FlutterErrorDetails> errors) {
  final overflows = errors
      .where((details) => details.exceptionAsString().contains('overflowed'))
      .toList();
  expect(
    overflows,
    isEmpty,
    reason: overflows.map((d) => d.exceptionAsString()).join('\n'),
  );
}

Future<void> _pumpScaledReport(
  WidgetTester tester,
  MissionReportContent content,
  Size viewSize, {
  double textScale = 3,
  String? capture,
  GlobalKey? boundary,
  VoidCallback? onReplay,
  VoidCallback? onReturnToMap,
  VoidCallback? onRetrySave,
}) async {
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final boundaryKey = boundary ?? GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: orionThemeData,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: RepaintBoundary(
          key: boundaryKey,
          child: MissionReportPanel(
            content: content,
            onReplay: onReplay,
            onReturnToMap: onReturnToMap,
            onRetrySave: onRetrySave,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (capture != null) {
    await tester.runAsync(() => captureReactorRimFixture(boundaryKey, capture));
  }
}

void _expectWholeWords(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget, reason: text);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  var start = 0;
  for (var i = 0; i <= text.length; i++) {
    if (i < text.length && text[i] != ' ') continue;
    if (start < i) {
      final tops = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: i),
          )
          .map((box) => box.top)
          .toSet();
      expect(
        tops.length,
        1,
        reason: '"${text.substring(start, i)}" in "$text" splits mid-word',
      );
    }
    start = i + 1;
  }
}

void _expectWholeStageName(WidgetTester tester) {
  if (find.text('OUTPOST ALPHA').evaluate().isNotEmpty) {
    _expectWholeWords(tester, 'OUTPOST ALPHA');
  } else {
    _expectWholeWords(tester, 'OUTPOST');
    _expectWholeWords(tester, 'ALPHA');
  }
}

void _expectWholeMedalCriteria(WidgetTester tester) {
  for (final label in const ['CLEARED', '10+ HULL', 'NO LEAKS']) {
    _expectWholeWords(tester, label);
  }
}

void _expectWholeStats(WidgetTester tester, List<String> texts) {
  for (final text in texts) {
    _expectWholeWords(tester, text);
  }
}

Map<String, List<Rect>> _paintedTitleWords(
  WidgetTester tester,
  String stageName,
) {
  final upper = stageName.toUpperCase();
  final words = upper.split(' ');
  final result = <String, List<Rect>>{};
  final joined = find.text(upper);
  if (joined.evaluate().isNotEmpty) {
    final paragraph = tester.renderObject<RenderParagraph>(joined);
    var cursor = 0;
    for (final word in words) {
      final start = upper.indexOf(word, cursor);
      result[word] = _paintedWordRects(paragraph, start, start + word.length);
      cursor = start + word.length;
    }
  } else {
    for (final word in words) {
      final finder = find.text(word);
      expect(finder, findsOneWidget, reason: 'title word "$word" missing');
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      result[word] = _paintedWordRects(paragraph, 0, word.length);
    }
  }
  return result;
}

List<Rect> _paintedWordRects(RenderParagraph paragraph, int start, int end) {
  return [
    for (final box in paragraph.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    ))
      Rect.fromPoints(
        paragraph.localToGlobal(Offset(box.left, box.top)),
        paragraph.localToGlobal(Offset(box.right, box.bottom)),
      ),
  ];
}

Rect _unionRects(Iterable<Rect> rects) {
  var union = rects.first;
  for (final rect in rects.skip(1)) {
    union = union.expandToInclude(rect);
  }
  return union;
}

bool _wordFitsAtScale(String word, double maxWidth, double scale) {
  final painter = TextPainter(
    text: TextSpan(
      text: word,
      style: OrionTypography.title(color: const Color(0xFFFFFFFF), size: 26),
    ),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(scale),
  )..layout();
  return painter.width <= maxWidth;
}

Future<void> _expectAction(
  WidgetTester tester,
  Size viewSize,
  String label,
  bool enabled,
) async {
  final button = find.ancestor(
    of: find.text(label),
    matching: find.byType(OrionPrimaryButton),
  );
  expect(button, findsOneWidget, reason: label);
  final rect = tester.getRect(button);
  expect(rect.width, greaterThanOrEqualTo(48), reason: '$label target width');
  expect(rect.height, greaterThanOrEqualTo(48), reason: '$label target height');
  expect(rect.left, greaterThanOrEqualTo(0), reason: '$label left edge');
  expect(
    rect.right,
    lessThanOrEqualTo(viewSize.width),
    reason: '$label right edge',
  );
  expect(rect.top, greaterThanOrEqualTo(0), reason: '$label top edge');
  expect(
    rect.bottom,
    lessThanOrEqualTo(viewSize.height),
    reason: '$label bottom edge',
  );
  expect(
    tester.widget<OrionPrimaryButton>(button).onPressed != null,
    enabled,
    reason: '$label enabled gate',
  );
  _expectWholeWords(tester, label);
  if (enabled) {
    await tester.tap(find.byTooltip(label));
    await tester.pump();
  }
}
