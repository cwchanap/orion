import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/orion_surface.dart';
import 'package:orion/game/ui/orion_typography.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

/// `File.path` uses the platform separator; every comparison below is
/// written against forward slashes, so normalise first or they silently
/// pass/fail off POSIX.
String _posixPath(File file) => file.path.replaceAll('\\', '/');

Iterable<File> _libDartFiles() sync* {
  for (final e in Directory('lib').listSync(recursive: true)) {
    if (e is File && _posixPath(e).endsWith('.dart')) yield e;
  }
}

void main() {
  test('ImageFilter.blur is centralised in OrionSurface', () {
    final filesWithBlur = <String>{
      for (final file in _libDartFiles())
        if (file.readAsStringSync().contains('ImageFilter.blur'))
          _posixPath(file),
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
    expect(OrionSurfaceTier.values.map((t) => t.blur).toSet(), {
      6.0,
      7.0,
      12.0,
      14.0,
    }, reason: 'the system sheet ships four blur values; a fifth is a bug');
  });

  test('the chamfered CommandFrame primitive is gone', () {
    final offenders = [
      for (final file in _libDartFiles())
        if (file.readAsStringSync().contains('commandFramePath') ||
            file.readAsStringSync().contains('CommandFrame'))
          _posixPath(file),
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
        if (_posixPath(file).contains('/ui/') &&
            file.readAsStringSync().contains('textTheme'))
          _posixPath(file),
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
        if (!_posixPath(file).endsWith('orion_typography.dart') &&
            file.readAsStringSync().contains('OrionTypography.title'))
          _posixPath(file),
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'use OrionTitle; it owns the caps and the semantics label',
    );
  });

  test('OrionTitle is handed real copy, never a shouted literal', () {
    // Passing an already-uppercased string would double-apply the rule and
    // leave assistive tech spelling out the shout. An acronym has no
    // mixed-case form — 'R & D' *is* the real copy — so the check only
    // fires on a shouted run of two or more letters.
    final offenders = <String>[];
    final call = RegExp(r"OrionTitle\(\s*'([^']*)'");
    final shouted = RegExp(r'[A-Z]{2,}');
    for (final file in _libDartFiles()) {
      for (final match in call.allMatches(file.readAsStringSync())) {
        final literal = match.group(1)!;
        if (literal.toUpperCase() == literal &&
            literal.toLowerCase() != literal &&
            shouted.hasMatch(literal)) {
          offenders.add('${_posixPath(file)}: $literal');
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
