# E2E Integration Test & CI Build Workflows — Design

**Date:** 2026-07-04
**Scope:** Add a smoke-level integration (e2e) test for the app and GitHub Actions workflows for (a) automated tests, (b) Android build verification, and (c) iOS build verification.

## Goals

- Catch regressions in app wiring / UI flow that the pure-logic unit suite can't see (app boot, navigation into a stage, tower placement via the real widget tree + Flame taps, starting a wave).
- Verify the app compiles and links on both supported platforms (Android, iOS) on every change.
- Run automatically on pushes to `main`, on PRs, on a weekly schedule (to catch runner-image / dependency drift), and on manual dispatch.

## Non-goals

- Full win/lose playthroughs (too slow/brittle for CI; the logic layer is already covered by `test/game/`).
- Generating downloadable or signed release artifacts. Builds are verification-only.
- App Store / Play Store signing, Fastlane, or release distribution.
- iOS integration tests (iOS stays covered by build verification + the unit suite; macOS runners are scarce and the iOS simulator + Flame GL is flaky on CI).

## Decisions

| Decision | Choice |
|---|---|
| Integration test scope | Smoke only (boot, enter stage, place a tower, start a wave) |
| Build artifacts | Verification only — debug build, no upload, no signing |
| Triggers | `push` to main + `pull_request` to main + weekly schedule + `workflow_dispatch` |
| Integration test platform | Android emulator only (ubuntu runner) |
| Workflow organization | 3 separate files: `ci.yml`, `build-android.yml`, `build-ios.yml` |

## Architecture

### Workflow organization (three files)

Three independent workflow files, each with its own trigger block and `concurrency` group. They run in **parallel** as separate status checks — no cross-file `needs:` gating.

- `.github/workflows/ci.yml` — unit + widget tests + the integration test (two jobs).
- `.github/workflows/build-android.yml` — Android build verification.
- `.github/workflows/build-ios.yml` — iOS build verification.

**Rationale:** clean separation of concerns; build failures don't muddy test feedback; each workflow is independently re-runnable from the Actions UI; the scarce/slow macOS runner is isolated so its flakiness never blocks Android or tests. The cost is ~5 lines of duplicated trigger YAML, which is easy to keep in sync.

### Shared trigger block

Every workflow uses:

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 6 * * 1'   # Mon 06:00 UTC — catches runner/dependency drift
  workflow_dispatch:
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

`cancel-in-progress: true` cancels superseded runs on the same branch (saves runner minutes on rapid pushes). The schedule runs against the default branch.

## Component design

### 1. Integration test — `integration_test/app_smoke_test.dart`

**Dependency:** add `integration_test` SDK package to `dev_dependencies` in `pubspec.yaml`. No `test_driver/` directory is required — modern `flutter test integration_test/` runs directly on a booted device/emulator without `flutter drive`.

**Binding:** `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` at the top of `main()`.

**Approach — true UI-driven e2e:** pump the real `OrionApp` from `lib/main.dart` and drive the actual widget tree plus Flame board taps. This is the point of a smoke test: it exercises the real wiring (`OrionApp` → `OrionGamePage` → `WorldMapView` → `OrionDefenseGame` → `GameSnapshot` → HUD). Async sprite-sheet + campaign-progress loading is covered by a `tester.runAsync` block.

**Smoke scenario — single `testWidgets`, five assertions:**

1. **Boot.** Pump `OrionApp`. Wait for the World Map. Expect to find the first stage name (`"Outpost Alpha"`) as a selectable element.
2. **Enter stage.** Tap the `"Outpost Alpha"` stage. Pump until the HUD shows `"Outpost Alpha"`, the `"Build"` phase chip, and a `"Start Wave"` button (bottom controls `ValueKey('start-wave')`).
3. **Select a buildable cell.** Compute a non-path cell using `BoardLayout` (its `pathCells` set + 8×12 grid) and tap the pixel center of that cell inside the rendered `GameWidget`'s global rect. Expect the tower picker to appear (`"Build Tower"` text / `ValueKey('tower-picker')`).
4. **Place a tower.** Tap a tower button (e.g. `"Laser 50"`). Pump until the `Gold` status chip decreases from its starting value and the bottom controls return to `"Start Wave"` (i.e. `selectedCell` cleared and placement succeeded).
5. **Start a wave.** Tap `"Start Wave"`. Expect the phase chip to flip from `"Build"` to `"Wave Active"`.

**Why this is robust:**
- Cell selection is computed from `BoardLayout`'s path data relative to the live `GameWidget` rect, so it is screen-size independent and survives layout changes.
- All assertions are on HUD text driven by the `GameSnapshot` (`ValueListenableBuilder`) — the same channel the player sees — not Flame internals.
- Step 4 verifies the full loop: board tap → `GameSession` logic → new `GameSnapshot` → UI rebuild → observable gold change.

**Harness details:**
- Use `tester.runAsync(() async { ... })` for the initial pump so Flame's async image loading (sprite sheets) and `SharedPreferences` campaign-progress loading complete.
- Use `tester.tap` + `tester.pumpAndSettle()` (with a bounded `Duration`) between steps; fall back to `waitUntil*`-style polling on the gold/phase chips since some transitions are frame-driven.

### 2. `ci.yml` — two parallel jobs

**Job `unit-tests`** (`ubuntu-latest`):
- `actions/setup-java@v4` — Temurin **17** (matches `JavaVersion.VERSION_17` in `android/app/build.gradle.kts`).
- `subosito/flutter-action@v2` — `channel: stable` (satisfies `flutter >=3.44.0`), `cache: true`.
- Steps: `flutter pub get` → `flutter analyze` → `flutter test`.
- Covers the existing `test/game/` and `test/widget_test.dart` suites.

**Job `integration-test`** (`ubuntu-latest`):
- Same Java + Flutter setup.
- Boot the Android emulator with `reactivecircus/android-emulator-runner@v2`:
  - `api-level: 34`, `arch: x86_64`, `target: google_apis`, `profile: pixel`.
  - `script: flutter test integration_test` runs once the emulator is booted.
- Flame requires GL; the runner uses **`-gpu swiftshader_indirect`** (software rendering) on Linux so the game renders headlessly. (Handled by the action's defaults on Linux.)

**Why two jobs:** unit feedback lands in ~2 min without waiting for emulator boot (~5–8 min); an emulator flake never blocks the unit suite, and vice-versa. `flutter analyze` stays on the unit job so it gates every PR.

### 3. `build-android.yml` (`ubuntu-latest`)

- Java Temurin **17** + Flutter `stable` (`cache: true`).
- `flutter pub get` → `flutter build apk --debug`.
- Debug build = fastest compile/link verification, no signing required.
- No artifact upload (verification-only).
- Future upgrade path: switch to `--release` (the gradle release type is already debug-signed) to also cover R8/tree-shaking.

### 4. `build-ios.yml` (`macos-latest`)

- Flutter `stable` (`cache: true`). Rely on the runner's default Xcode (can pin via `maxim-lobanov/setup-xcode` if it ever flakes).
- `flutter pub get` → `flutter build ios --debug --no-codesign`.
- `--no-codesign` is the key flag — verifies compile + link without any signing identity.
- macOS runner is the slowest/scarcest piece of the setup; it is isolated in its own workflow so a flake here never blocks Android or tests.

## Testing & verification

- The integration test is itself the new test artifact; it is verified by running `flutter test integration_test/` locally on an Android emulator before relying on CI.
- The three workflows are verified by triggering them on a feature branch (via `workflow_dispatch` and a draft PR) and confirming all green.
- Existing `flutter test` / `flutter analyze` must remain green — `ci.yml` enforces this on every PR.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Android emulator boot flakiness on CI | Isolated as its own job; `cancel-in-progress`; can re-run just that job. `swiftshader_indirect` avoids GPU dependency. |
| Flame GL not rendering headlessly | `swiftshader_indirect` software rendering; assertions are on HUD text (Flutter widgets), not Flame pixel output. |
| iOS runner scarcity / Xcode version drift | Isolated workflow; can pin Xcode if needed. Weekly schedule catches drift early. |
| Board cell tap coordinates depend on screen size | Computed relative to the live `GameWidget` rect using `BoardLayout`'s grid math. |
| Weekly schedule burns minutes | Single cron, low-traffic `0 6 * * 1`; `cancel-in-progress` applies. |

## Out of scope (future work)

- Signed release artifacts / TestFlight / Play Store (needs signing secrets + Fastlane).
- Full win/lose playthrough integration tests.
- iOS integration tests.
- Branch-protection rules requiring these status checks (a GitHub repo-settings task, not code).

## Execution amendment (2026-07-04)

The original spec was written assuming greenfield CI ("no `.github/workflows/` at all yet"). That was incorrect: a committed `.github/workflows/ci.yml` already existed on `main` with a `build_lint` job (`dart format` gate, `flutter analyze`, `flutter build web --release`) and a `unit_test` job (`flutter test --coverage` + Codecov OIDC). After user confirmation, the implementation **preserved those jobs byte-for-byte** and only (a) added `schedule` + `workflow_dispatch` triggers and (b) appended a new `integration-test` (Android emulator) job. Nothing on `main` was dropped.

Other deviations from the original plan, all empirically forced and reviewer-verified:
- `build-android.yml` and `build-ios.yml` pin `actions/checkout@v7` + `subosito/flutter-action@v2.23.0` (matching the existing `ci.yml`) instead of the plan's older pins.
- The Android jobs (`integration-test`, `build-android`) add `actions/setup-java@v4` (Temurin 17) since `android/app/build.gradle.kts` pins `VERSION_17`; the existing `ci.yml` jobs don't build Android and legitimately omit Java.
- The integration test uses `find.bySubtype<GameWidget>()` (not `find.byType(GameWidget)`, which matches zero widgets because `GameWidget` is generic), a bounded retry-tap loop (board geometry is set in async `onLoad`, after the HUD renders), and a dual-condition wait (the `AnimatedSwitcher` keeps the outgoing picker widget alive ~160 ms). No `pumpAndSettle` is used anywhere.
