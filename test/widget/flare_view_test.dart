import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/flare_rules.dart';
import 'package:orion/game/ui/flare_view.dart';
import 'package:orion/game/ui/orion_primary_button.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/util/format.dart';

import '../support/orion_finders.dart';
import '../support/real_fonts.dart';

const _productViewport = Size(390, 844);

FlareDraw _newDraw(Character character) =>
    FlareDraw(character: character, isNew: true, scripRefund: 0);

FlareDraw _duplicateDraw(Character character) => FlareDraw(
  character: character,
  isNew: false,
  scripRefund: GameBalance.flareDuplicateScripRefund[character.rank]!,
);

/// A ten-draw batch matching artboard 13's shape: two new recruits and
/// eight refunded duplicates interleaved in pull order.
FlareBatch _tenDrawBatch() => FlareBatch([
  _duplicateDraw(Character.haruto),
  _newDraw(Character.kaito),
  _duplicateDraw(Character.mio),
  _duplicateDraw(Character.haruto),
  _newDraw(Character.tetsuo),
  _duplicateDraw(Character.mio),
  _duplicateDraw(Character.haruto),
  _duplicateDraw(Character.mio),
  _duplicateDraw(Character.haruto),
  _duplicateDraw(Character.mio),
]);

Future<void> _pumpFlare(
  WidgetTester tester, {
  int scrip = 0,
  FlareBatch? result,
  bool isSavingProgress = false,
  ValueChanged<int>? onFire,
  VoidCallback? onResultDone,
  VoidCallback? onOpenRoster,
  bool embeddedInMenuShell = false,
  Size viewport = _productViewport,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await loadRealFonts();
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: orionThemeData,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: FlareView(
        scrip: scrip,
        result: result,
        isSavingProgress: isSavingProgress,
        onFire: onFire,
        onResultDone: onResultDone,
        onOpenRoster: onOpenRoster,
        embeddedInMenuShell: embeddedInMenuShell,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _fireButton(int count) => find.byKey(ValueKey('flare-fire-$count'));

void main() {
  testWidgets('fire screen shows the fixed six rank rates, prices and '
      'balance', (tester) async {
    await _pumpFlare(tester, scrip: 1240, onFire: (_) {});

    expect(findOrionTitle('Signal Flare'), findsOneWidget);
    expect(
      find.text(
        'Fire a flare over the snow. Whoever sees it walks in to join the '
        'camp.',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('1,240 Scrip'), findsOneWidget);

    expect(find.text('WHO ANSWERS'), findsOneWidget);
    // The fixed owner table, rarest first: S A B C D E.
    const rates = ['0.1%', '0.5%', '2%', '10%', '20%', '67.4%'];
    var previousLeft = -1.0;
    for (final rate in rates) {
      final rateFinder = find.text(rate);
      expect(rateFinder, findsOneWidget, reason: 'rate $rate');
      final left = tester.getRect(rateFinder).left;
      expect(left, greaterThan(previousLeft), reason: 'rate $rate order');
      previousLeft = left;
    }

    expect(find.text('FIRE FLARE · 100'), findsOneWidget);
    expect(find.text('FIRE 10 · 1,000'), findsOneWidget);
  });

  testWidgets('both fire buttons report their pack size', (tester) async {
    final fired = <int>[];
    await _pumpFlare(tester, scrip: 5000, onFire: fired.add);

    await tester.tap(_fireButton(1));
    await tester.tap(_fireButton(10));
    expect(fired, [1, 10]);
  });

  testWidgets('insufficient funds disable the matching pack with a readable '
      'reason', (tester) async {
    await _pumpFlare(tester, scrip: 500, onFire: (_) {});

    expect(
      tester.widget<OrionPrimaryButton>(_fireButton(1)).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<OrionPrimaryButton>(_fireButton(10)).onPressed,
      isNull,
    );
    expect(find.text('NEEDS 1,000 SCRIP'), findsOneWidget);
    expect(find.text('NEEDS 100 SCRIP'), findsNothing);

    // Below even a single flare: both packs stay off with their reasons.
    await _pumpFlare(tester, scrip: 30, onFire: (_) {});
    expect(tester.widget<OrionPrimaryButton>(_fireButton(1)).onPressed, isNull);
    expect(
      tester.widget<OrionPrimaryButton>(_fireButton(10)).onPressed,
      isNull,
    );
    expect(find.text('NEEDS 100 SCRIP'), findsOneWidget);
    expect(find.text('NEEDS 1,000 SCRIP'), findsOneWidget);
  });

  testWidgets('a missing fire callback renders both packs inert', (
    tester,
  ) async {
    await _pumpFlare(tester, scrip: 5000);

    expect(tester.widget<OrionPrimaryButton>(_fireButton(1)).onPressed, isNull);
    expect(
      tester.widget<OrionPrimaryButton>(_fireButton(10)).onPressed,
      isNull,
    );
  });

  testWidgets('a pending save disables both packs with a readable reason', (
    tester,
  ) async {
    final fired = <int>[];
    await _pumpFlare(
      tester,
      scrip: 5000,
      isSavingProgress: true,
      onFire: fired.add,
    );

    expect(tester.widget<OrionPrimaryButton>(_fireButton(1)).onPressed, isNull);
    expect(
      tester.widget<OrionPrimaryButton>(_fireButton(10)).onPressed,
      isNull,
    );
    expect(find.text('SAVING…'), findsOneWidget);

    await tester.tap(_fireButton(1));
    await tester.tap(_fireButton(10));
    expect(fired, isEmpty);
  });

  testWidgets('the fired pack keeps its spinner while the save is in flight', (
    tester,
  ) async {
    var saving = false;
    late StateSetter setBusy;
    await loadRealFonts();
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: orionThemeData,
        home: StatefulBuilder(
          builder: (context, setState) {
            setBusy = setState;
            return FlareView(
              scrip: 5000,
              isSavingProgress: saving,
              onFire: (_) {},
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_fireButton(1));
    setBusy(() => saving = true);
    await tester.pump();

    final firedButton = tester.widget<OrionPrimaryButton>(_fireButton(1));
    expect(firedButton.loading, isTrue);
    expect(tester.widget<OrionPrimaryButton>(_fireButton(10)).loading, isFalse);
    expect(
      tester.widget<OrionPrimaryButton>(_fireButton(10)).onPressed,
      isNull,
    );

    // Once the write drains the buttons re-enable and the spinner clears.
    setBusy(() => saving = false);
    await tester.pump();
    expect(
      tester.widget<OrionPrimaryButton>(_fireButton(1)).onPressed,
      isNotNull,
    );
    expect(tester.widget<OrionPrimaryButton>(_fireButton(1)).loading, isFalse);
  });

  testWidgets('the result screen lists every draw in order with its '
      'outcome', (tester) async {
    await _pumpFlare(tester, scrip: 335, result: _tenDrawBatch());

    expect(find.text('10 FLARES FIRED'), findsOneWidget);
    expect(findOrionTitle('2 new recruits'), findsOneWidget);

    // Hero cards highlight the two new recruits ahead of the draw grid.
    expect(find.byKey(const ValueKey('flare-hero-kaito')), findsOneWidget);
    expect(find.byKey(const ValueKey('flare-hero-tetsuo')), findsOneWidget);
    expect(find.text('NEW RECRUIT'), findsNWidgets(2));

    // All ten tiles exist; duplicates quote their rank refund.
    for (var index = 0; index < 10; index += 1) {
      expect(
        find.byKey(ValueKey('flare-draw-$index')),
        findsOneWidget,
        reason: 'draw $index',
      );
    }
    expect(find.text('+10 SCRIP'), findsNWidgets(8));
    // The two new tiles carry NEW marks inside the grid as well as heroes.
    expect(find.text('NEW'), findsNWidgets(2));

    // Draw-order check: tile 0 is haruto's duplicate, tile 1 the kaito
    // recruit, tile 4 the tetsuo recruit. Haruto's four duplicate tiles
    // share one semantics label — the keys above pin their positions.
    expect(
      find.bySemanticsLabel('Haruto, rank E, duplicate, +10 Scrip refund'),
      findsNWidgets(4),
    );
    expect(find.bySemanticsLabel('Kaito, rank C, new recruit'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Tetsuo, rank D, new recruit'),
      findsOneWidget,
    );

    expect(find.text('8 SPARE DOG TAGS TRADED'), findsOneWidget);
    expect(find.text('+${grouped(80)} Scrip'), findsOneWidget);
    expect(find.text('335'), findsOneWidget);
    expect(find.text('BALANCE'), findsOneWidget);
    // At normal width the strip stays side-by-side: the balance column
    // sits beside the caption, not stacked beneath the refund row.
    expect(
      tester.getRect(find.text('BALANCE')).top,
      lessThan(tester.getRect(find.text('+${grouped(80)} Scrip')).top),
      reason: 'the broad layout keeps the balance beside the details',
    );
  });

  testWidgets('a single-pull duplicate fits the same result layout', (
    tester,
  ) async {
    await _pumpFlare(
      tester,
      scrip: 10,
      result: FlareBatch([_duplicateDraw(Character.haruto)]),
    );

    expect(find.text('1 FLARE FIRED'), findsOneWidget);
    expect(findOrionTitle('No new recruits'), findsOneWidget);
    expect(find.byKey(const ValueKey('flare-draw-0')), findsOneWidget);
    expect(find.text('+10 SCRIP'), findsOneWidget);
    expect(find.text('1 SPARE DOG TAG TRADED'), findsOneWidget);
    expect(find.text('+10 Scrip'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
  });

  testWidgets('a single-pull recruit reads singular', (tester) async {
    await _pumpFlare(
      tester,
      scrip: 40,
      result: FlareBatch([_newDraw(Character.sayo)]),
    );

    expect(find.text('1 FLARE FIRED'), findsOneWidget);
    expect(findOrionTitle('New recruit'), findsOneWidget);
    expect(find.byKey(const ValueKey('flare-hero-sayo')), findsOneWidget);
    expect(find.text('0 SPARE DOG TAGS TRADED'), findsOneWidget);
  });

  testWidgets('FIRE AGAIN dismisses the result; TO ROSTER asks for the '
      'roster', (tester) async {
    var done = 0;
    var roster = 0;
    await _pumpFlare(
      tester,
      scrip: 335,
      result: _tenDrawBatch(),
      onResultDone: () => done += 1,
      onOpenRoster: () => roster += 1,
    );

    await tester.tap(find.byKey(const ValueKey('flare-again')));
    expect(done, 1);
    await tester.tap(find.byKey(const ValueKey('flare-to-roster')));
    expect(roster, 1);
  });

  testWidgets('compact 320x568 at 2x text keeps rates, packs and results '
      'reachable', (tester) async {
    const viewport = Size(320, 568);
    await _pumpFlare(
      tester,
      scrip: 1240,
      onFire: (_) {},
      viewport: viewport,
      textScaler: const TextScaler.linear(2),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('WHO ANSWERS'), findsOneWidget);
    for (final count in [1, 10]) {
      final rect = tester.getRect(_fireButton(count));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.bottom, lessThanOrEqualTo(568));
    }

    // The result state at the same compact settings keeps the summary and
    // both actions on screen.
    await _pumpFlare(
      tester,
      scrip: 335,
      result: _tenDrawBatch(),
      onResultDone: () {},
      onOpenRoster: () {},
      viewport: viewport,
      textScaler: const TextScaler.linear(2),
    );
    expect(tester.takeException(), isNull);
    for (final key in ['flare-again', 'flare-to-roster']) {
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.bottom, lessThanOrEqualTo(568));
    }
    await tester.scrollUntilVisible(find.text('8 SPARE DOG TAGS TRADED'), 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact result summary shows the complete refund and '
      'balance', (tester) async {
    const viewport = Size(320, 568);
    await _pumpFlare(
      tester,
      scrip: 335,
      result: _tenDrawBatch(),
      viewport: viewport,
      textScaler: const TextScaler.linear(2),
    );
    await tester.scrollUntilVisible(find.text('BALANCE'), 120);

    // Every summary string must paint its full content inside the width it
    // was given — replaying the widget's own style at its measured width
    // flags any line that ellipsis-truncated (didExceedMaxLines).
    for (final label in [
      '8 SPARE DOG TAGS TRADED',
      '+${grouped(80)} Scrip',
      'BALANCE',
      '335',
    ]) {
      final finder = find.text(label);
      final widget = tester.widget<Text>(finder);
      final width = tester.getSize(finder).width;
      final painter = TextPainter(
        text: TextSpan(text: widget.data, style: widget.style),
        maxLines: widget.maxLines,
        textDirection: TextDirection.ltr,
        textScaler: const TextScaler.linear(2),
      )..layout(maxWidth: width);
      expect(
        painter.didExceedMaxLines,
        isFalse,
        reason:
            '"$label" must render completely inside its ${width}px slot, '
            'not ellipsize',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact results reflow into readable tiles and hero cards', (
    tester,
  ) async {
    const viewport = Size(320, 568);

    // At 1x the fixed five-across grid would squeeze tiles to ~52px; the
    // result must reflow so captions stay readable.
    await _pumpFlare(
      tester,
      scrip: 335,
      result: _tenDrawBatch(),
      viewport: viewport,
    );
    final tile0 = tester.getRect(find.byKey(const ValueKey('flare-draw-0')));
    expect(
      tile0.width,
      greaterThan(64),
      reason: 'result tiles must not squeeze below a readable width',
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('flare-draw-4'))).top,
      greaterThan(tile0.top),
      reason: 'the grid must wrap to extra rows instead of forcing five across',
    );
    // Outcome captions must render at full scale inside their tile — a
    // FittedBox shrink would paint only ~9px of the ~15px line.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('flare-draw-0')),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
      reason: 'outcome captions must wrap, not shrink to fit',
    );
    expect(
      tester.getRect(find.text('+10 SCRIP').first).height,
      greaterThanOrEqualTo(13),
      reason: 'the refund caption must paint at full microLabel size',
    );

    // At 2x text the grid collapses toward a single column and hero cards
    // stack, keeping every caption at full scale.
    await _pumpFlare(
      tester,
      scrip: 335,
      result: _tenDrawBatch(),
      viewport: viewport,
      textScaler: const TextScaler.linear(2),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('flare-draw-1'))).top,
      greaterThan(
        tester.getRect(find.byKey(const ValueKey('flare-draw-0'))).top,
      ),
      reason: '2x text must reflow the grid instead of five-across',
    );
    expect(
      tester.getRect(find.text('+10 SCRIP').first).height,
      greaterThanOrEqualTo(24),
      reason: 'the refund caption must paint at the doubled scale',
    );
    final heroKaito = tester.getRect(
      find.byKey(const ValueKey('flare-hero-kaito')),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('flare-hero-tetsuo'))).top,
      greaterThan(heroKaito.top),
      reason: 'hero cards must stack at 2x text instead of squeezing',
    );
    expect(
      tester.getRect(find.text('NEW RECRUIT').first).width,
      lessThanOrEqualTo(heroKaito.width - 16),
      reason: 'NEW RECRUIT must fit inside its hero card, not clip',
    );
  });
}
