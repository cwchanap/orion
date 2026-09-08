# Orion UI Revamp — Foundation Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the Orion UI Revamp's design-system foundation — two typefaces with
three type roles, four blurred surface tiers, rounded-only geometry, named motion
durations, and nine art assets — without changing any scene layout.

**Architecture:** `OrionUiTheme` (an existing `ThemeExtension`) gains a typography
group and one new color token. Three new presentation widgets (`OrionSurface`,
`OrionReadout`, `OrionText`) become the vocabulary every later scene PR builds on.
`CommandFrame` (chamfered, forbidden by the new geometry rule) is deleted outright;
`MissionSurface` survives as a deprecated adapter so its 15 call sites convert
incrementally instead of in one commit.

**Tech Stack:** Flutter (Dart SDK ^3.12.0), Flame ^1.38.0, `flutter_test`,
`flutter_lints`. No new package dependencies.

**Spec:** `docs/superpowers/specs/2026-09-08-orion-ui-revamp-foundation-design.md`

## Global Constraints

- Palette values are fixed and come from the spec verbatim. Do not invent colors.
  The only new token is `sheetBlack` = `Color(0xFF080D13)`.
- Exactly four blur sigma values may exist in `lib/`: **6, 7, 12, 14**. A fifth is a bug.
- Radii: 14–20 for cards, 22 for pills, `shape: BoxShape.circle` for single-action
  controls. No chamfer, no bevel, anywhere.
- Micro-labels are muted-only: they must never resolve to `textPrimary`.
- All three type roles carry the shadow `BoxShadow`-equivalent
  `Shadow(color: Color(0xE605080D), offset: Offset(0, 1), blurRadius: 4)`.
- Oxanium ships **only as a variable font** (`Oxanium[wght].ttf`); weight is applied
  with `FontVariation('wght', 800)`, not `FontWeight` alone.
- No new package dependencies. Specifically **not** `google_fonts` — a runtime fetch
  breaks widget tests and offline builds.
- No scene layout changes in this plan. If a task requires relayouting a scene, stop
  and flag it — that work belongs to PR B/C/D.
- Every asset extracted from the design project MUST be verified for PNG magic
  (`\x89PNG\r\n\x1a\n`) and a trailing `IEND` chunk before being committed.
  `DesignSync.get_file` silently truncates at 256 KiB and produces files that
  `file(1)` still reports as valid PNGs.
- Gates that must stay green on every commit: `flutter analyze`,
  `dart format --output=none --set-exit-if-changed .`, and `flutter test`
  (857 passing at branch point `6e3f878`).

---

## File Structure

**Created:**
- `assets/fonts/Oxanium[wght].ttf` — variable weight axis, used at wght 800
- `assets/fonts/ChakraPetch-Bold.ttf` — micro-labels (w700)
- `assets/fonts/ChakraPetch-Medium.ttf` — body copy on reference surfaces (w500)
- `assets/fonts/OFL-Oxanium.txt`, `assets/fonts/OFL-ChakraPetch.txt` — licenses
- `lib/game/ui/orion_typography.dart` — the three type roles + `OrionText`/`OrionReadout`
- `lib/game/ui/orion_surface.dart` — `OrionSurfaceTier` enum + `OrionSurface`
- `assets/images/reactor_rim_ui/crests/*.png` — 7 stage crests
- `assets/images/reactor_rim_ui/boards/nebula.png`
- `assets/images/reactor_rim_ui/backdrops/command-center.png`
- `test/widget/orion_typography_test.dart`
- `test/widget/orion_surface_test.dart`
- `test/widget/design_system_tripwire_test.dart`

The asset-extraction script (Task 6) is a one-off and stays in the scratchpad; it is
deliberately not committed.

**Modified:**
- `pubspec.yaml` — `fonts:` block, `assets/fonts/`, three new image dirs
- `lib/game/ui/orion_ui_theme.dart` — `sheetBlack` token, `typography` group, motion durations
- `test/support/real_fonts.dart` — load the two new families
- `lib/game/ui/mission_surface.dart` — becomes a deprecated adapter over `OrionSurface`
- `lib/game/ui/orion_atlas_sprite.dart` — `OrionSceneArt.commandCenter`, crest registry
- 14 files under `lib/game/ui/` — 97 `textTheme` references migrated (Tasks 8–11)

**Deleted:**
- `lib/game/ui/command_frame.dart` and its test (Task 7)

---

### Task 1: Vendor the two typefaces

**Files:**
- Create: `assets/fonts/Oxanium[wght].ttf`, `assets/fonts/ChakraPetch-Bold.ttf`,
  `assets/fonts/ChakraPetch-Medium.ttf`, `assets/fonts/OFL-Oxanium.txt`,
  `assets/fonts/OFL-ChakraPetch.txt`
- Modify: `pubspec.yaml`

**Interfaces:**
- Consumes: nothing
- Produces: font families `Oxanium` (variable wght 200–800) and `ChakraPetch`
  (w500, w700), resolvable via `TextStyle(fontFamily: 'Oxanium')`.

- [ ] **Step 1: Download the fonts and their licenses**

Oxanium has **no static instances** in google/fonts — only the variable font. Do not
look for `Oxanium-ExtraBold.ttf`; it 404s.

```bash
mkdir -p assets/fonts
BASE=https://github.com/google/fonts/raw/main/ofl
curl -sSfL "$BASE/oxanium/Oxanium%5Bwght%5D.ttf"      -o "assets/fonts/Oxanium[wght].ttf"
curl -sSfL "$BASE/chakrapetch/ChakraPetch-Bold.ttf"   -o assets/fonts/ChakraPetch-Bold.ttf
curl -sSfL "$BASE/chakrapetch/ChakraPetch-Medium.ttf" -o assets/fonts/ChakraPetch-Medium.ttf
curl -sSfL "$BASE/oxanium/OFL.txt"                    -o assets/fonts/OFL-Oxanium.txt
curl -sSfL "$BASE/chakrapetch/OFL.txt"                -o assets/fonts/OFL-ChakraPetch.txt
```

- [ ] **Step 2: Verify each file is a real TrueType font, not an HTML error page**

```bash
file assets/fonts/*.ttf
```
Expected: three lines each reading `TrueType Font data` (or `TrueType font data`).
If any says `HTML document`, the download failed — stop and re-fetch.

- [ ] **Step 3: Declare the fonts and asset dirs in `pubspec.yaml`**

Add to the `flutter:` section, replacing the commented-out `# fonts:` example block.
The three new image directories are added now so later tasks don't re-touch this file.

```yaml
  assets:
    - assets/images/orion_sprite_sheet.png
    - assets/images/orion_tower_variety_sheet.png
    - assets/images/orion_terrain_background.png
    - assets/images/orion_path_tiles.png
    - assets/images/orion_boss_sheet.png
    - assets/images/reactor_rim_ui/stages/
    - assets/images/reactor_rim_ui/results/
    - assets/images/reactor_rim_ui/backdrops/
    - assets/images/reactor_rim_ui/crests/
    - assets/images/reactor_rim_ui/boards/
    - assets/audio/confirm.wav
    - assets/audio/clear.wav
    - assets/audio/victory.wav
    - assets/audio/defeat.wav

  fonts:
    - family: Oxanium
      fonts:
        - asset: assets/fonts/Oxanium[wght].ttf
    - family: ChakraPetch
      fonts:
        - asset: assets/fonts/ChakraPetch-Medium.ttf
          weight: 500
        - asset: assets/fonts/ChakraPetch-Bold.ttf
          weight: 700
```

Note: `assets/images/reactor_rim_ui/crests/` and `boards/` are declared here but the
directories don't exist yet. `flutter pub get` tolerates this; `flutter build` does
not. Task 6 creates them. If you run a build between Task 1 and Task 6 and it fails
on a missing asset dir, that is expected — proceed to Task 6.

- [ ] **Step 4: Verify resolution**

```bash
flutter pub get && flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add assets/fonts pubspec.yaml
git commit -m "feat: vendor Oxanium and Chakra Petch typefaces

Both OFL. Oxanium ships only as a variable font, so weight 800 is
applied via FontVariation rather than a static instance.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Load the new faces in the shared test font helper

**Files:**
- Modify: `test/support/real_fonts.dart`
- Test: exercised by Task 3 onward

**Interfaces:**
- Consumes: font assets from Task 1
- Produces: `loadRealFonts({bool withMaterialIcons = true})` additionally registers
  the `Oxanium` and `ChakraPetch` families from the project's own asset bundle.

- [ ] **Step 1: Extend the helper**

The existing helper reads Roboto from `FLUTTER_ROOT`. The new faces are project
assets, so they load from disk relative to the package root instead.

Append inside `loadRealFonts`, immediately before the `if (!withMaterialIcons) return;`
line:

```dart
  for (final family in const {
    'Oxanium': ['Oxanium[wght].ttf'],
    'ChakraPetch': ['ChakraPetch-Medium.ttf', 'ChakraPetch-Bold.ttf'],
  }.entries) {
    final familyLoader = FontLoader(family.key);
    for (final fileName in family.value) {
      final file = File('assets/fonts/$fileName');
      if (!file.existsSync()) fail('Missing project font: ${file.path}');
      familyLoader.addFont(
        Future.value(ByteData.view(file.readAsBytesSync().buffer)),
      );
    }
    await familyLoader.load();
  }
```

- [ ] **Step 2: Verify the existing suite still passes**

```bash
flutter test test/widget/
```
Expected: all pass. The helper is additive; no existing expectation changes.

- [ ] **Step 3: Commit**

```bash
git add test/support/real_fonts.dart
git commit -m "test: load Oxanium and Chakra Petch in shared font helper

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Add the `sheetBlack` token and motion durations to `OrionUiTheme`

**Files:**
- Modify: `lib/game/ui/orion_ui_theme.dart`
- Test: `test/widget/orion_typography_test.dart` (created here, extended in Task 4)

**Interfaces:**
- Consumes: nothing
- Produces: `OrionUiTheme.sheetBlack` (`Color`), and top-level constants
  `orionPressDuration`, `orionSheetDuration`, `orionLaneFlowDuration`,
  `orionHullPulseDuration`, `orionIdleBobDuration` (all `Duration`).

- [ ] **Step 1: Write the failing test**

Create `test/widget/orion_typography_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

void main() {
  test('sheetBlack sits between voidBlack and hullBlack', () {
    const t = OrionUiTheme.dark;
    expect(t.sheetBlack, const Color(0xFF080D13));
    expect(t.sheetBlack.r, greaterThan(t.voidBlack.r));
    expect(t.sheetBlack.r, lessThan(t.hullBlack.r));
  });

  test('sheetBlack survives copyWith and lerp', () {
    const t = OrionUiTheme.dark;
    expect(t.copyWith().sheetBlack, t.sheetBlack);
    expect(t.lerp(t, 0.5).sheetBlack, t.sheetBlack);
  });

  test('motion durations match the design system sheet', () {
    expect(orionPressDuration, const Duration(milliseconds: 90));
    expect(orionSheetDuration, const Duration(milliseconds: 220));
    expect(orionLaneFlowDuration, const Duration(milliseconds: 1100));
    expect(orionHullPulseDuration, const Duration(milliseconds: 2400));
    expect(orionIdleBobDuration, const Duration(milliseconds: 1600));
  });
}
```

The package name is `orion` (verified in `pubspec.yaml`), so `package:orion/...`
imports are correct throughout this plan.

- [ ] **Step 2: Run it to confirm it fails**

```bash
flutter test test/widget/orion_typography_test.dart
```
Expected: FAIL — `sheetBlack` isn't defined.

- [ ] **Step 3: Implement**

In `lib/game/ui/orion_ui_theme.dart`: add `required this.sheetBlack,` to the
constructor, `sheetBlack: Color(0xFF080D13),` to `static const dark`, the field
`final Color sheetBlack;`, a `Color? sheetBlack` parameter to `copyWith` with
`sheetBlack: sheetBlack ?? this.sheetBlack,`, and to `lerp`
`sheetBlack: Color.lerp(sheetBlack, other.sheetBlack, t)!,`.

Then append at file scope, next to the existing `orionMotionDuration`:

```dart
/// Motion durations from the Revamp system sheet (scene 1i). Route each through
/// [orionMotionDuration] at the call site so `disableAnimationsOf` still wins.
const orionPressDuration = Duration(milliseconds: 90);
const orionSheetDuration = Duration(milliseconds: 220);
const orionLaneFlowDuration = Duration(milliseconds: 1100);
const orionHullPulseDuration = Duration(milliseconds: 2400);
const orionIdleBobDuration = Duration(milliseconds: 1600);
```

- [ ] **Step 4: Run it to confirm it passes**

```bash
flutter test test/widget/orion_typography_test.dart
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/game/ui/orion_ui_theme.dart test/widget/orion_typography_test.dart
git commit -m "feat: add sheetBlack token and named motion durations

sheetBlack (#080D13) is the t3 gradient's bottom stop. It is the one
value the Revamp adds to the palette, which the system sheet describes
as unchanged.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: The three type roles

**Files:**
- Create: `lib/game/ui/orion_typography.dart`
- Modify: `test/widget/orion_typography_test.dart`

**Interfaces:**
- Consumes: `OrionUiTheme` (Task 3), fonts (Task 1)
- Produces:
  - `OrionTypography.readout({double size = 24, required Color color}) -> TextStyle`
  - `OrionTypography.title({required Color color}) -> TextStyle`
  - `OrionTypography.microLabel({Color? color}) -> TextStyle` — `color` may only be
    a muted tone; passing `textPrimary` throws `ArgumentError`
  - `OrionText.micro(String, {Color? color})` — widget
  - `OrionReadout({required String value, String? denominator, double size, required Color color})` — widget

- [ ] **Step 1: Write the failing tests**

Append to `test/widget/orion_typography_test.dart`:

```dart
  test('readout is Oxanium at variable weight 800', () {
    final s = OrionTypography.readout(color: const Color(0xFFFFC857));
    expect(s.fontFamily, 'Oxanium');
    expect(s.fontVariations, contains(const FontVariation('wght', 800)));
    expect(s.fontSize, 24);
    expect(s.shadows, isNotEmpty);
  });

  test('title is tracked caps-oriented Oxanium', () {
    final s = OrionTypography.title(color: const Color(0xFFF4F8FB));
    expect(s.fontFamily, 'Oxanium');
    expect(s.fontSize, 15);
    expect(s.letterSpacing, greaterThan(0));
  });

  test('microLabel is Chakra Petch 700 with design tracking', () {
    final s = OrionTypography.microLabel();
    expect(s.fontFamily, 'ChakraPetch');
    expect(s.fontWeight, FontWeight.w700);
    expect(s.fontSize, inInclusiveRange(7, 9));
    expect(s.letterSpacing! / s.fontSize!, inInclusiveRange(0.14, 0.24));
  });

  test('microLabel refuses textPrimary', () {
    expect(
      () => OrionTypography.microLabel(color: OrionUiTheme.dark.textPrimary),
      throwsArgumentError,
    );
  });

  testWidgets('OrionReadout renders a muted, smaller denominator', (t) async {
    await loadRealFonts();
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: OrionReadout(value: '03', denominator: '12', color: Color(0xFF46E6FF)),
      ),
    ));
    final value = t.widget<Text>(find.text('03'));
    final denom = t.widget<Text>(find.text('/12'));
    expect(denom.style!.fontSize, lessThan(value.style!.fontSize!));
    expect(denom.style!.color, isNot(value.style!.color));
  });
```

Add these imports at the top of the file:
```dart
import 'dart:ui' show FontVariation;
import 'package:orion/game/ui/orion_typography.dart';
import '../support/real_fonts.dart';
```

- [ ] **Step 2: Run to confirm failure**

```bash
flutter test test/widget/orion_typography_test.dart
```
Expected: FAIL — `orion_typography.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/game/ui/orion_typography.dart`:

```dart
import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';

import 'orion_ui_theme.dart';

/// Type roles from the Revamp system sheet (scene 1i): two faces, three roles.
///
/// Oxanium carries every numeral and the single screen title; Chakra Petch
/// carries every label. Nothing in the game UI reads Material's [TextTheme].
abstract final class OrionTypography {
  /// Shadow applied to all roles so contrast never depends on a surface fill.
  static const shadow = Shadow(
    color: Color(0xE605080D),
    offset: Offset(0, 1),
    blurRadius: 4,
  );

  /// Resource, hull, wave, cost and count numerals. The sheet's hero range is
  /// 22–40; smaller sizes are the same role used inline.
  static TextStyle readout({double size = 24, required Color color}) =>
      TextStyle(
        fontFamily: 'Oxanium',
        fontVariations: const [FontVariation('wght', 800)],
        fontSize: size,
        height: 1,
        color: color,
        shadows: const [shadow],
      );

  /// The one title per screen.
  static TextStyle title({required Color color}) => TextStyle(
        fontFamily: 'Oxanium',
        fontVariations: const [FontVariation('wght', 800)],
        fontSize: 15,
        height: 1,
        letterSpacing: 1.2,
        color: color,
        shadows: const [shadow],
      );

  /// Every label. Muted by construction: the sheet says "muted, never white".
  static TextStyle microLabel({Color? color, double size = 8}) {
    final resolved = color ?? OrionUiTheme.dark.textMuted;
    if (resolved == OrionUiTheme.dark.textPrimary) {
      throw ArgumentError.value(
        color,
        'color',
        'microLabel is muted-only; the system sheet forbids white labels.',
      );
    }
    return TextStyle(
      fontFamily: 'ChakraPetch',
      fontWeight: FontWeight.w700,
      fontSize: size,
      letterSpacing: size * 0.18,
      color: resolved,
      shadows: const [shadow],
    );
  }
}

/// A micro-label. Exists so call sites read as intent, not as styling.
class OrionText extends StatelessWidget {
  const OrionText.micro(this.data, {super.key, this.color, this.size = 8});

  final String data;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Text(data, style: OrionTypography.microLabel(color: color, size: size));
}

/// A numeric readout with an optional muted denominator.
///
/// The denominator is structurally smaller and muted, so the sheet's rule —
/// "never two full-size numbers" — cannot be violated by a caller.
class OrionReadout extends StatelessWidget {
  const OrionReadout({
    super.key,
    required this.value,
    required this.color,
    this.denominator,
    this.size = 24,
  });

  final String value;
  final Color color;
  final String? denominator;
  final double size;

  @override
  Widget build(BuildContext context) {
    final muted = OrionUiTheme.of(context).textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value, style: OrionTypography.readout(size: size, color: color)),
        if (denominator != null)
          Text(
            '/$denominator',
            style: OrionTypography.readout(size: size * 0.45, color: muted),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run to confirm passage**

```bash
flutter test test/widget/orion_typography_test.dart
```
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/game/ui/orion_typography.dart test/widget/orion_typography_test.dart
git commit -m "feat: add the three Revamp type roles

readout/title/microLabel over Oxanium and Chakra Petch. Two system-sheet
rules are structural rather than documented: microLabel throws on
textPrimary, and OrionReadout's denominator cannot be full size.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: The four surface tiers

**Files:**
- Create: `lib/game/ui/orion_surface.dart`
- Create: `test/widget/orion_surface_test.dart`

**Interfaces:**
- Consumes: `OrionUiTheme` (Task 3)
- Produces: `enum OrionSurfaceTier { t1, t2, t3, t4 }` with `double get blur`, and
  `OrionSurface({required OrionSurfaceTier tier, required Widget child, EdgeInsetsGeometry padding, double radius, bool topBorderOnly})`.

- [ ] **Step 1: Write the failing tests**

Create `test/widget/orion_surface_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/orion_surface.dart';

void main() {
  test('exactly four tiers exist, with the sheet blur values', () {
    expect(OrionSurfaceTier.values.map((t) => t.blur).toList(),
        [7.0, 6.0, 12.0, 14.0]);
  });

  testWidgets('every tier renders exactly one BackdropFilter', (t) async {
    for (final tier in OrionSurfaceTier.values) {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OrionSurface(tier: tier, child: const Text('x')),
        ),
      ));
      expect(find.byType(BackdropFilter), findsOneWidget,
          reason: 'tier $tier must blur its container, not its children');
    }
  });

  testWidgets('no tier is fully opaque', (t) async {
    for (final tier in OrionSurfaceTier.values) {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: OrionSurface(tier: tier, child: const Text('x'))),
      ));
      final box = t.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(OrionSurface),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final decoration = box.decoration as BoxDecoration;
      final colors = decoration.gradient is LinearGradient
          ? (decoration.gradient! as LinearGradient).colors
          : [decoration.color!];
      for (final c in colors) {
        expect(c.a, lessThan(1.0),
            reason: 'tier $tier: the art paid for is the art you see');
      }
    }
  });
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
flutter test test/widget/orion_surface_test.dart
```
Expected: FAIL — `orion_surface.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/game/ui/orion_surface.dart`:

```dart
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'orion_ui_theme.dart';

/// The four surface tiers from the Revamp system sheet (scene 1i).
///
/// Tier is an enum rather than a number so a fifth blur value — which the sheet
/// calls a bug — is unrepresentable. Budget 5–9 of these per screen, and blur
/// the container rather than each child: an eight-tile rail is one blurred row.
enum OrionSurfaceTier {
  /// Floating control on live art: radial, pacing, back, locked nodes, toasts.
  t1(7),

  /// Content card: rail tiles, stat/counter/spec cards, tech plates.
  t2(6),

  /// A sheet or drawer that deliberately covers the scene.
  t3(12),

  /// The full-width dock shelf — the one surface that spans edge to edge.
  t4(14);

  const OrionSurfaceTier(this.blur);

  final double blur;
}

/// Translucent, blurred, rounded chrome. Pure presentation: no gestures,
/// animation, or semantics of its own.
///
/// Solid primary actions (WAVE, DEPLOY) deliberately do not use this.
class OrionSurface extends StatelessWidget {
  const OrionSurface({
    super.key,
    required this.tier,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 18,
    this.topBorderOnly = false,
  });

  final OrionSurfaceTier tier;
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// 14–20 for cards, 22 for pills. Circles use [BoxShape.circle] elsewhere.
  final double radius;

  /// t4's shelf is bordered along its top edge only.
  final bool topBorderOnly;

  @override
  Widget build(BuildContext context) {
    final t = OrionUiTheme.of(context);
    final (Gradient? gradient, Color? color) = switch (tier) {
      OrionSurfaceTier.t1 => (null, t.hullBlack.withValues(alpha: 0.55)),
      OrionSurfaceTier.t2 => (
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              t.panelRaised.withValues(alpha: 0.66),
              t.hullBlack.withValues(alpha: 0.76),
            ],
          ),
          null,
        ),
      OrionSurfaceTier.t3 => (
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              t.panelBlue.withValues(alpha: 0.90),
              t.sheetBlack.withValues(alpha: 0.94),
            ],
          ),
          null,
        ),
      OrionSurfaceTier.t4 => (
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              t.voidBlack.withValues(alpha: 0.50),
              t.voidBlack.withValues(alpha: 0.62),
            ],
          ),
          null,
        ),
    };

    final borderColor = switch (tier) {
      OrionSurfaceTier.t1 => t.systemCyan.withValues(alpha: 0.5),
      OrionSurfaceTier.t2 => t.frameSteel,
      OrionSurfaceTier.t3 => t.systemCyan.withValues(alpha: 0.3),
      OrionSurfaceTier.t4 => t.systemCyan.withValues(alpha: 0.14),
    };

    final borderRadius = BorderRadius.circular(radius);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: tier.blur, sigmaY: tier.blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            gradient: gradient,
            borderRadius: borderRadius,
            border: topBorderOnly
                ? Border(top: BorderSide(color: borderColor))
                : Border.fromBorderSide(BorderSide(color: borderColor)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run to confirm passage**

```bash
flutter test test/widget/orion_surface_test.dart
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/game/ui/orion_surface.dart test/widget/orion_surface_test.dart
git commit -m "feat: add the four Revamp surface tiers

Tier is an enum so a fifth blur value is unrepresentable. Every tier is
translucent by construction; no tier may be fully opaque.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Extract and commit the nine art assets

**Files:**
- Create: `assets/images/reactor_rim_ui/crests/{outpost-alpha,aurora-gate,nebula-relay,salvage-rift,asteroid-foundry,void-bastion,singularity-core}.png`
- Create: `assets/images/reactor_rim_ui/boards/nebula.png`
- Create: `assets/images/reactor_rim_ui/backdrops/command-center.png`

**Interfaces:**
- Consumes: nothing
- Produces: nine PNGs on disk at the paths above.

- [ ] **Step 1: Extract from the standalone bundle**

`DesignSync.get_file` truncates at 256 KiB and yields corrupt-but-parseable PNGs.
Use the standalone bundle instead, which inlines every referenced asset. The user's
copy is at `~/Downloads/Orion UI Revamp - standalone.html`; it is also in the design
project as `Orion UI Revamp - standalone.html`.

Write this to the scratchpad (not the repo) and run it:

```python
import base64, json, os, re, sys

BUNDLE = os.path.expanduser('~/Downloads/Orion UI Revamp - standalone.html')
EXPORT = sys.argv[1]   # the export.dc.html content, assets/images/... paths intact
OUT = 'assets/images/reactor_rim_ui'

raw = open(BUNDLE, encoding='utf-8').read()
lines = raw.split('\n')
blob = next(json.loads(l) for l in lines if l.startswith('{"') and '"mime"' in l[:400])
tmpl = '\n'.join(l for l in lines if l is not blob)

uuids = re.findall(r'url\(&quot;([0-9a-f-]{36})&quot;\)', raw)
names = re.findall(r'url\(assets/images/([^)]+\.png)\)', open(EXPORT).read())
assert len(uuids) == len(names), f'{len(uuids)} != {len(names)}'
uuid_to_name = dict(zip(uuids, names))

DEST = {
    'crest_outpost_alpha.png':     'crests/outpost-alpha.png',
    'crest_aurora_gate.png':       'crests/aurora-gate.png',
    'crest_nebula_relay.png':      'crests/nebula-relay.png',
    'crest_salvage_rift.png':      'crests/salvage-rift.png',
    'crest_asteroid_foundry.png':  'crests/asteroid-foundry.png',
    'crest_void_bastion.png':      'crests/void-bastion.png',
    'crest_singularity_core.png':  'crests/singularity-core.png',
    'board_nebula.png':            'boards/nebula.png',
    'scene_cic.png':               'backdrops/command-center.png',
}

written = 0
for uuid, name in uuid_to_name.items():
    dest = DEST.get(name)
    if not dest or uuid not in blob:
        continue
    data = base64.b64decode(blob[uuid]['data'])
    assert data[:8] == b'\x89PNG\r\n\x1a\n', f'{name}: not a PNG'
    assert b'IEND' in data[-12:], f'{name}: truncated, no IEND'
    path = os.path.join(OUT, dest)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'wb').write(data)
    print(f'{dest:34} {len(data):9} bytes')
    written += 1
print('written:', written)
```

Expected: `written: 9`. The two crests not referenced by any scene
(`void_bastion`, `singularity_core`) are **not** in the bundle's url list — if the
script writes only 7, fetch those two via `DesignSync.get_file` instead (they are
~50 KB, well under the cap) and verify `IEND` on each before writing.

- [ ] **Step 2: Verify every file independently**

```bash
find assets/images/reactor_rim_ui/crests assets/images/reactor_rim_ui/boards \
     assets/images/reactor_rim_ui/backdrops/command-center.png -name '*.png' \
  | while read f; do
      printf '%-58s ' "$f"
      python3 -c "
import sys; d=open(sys.argv[1],'rb').read()
print('OK' if d[:8]==b'\x89PNG\r\n\x1a\n' and b'IEND' in d[-12:] else 'CORRUPT', len(d))
" "$f"
    done
```
Expected: nine lines, every one `OK`. Any `CORRUPT` means the file came through the
256 KiB cap — re-extract it from the bundle.

- [ ] **Step 3: Confirm the app still builds with the new asset dirs**

```bash
flutter pub get && flutter analyze
```
Expected: `No issues found!` (the dirs declared in Task 1 now exist).

- [ ] **Step 4: Commit**

```bash
git add assets/images/reactor_rim_ui/crests assets/images/reactor_rim_ui/boards \
        assets/images/reactor_rim_ui/backdrops/command-center.png
git status --short   # confirm ONLY these nine files are staged
git commit -m "feat: add Revamp crest, board and command-center art

Nine assets extracted from the design project's standalone bundle and
verified for a trailing IEND chunk. DesignSync.get_file truncates at
256 KiB and produces PNGs that file(1) still reports as valid, so the
bundle is the only reliable route for anything over that size.

board_foundry and board_void are deliberately absent: no scene in 1a-1h
references them.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Run `git status --short` before committing. PR #29 was bitten by `git add -A`
sweeping in untracked PNGs; stage these paths explicitly.

---

### Task 7: Retire `CommandFrame`

**Files:**
- Delete: `lib/game/ui/command_frame.dart`
- Modify: `lib/game/ui/stage_briefing_sheet.dart` (3 sites),
  `lib/game/ui/run_module_draft_panel.dart` (3), `lib/game/ui/world_map_view.dart` (1),
  `lib/game/ui/mission_report_panel.dart` (2), `lib/game/ui/orion_game_page.dart` (1)
- Delete: the `command_frame` test file, if one exists
  (`find test -name '*command_frame*'`)

**Interfaces:**
- Consumes: `OrionSurface` (Task 5)
- Produces: no `CommandFrame` symbol anywhere in `lib/`.

- [ ] **Step 1: Confirm the exact call-site inventory**

```bash
grep -rn 'CommandFrame(' lib/ | grep -v command_frame.dart
```
Expected: 10 lines across the 5 files above. If the count differs, the branch has
moved — re-derive the list before editing.

- [ ] **Step 2: Replace each call site**

`CommandFrame` and `OrionSurface` take the same `child` and `padding`, so each site
is a mechanical swap. Map the old `emphasized` flag onto a tier:

- `emphasized: true`  → `tier: OrionSurfaceTier.t3` (it was a sheet)
- default / `false`   → `tier: OrionSurfaceTier.t2` (it was a card)

Drop the `chamfer:` argument entirely — that is the point of this task. Replace the
import `import 'command_frame.dart';` with `import 'orion_surface.dart';` in each
file.

Example, from `lib/game/ui/world_map_view.dart:271`:

```dart
// before
child: CommandFrame(
  padding: const EdgeInsets.all(12),
  child: someChild,
),

// after
child: OrionSurface(
  tier: OrionSurfaceTier.t2,
  padding: const EdgeInsets.all(12),
  child: someChild,
),
```

- [ ] **Step 3: Delete the primitive and its test**

```bash
git rm lib/game/ui/command_frame.dart
find test -name '*command_frame*' -exec git rm {} +
```

- [ ] **Step 4: Verify nothing references it and the suite is green**

```bash
grep -rn 'CommandFrame\|commandFramePath' lib/ test/ || echo "clean"
flutter analyze && flutter test
```
Expected: `clean`, `No issues found!`, and the full suite passing. Test count may
drop if a `command_frame` test file existed — note the new number in the commit.

If a deleted test asserted behavior that still matters (as `ReactorButton`'s
semantics tests did in `5a27b2a`), migrate that assertion onto `OrionSurface`
rather than dropping it.

- [ ] **Step 5: Commit**

```bash
git add -u lib test
git commit -m "refactor: replace CommandFrame with tiered OrionSurface

The Revamp system sheet permits rounded surfaces only - no chamfer, no
bevelled plate - so the chamfered painter is deleted rather than left
importable, where a later scene PR could reintroduce the geometry.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Make `MissionSurface` an adapter

**Files:**
- Modify: `lib/game/ui/mission_surface.dart`

**Interfaces:**
- Consumes: `OrionSurface` (Task 5)
- Produces: `MissionSurface` unchanged in signature, now `@Deprecated`, delegating
  to `OrionSurface(tier: t2)` (or `t3` when `emphasized`).

- [ ] **Step 1: Write the failing test**

Append to `test/widget/orion_surface_test.dart`:

```dart
  testWidgets('MissionSurface delegates to a tiered OrionSurface', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: MissionSurface(child: Text('x'))),
    ));
    expect(find.byType(OrionSurface), findsOneWidget);
    expect(t.widget<OrionSurface>(find.byType(OrionSurface)).tier,
        OrionSurfaceTier.t2);
  });

  testWidgets('an emphasized MissionSurface is a t3 sheet', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: MissionSurface(emphasized: true, child: Text('x'))),
    ));
    expect(t.widget<OrionSurface>(find.byType(OrionSurface)).tier,
        OrionSurfaceTier.t3);
  });
```

Add `import 'package:orion/game/ui/mission_surface.dart';` to that file.

- [ ] **Step 2: Run to confirm failure**

```bash
flutter test test/widget/orion_surface_test.dart
```
Expected: FAIL — `MissionSurface` renders a `DecoratedBox`, not an `OrionSurface`.

- [ ] **Step 3: Rewrite the body**

Keep the constructor exactly as it is so all 15 call sites still compile. Replace
only `build`, and mark the class deprecated:

```dart
@Deprecated(
  'Use OrionSurface with an explicit tier. This adapter exists so the 15 '
  'pre-Revamp call sites convert incrementally; delete it in PR D.',
)
class MissionSurface extends StatelessWidget {
  // ...constructor unchanged...

  @override
  Widget build(BuildContext context) => OrionSurface(
        tier: emphasized ? OrionSurfaceTier.t3 : OrionSurfaceTier.t2,
        padding: padding,
        radius: radius,
        child: child,
      );
}
```

`backgroundColor` and `borderColor` are now ignored — the tier owns them. Check
whether any call site passes them:

```bash
grep -rn 'MissionSurface(' -A4 lib/ | grep -n 'backgroundColor\|borderColor'
```
If any does, that site is asserting a color the tier system now owns. Convert it to
the nearest tier and delete the override; do **not** add a passthrough.

- [ ] **Step 4: Run the full suite**

```bash
flutter test
```
Expected: all pass. Existing widget tests that assert `MissionSurface` colors may
now fail — those assertions were testing the old opaque fills and should be updated
to the tier's values, not reverted.

- [ ] **Step 5: Commit**

```bash
git add lib/game/ui/mission_surface.dart test/widget/orion_surface_test.dart
git commit -m "refactor: MissionSurface delegates to OrionSurface

Deprecated adapter so the 15 call sites convert incrementally rather
than in one commit alongside the CommandFrame removal.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Register crest and command-center art

**Files:**
- Modify: `lib/game/ui/orion_atlas_sprite.dart` (this is where `OrionArt` lives)
- Modify: `test/widget/orion_art_test.dart`

**Interfaces:**
- Consumes: assets from Task 6
- Produces: `OrionSceneArt.commandCenter`, and
  `OrionArt.crestFor(StageDefinition) -> OrionArtDescriptor`.

- [ ] **Step 1: Write the failing test**

Append to `test/widget/orion_art_test.dart`:

```dart
  test('every campaign stage has a crest descriptor', () {
    for (final stage in OrionCampaign.stages) {
      final crest = OrionArt.crestFor(stage);
      expect(crest.fileName, contains('crests/'));
      expect(crest.semanticLabel, isNotEmpty);
    }
  });

  test('commandCenter scene art is registered', () {
    expect(OrionSceneArt.values, contains(OrionSceneArt.commandCenter));
  });
```

Match `OrionCampaign.stages` to whatever the real accessor is:
```bash
grep -n 'stages' lib/game/campaign/orion_campaign.dart | head
```

- [ ] **Step 2: Run to confirm failure**

```bash
flutter test test/widget/orion_art_test.dart
```
Expected: FAIL — `crestFor` is undefined.

- [ ] **Step 3: Implement**

Add `commandCenter` to the `OrionSceneArt` enum and wire its filename
(`reactor_rim_ui/backdrops/command-center.png`) wherever the existing scene-art
filenames are resolved — follow the pattern already used for `worldMap`,
`techTree`, and `missionReport`; do not add a parallel lookup.

Add the crest registry beside the existing stage map, reusing `sourceRectFor`
(crests are 160×160, so the rect is the full image):

```dart
  static final Map<String, OrionArtDescriptor> _crests = Map.unmodifiable({
    for (final stage in OrionCampaign.stages)
      stage.id: OrionArtDescriptor(
        fileName: 'reactor_rim_ui/crests/${stage.id}.png',
        sourceRectFor: ({required imageWidth, required imageHeight}) =>
            ui.Rect.fromLTWH(0, 0, imageWidth, imageHeight),
        semanticLabel: '${stage.name} crest',
        fallbackIcon: Icons.shield_outlined,
      ),
  });

  static OrionArtDescriptor crestFor(StageDefinition stage) =>
      _crests[stage.id]!;
```

The seven `stage.id` values are already verified to match the committed crest
filenames exactly (`outpost-alpha`, `nebula-relay`, `salvage-rift`,
`asteroid-foundry`, `aurora-gate`, `void-bastion`, `singularity-core`), and this
mirrors the stage map's existing `reactor_rim_ui/stages/${stage.id}.png` convention
at `lib/game/ui/orion_atlas_sprite.dart:250`.

If a future stage id ever diverges, rename the **file** to match the id. Do not add a
`Map<String, String>` translation table — that would trip the existing
no-parallel-API tripwire at `test/widget/orion_art_test.dart:117`.

- [ ] **Step 4: Run to confirm passage**

```bash
flutter test test/widget/orion_art_test.dart
```
Expected: PASS, including the pre-existing no-parallel-API tripwire.

- [ ] **Step 5: Commit**

```bash
git add lib/game/ui/orion_atlas_sprite.dart test/widget/orion_art_test.dart
git commit -m "feat: register stage crests and the command-center backdrop

Crests reuse the existing sourceRectFor descriptor mechanism rather than
introducing a parallel path-string API.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Tasks 10–13: Migrate the 97 `textTheme` references

97 references across 14 files. Each task below is one commit and one test run, split
so a reviewer can reject one group while approving its neighbors. **Do not relayout
anything** — this is a style-source swap only. If a widget's size changes visibly,
the mapping is wrong.

**Mapping rules (identical for all four tasks):**

| Was | Becomes |
|---|---|
| `textTheme.labelSmall` on a label | `OrionTypography.microLabel(color: …)` |
| `textTheme.labelSmall` on a number | `OrionTypography.readout(size: 11, color: …)` |
| `textTheme.bodySmall` / `bodyMedium` | `OrionTypography.microLabel(size: 9, color: …)` |
| `textTheme.titleLarge` / `headlineSmall` | `OrionTypography.title(color: …)` |
| A bare number with a `/total` sibling | `OrionReadout(value:, denominator:)` |

Any `copyWith(color: uiTheme.textPrimary)` on a **label** must become a muted tone —
`OrionTypography.microLabel` throws on `textPrimary` by design. That throw is the
system sheet's "muted, never white" rule finding a real violation; fix the color,
do not work around the check.

### Task 10: Dock, HUD and toast

**Files:** `lib/game/ui/mission_command_dock.dart` (6),
`lib/game/ui/mission_command_hud.dart` (5), `lib/game/ui/command_toast.dart` (1),
`lib/game/ui/acquired_run_module_control.dart` (5) — 17 references

- [ ] **Step 1:** Apply the mapping table above to all 17 references.
- [ ] **Step 2:** `flutter test test/widget/ && flutter analyze` — expected: green.
- [ ] **Step 3:** `flutter test` — expected: full suite green.
- [ ] **Step 4:** Commit:
```bash
git add -u lib/game/ui
git commit -m "refactor: migrate dock and HUD type to Orion type roles

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 11: Sheets and panels

**Files:** `lib/game/ui/stage_briefing_sheet.dart` (9),
`lib/game/ui/mission_report_panel.dart` (11),
`lib/game/ui/run_module_draft_panel.dart` (7),
`lib/game/ui/feedback_settings_sheet.dart` (1) — 28 references

- [ ] **Step 1:** Apply the mapping table.
- [ ] **Step 2:** `flutter test test/widget/ && flutter analyze` — expected: green.
- [ ] **Step 3:** `flutter test` — expected: full suite green.
- [ ] **Step 4:** Commit:
```bash
git add -u lib/game/ui
git commit -m "refactor: migrate sheet and panel type to Orion type roles

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 12: Scanner, inspector, world map

**Files:** `lib/game/ui/next_wave_scanner.dart` (8),
`lib/game/ui/tower_inspector.dart` (8), `lib/game/ui/world_map_view.dart` (5),
`lib/game/ui/orion_game_page.dart` (2) — 23 references

- [ ] **Step 1:** Apply the mapping table.
- [ ] **Step 2:** `flutter test test/widget/ && flutter analyze` — expected: green.
- [ ] **Step 3:** `flutter test` — expected: full suite green.
- [ ] **Step 4:** Commit:
```bash
git add -u lib/game/ui
git commit -m "refactor: migrate scanner, inspector and map type to Orion roles

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 13: Codex and tech tree

**Files:** `lib/game/ui/codex_view.dart` (17), `lib/game/ui/tech_tree_view.dart` (12)
— 29 references

`codex_view.dart` passes `ThemeData` into private helpers (`_towerCard(ThemeData …)`).
Change those signatures to take `OrionUiTheme` instead, or drop the parameter and
read `OrionUiTheme.of(context)` — do not keep threading `ThemeData` through solely
for type.

- [ ] **Step 1:** Apply the mapping table and adjust the helper signatures.
- [ ] **Step 2:** `flutter test test/widget/ && flutter analyze` — expected: green.
- [ ] **Step 3:** `flutter test` — expected: full suite green.
- [ ] **Step 4:** Commit:
```bash
git add -u lib/game/ui
git commit -m "refactor: migrate codex and tech tree type to Orion type roles

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 14: The four tripwires

**Files:**
- Create: `test/widget/design_system_tripwire_test.dart`

**Interfaces:**
- Consumes: everything above
- Produces: nothing — this task only guards.

Written last, because three of the four cannot pass until Tasks 7–13 are complete.

- [ ] **Step 1: Write the tripwires**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/orion_typography.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

Iterable<File> _libDartFiles() sync* {
  for (final e in Directory('lib').listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}

void main() {
  test('only the four sanctioned blur values exist in lib/', () {
    final offenders = <String>[];
    final blur = RegExp(r'ImageFilter\.blur\(\s*sigmaX:\s*([0-9.]+)');
    for (final file in _libDartFiles()) {
      for (final m in blur.allMatches(file.readAsStringSync())) {
        final sigma = double.parse(m.group(1)!);
        if (!{6.0, 7.0, 12.0, 14.0}.contains(sigma)) {
          offenders.add('${file.path}: sigma $sigma');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'the system sheet ships four blur values; a fifth is a bug');
  });

  test('the chamfered CommandFrame primitive is gone', () {
    final offenders = [
      for (final file in _libDartFiles())
        if (file.readAsStringSync().contains('commandFramePath') ||
            file.readAsStringSync().contains('CommandFrame'))
          file.path,
    ];
    expect(offenders, isEmpty,
        reason: 'surfaces are rounded only: no chamfer, no bevelled plate');
  });

  test('game UI does not read Material TextTheme', () {
    final offenders = [
      for (final file in _libDartFiles())
        if (file.path.contains('/ui/') &&
            file.readAsStringSync().contains('textTheme'))
          file.path,
    ];
    expect(offenders, isEmpty,
        reason: 'type comes from OrionTypography, not Material roles');
  });

  test('microLabel cannot be white', () {
    expect(
      () => OrionTypography.microLabel(color: OrionUiTheme.dark.textPrimary),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 2: Run them**

```bash
flutter test test/widget/design_system_tripwire_test.dart
```
Expected: PASS (4 tests). A failure here is a real finding from Tasks 7–13 — fix the
offending file, not the tripwire.

- [ ] **Step 3: Run every gate**

```bash
flutter test
flutter analyze
dart format --output=none --set-exit-if-changed .
git diff --check
```
Expected: full suite green (≥857 minus any `command_frame` tests removed in Task 7),
no analyzer issues, no formatting diff, no whitespace errors.

- [ ] **Step 4: Commit**

```bash
git add test/widget/design_system_tripwire_test.dart
git commit -m "test: add design-system tripwires

Guards the four rules the system sheet states but code cannot otherwise
enforce: the blur budget, the chamfer ban, the TextTheme ban, and
muted-only micro-labels.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 15: Measure the blur budget on device

**Files:** none — this task produces a measurement and a decision.

The spec flags this as the one change that can cost frame budget: the app had zero
`BackdropFilter`s before this PR.

- [ ] **Step 1: Run the app on a device or simulator**

```bash
flutter run --profile -d <device-id>
```
Use a real iPhone if one is available; a simulator does not model GPU cost honestly.

- [ ] **Step 2: Drive a live wave and watch the raster thread**

Open DevTools' performance overlay. Start a wave on the busiest scene (1a) and let it
run to completion.

- [ ] **Step 3: Record the result**

Expected: raster stays under 16ms/frame. Record the observed worst-case raster time
in the PR description either way.

- [ ] **Step 4: Decide**

If raster exceeds 16ms, apply the spec's fallback — keep blur on `t3`/`t4` only and
make `t1`/`t2` opaque fills at the same colors — then re-measure and note the change
in the PR. Do **not** abandon translucency wholesale, and do not tune blur sigmas to
a fifth value; the tripwire in Task 14 will reject that.

- [ ] **Step 5: Commit only if the fallback was applied**

```bash
git add -u lib/game/ui/orion_surface.dart
git commit -m "perf: restrict blur to t3/t4 after on-device measurement

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 16: Open the PR

- [ ] **Step 1: Confirm the branch is clean and stacked correctly**

```bash
git log --oneline agent/hpa-9-reactor-rim-full-scene-parity-plan..HEAD
git status --short
```
Expected: the tasks above as separate commits, and an empty status.

- [ ] **Step 2: Push and open against #29's branch**

```bash
git push -u origin agent/orion-ui-revamp-foundation
gh pr create --base agent/hpa-9-reactor-rim-full-scene-parity-plan \
  --title "Orion UI Revamp (A/4): design-system foundation" \
  --body-file <(cat <<'BODY'
## Summary

Foundation layer of the Orion UI Revamp, from the Claude Design export
`Orion UI Revamp export.dc.html` (system sheet: scene 1i). **No scene layout
changes** — those land in PRs B/C/D.

- Two OFL typefaces vendored; three type roles replace 97 Material `textTheme` reads
- Four blurred surface tiers; `CommandFrame`'s chamfered painter deleted
- One new palette token (`sheetBlack`), named motion durations
- Nine art assets: 7 stage crests, 1 board skin, 1 command-center backdrop
- Four tripwires guarding the blur budget, the chamfer ban, the `TextTheme` ban,
  and muted-only micro-labels

## What this reverses from #29

The export asserts several things #29 shipped as "intentional deviation". This PR
lands only the typography reversal; the rest are scoped to later PRs and listed in
the spec's deferred items.

## Known export error, not implemented

Scene 1b shows `≤6 TOWER CAP`. Orion has no tower-cap rule and #29 removed it for
that reason. That removal stands.

## Art provenance

`DesignSync.get_file` silently truncates at 256 KiB, returning PNGs that `file(1)`
still reports as valid. All nine assets were extracted from the project's standalone
bundle instead and verified for a trailing `IEND` chunk. `board_foundry` and
`board_void` are deliberately absent — no scene references them.

## Spec

`docs/superpowers/specs/2026-09-08-orion-ui-revamp-foundation-design.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01MRREESz3AquBzwMNdsy3dt
BODY
)
```
