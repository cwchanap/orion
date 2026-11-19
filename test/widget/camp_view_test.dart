import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/util/format.dart';
import 'package:orion/game/ui/camp_view.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_primary_button.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';
import 'package:orion/game/ui/tower_stat_scale.dart';

import '../support/orion_finders.dart';
import '../support/real_fonts.dart';

const _productViewport = Size(390, 844);

/// Test [AssetBundle] that can fail or stub specific asset paths while
/// delegating everything else to [rootBundle].
final class _TestAssetBundle extends CachingAssetBundle {
  _TestAssetBundle({this.failures = const {}, this.stubs = const {}});

  final Set<String> failures;
  final Map<String, ByteData> stubs;

  @override
  Future<ByteData> load(String key) {
    if (failures.contains(key)) {
      return Future.error(StateError('missing $key'));
    }
    final stub = stubs[key];
    if (stub != null) {
      return Future.value(stub);
    }
    return rootBundle.load(key);
  }
}

/// A fully opaque portrait stand-in with four vertical bands: bright,
/// saturated amber, mid gray and near-black. The shipped portraits are
/// JPG-derived RGB with no alpha channel, which is exactly what defeated the
/// old srcIn silhouette — synthetic bands make the rendered luminance
/// spread, desaturation and midtone crush measurable.
Future<ByteData> _bandedPortraitPng(WidgetTester tester) async {
  const side = 8;
  const bands = [
    [0xF0, 0xF0, 0xF0], // bright neutral
    [0xFF, 0xD0, 0x40], // saturated amber (high luma, high chroma)
    [0x80, 0x80, 0x80], // midtone
    [0x10, 0x10, 0x10], // dark
  ];
  final pixels = Uint8List(side * side * 4);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final offset = (y * side + x) * 4;
      final band = bands[x * bands.length ~/ side];
      pixels[offset] = band[0];
      pixels[offset + 1] = band[1];
      pixels[offset + 2] = band[2];
      pixels[offset + 3] = 0xFF;
    }
  }
  return (await tester.runAsync(() async {
    final decoded = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      side,
      side,
      ui.PixelFormat.rgba8888,
      decoded.complete,
    );
    final image = await decoded.future;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return png;
  }))!;
}

/// Pumps the standalone Camp (with its own header) inside a plain MaterialApp.
Future<void> _pumpCamp(
  WidgetTester tester, {
  Map<Character, int> ownedLevels = CampaignSave.starterOwnedLevels,
  List<Character> squad = CampaignSave.starterSquad,
  int scrip = 0,
  bool isSavingProgress = false,
  ValueChanged<Character>? onLevelUp,
  Size viewport = _productViewport,
  TextScaler textScaler = TextScaler.noScaling,
  AssetBundle? assetBundle,
}) async {
  await loadRealFonts();
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(PaintingBinding.instance.imageCache.clear);
  Widget home = CampView(
    ownedLevels: ownedLevels,
    squad: squad,
    scrip: scrip,
    isSavingProgress: isSavingProgress,
    onLevelUp: onLevelUp,
  );
  if (assetBundle != null) {
    home = DefaultAssetBundle(bundle: assetBundle, child: home);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: orionThemeData,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: home,
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
          find.bySemanticsLabel('Locked character, rank E, not recruited'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel(RegExp('Mio')), findsNothing);
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

  testWidgets('an owned card announces a tappable button to screen readers', (
    tester,
  ) async {
    // excludeSemantics strips the InkWell's own action, so the card's
    // Semantics node must carry the tap itself — otherwise assistive tech
    // announces a dead button that can never open the character sheet.
    await _pumpCamp(tester, ownedLevels: const {Character.haruto: 7});

    final semantics = tester.ensureSemantics();
    try {
      final ownedNode = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Haruto, rank E, level 7')),
      );
      final ownedData = ownedNode.getSemanticsData();
      expect(ownedData.flagsCollection.isButton, isTrue);
      expect(ownedData.actions & SemanticsAction.tap.index, isNot(0));
      ownedNode.owner!.performAction(ownedNode.id, SemanticsAction.tap);

      final lockedData = tester
          .getSemantics(
            find.bySemanticsLabel('Locked character, rank E, not recruited'),
          )
          .getSemanticsData();
      expect(lockedData.flagsCollection.isButton, isFalse);
      expect(lockedData.actions & SemanticsAction.tap.index, 0);
    } finally {
      semantics.dispose();
    }

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('character-sheet')), findsOneWidget);
  });

  testWidgets('tapping an owned card opens the character sheet', (
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

    // The economy strip: committed wallet chip and the Level Up action.
    // With no purchase callback the action renders disabled — a read-only
    // host keeps its layout without implying a working purchase.
    expect(find.bySemanticsLabel('0 Scrip'), findsOneWidget);
    final levelUp = tester.widget<OrionPrimaryButton>(
      find.byKey(const ValueKey('level-up-button')),
    );
    expect(levelUp.onPressed, isNull);

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

  // --- HPA-923 task 4: the sheet's Level Up economy strip ---

  /// The exact preview pipeline the sheet renders: tier-1 style stats
  /// scaled by the persistent rank+level factor at [level].
  TowerStats scaledStats(Character character, int level) =>
      GameBalance.towerStats(character.style, level: 1).scaleDamageChannels(
        GameBalance.characterScalingFactor(character.rank, level),
      );

  OrionPrimaryButton levelUpButton(WidgetTester tester) =>
      tester.widget<OrionPrimaryButton>(
        find.byKey(const ValueKey('level-up-button')),
      );

  testWidgets('sheet shows wallet, cost and next-level stat deltas', (
    tester,
  ) async {
    await _pumpCamp(
      tester,
      ownedLevels: const {Character.haruto: 4, Character.mio: 1},
      squad: const [Character.haruto],
      scrip: 500,
      onLevelUp: (_) {},
    );
    await _showCard(tester, Character.haruto);
    await tester.tap(_card(Character.haruto));
    await tester.pumpAndSettle();

    // The committed balance, the 4→5 price and the LV line.
    expect(find.bySemanticsLabel('500 Scrip'), findsOneWidget);
    expect(find.text('LV 4 / 40'), findsOneWidget);
    final cost = GameBalance.levelUpCost(4)!;
    expect(find.text('LEVEL UP · $cost'), findsOneWidget);
    expect(levelUpButton(tester).onPressed, isNotNull);

    // The preview reads the shared scaling path: damage grows, cadence
    // and range never scale so they carry no next-level delta.
    final damageDelta =
        scaledStats(Character.haruto, 5).damage -
        scaledStats(Character.haruto, 4).damage;
    final damageDeltaText = find.byKey(
      const ValueKey('sheet-stat-delta-DAMAGE'),
    );
    expect(damageDeltaText, findsOneWidget);
    expect(
      tester.widget<Text>(damageDeltaText).data,
      '+${decimal(damageDelta)}',
    );
    expect(find.byKey(const ValueKey('sheet-stat-delta-FIRE')), findsNothing);
    expect(find.byKey(const ValueKey('sheet-stat-delta-RANGE')), findsNothing);
  });

  testWidgets(
    'damage-type secondary channels preview a delta; fixed channels do not',
    (tester) async {
      // corrosion/drone ride the damage channel through the character
      // factor; pierce/chain/slow/splash never scale.
      for (final (character, label, scales) in [
        (Character.shiori, 'CORROSION', true),
        (Character.tetsuo, 'DRONES', true),
        (Character.sayo, 'PIERCE', false),
        (Character.kaito, 'CHAIN', false),
      ]) {
        await _pumpCamp(
          tester,
          ownedLevels: {character: 9},
          squad: [character],
          scrip: 9999,
          onLevelUp: (_) {},
        );
        await _showCard(tester, character);
        await tester.tap(_card(character));
        await tester.pumpAndSettle();

        final metric = TowerStatScale.forType(character.style).secondaryMetric;
        expect(metric, isNotNull, reason: character.name);
        final delta =
            metric!.valueOf(scaledStats(character, 10)) -
            metric.valueOf(scaledStats(character, 9));
        final deltaFinder = find.byKey(ValueKey('sheet-stat-delta-$label'));
        if (scales) {
          expect(deltaFinder, findsOneWidget, reason: character.name);
          expect(
            tester.widget<Text>(deltaFinder).data,
            '+${decimal(delta)}',
            reason: character.name,
          );
        } else {
          expect(
            delta,
            0,
            reason: '$label must not scale with persistent level',
          );
          expect(deltaFinder, findsNothing, reason: character.name);
        }

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('Level Up fires the purchase callback once per press', (
    tester,
  ) async {
    final bought = <Character>[];
    await _pumpCamp(
      tester,
      ownedLevels: const {Character.haruto: 2, Character.mio: 1},
      squad: const [Character.haruto],
      scrip: 200,
      onLevelUp: bought.add,
    );
    await _showCard(tester, Character.haruto);
    await tester.tap(_card(Character.haruto));
    await tester.pumpAndSettle();

    expect(levelUpButton(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('level-up-button')));
    await tester.pump();
    expect(bought, [Character.haruto]);
  });

  testWidgets('insufficient Scrip disables Level Up with a readable reason', (
    tester,
  ) async {
    var presses = 0;
    await _pumpCamp(
      tester,
      ownedLevels: const {Character.haruto: 1},
      squad: const [Character.haruto],
      scrip: 30,
      onLevelUp: (_) => presses++,
    );
    await _showCard(tester, Character.haruto);
    await tester.tap(_card(Character.haruto));
    await tester.pumpAndSettle();

    expect(levelUpButton(tester).onPressed, isNull);
    expect(
      find.text('NEEDS ${GameBalance.levelUpCost(1)} SCRIP'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('level-up-button')));
    await tester.pumpAndSettle();
    expect(presses, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the level cap disables Level Up with a readable reason', (
    tester,
  ) async {
    var presses = 0;
    await _pumpCamp(
      tester,
      ownedLevels: const {Character.haruto: GameBalance.characterMaxLevel},
      squad: const [Character.haruto],
      scrip: 99999,
      onLevelUp: (_) => presses++,
    );
    await _showCard(tester, Character.haruto);
    await tester.tap(_card(Character.haruto));
    await tester.pumpAndSettle();

    expect(levelUpButton(tester).onPressed, isNull);
    expect(find.text('MAX LEVEL REACHED'), findsOneWidget);
    // At the cap no price is offered and no next-level delta renders.
    expect(find.text('LEVEL UP'), findsOneWidget);
    expect(find.textContaining('LEVEL UP ·'), findsNothing);
    expect(find.byKey(const ValueKey('sheet-stat-delta-DAMAGE')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('level-up-button')));
    await tester.pumpAndSettle();
    expect(presses, 0);
  });

  testWidgets('a write in flight holds Level Up busy and single-flight', (
    tester,
  ) async {
    var presses = 0;
    await _pumpCamp(
      tester,
      ownedLevels: const {Character.haruto: 3},
      squad: const [Character.haruto],
      scrip: 500,
      isSavingProgress: true,
      onLevelUp: (_) => presses++,
    );
    await _showCard(tester, Character.haruto);
    await tester.tap(_card(Character.haruto));
    // The busy button's spinner never settles — pump frames explicitly.
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('character-sheet')), findsOneWidget);
    expect(levelUpButton(tester).loading, isTrue);
    await tester.tap(find.byKey(const ValueKey('level-up-button')));
    await tester.pump();
    expect(presses, 0);
  });

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
      final harutoAsset =
          'assets/images/${OrionArt.characterPortrait(Character.haruto).fileName}';
      final bundle = _TestAssetBundle(failures: {harutoAsset});

      await _pumpCamp(tester, assetBundle: bundle);
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
    // The pinned purchase footer stays fully on the compact surface.
    final footerRect = tester.getRect(
      find.byKey(const ValueKey('level-up-button')),
    );
    expect(footerRect.right, lessThanOrEqualTo(320));
    expect(footerRect.bottom, lessThanOrEqualTo(568));
    expect(tester.takeException(), isNull);
  });

  // --- Task 8 (live-browser findings): the SQUAD tag clipped to 'SQ…' and
  // locked portraits flattened to an invisible black slab. These regressions
  // assert the *rendered* outcome — every glyph painted, no rank overlap —
  // not just widget presence.

  /// Asserts the SQUAD tag on [character]'s card paints all five glyphs at
  /// the current card constraints, stays inside the card, keeps the rank
  /// glyph painted, and does not overlap the rank badge.
  void expectReadableSquadTag(WidgetTester tester, Character character) {
    final card = _card(character);
    final cardRect = tester.getRect(card);
    final tag = find.descendant(of: card, matching: find.text('SQUAD'));
    expect(tag, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(tag);
    // Ellipsis ('SQ…') or an edge clip lays out no box for the closing 'D' —
    // checking the final glyph's paint box catches clipping that a widget
    // find cannot.
    expect(
      paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 4, extentOffset: 5),
      ),
      isNotEmpty,
      reason: 'SQUAD is ellipsized — the closing D has no paint box',
    );
    final tagRect = tester.getRect(tag);
    expect(tagRect.right, lessThanOrEqualTo(cardRect.right));
    expect(tagRect.bottom, lessThanOrEqualTo(cardRect.bottom));

    final rank = find.descendant(
      of: card,
      matching: find.text(character.rank.label),
    );
    final rankParagraph = tester.renderObject<RenderParagraph>(rank);
    expect(
      rankParagraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 1),
      ),
      isNotEmpty,
      reason: 'rank glyph clipped at this text scale',
    );
    final rankRect = tester.getRect(rank);
    expect(rankRect.right, lessThanOrEqualTo(cardRect.right));
    expect(
      tagRect.overlaps(rankRect),
      isFalse,
      reason: 'SQUAD tag overlaps the rank badge',
    );
  }

  testWidgets('squad tag paints the full word at the 390 product width', (
    tester,
  ) async {
    await _pumpCamp(
      tester,
      ownedLevels: const {Character.haruto: 7},
      squad: const [Character.haruto],
    );
    await _showCard(tester, Character.haruto);
    expectReadableSquadTag(tester, Character.haruto);
    expect(tester.takeException(), isNull);
  });

  testWidgets('squad tag stays whole at 320 with 2x text', (tester) async {
    await _pumpCamp(
      tester,
      ownedLevels: const {Character.haruto: 7},
      squad: const [Character.haruto],
      viewport: const Size(320, 568),
      textScaler: const TextScaler.linear(2),
    );

    // A scaled-up pill cannot fit three ~91px columns; the grid must widen
    // to two columns rather than shrink the accessible label. (Checked
    // before scrolling — the grid lazily disposes off-screen cards.)
    final first = tester.getRect(_card(Character.hikari));
    final second = tester.getRect(_card(Character.jin));
    final third = tester.getRect(_card(Character.akane));
    expect(second.left, greaterThan(first.right));
    expect(
      third.top,
      greaterThan(first.top),
      reason: 'at 320 with 2x text the roster must drop to two columns',
    );

    await _showCard(tester, Character.haruto);
    expectReadableSquadTag(tester, Character.haruto);
    expect(tester.takeException(), isNull);
  });

  testWidgets('squad tag grows with the ambient text scaler', (tester) async {
    const owned = {Character.haruto: 7};
    const squad = [Character.haruto];
    await _pumpCamp(tester, ownedLevels: owned, squad: squad);
    await _showCard(tester, Character.haruto);
    final tag = find.descendant(
      of: _card(Character.haruto),
      matching: find.text('SQUAD'),
    );
    expect(
      tester.widget<Text>(tag).textScaler,
      isNull,
      reason: 'the SQUAD tag must inherit MediaQuery text scaling',
    );
    final width1x = tester.getRect(tag).width;

    await _pumpCamp(
      tester,
      ownedLevels: owned,
      squad: squad,
      textScaler: const TextScaler.linear(2),
    );
    await _showCard(tester, Character.haruto);
    expectReadableSquadTag(tester, Character.haruto);
    final width2x = tester
        .getRect(
          find.descendant(
            of: _card(Character.haruto),
            matching: find.text('SQUAD'),
          ),
        )
        .width;
    expect(
      width2x,
      greaterThan(width1x * 1.5),
      reason:
          'tag text must grow under the 2x accessibility scaler '
          '(1x=$width1x, 2x=$width2x)',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('locked cards silhouette the shared portrait descriptor', (
    tester,
  ) async {
    await _pumpCamp(tester, ownedLevels: const {}, squad: const []);
    final hikari = _card(Character.hikari);

    // The locked art still flows through the shared descriptor, so the
    // error-fallback contract (Icons.person) is unchanged.
    final sprite = tester.widget<OrionAtlasSprite>(
      find.descendant(of: hikari, matching: find.byType(OrionAtlasSprite)),
    );
    expect(
      sprite.art,
      same(OrionArt.characterPortrait(Character.hikari)),
      reason: 'locked cards must keep the shared portrait descriptor',
    );

    final filter = tester.widget<ColorFiltered>(
      find.descendant(of: hikari, matching: find.byType(ColorFiltered)),
    );
    expect(
      filter.colorFilter,
      same(orionLockedPortraitFilter),
      reason:
          'locked portraits must use the shared muted-silhouette filter — '
          'srcIn flattens opaque art to a black slab',
    );
  });

  testWidgets('locked silhouette mutes chroma, crushes midtones, keeps shape', (
    tester,
  ) async {
    final portraitPng = await _bandedPortraitPng(tester);
    final hikariAsset =
        'assets/images/${OrionArt.characterPortrait(Character.hikari).fileName}';
    final bundle = _TestAssetBundle(stubs: {hikariAsset: portraitPng});

    await _pumpCamp(
      tester,
      ownedLevels: const {},
      squad: const [],
      assetBundle: bundle,
    );
    final hikariImage = tester.widget<Image>(
      find.descendant(
        of: _card(Character.hikari),
        matching: find.byType(Image),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        hikariImage.image,
        tester.element(_card(Character.hikari)),
      ),
    );
    await tester.pumpAndSettle();

    // Grid items are repaint-boundary wrapped, so the card's composited
    // pixels (silhouette filter + locked opacity over the card fill) can
    // be sampled directly.
    final cardRect = tester.getRect(_card(Character.hikari));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(
            of: _card(Character.hikari),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    late ui.Image shot;
    late ByteData bytes;
    await tester.runAsync(() async {
      shot = await boundary.toImage();
      bytes = (await shot.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });
    expect(
      shot.width,
      closeTo(cardRect.width, 2),
      reason: 'expected the card repaint boundary, not an ancestor',
    );

    // Sample the portrait area above the name scrim and clear of the
    // badge strip, once per synthetic band. rawRgba bytes are
    // premultiplied, so the stored channels already are the pixel
    // composited over black — the on-screen darkness.
    double meanChannel(int channel, double xFrom, double xTo) {
      var sum = 0.0;
      var count = 0;
      final yFrom = (shot.height * 0.30).round();
      final yTo = (shot.height * 0.55).round();
      for (var y = yFrom; y < yTo; y++) {
        for (
          var x = (shot.width * xFrom).round();
          x < (shot.width * xTo).round();
          x++
        ) {
          sum += bytes.getUint8((y * shot.width + x) * 4 + channel);
          count++;
        }
      }
      return sum / count;
    }

    double luma(double xFrom, double xTo) =>
        0.2126 * meanChannel(0, xFrom, xTo) +
        0.7152 * meanChannel(1, xFrom, xTo) +
        0.0722 * meanChannel(2, xFrom, xTo);

    final bright = luma(0.03, 0.22);
    final amber = luma(0.28, 0.47);
    final mid = luma(0.53, 0.72);
    final dark = luma(0.78, 0.97);

    // Shape: the bright band must separate clearly from the dark band.
    expect(
      bright - dark,
      greaterThanOrEqualTo(28),
      reason:
          'locked portrait lost its shape: bright $bright vs dark $dark '
          '(srcIn flattened the opaque art)',
    );
    expect(
      bright,
      greaterThanOrEqualTo(40),
      reason: 'silhouette is near-invisible against the dark card',
    );
    expect(
      bright,
      lessThan(176),
      reason: 'locked art is not muted — it reads as owned',
    );

    // No color: the saturated amber band must render near-neutral —
    // costume/palette hues are part of the hidden identity.
    final r = meanChannel(0, 0.28, 0.47);
    final g = meanChannel(1, 0.28, 0.47);
    final b = meanChannel(2, 0.28, 0.47);
    expect(
      (r - g).abs() < 8 && (g - b).abs() < 8,
      isTrue,
      reason: 'silhouette leaks color: r=$r g=$g b=$b',
    );

    // Contrast crush: a 50% midtone must land well below a linear share
    // of the bright band — that is what turns costume/facial detail into
    // a flat shadow instead of a readable portrait.
    expect(
      mid,
      lessThan(bright * 0.45),
      reason:
          'midtone detail survives: mid $mid vs bright $bright — '
          'the treatment must crush midtones, not just dim uniformly',
    );
    expect(amber, greaterThan(dark + 20), reason: 'amber band vanished');
  });

  testWidgets('camp handles zero-size first frame without crashing', (
    tester,
  ) async {
    await _pumpCamp(tester, viewport: Size.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back closes character sheet without popping route', (
    tester,
  ) async {
    await loadRealFonts();
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var routePopped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: orionThemeData,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute<void>(
                          builder: (_) => const CampView(
                            ownedLevels: CampaignSave.starterOwnedLevels,
                            squad: CampaignSave.starterSquad,
                            scrip: 0,
                          ),
                        ),
                      )
                      .then((_) => routePopped = true);
                },
                child: const Text('Open Camp'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Camp'));
    await tester.pumpAndSettle();
    await _showCard(tester, Character.haruto);
    await tester.tap(_card(Character.haruto));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('character-sheet')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('character-sheet')), findsNothing);
    expect(_card(Character.haruto), findsOneWidget);
    expect(routePopped, isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(routePopped, isTrue);
  });

  testWidgets(
    'high-rank and max-level damage bars stay below full on character sheet',
    (tester) async {
      const owned = {
        Character.hikari: 1,
        Character.akane: 1,
        Character.haruto: GameBalance.characterMaxLevel,
      };
      for (final character in owned.keys) {
        await _pumpCamp(tester, ownedLevels: owned, squad: [character]);
        await _showCard(tester, character);
        await tester.tap(_card(character));
        await tester.pumpAndSettle();

        final bar = tester.widget<FractionallySizedBox>(
          find.byKey(const ValueKey('sheet-stat-fill-DAMAGE')),
        );
        expect(bar.widthFactor, lessThan(1.0), reason: character.name);

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('camp portraits decode at display size via ResizeImage', (
    tester,
  ) async {
    await _pumpCamp(tester);
    final hikariImage = tester.widget<Image>(
      find
          .descendant(of: _card(Character.hikari), matching: find.byType(Image))
          .first,
    );
    expect(hikariImage.image, isA<ResizeImage>());
    final resized = hikariImage.image as ResizeImage;
    expect(resized.width, isNotNull);
    expect(resized.width!, lessThan(400));
  });
}
