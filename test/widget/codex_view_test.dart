import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_reward_label.dart';
import 'package:orion/game/codex/codex_data.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/codex_view.dart';
import 'package:orion/game/ui/world_map_view.dart';

void main() {
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

  testWidgets('world map shows a Codex button that fires onOpenCodex', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: OrionCampaign.stages,
            progress: CampaignProgress(),
            feedback: null,
            onStageSelected: (_) {},
            onResetCampaign: () {},
            onOpenTechTree: () {},
            onOpenCodex: () => pressed = true,
          ),
        ),
      ),
    );
    expect(find.byTooltip('Codex'), findsOneWidget);
    await tester.tap(find.byTooltip('Codex'));
    expect(pressed, isTrue);
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

  // Short surface (spec §10.3) with a faked software keyboard: the search
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
}
