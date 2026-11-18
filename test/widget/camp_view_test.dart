import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/camp_view.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/tower_stat_scale.dart';
import 'package:orion/game/util/format.dart';

import '../support/orion_finders.dart';

const _productViewport = Size(390, 844);

/// Pumps the standalone Camp (with its own header) inside a plain MaterialApp.
Future<void> _pumpCamp(
  WidgetTester tester, {
  Map<Character, int> ownedLevels = CampaignSave.starterOwnedLevels,
  List<Character> squad = CampaignSave.starterSquad,
  Size viewport = _productViewport,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: CampView(ownedLevels: ownedLevels, squad: squad),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _card(Character character) =>
    find.byKey(ValueKey('camp-card-${character.name}'));

Future<void> _showCard(WidgetTester tester, Character character) async {
  await tester.scrollUntilVisible(
    _card(character),
    250,
    scrollable: find.descendant(
      of: find.byType(GridView),
      matching: find.byType(Scrollable),
    ),
  );
  // scrollUntilVisible may leave the card's center below the fold; bring it
  // fully into the viewport so a later tap() actually lands on the card, and
  // settle so its render box reflects the final scroll offset.
  await tester.ensureVisible(_card(character));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('roster renders all twelve characters in enum order', (
    tester,
  ) async {
    await _pumpCamp(tester);

    // First grid row holds the three highest ranks left to right.
    final firstRow = [
      tester.getRect(_card(Character.hikari)).left,
      tester.getRect(_card(Character.jin)).left,
      tester.getRect(_card(Character.akane)).left,
    ];
    expect(firstRow[0], lessThan(firstRow[1]));
    expect(firstRow[1], lessThan(firstRow[2]));

    for (final character in Character.values) {
      await _showCard(tester, character);
      expect(
        _card(character),
        findsOneWidget,
        reason: 'roster is missing ${character.name}',
      );
    }
  });

  testWidgets(
    'owned cards show level and squad tag, locked cards read not recruited',
    (tester) async {
      await _pumpCamp(
        tester,
        ownedLevels: const {Character.haruto: 7},
        squad: const [Character.haruto],
      );

      await _showCard(tester, Character.haruto);
      expect(
        find.descendant(
          of: _card(Character.haruto),
          matching: find.text('SQUAD'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _card(Character.haruto),
          matching: find.text('Lv 7'),
        ),
        findsOneWidget,
      );

      await _showCard(tester, Character.mio);
      final mioCard = _card(Character.mio);
      expect(
        find.descendant(of: mioCard, matching: find.text('???')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: mioCard, matching: find.text('NOT RECRUITED')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: mioCard, matching: find.text('SQUAD')),
        findsNothing,
      );

      final semantics = tester.ensureSemantics();
      try {
        expect(
          find.bySemanticsLabel(
            RegExp('^Haruto, rank E, level 7, squad member'),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp('^Mio, rank E, locked')),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('recruited count and squad tag read from the profile', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCamp(
        tester,
        ownedLevels: const {Character.haruto: 1, Character.mio: 1},
        squad: const [Character.haruto],
      );
      expect(
        find.bySemanticsLabel('2 of 12 characters recruited'),
        findsOneWidget,
      );
      expect(find.text('SQUAD 1/6'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('tapping an owned card opens the read-only character sheet', (
    tester,
  ) async {
    await _pumpCamp(tester);

    await _showCard(tester, Character.haruto);
    await tester.tap(_card(Character.haruto));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('character-sheet')), findsOneWidget);
    // Identity: rank badge, full name, role, persistent level.
    expect(find.text('E'), findsWidgets);
    expect(findOrionTitle('Haruto Sakaki'), findsOneWidget);
    expect(find.text('Pulse laser gunner'), findsOneWidget);
    expect(find.text('LV 1 / 40'), findsOneWidget);

    // Signature panel: working name, battle-tier tag, role sentence.
    expect(find.text('SIGNATURE SKILL'), findsOneWidget);
    expect(find.text('BATTLE TIER 3'), findsOneWidget);
    expect(find.text('Steady Volley'), findsOneWidget);
    expect(find.text(Character.haruto.signature.role), findsOneWidget);

    // Bio and the combat stat bars.
    expect(find.text(Character.haruto.bio), findsOneWidget);
    expect(find.text('DAMAGE'), findsOneWidget);
    expect(find.text('FIRE'), findsOneWidget);
    expect(find.text('RANGE'), findsOneWidget);

    // Read-only: no level-up or currency affordance anywhere.
    expect(find.textContaining('LEVEL UP'), findsNothing);
    expect(find.textContaining('Level up'), findsNothing);
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('character-sheet')), findsNothing);
    expect(_card(Character.haruto), findsOneWidget);
  });

  testWidgets('locked cards do not open a sheet', (tester) async {
    await _pumpCamp(tester);
    await _showCard(tester, Character.hikari);
    await tester.tap(_card(Character.hikari));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('character-sheet')), findsNothing);
  });

  testWidgets('sheet stat bars use the shared scale and persistent level', (
    tester,
  ) async {
    await _pumpCamp(
      tester,
      ownedLevels: const {Character.elena: 10},
      squad: const [Character.elena],
    );
    await _showCard(tester, Character.elena);
    await tester.tap(_card(Character.elena));
    await tester.pumpAndSettle();

    expect(find.text('LV 10 / 40'), findsOneWidget);

    // The sheet's damage figure must equal the real deploy pipeline: style
    // tier-1 stats scaled by the persistent rank+level factor.
    final stats = GameBalance.towerStats(Character.elena.style, level: 1)
        .scaleDamageChannels(
          GameBalance.characterScalingFactor(Character.elena.rank, 10),
        );
    expect(find.text(number(stats.damage)), findsOneWidget);

    // Fills come from TowerStatScale — assert the contract still holds for
    // every roster member rather than a bespoke meter.
    for (final character in Character.values) {
      final scale = TowerStatScale.forType(character.style);
      final resolved = GameBalance.towerStats(character.style, level: 1)
          .scaleDamageChannels(
            GameBalance.characterScalingFactor(character.rank, 1),
          );
      expect(scale.damageFill(resolved), inInclusiveRange(0, 1));
      expect(scale.fireFill(resolved), inInclusiveRange(0, 1));
      expect(scale.rangeFill(resolved), inInclusiveRange(0, 1));
    }
  });

  testWidgets('missing portrait art falls back to the roster icon', (
    tester,
  ) async {
    // The descriptor contract: every character portrait and chibi declares a
    // fallback icon plus its semantics label, so a cold Flame cache never
    // strands the card without a placeholder.
    for (final character in Character.values) {
      final portrait = OrionArt.characterPortrait(character);
      expect(
        portrait.fileName,
        'characters/${character.name}/portrait.png',
        reason: character.name,
      );
      expect(portrait.fallbackIcon, Icons.person, reason: character.name);
      expect(
        portrait.semanticLabel,
        '${character.displayName} portrait',
        reason: character.name,
      );
      final chibi = OrionArt.characterChibi(character);
      expect(
        chibi.fileName,
        'characters/${character.name}/chibi.png',
        reason: character.name,
      );
      expect(chibi.fallbackIcon, Icons.person_outline, reason: character.name);
    }

    // Cold-cache render: no image resolves, yet every card still mounts its
    // semantics label and no exception leaks.
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCamp(tester);
      await _showCard(tester, Character.haruto);
      expect(
        find.bySemanticsLabel(RegExp('^Haruto, rank E, level 1')),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('camp stays usable at 320x568 with 2x text', (tester) async {
    await _pumpCamp(
      tester,
      viewport: const Size(320, 568),
      textScaler: const TextScaler.linear(2),
    );
    await _showCard(tester, Character.mio);
    expect(tester.takeException(), isNull);

    await tester.tap(_card(Character.mio));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('character-sheet')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
