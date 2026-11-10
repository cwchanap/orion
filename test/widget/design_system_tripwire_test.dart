import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

const _rawColorAllowlist = <String>{
  'lib/game/ui/mission_report_panel.dart',
  'lib/game/ui/next_wave_scanner.dart',
  'lib/game/ui/stage_briefing_sheet.dart',
};

void main() {
  test('no game UI file blurs a backdrop', () {
    final offenders = [
      for (final file in _libDartFiles())
        if (file.readAsStringSync().contains('BackdropFilter') ||
            file.readAsStringSync().contains('ImageFilter.blur'))
          _posixPath(file),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'the arcade command deck renders solid panels only; the blur tier '
          'is retired, so neither BackdropFilter nor ImageFilter.blur may '
          'appear anywhere in lib/',
    );
  });

  test('the retired surface APIs are gone', () {
    final offenders = [
      for (final file in _libDartFiles())
        if (file.readAsStringSync().contains('OrionSurfaceTier') ||
            file.readAsStringSync().contains('OrionInnerSurface') ||
            file.readAsStringSync().contains('MissionSurface'))
          _posixPath(file),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'one surface API remains: OrionSurface with a semantic role. The '
          'blur-tier enum and both adapters were removed in the foundation '
          'change; do not reintroduce them',
    );
  });

  test('raw colors stay inside orion_ui_theme.dart in game UI', () {
    final rawColor = RegExp(r'Color\(0x');
    final offenders = <String>[
      for (final file in _libDartFiles())
        if (_posixPath(file).contains('/game/ui/') &&
            !_posixPath(file).endsWith('orion_ui_theme.dart') &&
            rawColor.hasMatch(file.readAsStringSync()))
          _posixPath(file),
    ]..sort();
    expect(
      offenders.toSet(),
      _rawColorAllowlist,
      reason:
          'game UI consumes theme roles; a raw Color(0x...) literal belongs '
          'in orion_ui_theme.dart. Files awaiting their restyle task sit in '
          '_rawColorAllowlist, which only shrinks until Task 5 empties it',
    );
  });

  test('every allowlisted file still needs the exception', () {
    final rawColor = RegExp(r'Color\(0x');
    final stale = [
      for (final path in _rawColorAllowlist)
        if (!File(path).existsSync() ||
            !rawColor.hasMatch(File(path).readAsStringSync()))
          path,
    ];
    expect(
      stale,
      isEmpty,
      reason:
          'an allowlist entry whose file no longer holds raw colors is '
          'stale; remove it so the list keeps shrinking to zero',
    );
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
