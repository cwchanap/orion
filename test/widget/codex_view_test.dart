import 'dart:ui' show Tristate;

import 'package:flame/flame.dart';
import 'package:flame/widgets.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_reward_label.dart';
import 'package:orion/game/codex/codex_data.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/codex_view.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_menu_shell.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/tower_stat_scale.dart';
import 'package:orion/game/util/format.dart';

import '../support/reactor_rim_visual_capture.dart';
import '../support/real_fonts.dart';

void main() {
  testWidgets('tower detail leads with its portrait beside the heading', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: CodexView(progress: CampaignProgress())),
    );
    await tester.pumpAndSettle();
    final detail = find.byKey(const ValueKey('codex-detail'));
    final portrait = find
        .descendant(of: detail, matching: find.byType(OrionAtlasSprite))
        .first;
    final heading = find.descendant(of: detail, matching: find.text('LASER'));
    expect(
      tester.getRect(heading).left,
      greaterThanOrEqualTo(tester.getRect(portrait).right),
    );
    expect(
      tester.getRect(heading).top,
      lessThan(tester.getRect(portrait).bottom),
    );
  });

  testWidgets('renders the four section chips and Towers content by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );

    for (final chip in const ['Towers', 'Enemies', 'Effects', 'Stages']) {
      expect(find.text(chip), findsWidgets);
    }
    // Default section is Towers: the first tower label appears.
    expect(find.text(TowerType.laser.label), findsOneWidget);
  });

  testWidgets('tapping Enemies shows the enemy section', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );
    await tester.tap(find.text('Enemies'));
    await tester.pumpAndSettle();
    // Assert the basic drone's role description — authored prose rendered only
    // on the enemy card. The enemy label ('Drones') collides with the Drone
    // Bay stat-row key in the Towers section, so it can't distinguish sections.
    final basicDrone = CodexData.enemies.firstWhere(
      (e) => e.archetype == EnemyArchetype.basicDrone,
    );
    expect(find.text(basicDrone.roleDescription), findsOneWidget);
  });

  testWidgets('tapping Effects shows the effects section', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );
    await tester.tap(find.text('Effects'));
    await tester.pumpAndSettle();
    // 'Armor Shred' (capital S) is unique to the effects glossary; the
    // specialty-line stat key is 'Armor shred' (lowercase).
    expect(find.text('Armor Shred'), findsOneWidget);
  });

  testWidgets('tapping Stages shows the stages section', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );
    await tester.tap(find.text('Stages'));
    await tester.pumpAndSettle();
    // The first stage card title is '<name> (<mapLabel>)'.
    expect(find.textContaining('Outpost Alpha'), findsOneWidget);
  });

  // Regression: switching chips must not carry one section's scroll offset
  // into another, and returning to a section must restore its prior offset.
  // The offset is read via the section ListView's own controller, looked up
  // by PageStorageKey (never find.byType(Scrollable) — once search lands, the
  // TextField's EditableText adds another Scrollable).
  testWidgets('retains each section scroll offset when switching chips', (
    tester,
  ) async {
    // Short viewport so the Towers list overflows and can actually scroll.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );

    // Scroll Towers (section 0) to a nonzero offset.
    await tester.drag(
      find.byKey(const PageStorageKey<int>(0)),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    final towersOffset = tester
        .widget<ListView>(find.byKey(const PageStorageKey<int>(0)))
        .controller!
        .offset;
    expect(towersOffset, greaterThan(0));

    // Enemies (section 1) begins at zero despite Towers' nonzero offset.
    await tester.tap(find.text('Enemies'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ListView>(find.byKey(const PageStorageKey<int>(1)))
          .controller!
          .offset,
      0,
    );

    // Returning to Towers restores its prior offset.
    await tester.tap(find.text('Towers'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ListView>(find.byKey(const PageStorageKey<int>(0)))
          .controller!
          .offset,
      towersOffset,
    );
  });

  testWidgets('back button invokes onBack', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(
          progress: CampaignProgress(),
          onBack: () => pressed = true,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Back'));
    expect(pressed, isTrue);
  });

  testWidgets('the shared shell shows a Codex tab that reports selection', (
    tester,
  ) async {
    final selected = <OrionMenuDestination>[];
    await tester.pumpWidget(
      MaterialApp(
        home: OrionMenuShell(
          destination: OrionMenuDestination.sectors,
          medalEarned: 0,
          medalTotal: 15,
          researchPoints: 0,
          onDestinationSelected: selected.add,
          onOpenSettings: () {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    expect(find.byTooltip('Codex'), findsOneWidget);
    await tester.tap(find.byTooltip('Codex'));
    expect(selected, [OrionMenuDestination.codex]);
  });

  testWidgets('renders every section without overflow on a narrow surface', (
    tester,
  ) async {
    // 360 x 640 logical surface (spec §10.3).
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );

    for (final chip in const ['Towers', 'Enemies', 'Effects', 'Stages']) {
      await tester.tap(find.text(chip));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
  });

  // Regression: the cadence formatter must preserve two-decimal precision for
  // fire / field-tick / drone-attack intervals instead of collapsing them via
  // number()'s one-decimal rounding.
  testWidgets('Pulse Laser exposes its 0.24s fire interval (not prose-only)', (
    tester,
  ) async {
    // Tall surface so the lazy Towers ListView builds every tower card,
    // including the Pulse Laser specialization rows near the bottom.
    tester.view.physicalSize = const Size(800, 10000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();
    // Towers is the default section. Pulse Laser's defining benefit is its
    // 0.24s fire interval; it must render as a numeric row, not be hidden.
    expect(find.text('0.24s'), findsOneWidget);
    // The specialization heading renders as "Pulse Laser (<cost>g)".
    expect(
      find.textContaining(TowerSpecialization.pulseLaser.label),
      findsOneWidget,
    );
  });

  testWidgets('Gravity Well field tick interval renders at 0.45s', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 10000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();
    // Both Gravity Well specializations tick at 0.45s; the Field row is a
    // single composite value string, so match by substring. number() would
    // have rendered 0.5s here.
    expect(find.textContaining('0.45s'), findsWidgets);
  });

  // Regression: shield/armor damage multipliers must preserve two-decimal
  // precision (e.g. 1.55, 1.65) instead of collapsing to one decimal via
  // number()'s toStringAsFixed(1) rounding.
  testWidgets('Magnetic Railgun vs Armored multiplier renders at x1.55', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 10000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();
    // Magnetic Railgun's armorDamageMultiplier is 1.55; number() would have
    // rendered x1.6.
    expect(find.text('x1.55'), findsOneWidget);
  });

  testWidgets('Overload Relay vs Shield multiplier renders at x1.65', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 10000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();
    // Overload Relay's shieldDamageMultiplier is 1.65; number() would have
    // rendered x1.6 or x1.7.
    expect(find.text('x1.65'), findsOneWidget);
  });

  // Regression: stageRewardLabel already prefixes uncleared rewards with
  // "Reward: "; the codex must not also key the row with "Reward" and produce
  // "Reward Reward: +30 Gold".
  testWidgets(
    'uncleared side stage reward renders without duplicated Reward wording',
    (tester) async {
      final progress = CampaignProgress(); // salvage-rift locked + uncleared
      await tester.pumpWidget(
        MaterialApp(
          home: CodexView(progress: progress, onBack: () {}),
        ),
      );
      await tester.tap(find.text('Stages'));
      await tester.pumpAndSettle();

      final salvageRift = OrionCampaign.stages.firstWhere(
        (s) => s.id == 'salvage-rift',
      );
      final expected = stageRewardLabel(salvageRift, isCleared: false);
      expect(expected, 'Reward: +${GameBalance.salvageRiftGoldBonus} Gold');
      expect(find.text(expected!), findsOneWidget);
      // No keyed-row duplication.
      expect(find.textContaining('Reward Reward'), findsNothing);
    },
  );

  // Pin the three status badge labels specified by the feature contract.
  testWidgets('status badges render Locked / Unlocked / Cleared', (
    tester,
  ) async {
    // outpost-alpha cleared => Cleared; nebula-relay (dep cleared, not cleared
    // itself) => Unlocked; aurora-gate (dep asteroid-foundry not cleared) =>
    // Locked. All three badges appear in one Stages view.
    final progress = CampaignProgress(
      bestResultsByStageId: {
        OrionCampaign.stageOneId: const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 0,
        ),
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: progress, onBack: () {}),
      ),
    );
    await tester.tap(find.text('Stages'));
    await tester.pumpAndSettle();

    expect(find.text('Cleared'), findsOneWidget);
    expect(find.text('Unlocked'), findsOneWidget);
    expect(find.text('Locked'), findsWidgets);
    // The old non-contract label must be gone.
    expect(find.text('Open'), findsNothing);
  });

  // ---------------------------------------------------------------------
  // Search (HPA-753). Helpers and new-behavior tests.
  // ---------------------------------------------------------------------

  Widget codexHost({TextScaler? textScaler}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: textScaler == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
    home: CodexView(progress: CampaignProgress(), onBack: () {}),
  );

  // Tall surface so every lazy list card is built and negative assertions
  // only inspect entries that are visible without filtering.
  Future<void> pumpCodex(
    WidgetTester tester, {
    Size size = const Size(800, 10000),
    TextScaler? textScaler,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(codexHost(textScaler: textScaler));
    await tester.pumpAndSettle();
  }

  final searchField = find.byType(TextField);

  String queryText(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).controller.text;

  bool searchFocused(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

  ScrollController sectionController(WidgetTester tester, int section) => tester
      .widget<ListView>(find.byKey(PageStorageKey<int>(section)))
      .controller!;

  double maxExtent(WidgetTester tester, int section) =>
      sectionController(tester, section).position.maxScrollExtent;

  // Fixed pumps instead of pumpAndSettle: a focused field's blinking caret
  // schedules frames forever, and iOS overscroll needs time to decay.
  Future<void> dragResultList(WidgetTester tester, int section) async {
    await tester.drag(
      find.byKey(PageStorageKey<int>(section)),
      const Offset(0, -40),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('searching towers filters to matching cards only', (
    tester,
  ) async {
    await pumpCodex(tester);
    // Precondition: the Laser card is visible without filtering.
    expect(find.text(TowerType.laser.label), findsOneWidget);

    await tester.enterText(searchField, 'gravity');
    await tester.pump();

    expect(find.text(TowerType.laser.label), findsNothing);
    expect(find.text(TowerType.gravityWell.label), findsOneWidget);
  });

  testWidgets('query matching ignores case and surrounding whitespace', (
    tester,
  ) async {
    await pumpCodex(tester);
    await tester.enterText(searchField, '  GRAVITY  ');
    await tester.pump();

    expect(find.text(TowerType.gravityWell.label), findsOneWidget);
    expect(find.text(TowerType.laser.label), findsNothing);
  });

  testWidgets('a specialization match shows the parent tower card', (
    tester,
  ) async {
    await pumpCodex(tester);
    expect(find.text(TowerType.gravityWell.label), findsOneWidget);

    await tester.enterText(searchField, 'pulse');
    await tester.pump();

    // The Laser card (parent of Pulse Laser) is the single result.
    expect(find.text(TowerType.laser.label), findsOneWidget);
    expect(
      find.textContaining(TowerSpecialization.pulseLaser.label),
      findsOneWidget,
    );
    expect(find.text(TowerType.gravityWell.label), findsNothing);
  });

  testWidgets('enemies search filters trait glossary and cards independently', (
    tester,
  ) async {
    await pumpCodex(tester);
    await tester.tap(find.text('Enemies'));
    await tester.pumpAndSettle();
    expect(find.text('Drones'), findsOneWidget); // visible without filtering

    // Trait-only hit: the glossary line stays, enemy cards and divider go.
    await tester.enterText(searchField, 'large numbers');
    await tester.pump();
    expect(find.text(EnemyTrait.swarm.label), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
    expect(find.text('Drones'), findsNothing);

    // Enemy-only hit: the card stays, glossary and divider go.
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    await tester.enterText(searchField, 'bruiser');
    await tester.pump();
    expect(find.text(EnemyTrait.heavy.label), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
    expect(find.text(EnemyTrait.armored.label), findsNothing);

    // Both groups hit: the divider shows iff both sets are nonempty.
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    await tester.enterText(searchField, 'armored');
    await tester.pump();
    expect(find.byType(Divider), findsOneWidget);
    expect(find.text(EnemyArchetype.armoredDrone.label), findsOneWidget);
    expect(find.text(EnemyTrait.armored.label), findsWidgets);
  });

  testWidgets('effects search filters the effect glossary', (tester) async {
    await pumpCodex(tester);
    await tester.tap(find.text('Effects'));
    await tester.pumpAndSettle();
    expect(find.text('Slow'), findsOneWidget); // visible without filtering

    await tester.enterText(searchField, 'chain');
    await tester.pump();

    expect(find.text('Chain Lightning'), findsOneWidget);
    expect(find.text('Slow'), findsNothing);
  });

  testWidgets('stages search filters stage cards', (tester) async {
    await pumpCodex(tester);
    await tester.tap(find.text('Stages'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Outpost Alpha'), findsOneWidget);

    await tester.enterText(searchField, 'nebula');
    await tester.pump();

    expect(find.textContaining('Nebula Relay'), findsOneWidget);
    expect(find.textContaining('Outpost Alpha'), findsNothing);
  });

  testWidgets('zero results render an in-list no-matches message', (
    tester,
  ) async {
    await pumpCodex(tester);
    await tester.enterText(searchField, 'zzzz');
    await tester.pump();

    expect(find.text('No matches in Towers'), findsOneWidget);
    // The section ListView is retained (not swapped for a Center), so the
    // zero-result list keeps its key, controller and drag behavior.
    expect(find.byKey(const PageStorageKey<int>(0)), findsOneWidget);

    await tester.tap(find.text('Effects'));
    await tester.pumpAndSettle();
    await tester.enterText(searchField, 'zzzz');
    await tester.pump();
    expect(find.text('No matches in Effects'), findsOneWidget);
  });

  testWidgets('no-matches message is centered in the results area', (
    tester,
  ) async {
    await pumpCodex(tester);
    await tester.enterText(searchField, 'zzzz');
    await tester.pump();

    // Centered, the message shrink-wraps its glyphs inside the list slot;
    // left-aligned, its Text box is stretched to the full slot width.
    final messageWidth = tester
        .getSize(find.text('No matches in Towers'))
        .width;
    final listWidth = tester
        .getSize(find.byKey(const PageStorageKey<int>(0)))
        .width;
    expect(messageWidth, lessThan(listWidth / 2));
    expect(
      tester.getCenter(find.text('No matches in Towers')).dx,
      closeTo(
        tester.getCenter(find.byKey(const PageStorageKey<int>(0))).dx,
        0.1,
      ),
    );
  });

  testWidgets('clear action restores the full list', (tester) async {
    await pumpCodex(tester);
    await tester.enterText(searchField, 'gravity');
    await tester.pump();
    expect(find.text(TowerType.laser.label), findsNothing);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();

    expect(queryText(tester), '');
    expect(find.text(TowerType.laser.label), findsOneWidget);
    // The optional Clear action disappears once the field is empty.
    expect(find.byTooltip('Clear'), findsNothing);
  });

  testWidgets('changing the query resets the active section scroll offset', (
    tester,
  ) async {
    await pumpCodex(tester, size: const Size(800, 600));
    await tester.drag(
      find.byKey(const PageStorageKey<int>(0)),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(sectionController(tester, 0).offset, greaterThan(0));

    await tester.enterText(searchField, 'gravity');
    await tester.pump();

    expect(sectionController(tester, 0).offset, 0);
  });

  // The shell hosts the Codex by in-place view swap (no Navigator), so a
  // bare PageStorageKey would park offsets in the app-long root route bucket.
  // Reopening the Codex must start each section from the top again, like the
  // pre-search view did, while offsets still survive chip switches within a
  // visit (previous test).
  testWidgets('reopening the codex resets section scroll offsets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var showCodex = true;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => showCodex
              ? CodexView(
                  progress: CampaignProgress(),
                  onBack: () => setState(() => showCodex = false),
                )
              : TextButton(
                  onPressed: () => setState(() => showCodex = true),
                  child: const Text('Open Codex'),
                ),
        ),
      ),
    );

    // Scroll Towers (section 0) down, then leave and reopen the Codex.
    await tester.drag(
      find.byKey(const PageStorageKey<int>(0)),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(sectionController(tester, 0).offset, greaterThan(0));

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Codex'));
    await tester.pumpAndSettle();

    // A fresh visit begins at the top, not at the stored route-bucket offset.
    expect(sectionController(tester, 0).offset, 0);
  });

  testWidgets(
    "switching tabs with an active query keeps other sections' offsets",
    (tester) async {
      await pumpCodex(tester, size: const Size(800, 600));
      await tester.tap(find.text('Enemies'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const PageStorageKey<int>(1)),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      final enemiesOffset = sectionController(tester, 1).offset;
      expect(enemiesOffset, greaterThan(0));

      // Filtering on Towers resets only Towers' scroll.
      await tester.tap(find.text('Towers'));
      await tester.pumpAndSettle();
      await tester.enterText(searchField, 'gravity');
      await tester.pump();
      expect(sectionController(tester, 0).offset, 0);

      // Returning to Enemies clears the query but restores its prior offset.
      await tester.tap(find.text('Enemies'));
      await tester.pumpAndSettle();
      expect(queryText(tester), '');
      expect(sectionController(tester, 1).offset, enemiesOffset);
    },
  );

  testWidgets(
    'switching tabs with an active query resets the searched section scroll offset on return',
    (tester) async {
      await pumpCodex(tester, size: const Size(800, 600));

      // Search and scroll within the filtered results.
      await tester.enterText(searchField, 'armor');
      await tester.pump();
      await tester.drag(
        find.byKey(const PageStorageKey<int>(0)),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(sectionController(tester, 0).offset, greaterThan(0));

      // Switching away clears the query.
      await tester.tap(find.text('Enemies'));
      await tester.pumpAndSettle();
      expect(queryText(tester), '');

      // Returning to Towers shows the full list reset to the top.
      await tester.tap(find.text('Towers'));
      await tester.pumpAndSettle();
      expect(sectionController(tester, 0).offset, 0);
    },
  );

  testWidgets(
    're-tapping the selected chip keeps the query; a different chip clears it',
    (tester) async {
      await pumpCodex(tester);
      await tester.tap(searchField);
      await tester.pump();
      await tester.enterText(searchField, 'gravity');
      await tester.pump();
      expect(searchFocused(tester), isTrue);

      // Re-tap the already-selected Towers chip: query and focus survive.
      await tester.tap(find.text('Towers'));
      await tester.pump();
      expect(queryText(tester), 'gravity');
      expect(searchFocused(tester), isTrue);
      expect(find.text(TowerType.gravityWell.label), findsOneWidget);

      // A different chip clears the query and shows the full enemy list.
      await tester.tap(find.text('Enemies'));
      await tester.pump();
      expect(queryText(tester), '');
      expect(searchFocused(tester), isFalse);
      final basicDrone = CodexData.enemies.firstWhere(
        (e) => e.archetype == EnemyArchetype.basicDrone,
      );
      expect(find.text(basicDrone.roleDescription), findsOneWidget);

      // The query filters only the active section's own data.
      await tester.enterText(searchField, 'heavy');
      await tester.pump();
      expect(find.text('Drone Bay'), findsNothing); // tower, other section
      expect(find.text(EnemyArchetype.heavyDrone.label), findsOneWidget);
      expect(find.text('Drones'), findsNothing); // basic drone filtered out
      expect(find.byType(Divider), findsOneWidget); // trait + cards both hit
    },
  );

  // Mouse (and web touch) taps outside the field unfocus it on pointer-down
  // through EditableText's tap-outside default action, before _selectSection's
  // re-tap guard runs. The chips must sit inside the field's tap region so a
  // re-tap of the selected chip cannot steal focus on those devices.
  testWidgets('mouse re-tap of the selected chip keeps query and focus', (
    tester,
  ) async {
    await pumpCodex(tester);
    await tester.tap(searchField);
    await tester.pump();
    await tester.enterText(searchField, 'gravity');
    await tester.pump();
    expect(searchFocused(tester), isTrue);

    // One long-lived mouse pointer for every tap below (a fresh pointer with
    // the same id trips MouseTracker while the previous one is connected).
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    Future<void> mouseTap(Finder target) async {
      await mouse.down(tester.getCenter(target));
      await mouse.up();
      await tester.pump();
    }

    // Re-tap the already-selected Towers chip: query and focus survive.
    await mouseTap(find.text('Towers'));
    expect(queryText(tester), 'gravity');
    expect(searchFocused(tester), isTrue);

    // A different chip still clears the query and drops focus explicitly.
    await mouseTap(find.text('Enemies'));
    expect(queryText(tester), '');
    expect(searchFocused(tester), isFalse);
  });

  // Short surface with a faked software keyboard: the search
  // chrome must stay clamped and usable at large text scales.
  testWidgets('keyboard-open short surface stays usable at 2x and 3x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.reset);
    // Widget finders cannot see the semantics tree: assert the search label
    // and the no-results message are actually exposed (exactly once) to
    // assistive technology, not merely rendered. Disposed in the body: the
    // binding verifies handles before addTearDown callbacks run.
    final semantics = tester.ensureSemantics();

    for (final scaler in const [TextScaler.linear(2), TextScaler.linear(3)]) {
      // The previous iteration ended on another chip; state survives the
      // repump, so return to a known section (and empty query) first.
      if (scaler != const TextScaler.linear(2)) {
        await tester.tap(find.text('Towers'));
        await tester.pump();
      }
      await tester.pumpWidget(codexHost(textScaler: scaler));
      await tester.pump();

      // Exactly one accessible search label, reflecting the section.
      expect(find.bySemanticsLabel('Search towers'), findsOneWidget);

      // No-results message is announced while the keyboard is up.
      await tester.enterText(searchField, 'zzzz');
      await tester.pump();
      expect(find.bySemanticsLabel('No matches in Towers'), findsOneWidget);

      // The Clear tooltip is usable and restores the list.
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      expect(find.text(TowerType.laser.label), findsOneWidget);

      // Switching tabs keeps the compact chrome overflow-free.
      await tester.tap(find.text('Enemies'));
      await tester.pump();
      expect(find.bySemanticsLabel('Search enemies'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });

  testWidgets('result cards keep full text scale outside the clamped chrome', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cardLabel = find.text(TowerType.laser.label);
    final chromeLabel = find.text('Search towers');

    await tester.pumpWidget(codexHost());
    await tester.pump();
    final cardAt1x = tester.getSize(cardLabel).height;
    final chromeAt1x = tester.getSize(chromeLabel).height;

    await tester.pumpWidget(codexHost(textScaler: const TextScaler.linear(3)));
    await tester.pump();
    final cardAt3x = tester.getSize(cardLabel).height;
    final chromeAt3x = tester.getSize(chromeLabel).height;

    // The scrolling card body scales fully (3x)...
    expect(cardAt3x, greaterThan(cardAt1x * 2.5));
    // ...while the header/chips/search chrome stays clamped near 1.15x.
    expect(chromeAt3x, lessThan(chromeAt1x * 1.35));
  });

  // A user drag on the results must dismiss the keyboard even when the list
  // cannot scroll (Android clamps, iOS bounces); a programmatic scroll start
  // must not. Parametrized per platform.
  Future<void> dragDismissScenarios(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    // The faked keyboard stays up for every populated drag below: unfocus
    // must not depend on the (never-shrinking) fake viewInsets.
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.reset);

    // Empty zero-scroll-extent result list: drag start must unfocus.
    await tester.pumpWidget(codexHost());
    await tester.pump();
    await tester.enterText(searchField, 'zzzz');
    await tester.pump();
    expect(maxExtent(tester, 0), 0); // precondition: cannot scroll
    expect(searchFocused(tester), isTrue);
    await dragResultList(tester, 0);
    expect(searchFocused(tester), isFalse);

    // Short populated result list on the keyboard-open surface. The single
    // 'pierce' card may overflow the inset viewport — only the user-drag
    // unfocus matters here, not the scroll extent.
    await tester.tap(find.text('Effects'));
    await tester.pump();
    await tester.enterText(searchField, 'pierce');
    await tester.pump();
    expect(find.text('Pierce'), findsOneWidget); // precondition: one card
    expect(searchFocused(tester), isTrue);
    await dragResultList(tester, 2);
    expect(searchFocused(tester), isFalse);

    // Ordinary scrollable result list, still with the keyboard up.
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(maxExtent(tester, 2), greaterThan(0));
    await tester.tap(searchField);
    await tester.pump();
    expect(searchFocused(tester), isTrue);
    await dragResultList(tester, 2);
    expect(searchFocused(tester), isFalse);

    // A programmatic scroll start (no dragDetails) keeps focus.
    await tester.tap(searchField);
    await tester.pump();
    expect(searchFocused(tester), isTrue);
    sectionController(tester, 2).jumpTo(10);
    await tester.pump();
    expect(searchFocused(tester), isTrue);

    // Empty-list drag also unfocuses at a large text scale, where the tiny
    // inset viewport may even scroll the no-matches message itself.
    await tester.pumpWidget(codexHost(textScaler: const TextScaler.linear(3)));
    await tester.pump();
    await tester.tap(find.text('Towers'));
    await tester.pump();
    await tester.enterText(searchField, 'zzzz');
    await tester.pump();
    expect(searchFocused(tester), isTrue);
    await dragResultList(tester, 0);
    expect(searchFocused(tester), isFalse);

    // Additional coverage without the fake inset: a short populated list and
    // an empty no-matches list that genuinely cannot scroll, at 1x and 3x.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpWidget(codexHost());
    await tester.pump();
    await tester.tap(find.text('Effects'));
    await tester.pump();
    await tester.enterText(searchField, 'pierce');
    await tester.pump();
    expect(maxExtent(tester, 2), 0); // precondition: single short card
    expect(searchFocused(tester), isTrue);
    await dragResultList(tester, 2);
    expect(searchFocused(tester), isFalse);

    await tester.tap(find.text('Towers'));
    await tester.pump();
    await tester.pumpWidget(codexHost(textScaler: const TextScaler.linear(3)));
    await tester.pump();
    await tester.enterText(searchField, 'zzzz');
    await tester.pump();
    expect(maxExtent(tester, 0), 0); // precondition: cannot scroll
    expect(searchFocused(tester), isTrue);
    await dragResultList(tester, 0);
    expect(searchFocused(tester), isFalse);
  }

  Future<void> verifyDragDismissesKeyboard(
    WidgetTester tester,
    TargetPlatform platform,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    // Reset inside the body: the binding checks debug variables before
    // addTearDown callbacks would run.
    try {
      await dragDismissScenarios(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('drag on results dismisses the keyboard on android', (
    tester,
  ) async {
    await verifyDragDismissesKeyboard(tester, TargetPlatform.android);
  });

  testWidgets('drag on results dismisses the keyboard on ios', (tester) async {
    await verifyDragDismissesKeyboard(tester, TargetPlatform.iOS);
  });

  group('command-deck tabs, tiles and detail (HPA-699)', () {
    Finder tabText(String label) => find.text(label);

    Rect tabRect(WidgetTester tester, String label) =>
        tester.getRect(tabText(label));

    testWidgets('the four tabs form a single segmented row', (tester) async {
      await pumpCodex(tester, size: const Size(390, 844));
      const labels = ['Towers', 'Enemies', 'Effects', 'Stages'];

      final top = tabRect(tester, labels.first).top;
      for (final label in labels) {
        expect(
          tabRect(tester, label).top,
          closeTo(top, 1),
          reason: '$label must sit on the single tab row',
        );
      }

      expect(
        find.ancestor(of: tabText('Towers'), matching: find.byType(Wrap)),
        findsNothing,
        reason: 'the seg row keeps tabs on one line; Wrap may wrap them',
      );
      for (final label in labels) {
        expect(
          find.ancestor(
            of: tabText(label),
            matching: find.byWidgetPredicate(
              (widget) => widget is Expanded || widget is Flexible,
            ),
          ),
          findsWidgets,
          reason: 'each seg cell takes an equal flex share (flex: 1)',
        );
      }
    });

    testWidgets('the tab row stays a single line at 360x640', (tester) async {
      await pumpCodex(tester, size: const Size(360, 640));
      const labels = ['Towers', 'Enemies', 'Effects', 'Stages'];
      final top = tabRect(tester, labels.first).top;
      for (final label in labels) {
        expect(
          tabRect(tester, label).top,
          closeTo(top, 1),
          reason: 'the seg row must not fold to a second line at 360 wide',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('tower entries render as sprite tiles in a grid', (
      tester,
    ) async {
      await pumpCodex(tester, size: const Size(390, 844));

      for (final type in TowerType.values) {
        final tile = find.byKey(ValueKey('codex-tile-${type.name}'));
        expect(tile, findsOneWidget, reason: '${type.name} tile missing');
        expect(
          find.descendant(of: tile, matching: find.byType(OrionAtlasSprite)),
          findsWidgets,
          reason: '${type.name} tile must show the atlas sprite',
        );
      }

      Rect labelRect(TowerType type) => tester.getRect(find.text(type.label));
      final firstRow = [
        TowerType.laser,
        TowerType.rocket,
        TowerType.cryo,
        TowerType.railgun,
      ];
      final rowTop = labelRect(firstRow.first).top;
      for (final type in firstRow) {
        expect(labelRect(type).top, closeTo(rowTop, 4));
      }
      expect(
        labelRect(TowerType.nanite).top,
        greaterThan(rowTop),
        reason: 'the fifth tile belongs to the second grid row',
      );

      for (final type in TowerType.values) {
        expect(
          find.text('W${GameBalance.towerUnlockWave(type)}'),
          findsWidgets,
          reason: '${type.name} tile needs its W-wave badge',
        );
      }

      expect(find.text('Range').evaluate().length, lessThanOrEqualTo(4));
      expect(find.text('Damage').evaluate().length, lessThanOrEqualTo(4));
    });

    testWidgets('tapping a tile swaps the detail panel to that tower', (
      tester,
    ) async {
      await pumpCodex(tester, size: const Size(390, 844));
      final detail = find.byKey(const ValueKey('codex-detail'));
      expect(detail, findsOneWidget);

      for (final probe in ['Damage', 'Range']) {
        expect(
          find.descendant(of: detail, matching: find.text(probe)),
          findsWidgets,
        );
      }
      expect(
        find.descendant(
          of: detail,
          matching: find.textContaining('Pulse Laser'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: detail,
          matching: find.textContaining('Siege Rocket'),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('codex-tile-rocket')));
      await tester.pump();
      expect(
        find.descendant(
          of: detail,
          matching: find.textContaining('Pulse Laser'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: detail,
          matching: find.textContaining('Siege Rocket'),
        ),
        findsOneWidget,
      );
      expect(find.text(TowerType.laser.label), findsOneWidget);
    });

    testWidgets('the selected tile reports selected: true in semantics', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await pumpCodex(tester, size: const Size(390, 844));
        bool selected(String name) => find
            .byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.selected == true &&
                  (widget.properties.label ?? '').contains(name),
            )
            .evaluate()
            .isNotEmpty;

        expect(selected('Laser'), isTrue);
        expect(selected('Rocket'), isFalse);

        await tester.tap(find.byKey(const ValueKey('codex-tile-rocket')));
        await tester.pump();
        expect(selected('Rocket'), isTrue);
        expect(selected('Laser'), isFalse);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('the detail stat rows carry scale-derived bar fills', (
      tester,
    ) async {
      await pumpCodex(tester, size: const Size(390, 844));
      final detail = find.byKey(const ValueKey('codex-detail'));

      List<double> barFills() {
        final fills = <double>[];
        final bars = find.descendant(
          of: detail,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is LinearProgressIndicator ||
                widget is FractionallySizedBox,
          ),
        );
        for (final element in bars.evaluate()) {
          final widget = element.widget;
          if (widget is LinearProgressIndicator && widget.value != null) {
            fills.add(widget.value!);
          }
          if (widget is FractionallySizedBox && widget.widthFactor != null) {
            fills.add(widget.widthFactor!);
          }
        }
        return fills;
      }

      final stats = GameBalance.towerStats(TowerType.laser, level: 1);
      final scale = TowerStatScale.forType(TowerType.laser);
      final fills = barFills();
      expect(
        fills.length,
        greaterThanOrEqualTo(3),
        reason: 'Damage, Fire rate and Range each carry a bar',
      );
      expect(
        fills,
        contains(closeTo(scale.damageFill(stats), 0.02)),
        reason: 'damage bar fill must come from TowerStatScale',
      );
      expect(fills, contains(closeTo(scale.rangeFill(stats), 0.02)));
    });

    testWidgets('tiles and detail live inside the retained section list', (
      tester,
    ) async {
      await pumpCodex(tester, size: const Size(390, 844));
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('codex-tile-laser')),
          matching: find.byKey(const PageStorageKey<int>(0)),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('codex-detail')),
          matching: find.byKey(const PageStorageKey<int>(0)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('searching filters tiles, not just cards', (tester) async {
      await pumpCodex(tester, size: const Size(390, 844));
      await tester.enterText(searchField, 'gravity');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('codex-tile-gravityWell')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('codex-tile-laser')), findsNothing);
    });
  });

  group('command-deck fix round 1 (HPA-699)', () {
    final detail = find.byKey(const ValueKey('codex-detail'));

    Finder tileFinder(TowerType type) =>
        find.byKey(ValueKey('codex-tile-${type.name}'));

    Finder enemyTileFinder(EnemyArchetype archetype) =>
        find.byKey(ValueKey('codex-enemy-tile-${archetype.name}'));

    bool breaksInsideWord(
      WidgetTester tester,
      Finder textFinder,
      TextScaler scaler,
    ) {
      final widget = tester.widget<Text>(textFinder);
      final painter = TextPainter(
        text: TextSpan(text: widget.data ?? '', style: widget.style),
        textAlign: widget.textAlign ?? TextAlign.start,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: widget.maxLines,
        ellipsis: widget.overflow == TextOverflow.ellipsis ? '…' : null,
        locale: widget.locale,
        strutStyle: widget.strutStyle,
        textHeightBehavior: widget.textHeightBehavior,
        textWidthBasis: widget.textWidthBasis ?? TextWidthBasis.parent,
      )..layout(maxWidth: tester.getSize(textFinder).width);
      final text = painter.text!.toPlainText();
      var offset = 0;
      while (offset < text.length) {
        final line = painter.getLineBoundary(TextPosition(offset: offset));
        if (line.isCollapsed || line.end >= text.length) {
          return false;
        }
        final endsCleanly = text[line.end - 1] == ' ' || text[line.end] == ' ';
        if (!endsCleanly) {
          return true;
        }
        offset = line.end;
      }
      return false;
    }

    List<(String, String)> expectedSpecialtyLines(TowerStats s) {
      final out = <(String, String)>[];
      if (s.splashRadius > 0) {
        out.add(('Splash radius', number(s.splashRadius)));
      }
      if (s.slowMultiplier < 1) {
        out.add((
          'Slow',
          '${percent(1 - s.slowMultiplier)} for ${number(s.slowDuration)}s',
        ));
      }
      if (s.pierceCount > 0) out.add(('Pierce', '${s.pierceCount}'));
      if (s.chainCount > 0) {
        out.add(('Chain', '${s.chainCount} (range ${number(s.chainRange)})'));
      }
      if (s.corrosionDamagePerSecond > 0) {
        out.add((
          'Corrosion',
          '${number(s.corrosionDamagePerSecond)}/s for ${number(s.corrosionDuration)}s',
        ));
      }
      if (s.armorShred > 0) out.add(('Armor shred', percent(s.armorShred)));
      if (s.fieldRadius > 0) {
        out.add((
          'Field',
          'r ${number(s.fieldRadius)}, ${number(s.fieldDuration)}s, tick ${cadence(s.fieldTickInterval)}s',
        ));
      }
      if (s.droneCount > 0) {
        out.add((
          'Drones',
          '${s.droneCount} (cap ${s.maxActiveDrones}), ${number(s.droneDamage)} dmg / ${cadence(s.droneAttackInterval)}s, ${number(s.droneLifetime)}s life',
        ));
      }
      if (s.shieldDamageMultiplier != 1) {
        out.add(('vs Shield', 'x${decimal(s.shieldDamageMultiplier)}'));
      }
      if (s.armorDamageMultiplier != 1) {
        out.add(('vs Armored', 'x${decimal(s.armorDamageMultiplier)}'));
      }
      if (s.slowedDamageMultiplier != 1) {
        out.add(('vs Slowed', 'x${number(s.slowedDamageMultiplier)}'));
      }
      return out;
    }

    Set<String> paintSignature(WidgetTester tester, Finder scope) {
      final signature = <String>{};
      final decorated = find.descendant(
        of: scope,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox ||
              widget is Container ||
              widget is Material ||
              widget is PhysicalModel ||
              widget is PhysicalShape ||
              widget is Ink ||
              widget is CustomPaint ||
              widget is Opacity ||
              widget is AnimatedOpacity,
        ),
      );
      for (final element in decorated.evaluate()) {
        final widget = element.widget;
        if (widget is DecoratedBox) {
          signature.add('DecoratedBox:${widget.decoration}');
        } else if (widget is Container) {
          signature.add('Container:${widget.decoration}:${widget.color}');
        } else if (widget is Material) {
          signature.add(
            'Material:${widget.type}:${widget.color}:${widget.elevation}:'
            '${widget.borderRadius}:${widget.shape}',
          );
        } else if (widget is PhysicalModel) {
          signature.add(
            'PhysicalModel:${widget.color}:${widget.elevation}:${widget.shape}',
          );
        } else if (widget is PhysicalShape) {
          signature.add('PhysicalShape:${widget.color}:${widget.elevation}');
        } else if (widget is Ink) {
          signature.add('Ink:${widget.decoration}');
        } else if (widget is CustomPaint) {
          signature.add(
            'CustomPaint:${widget.painter?.runtimeType}:'
            '${widget.foregroundPainter?.runtimeType}',
          );
        } else if (widget is Opacity) {
          signature.add('Opacity:${widget.opacity}');
        } else if (widget is AnimatedOpacity) {
          signature.add('AnimatedOpacity');
        }
      }
      return signature;
    }

    for (final size in const [Size(390, 844), Size(360, 640)]) {
      for (final scaler in const [TextScaler.linear(1), TextScaler.linear(3)]) {
        testWidgets('every tile paints its full label at ${size.width.toInt()}x'
            '${size.height.toInt()} text x${scaler.scale(1).round()}', (
          tester,
        ) async {
          await loadRealFonts();
          await pumpCodex(tester, size: size, textScaler: scaler);
          for (final entry in CodexData.towers) {
            final tile = tileFinder(entry.type);
            await tester.scrollUntilVisible(
              tile,
              400,
              scrollable: find.byType(Scrollable).first,
            );
            final label = find.descendant(
              of: tile,
              matching: find.text(entry.label),
            );
            expect(
              label,
              findsOneWidget,
              reason: '${entry.type.name} tile must show its label',
            );
            final paragraph = tester.renderObject<RenderParagraph>(label);
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason:
                  '${entry.label} truncates inside its fixed-column tile '
                  'at $size text x${scaler.scale(1).round()} — the full '
                  'tower name must paint',
            );
            expect(
              breaksInsideWord(tester, label, scaler),
              isFalse,
              reason:
                  '${entry.label} breaks mid-word inside its tile at $size '
                  'text x${scaler.scale(1).round()} — the name may wrap at '
                  'spaces or grow the tile, never split a word',
            );
          }
        });

        testWidgets('the wave badge never overlaps tile art or label at '
            '${size.width.toInt()}x${size.height.toInt()} text '
            'x${scaler.scale(1).round()}', (tester) async {
          await loadRealFonts();
          await pumpCodex(tester, size: size, textScaler: scaler);
          for (final entry in CodexData.towers) {
            final tile = tileFinder(entry.type);
            await tester.scrollUntilVisible(
              tile,
              400,
              scrollable: find.byType(Scrollable).first,
            );
            final tileRect = tester.getRect(tile);
            final badge = find.descendant(
              of: tile,
              matching: find.text('W${entry.unlockWave}'),
            );
            expect(
              badge,
              findsOneWidget,
              reason: '${entry.type.name} tile must show its W-wave badge',
            );
            final badgeRect = tester.getRect(badge);
            expect(
              tileRect.contains(badgeRect.topLeft) &&
                  tileRect.contains(badgeRect.bottomRight),
              isTrue,
              reason:
                  'the W badge must stay inside the ${entry.type.name} '
                  'tile bounds',
            );
            final sprites = find.descendant(
              of: tile,
              matching: find.byType(OrionAtlasSprite),
            );
            expect(sprites, findsWidgets);
            for (final element in sprites.evaluate()) {
              final spriteRect = tester.getRect(find.byWidget(element.widget));
              expect(
                badgeRect.overlaps(spriteRect),
                isFalse,
                reason:
                    'the W badge overlays sprite space on ${entry.type.name} '
                    'at $size text x${scaler.scale(1).round()}',
              );
            }
            final label = find.descendant(
              of: tile,
              matching: find.text(entry.label),
            );
            expect(label, findsOneWidget);
            expect(
              badgeRect.overlaps(tester.getRect(label)),
              isFalse,
              reason: 'the W badge overlaps the ${entry.label} tile label',
            );
          }
        });
      }

      testWidgets('the detail header keeps its title and cost whole at '
          '${size.width.toInt()}x${size.height.toInt()} 3x text', (
        tester,
      ) async {
        await loadRealFonts();
        await pumpCodex(
          tester,
          size: size,
          textScaler: const TextScaler.linear(3),
        );
        for (final entry in CodexData.towers) {
          await tester.enterText(searchField, entry.label);
          await tester.pump();
          expect(
            tileFinder(entry.type),
            findsOneWidget,
            reason: 'search must isolate the ${entry.type.name} tile',
          );
          expect(detail, findsOneWidget);
          final title = find.descendant(
            of: detail,
            matching: find.text(entry.label.toUpperCase()),
          );
          expect(
            title,
            findsOneWidget,
            reason: 'the detail must headline ${entry.label}',
          );
          expect(
            tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
            isFalse,
            reason: 'the ${entry.label} detail title truncates at $size 3x',
          );
          expect(
            breaksInsideWord(tester, title, const TextScaler.linear(3)),
            isFalse,
            reason:
                'the ${entry.label} detail header splits the name '
                'mid-word at $size 3x — wrap at spaces only',
          );
          final cost = find.descendant(
            of: detail,
            matching: find.text('${entry.baseStats.cost}g'),
          );
          expect(
            cost,
            findsOneWidget,
            reason: 'the detail must show the real ${entry.label} cost',
          );
          expect(
            tester.renderObject<RenderParagraph>(cost).didExceedMaxLines,
            isFalse,
            reason: 'the ${entry.label} detail cost truncates at $size 3x',
          );
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('every tab keeps a 48dp target at '
          '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await pumpCodex(tester, size: size);
          for (final label in const [
            'Towers',
            'Enemies',
            'Effects',
            'Stages',
          ]) {
            final rect = tester.getRect(find.bySemanticsLabel(label));
            expect(
              rect.width,
              greaterThanOrEqualTo(48),
              reason:
                  '$label is ${rect.width.toStringAsFixed(1)}dp wide — '
                  'below the 48dp touch floor at $size',
            );
            expect(
              rect.height,
              greaterThanOrEqualTo(48),
              reason:
                  '$label is ${rect.height.toStringAsFixed(1)}dp tall — '
                  'below the 48dp touch floor at $size',
            );
          }
        } finally {
          handle.dispose();
        }
      });
    }

    testWidgets('the tabs announce selection, grouping and focus support', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpCodex(tester, size: const Size(390, 844));
        final missing = <String>[];
        for (final label in const ['Towers', 'Enemies', 'Effects', 'Stages']) {
          final node = tester.getSemantics(find.bySemanticsLabel(label));
          final data = node.getSemanticsData();
          if (data.flagsCollection.isButton != true) {
            missing.add('$label: button flag');
          }
          if (data.flagsCollection.isInMutuallyExclusiveGroup != true) {
            missing.add('$label: mutually-exclusive-group flag');
          }
          if (data.flagsCollection.isFocused == Tristate.none) {
            missing.add('$label: focus state');
          }
          if (data.actions & SemanticsAction.tap.index == 0) {
            missing.add('$label: tap action');
          }
        }
        if (tester
                .getSemantics(find.bySemanticsLabel('Towers'))
                .getSemanticsData()
                .flagsCollection
                .isSelected !=
            Tristate.isTrue) {
          missing.add('Towers: selected state (active tab)');
        }
        if (tester
                .getSemantics(find.bySemanticsLabel('Enemies'))
                .getSemanticsData()
                .flagsCollection
                .isSelected !=
            Tristate.isFalse) {
          missing.add('Enemies: unselected state (inactive tab)');
        }
        expect(
          missing,
          isEmpty,
          reason:
              'each tab is one cell of a segmented control — it must '
              'announce as a button, publish focus and selection state, '
              'declare the mutually-exclusive group and offer a tap '
              'action: $missing',
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('semantics activation switches each tab section', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpCodex(tester, size: const Size(390, 844));
        final sectionChecks = <String, Pattern>{
          'Towers': 'Pulse Laser',
          'Enemies': 'Standard fodder',
          'Effects': 'Chain Lightning',
          'Stages': 'Outpost Alpha',
        };
        for (final entry in sectionChecks.entries) {
          final node = tester.getSemantics(find.bySemanticsLabel(entry.key));
          node.owner!.performAction(node.id, SemanticsAction.tap);
          await tester.pump();
          expect(
            find.textContaining(entry.value),
            findsWidgets,
            reason:
                'semantics-activating the ${entry.key} tab must show the '
                '${entry.key} section',
          );
        }
      } finally {
        handle.dispose();
      }
    });

    testWidgets('keyboard focus and activation reach the tabs', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpCodex(tester, size: const Size(390, 844));

        Future<void> tabTo(String label) async {
          for (var i = 0; i < 10; i += 1) {
            final focused =
                tester
                    .getSemantics(find.bySemanticsLabel(label))
                    .getSemanticsData()
                    .flagsCollection
                    .isFocused ==
                Tristate.isTrue;
            if (focused) return;
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
          }
          fail('$label never received keyboard focus within 10 Tab presses');
        }

        await tabTo('Enemies');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(
          find.byKey(const PageStorageKey<int>(1)),
          findsOneWidget,
          reason: 'Enter must activate the focused Enemies tab',
        );

        await tabTo('Effects');
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(
          find.byKey(const PageStorageKey<int>(2)),
          findsOneWidget,
          reason: 'Space must activate the focused Effects tab',
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a focused tab paints a visible treatment', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpCodex(tester, size: const Size(390, 844));
        final tabScope = find.ancestor(
          of: find.text('Enemies'),
          matching: find.byType(InkWell),
        );
        expect(tabScope, findsOneWidget);
        final before = paintSignature(tester, tabScope);
        for (var i = 0; i < 10; i += 1) {
          final focused =
              tester
                  .getSemantics(find.bySemanticsLabel('Enemies'))
                  .getSemanticsData()
                  .flagsCollection
                  .isFocused ==
              Tristate.isTrue;
          if (focused) break;
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Enemies'))
              .getSemanticsData()
              .flagsCollection
              .isFocused,
          Tristate.isTrue,
          reason: 'the Enemies tab must hold keyboard focus for this check',
        );
        await tester.pump();
        expect(
          paintSignature(tester, tabScope),
          isNot(equals(before)),
          reason:
              'keyboard focus changes nothing the eye can see — the tab '
              'needs a focus-driven border, overlay or tint INSIDE its own '
              'paint, since InkWell ink hides behind the opaque rail fill',
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a focused tile paints a visible treatment', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpCodex(tester, size: const Size(390, 844));
        final tile = tileFinder(TowerType.rocket);
        final before = paintSignature(tester, tile);
        var focused = false;
        for (var i = 0; i < 14; i += 1) {
          focused =
              tester
                  .getSemantics(
                    find.byWidgetPredicate(
                      (widget) =>
                          widget is Semantics &&
                          widget.properties.label == 'Rocket',
                    ),
                  )
                  .getSemanticsData()
                  .flagsCollection
                  .isFocused ==
              Tristate.isTrue;
          if (focused) break;
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(
          focused,
          isTrue,
          reason:
              'the Rocket tile never received keyboard focus within 14 '
              'Tab presses — tiles must be focusable targets',
        );
        await tester.pump();
        expect(
          paintSignature(tester, tile),
          isNot(equals(before)),
          reason:
              'keyboard focus changes nothing the eye can see on the '
              'Rocket tile — it needs a focus-driven border, overlay or '
              'tint INSIDE its own paint, since InkWell ink hides behind '
              'the opaque tile surface',
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('the detail reports upgrade cost and every base specialty '
        'metric', (tester) async {
      await pumpCodex(tester);
      final missing = <String>[];
      for (final entry in CodexData.towers) {
        await tester.enterText(searchField, entry.label);
        await tester.pump();
        expect(
          tileFinder(entry.type),
          findsOneWidget,
          reason: 'search must isolate the ${entry.type.name} tile',
        );
        expect(detail, findsOneWidget);
        if (find
            .descendant(of: detail, matching: find.text('Upgrade cost'))
            .evaluate()
            .isEmpty) {
          missing.add('${entry.label}: "Upgrade cost" label');
        }
        if (find
            .descendant(of: detail, matching: find.text('${entry.upgradeCost}'))
            .evaluate()
            .isEmpty) {
          missing.add(
            '${entry.label}: "${entry.upgradeCost}" upgrade cost value',
          );
        }
        for (final (key, value) in expectedSpecialtyLines(entry.baseStats)) {
          if (find
              .descendant(of: detail, matching: find.text(key))
              .evaluate()
              .isEmpty) {
            missing.add('${entry.label}: "$key" metric label');
          }
          if (find
              .descendant(of: detail, matching: find.text(value))
              .evaluate()
              .isEmpty) {
            missing.add('${entry.label}: "$value" ($key) metric value');
          }
        }
      }
      expect(
        missing,
        isEmpty,
        reason:
            'the tower detail dropped metrics the base codex card showed — '
            'upgradeCost and the live _specialtyLines values from '
            'GameBalance: $missing',
      );
    });

    testWidgets('enemy entries render as sprite tiles backed by existing art', (
      tester,
    ) async {
      await pumpCodex(tester);
      await tester.tap(find.text('Enemies'));
      await tester.pumpAndSettle();
      for (final entry in CodexData.enemies) {
        final tile = enemyTileFinder(entry.archetype);
        expect(
          tile,
          findsOneWidget,
          reason: 'the ${entry.archetype.name} enemy tile is missing',
        );
        expect(
          find.descendant(of: tile, matching: find.text(entry.label)),
          findsOneWidget,
          reason: 'the ${entry.label} tile must show its label',
        );
        final expectedArt = entry.traits.contains(EnemyTrait.heavy)
            ? 'Heavy drone threat'
            : 'Drone threat';
        expect(
          find.descendant(
            of: tile,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is OrionAtlasSprite &&
                  widget.art.semanticLabel == expectedArt,
            ),
          ),
          findsWidgets,
          reason:
              'the ${entry.label} tile must present the existing '
              '"$expectedArt" sprite — no enemy art was added, so reuse the '
              'drone atlas sprites already in OrionArt',
        );
        for (final trait in entry.traits) {
          final traitArt = OrionArt.trait(trait);
          if (traitArt == null) continue;
          expect(
            find.descendant(
              of: tile,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is OrionAtlasSprite &&
                    widget.art.semanticLabel == traitArt.semanticLabel,
              ),
            ),
            findsWidgets,
            reason:
                'the ${entry.label} tile must show the existing '
                '"${traitArt.semanticLabel}" indicator art',
          );
        }
      }
    });

    testWidgets('tapping an enemy tile shows its detail with real stats', (
      tester,
    ) async {
      await pumpCodex(tester);
      await tester.tap(find.text('Enemies'));
      await tester.pumpAndSettle();
      final enemyDetail = find.byKey(const ValueKey('codex-enemy-detail'));
      for (final archetype in [
        EnemyArchetype.swarmDrone,
        EnemyArchetype.armoredHeavyDrone,
      ]) {
        final entry = CodexData.enemies.firstWhere(
          (e) => e.archetype == archetype,
        );
        await tester.tap(enemyTileFinder(archetype));
        await tester.pump();
        expect(
          enemyDetail,
          findsOneWidget,
          reason: 'selecting ${entry.label} must open an enemy detail',
        );
        expect(
          find.descendant(
            of: enemyDetail,
            matching: find.text(entry.roleDescription),
          ),
          findsOneWidget,
        );
        for (final (key, value) in <(String, String)>[
          ('Health', number(entry.stats.health)),
          ('Speed', number(entry.stats.speed)),
          ('Base damage', '${entry.stats.baseDamage}'),
          ('Reward', '${entry.stats.goldReward}g'),
          if (entry.stats.shieldHealth > 0)
            ('Shield', number(entry.stats.shieldHealth)),
          if (entry.stats.armorReduction > 0)
            ('Armor', percent(entry.stats.armorReduction)),
          if (entry.stats.regenPerSecond > 0)
            ('Regen', '${number(entry.stats.regenPerSecond)}/s'),
        ]) {
          expect(
            find.descendant(of: enemyDetail, matching: find.text(key)),
            findsWidgets,
            reason: 'the ${entry.label} detail lost its "$key" row',
          );
          expect(
            find.descendant(of: enemyDetail, matching: find.text(value)),
            findsWidgets,
            reason:
                'the ${entry.label} detail must report the live "$key" '
                'value "$value" from GameBalance',
          );
        }
        for (final trait in entry.traits) {
          expect(
            find.descendant(of: enemyDetail, matching: find.text(trait.label)),
            findsWidgets,
            reason:
                'the ${entry.label} detail must keep its '
                '"${trait.label}" trait badge',
          );
        }
      }
    });

    testWidgets('searching filters enemy tiles and keeps the trait glossary', (
      tester,
    ) async {
      await pumpCodex(tester);
      await tester.tap(find.text('Enemies'));
      await tester.pumpAndSettle();

      await tester.enterText(searchField, 'bruiser');
      await tester.pump();
      expect(
        enemyTileFinder(EnemyArchetype.heavyDrone),
        findsOneWidget,
        reason: 'a role-sentence match must surface the enemy tile',
      );
      expect(
        enemyTileFinder(EnemyArchetype.basicDrone),
        findsNothing,
        reason: 'non-matching enemy tiles must filter out',
      );
      expect(
        find.text(EnemyTrait.swarm.label),
        findsNothing,
        reason: 'the trait glossary filters with the same query',
      );

      await tester.enterText(searchField, 'large numbers');
      await tester.pump();
      expect(
        find.text(EnemyTrait.swarm.label),
        findsOneWidget,
        reason: 'a trait-effect match must keep the trait glossary row',
      );
      expect(
        find.text(EnemyTrait.heavy.label),
        findsNothing,
        reason: 'non-matching trait glossary rows filter out',
      );
      expect(
        enemyTileFinder(EnemyArchetype.swarmDrone),
        findsNothing,
        reason:
            'a trait-only match must not resurrect enemy tiles — the '
            'glossary and the tiles filter independently',
      );
    });

    testWidgets(
      'enemy tiles and detail live inside the retained section list',
      (tester) async {
        await pumpCodex(tester);
        await tester.tap(find.text('Enemies'));
        await tester.pumpAndSettle();
        await tester.tap(enemyTileFinder(EnemyArchetype.basicDrone));
        await tester.pump();
        final enemyDetail = find.byKey(const ValueKey('codex-enemy-detail'));
        expect(
          find.ancestor(
            of: enemyTileFinder(EnemyArchetype.basicDrone),
            matching: find.byKey(const PageStorageKey<int>(1)),
          ),
          findsOneWidget,
        );
        expect(
          find.ancestor(
            of: enemyDetail,
            matching: find.byKey(const PageStorageKey<int>(1)),
          ),
          findsOneWidget,
        );
      },
    );
  });

  testWidgets('capture codex command-deck fixtures', (tester) async {
    await loadRealFonts();
    OrionArtDescriptor.resetSpriteCache();
    await tester.runAsync(() async {
      await Flame.images.load('orion_sprite_sheet.png');
      await Flame.images.load('orion_tower_variety_sheet.png');
    });

    final boundaryKey = GlobalKey();

    Future<void> pumpScene(Size size, {TextScaler? textScaler}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: orionThemeData,
            builder: textScaler == null
                ? null
                : (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: textScaler),
                    child: child!,
                  ),
            home: OrionMenuShell(
              destination: OrionMenuDestination.codex,
              medalEarned: 0,
              medalTotal: 21,
              researchPoints: 0,
              onDestinationSelected: (_) {},
              onOpenSettings: () {},
              child: CodexView(
                progress: CampaignProgress(),
                embeddedInMenuShell: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => warmSceneImages(tester.element(find.byType(CodexView)), [
          'reactor_rim_ui/backdrops/map-room.png',
        ]),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapTile(Key key) async {
      await tester.ensureVisible(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
    }

    await pumpScene(const Size(390, 844));
    await tapTile(const ValueKey('codex-tile-laser'));
    expect(find.byKey(const ValueKey('codex-detail')), findsOneWidget);
    for (final type in TowerType.values) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('codex-tile-${type.name}')),
          matching: find.byType(SpriteWidget),
        ),
        findsOneWidget,
        reason: '${type.label} artwork must load before the capture.',
      );
    }
    await tester.runAsync(
      () => captureReactorRimFixture(boundaryKey, 'fixture-codex-towers.png'),
    );

    await pumpScene(const Size(360, 640));
    await tapTile(const ValueKey('codex-tile-laser'));
    await tester.runAsync(
      () => captureReactorRimFixture(
        boundaryKey,
        'fixture-codex-towers-compact.png',
      ),
    );

    await pumpScene(
      const Size(360, 640),
      textScaler: const TextScaler.linear(3),
    );
    await tapTile(const ValueKey('codex-tile-laser'));
    await tester.runAsync(
      () => captureReactorRimFixture(
        boundaryKey,
        'fixture-codex-towers-large-text.png',
      ),
    );

    await pumpScene(const Size(390, 844));
    await tester.tap(find.text('Enemies'));
    await tester.pumpAndSettle();
    await tapTile(const ValueKey('codex-enemy-tile-armoredDrone'));
    expect(find.byKey(const ValueKey('codex-enemy-detail')), findsOneWidget);
    await tester.runAsync(
      () => captureReactorRimFixture(boundaryKey, 'fixture-codex-enemies.png'),
    );

    await pumpScene(const Size(360, 640));
    await tester.tap(find.text('Enemies'));
    await tester.pumpAndSettle();
    await tapTile(const ValueKey('codex-enemy-tile-armoredDrone'));
    await tester.runAsync(
      () => captureReactorRimFixture(
        boundaryKey,
        'fixture-codex-enemies-compact.png',
      ),
    );
  });
}
