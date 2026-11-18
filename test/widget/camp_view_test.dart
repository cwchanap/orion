import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/camp_view.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/tower_stat_scale.dart';

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

/// Fails `Flame.images.load` for the named files and defers to the real
/// cache for everything else — the only seam [OrionArtDescriptor] loads
/// through, so a listed portrait error surfaces exactly like a missing
/// asset: the shared `sprite` future completes with an error and the
/// `OrionAtlasSprite` fallback branch renders.
final class _FailingImages extends Images {
  final failures = <String>{};

  @override
  Future<ui.Image> load(String fileName, {String? key, String? package}) {
    if (failures.contains(fileName)) {
      return Future.error(StateError('missing $fileName'));
    }
    return super.load(fileName, key: key, package: package);
  }
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

  testWidgets(
    'sheet stat bars render the shared-scale fractions from rank and level',
    (tester) async {
      // Two same-style members at different rank+level: one shared scale
      // object (railgun) while the fills differ through the real deploy
      // pipeline — style tier-1 stats scaled by the persistent factor.
      const owned = {Character.elena: 10, Character.sayo: 2};
      expect(
        Character.elena.style,
        Character.sayo.style,
        reason: 'the pair must exercise one shared TowerStatScale',
      );
      double expectedFill(Character character, String label) {
        final stats = GameBalance.towerStats(character.style, level: 1)
            .scaleDamageChannels(
              GameBalance.characterScalingFactor(
                character.rank,
                owned[character]!,
              ),
            );
        final scale = TowerStatScale.forType(character.style);
        return switch (label) {
          'DAMAGE' => scale.damageFill(stats),
          'FIRE' => scale.fireFill(stats),
          'RANGE' => scale.rangeFill(stats),
          _ => scale.secondaryFill(stats)!,
        };
      }

      for (final character in owned.keys) {
        await _pumpCamp(tester, ownedLevels: owned, squad: [character]);
        await _showCard(tester, character);
        await tester.tap(_card(character));
        await tester.pumpAndSettle();

        for (final label in const ['DAMAGE', 'FIRE', 'RANGE', 'PIERCE']) {
          final bar = tester.widget<FractionallySizedBox>(
            find.byKey(ValueKey('sheet-stat-fill-$label')),
          );
          expect(
            bar.widthFactor,
            closeTo(expectedFill(character, label), 1e-9),
            reason: '${character.name} $label',
          );
        }

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('portrait descriptors declare the roster fallback contract', (
    tester,
  ) async {
    // Every character portrait and chibi declares a fallback icon plus its
    // semantics label, so an unresolvable load never strands a card without
    // a placeholder.
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
  });

  testWidgets(
    'a failed portrait load renders the roster icon on card and sheet',
    (tester) async {
      // Force the real descriptor load path to error: Flame.images is the
      // single seam OrionArtDescriptor._loadSprite reads through. The shared
      // sprite memo must reset alongside so the new loader (not a prior
      // generation's pending future) serves these builds.
      final images = _FailingImages()
        ..failures.add(OrionArt.characterPortrait(Character.haruto).fileName);
      final previous = Flame.images;
      Flame.images = images;
      OrionArtDescriptor.resetSpriteCache();
      addTearDown(() {
        Flame.images = previous;
        OrionArtDescriptor.resetSpriteCache();
      });

      await _pumpCamp(tester);
      await _showCard(tester, Character.haruto);

      // The failed card portrait paints the descriptor's fallback icon.
      final harutoCard = _card(Character.haruto);
      expect(
        find.descendant(of: harutoCard, matching: find.byIcon(Icons.person)),
        findsOneWidget,
      );
      final semantics = tester.ensureSemantics();
      try {
        expect(
          find.bySemanticsLabel(RegExp('^Haruto, rank E, level 1')),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }

      // The sheet stays fully usable over the same failed art: fallback icon
      // in the hero, identity, signature and stats all render, Back works.
      await tester.tap(harutoCard);
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('character-sheet'));
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.byIcon(Icons.person)),
        findsOneWidget,
      );
      expect(findOrionTitle('Haruto Sakaki'), findsOneWidget);
      expect(find.text('Steady Volley'), findsOneWidget);
      expect(find.text('DAMAGE'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
