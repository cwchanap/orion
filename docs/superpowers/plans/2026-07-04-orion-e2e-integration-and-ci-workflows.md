# E2E Integration Test & CI Build Workflows — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a smoke-level Flutter integration test and three GitHub Actions workflows (tests, Android build verification, iOS build verification).

**Architecture:** One new integration-test file drives the real `OrionApp` on an Android emulator (world-map → enter stage → place tower → start wave). Three workflow files run on identical triggers (push to main, PRs, weekly, manual) as independent parallel status checks: `ci.yml` (unit/widget tests + the integration test), `build-android.yml`, and `build-ios.yml` (both build-verification only, no signing/artifacts).

**Tech Stack:** Flutter `>=3.44.0` / Dart `^3.12.0`, Flame `^1.37.0`, the built-in `integration_test` SDK package, GitHub Actions (`subosito/flutter-action@v2`, `actions/setup-java@v4`, `reactivecircus/android-emulator-runner@v2`).

## Global Constraints

- **Dart SDK** `^3.12.0`; **Flutter** `>=3.44.0`; **flame** `^1.37.0` (do not change).
- **Java** Temurin **17** for any Android build/integration job (matches `JavaVersion.VERSION_17` in `android/app/build.gradle.kts`).
- Build commands are exactly: Android `flutter build apk --debug`; iOS `flutter build ios --debug --no-codesign`. No signing, no artifact upload.
- Triggers for every workflow: `push` on `main`, `pull_request` on `main`, `schedule: cron: '0 6 * * 1'`, `workflow_dispatch`. Each workflow has its own `concurrency` group.
- Integration test runs on an **Android emulator only** (ubuntu) with software rendering (`swiftshader_indirect`).
- **Never use `tester.pumpAndSettle()` in the integration test** — a live Flame game loop continuously schedules frames, so `pumpAndSettle` never reaches quiescence and times out on a real device. Use the bounded `_pumpUntil` polling helper only.
- Follow existing repo conventions: no comments unless asked; match existing test style in `test/`.

---

## File Structure

- **Create** `integration_test/app_smoke_test.dart` — the single smoke test (created in Task 1, extended in Task 2).
- **Modify** `pubspec.yaml` — add `integration_test` SDK to `dev_dependencies`.
- **Create** `.github/workflows/ci.yml` — `unit-tests` + `integration-test` jobs.
- **Create** `.github/workflows/build-android.yml` — Android debug build verification.
- **Create** `.github/workflows/build-ios.yml` — iOS debug build verification (macos runner, `--no-codesign`).

No production (`lib/`) code changes are required — the app already exposes everything the test drives through the widget tree.

---

### Task 1: Add `integration_test` dependency and boot-to-world-map smoke

**Files:**
- Modify: `pubspec.yaml` (the `dev_dependencies:` block)
- Create: `integration_test/app_smoke_test.dart`

**Interfaces:**
- Consumes: `OrionApp` from `package:orion/main.dart`.
- Produces: a working integration-test harness (binding + `_pumpUntil` helper) that Task 2 extends; the file `integration_test/app_smoke_test.dart` is the artifact later workflows run via `flutter test integration_test`.

- [ ] **Step 1: Add the `integration_test` SDK dependency**

In `pubspec.yaml`, add `integration_test` to the `dev_dependencies` block (right after the `flutter_test` entry):

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter

  integration_test:
    sdk: flutter

  # The "flutter_lints" package below contains a set of recommended lints to
  # encourage good coding practices...
  flutter_lints: ^6.0.0
```

- [ ] **Step 2: Create the boot-only smoke test**

Create `integration_test/app_smoke_test.dart` with exactly this content (the harness + the boot assertion only; Task 2 adds the interactions):

```dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:orion/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boots into the Orion world map', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const OrionApp());
    });

    await _pumpUntil(tester, () => tester.any(find.text('Orion Sector Map')));

    expect(find.text('Orion Sector Map'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Start Wave'), findsNothing);
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Condition was not met within $timeout.');
}
```

Notes for the implementer:
- `runAsync` is required for the first pump so Flame's async image loading and the real `SharedPreferences` platform call can complete.
- `_pumpUntil` polls in 100 ms steps instead of `pumpAndSettle` (Flame's loop never settles on a real device).
- The world-map stage node renders `mapLabel` = `Alpha` (not "Outpost Alpha"); the HUD shows "Outpost Alpha" only after entering the stage.

- [ ] **Step 3: Fetch deps and confirm static analysis is clean**

Run: `flutter pub get`
Expected: resolves `integration_test` with no errors.

Run: `flutter analyze`
Expected: "No issues found!" (the new test file is analyzed like any other).

- [ ] **Step 4: Run the boot smoke on a running Android emulator**

Boot an Android emulator (via Android Studio Device Manager or `flutter emulators --launch <id>`; check `flutter devices` shows it), then:

Run: `flutter test integration_test/app_smoke_test.dart`
Expected: PASS (1 test). If it times out finding "Orion Sector Map", confirm an emulator/device is selected with `flutter devices` and that the app boots manually via `flutter run`.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml integration_test/app_smoke_test.dart
git commit -m "test: add integration test harness with boot smoke"
```

---

### Task 2: Extend the smoke test to place a tower and start a wave

**Files:**
- Modify: `integration_test/app_smoke_test.dart`

**Interfaces:**
- Consumes: `GameBalance.startingGold`, `GameBalance.towerStats(TowerType.laser, level: 1).cost`, `BoardLayout` (columns/rows + path data), `GridPosition`, `TowerType`, and the Flame `GameWidget` type for coordinate computation.
- Produces: the complete smoke scenario that `ci.yml` (Task 3) runs.

- [ ] **Step 1: Replace the boot test with the full smoke scenario**

Replace the entire contents of `integration_test/app_smoke_test.dart` with:

```dart
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/board_layout.dart';
import 'package:orion/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('places a tower and starts a wave', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const OrionApp());
    });

    // 1. World map is showing with the first stage ("Alpha").
    await _pumpUntil(tester, () => tester.any(find.text('Orion Sector Map')));
    expect(find.text('Alpha'), findsOneWidget);

    // 2. Enter the first stage.
    await tester.tap(find.text('Alpha'));
    await _pumpUntil(tester, () => tester.any(find.text('Outpost Alpha')));
    expect(find.text('Outpost Alpha'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);

    final startingGold = GameBalance.startingGold;
    final laserCost = GameBalance.towerStats(TowerType.laser, level: 1).cost;

    // 3. Tap the center of a known buildable cell to open the tower picker.
    //    Cell (0,0) is never on the enemy path (see BoardLayout.pathCells).
    await tester.tapAt(_cellCenter(tester, const GridPosition(0, 0)));
    await _pumpUntil(tester, () => tester.any(find.text('Build Tower')));
    expect(find.text('Build Tower'), findsOneWidget);

    // 4. Place a Laser tower; gold decreases and the picker closes.
    await tester.tap(find.text('Laser $laserCost'));
    await _pumpUntil(
      tester,
      () => tester.any(find.text('Gold ${startingGold - laserCost}')),
    );
    expect(find.text('Gold ${startingGold - laserCost}'), findsOneWidget);
    expect(find.text('Build Tower'), findsNothing);

    // 5. Start a wave; the phase chip flips from Build to Wave Active.
    await tester.tap(find.text('Start Wave'));
    await _pumpUntil(tester, () => tester.any(find.text('Wave Active')));
    expect(find.text('Wave Active'), findsOneWidget);
    expect(find.text('Build'), findsNothing);
  });
}

Offset _cellCenter(WidgetTester tester, GridPosition cell) {
  // The GameWidget fills the SafeArea; the board is centered inside it.
  final boardRect = tester.getRect(find.byType(GameWidget));
  final cellSize = (boardRect.width / BoardLayout.columns)
      .clamp(0.0, boardRect.height / BoardLayout.rows);
  final boardWidth = BoardLayout.columns * cellSize;
  final boardHeight = BoardLayout.rows * cellSize;
  final origin = Offset(
    boardRect.left + (boardRect.width - boardWidth) / 2,
    boardRect.top + (boardRect.height - boardHeight) / 2,
  );
  return Offset(
    origin.dx + (cell.column + 0.5) * cellSize,
    origin.dy + (cell.row + 0.5) * cellSize,
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Condition was not met within $timeout.');
}
```

Why this is robust (for the implementer):
- `_cellCenter` replicates `OrionDefenseGame._layoutBoard` exactly (`cellSize = (w/cols).clamp(0, h/rows)`, centered origin), computed against the live `GameWidget` rect, so it is screen-size independent.
- Cell `(0,0)` is not in `BoardLayout.pathCells`, so it is always buildable. Its center is at the top of the board, away from the (pointer-capturing) bottom controls.
- Assertions are on HUD text driven by the `GameSnapshot` (`ValueListenableBuilder`), not Flame internals — the same channel the player sees.
- The tower-button label format is `"Laser $cost"` (see `_TowerButton` in `lib/game/ui/orion_game_page.dart`); computing the cost from `GameBalance` keeps the test stable under tuning changes.

- [ ] **Step 2: Confirm static analysis is clean**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Run the full smoke on a running Android emulator**

Run: `flutter test integration_test/app_smoke_test.dart`
Expected: PASS (1 test) covering boot → enter stage → place tower → start wave. If "Build Tower" never appears, the cell-center math is off — print `_cellCenter(...)` and confirm it lands inside the rendered `GameWidget` rect.

- [ ] **Step 4: Commit**

```bash
git add integration_test/app_smoke_test.dart
git commit -m "test: extend smoke test to place tower and start wave"
```

---

### Task 3: Add `ci.yml` (unit/widget tests + integration test)

> **Execution amendment (2026-07-05):** The greenfield workflow below is **superseded** — see the design spec's [Execution amendment (2026-07-04)](../specs/2026-07-04-orion-e2e-integration-and-ci-workflows-design.md#execution-amendment-2026-07-04). A `ci.yml` already existed on `main` with a `build_lint` job (`dart format` gate, `flutter analyze`, `flutter build web --release`) and a `unit_test` job (`flutter test --coverage` + Codecov OIDC). The actual implementation **preserved those jobs** and only appended a new `integration-test` job. The YAML in Step 1 below is retained for plan-history fidelity only; do not re-create `ci.yml` from it. Subsequent review hardening (SHA-pinned actions, Gradle cache, `ubuntu-22.04` for the emulator job, Codecov upload gated to non-fork runs) is reflected in the committed `.github/workflows/ci.yml`, not in the snippet below.

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the test suites (`test/`, `integration_test/`) from Tasks 1–2.
- Produces: two independent status checks (`unit-tests`, `integration-test`) that gate PRs.

- [ ] **Step 1: Create the workflow file**

Create `.github/workflows/ci.yml` with exactly this content:

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 6 * * 1'
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - run: flutter pub get

      - run: flutter analyze

      - run: flutter test

  integration-test:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - run: flutter pub get

      - name: Run integration tests on Android emulator
        uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: 34
          target: google_apis
          arch: x86_64
          profile: pixel
          script: flutter test integration_test
```

Notes for the implementer:
- The two jobs run in parallel; a flaky emulator never blocks the unit suite.
- `reactivecircus/android-emulator-runner` uses `-gpu swiftshader_indirect` (software rendering) by default on Linux, which Flame needs headlessly.
- `flutter test integration_test` (not `flutter drive`) is the correct modern invocation — it runs every file under `integration_test/` on the booted device.

- [ ] **Step 2: Validate the YAML parses**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo OK`
Expected: `OK` (no traceback). If python3 is unavailable, any YAML linter (`npx -y yaml-lint .github/workflows/ci.yml`) is fine.

- [ ] **Step 3: Locally confirm the commands the `unit-tests` job runs**

Run: `flutter analyze && flutter test`
Expected: analyze reports "No issues found!" and all tests pass.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add unit/widget tests and Android integration test workflow"
```

---

### Task 4: Add `build-android.yml` (Android build verification)

**Files:**
- Create: `.github/workflows/build-android.yml`

**Interfaces:**
- Consumes: the Android platform in `android/`.
- Produces: an `ubuntu-latest` status check that verifies the Android app compiles + links as a debug APK.

- [ ] **Step 1: Create the workflow file**

Create `.github/workflows/build-android.yml` with exactly this content:

```yaml
name: build-android

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 6 * * 1'
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-android:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - run: flutter pub get

      - run: flutter build apk --debug
```

- [ ] **Step 2: Validate the YAML parses**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-android.yml'))" && echo OK`
Expected: `OK`.

- [ ] **Step 3: Locally confirm the build command succeeds**

Run: `flutter build apk --debug`
Expected: build completes with no errors (it produces a debug APK under `build/app/outputs/...`; we do not upload it).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/build-android.yml
git commit -m "ci: add Android debug build verification workflow"
```

---

### Task 5: Add `build-ios.yml` (iOS build verification, no codesign)

**Files:**
- Create: `.github/workflows/build-ios.yml`

**Interfaces:**
- Consumes: the iOS platform in `ios/`.
- Produces: a `macos-latest` status check that verifies the iOS app compiles + links without any signing identity.

- [ ] **Step 1: Create the workflow file**

Create `.github/workflows/build-ios.yml` with exactly this content:

```yaml
name: build-ios

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 6 * * 1'
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-ios:
    runs-on: macos-latest
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - run: flutter pub get

      - run: flutter build ios --debug --no-codesign
```

Notes for the implementer:
- `--no-codesign` is mandatory — it skips code signing so the build succeeds with no provisioning profile.
- This relies on the runner's default Xcode. If it ever fails on a runner-image Xcode bump, pin with `maxim-lobanov/setup-xcode@v1` — out of scope for now.

- [ ] **Step 2: Validate the YAML parses**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-ios.yml'))" && echo OK`
Expected: `OK`.

- [ ] **Step 3: Locally confirm the iOS build command succeeds (requires macOS host)**

Run: `flutter build ios --debug --no-codesign`
Expected: build completes with no errors. (On non-macOS hosts, skip this step — note "skipped, requires macOS" in the task report and rely on the workflow's first run.)

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/build-ios.yml
git commit -m "ci: add iOS debug build verification workflow"
```

---

## Final verification

After all five tasks:

- [ ] `flutter analyze` → "No issues found!"
- [ ] `flutter test` → all unit/widget tests pass.
- [ ] `flutter test integration_test/app_smoke_test.dart` → passes on an Android emulator.
- [ ] `flutter build apk --debug` → succeeds.
- [ ] `flutter build ios --debug --no-codesign` → succeeds (on macOS).
- [ ] All three workflow YAMLs parse.
- [ ] On push/PR, all four status checks (`unit-tests`, `integration-test`, `build-android`, `build-ios`) appear and go green. (First real verification happens on the initial push that contains these files.)
