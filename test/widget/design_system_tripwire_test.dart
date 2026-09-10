import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/orion_surface.dart';
import 'package:orion/game/ui/orion_typography.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

Iterable<File> _libDartFiles() sync* {
  for (final e in Directory('lib').listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}

void main() {
  test('ImageFilter.blur is centralised in OrionSurface', () {
    final filesWithBlur = <String>{
      for (final file in _libDartFiles())
        if (file.readAsStringSync().contains('ImageFilter.blur')) file.path,
    };
    expect(
      filesWithBlur,
      {'lib/game/ui/orion_surface.dart'},
      reason:
          'every blur must go through OrionSurface, the one place the blur '
          'budget is enforced; a second call site can drift from the four '
          'sanctioned sigmas unnoticed — and an empty set here would mean '
          'the sanctioned call itself was deleted, not just moved',
    );
  });

  test('only the four sanctioned blur values exist in lib/', () {
    expect(
      OrionSurfaceTier.values.map((t) => t.blur).toSet(),
      {6.0, 7.0, 12.0, 14.0},
      reason: 'the system sheet ships four blur values; a fifth is a bug',
    );
  });

  test('the chamfered CommandFrame primitive is gone', () {
    final offenders = [
      for (final file in _libDartFiles())
        if (file.readAsStringSync().contains('commandFramePath') ||
            file.readAsStringSync().contains('CommandFrame'))
          file.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'surfaces are rounded only: no chamfer, no bevelled plate',
    );
  });

  test('game UI does not read Material TextTheme', () {
    final offenders = [
      for (final file in _libDartFiles())
        if (file.path.contains('/ui/') &&
            file.readAsStringSync().contains('textTheme'))
          file.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'type comes from OrionTypography, not Material roles',
    );
  });

  test('screen titles go through OrionTitle', () {
    // OrionTitle carries the caps and keeps the real copy as the semantics
    // label. A bare Text styled with the title role renders sentence case and
    // drifts the screen back off the sheet, so the role's only caller is the
    // widget that owns it.
    final offenders = [
      for (final file in _libDartFiles())
        if (!file.path.endsWith('orion_typography.dart') &&
            file.readAsStringSync().contains('OrionTypography.title'))
          file.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'use OrionTitle; it owns the caps and the semantics label',
    );
  });

  test('OrionTitle is handed real copy, never a shouted literal', () {
    // Passing an already-uppercased string would double-apply the rule and
    // leave assistive tech spelling out the shout.
    final offenders = <String>[];
    final call = RegExp(r"OrionTitle\(\s*'([^']*)'");
    for (final file in _libDartFiles()) {
      for (final match in call.allMatches(file.readAsStringSync())) {
        final literal = match.group(1)!;
        if (literal.toUpperCase() == literal &&
            literal.toLowerCase() != literal) {
          offenders.add('${file.path}: $literal');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'OrionTitle uppercases for display');
  });

  test('Material components take Orion colours, not a generated seed', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(
      main.contains('ColorScheme.fromSeed'),
      isFalse,
      reason: 'a seeded scheme colours Material widgets off palette',
    );
  });

  test('microLabel cannot be white', () {
    expect(
      () => OrionTypography.microLabel(color: OrionUiTheme.dark.textPrimary),
      throwsArgumentError,
    );
  });
}
