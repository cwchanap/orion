import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/camp_view.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';
import 'package:orion/game/ui/tower_stat_scale.dart';

import '../support/orion_finders.dart';

const _productViewport = Size(390, 844);

/// An [Images] that serves in-memory stubs for the listed files and leaves
/// every other load pending (matching the cold-cache behaviour the rest of
/// this file relies on). Lets a test paint a real [OrionAtlasSprite] frame
/// without touching real profile art.
final class _StubImages extends Images {
  _StubImages(this.stubs);

  final Map<String, ui.Image> stubs;

  @override
  Future<ui.Image> load(String fileName, {String? key, String? package}) {
    final stub = stubs[fileName];
    if (stub != null) return Future.value(stub);
    return Completer<ui.Image>().future;
  }
}

/// A fully opaque portrait stand-in: the left half near-white, the right
/// half near-black. The shipped portraits are JPG-derived RGB with no alpha
/// channel, which is exactly what defeated the old srcIn silhouette — a
/// synthetic split makes the resulting luminance spread measurable.
Future<ui.Image> _splitPortraitImage(WidgetTester tester) {
  const side = 8;
  final pixels = Uint8List(side * side * 4);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final offset = (y * side + x) * 4;
      final bright = x < side / 2 ? 0xF0 : 0x10;
      pixels[offset] = bright;
      pixels[offset + 1] = bright;
      pixels[offset + 2] = bright;
      pixels[offset + 3] = 0xFF;
    }
  }
  return tester
      .runAsync(() {
        final decoded = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          pixels,
          side,
          side,
          ui.PixelFormat.rgba8888,
          decoded.complete,
        );
        return decoded.future;
      })
      .then((image) => image!);
}

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

  // --- Task 8 (live-browser findings): the SQUAD tag clipped to 'SQ…' and
  // locked portraits flattened to an invisible black slab. These regressions
  // assert the *rendered* outcome — every glyph painted, no rank overlap —
  // not just widget presence.

  /// Asserts the SQUAD tag on [character]'s card paints all five glyphs at
  /// the current card constraints, stays inside the card, and does not
  /// overlap the rank badge.
  void expectReadableSquadTag(WidgetTester tester, Character character) {
    final card = _card(character);
    final tag = find.descendant(of: card, matching: find.text('SQUAD'));
    expect(tag, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(tag);
    // Ellipsis ('SQ…') lays out no box for the closing 'D' — checking the
    // final glyph's paint box catches clipping that a widget find cannot.
    expect(
      paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 4, extentOffset: 5),
      ),
      isNotEmpty,
      reason: 'SQUAD is ellipsized — the closing D has no paint box',
    );
    final tagRect = tester.getRect(tag);
    final cardRect = tester.getRect(card);
    expect(tagRect.right, lessThanOrEqualTo(cardRect.right));
    expect(tagRect.bottom, lessThanOrEqualTo(cardRect.bottom));
    final rankRect = tester.getRect(
      find.descendant(of: card, matching: find.text(character.rank.label)),
    );
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
    await _showCard(tester, Character.haruto);
    expectReadableSquadTag(tester, Character.haruto);
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

  testWidgets('locked silhouette keeps discernible luminance over opaque art', (
    tester,
  ) async {
    final portrait = await _splitPortraitImage(tester);
    final previous = Flame.images;
    Flame.images = _StubImages({
      OrionArt.characterPortrait(Character.hikari).fileName: portrait,
    });
    OrionArtDescriptor.resetSpriteCache();
    addTearDown(() {
      Flame.images = previous;
      OrionArtDescriptor.resetSpriteCache();
    });

    await _pumpCamp(tester, ownedLevels: const {}, squad: const []);

    // Grid items are repaint-boundary wrapped, so the card's composited
    // pixels (silhouette filter + locked opacity over the card fill) can be
    // sampled directly.
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

    // Sample the portrait area above the name scrim and clear of the badge
    // strip: bright-left vs dark-right halves of the synthetic portrait.
    // rawRgba bytes are premultiplied, so the stored channels already are
    // the pixel composited over black — the on-screen darkness.
    double meanLuma(double xFrom, double xTo) {
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
          final offset = (y * shot.width + x) * 4;
          sum +=
              0.2126 * bytes.getUint8(offset) +
              0.7152 * bytes.getUint8(offset + 1) +
              0.0722 * bytes.getUint8(offset + 2);
          count++;
        }
      }
      return sum / count;
    }

    final bright = meanLuma(0.08, 0.42);
    final dark = meanLuma(0.58, 0.92);
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
  });
}
