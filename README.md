# Orion

Orion is a portrait, touch-first space tower-defense game built with Flutter and
Flame.

## Local Development

Install dependencies:

```bash
flutter pub get
```

Run the app:

```bash
flutter run
```

Run the local checks:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release
```

## Git Hooks

Install the repo-owned pre-commit hook once per checkout:

```bash
scripts/install-git-hooks.sh
```

The pre-commit hook checks Dart formatting and runs `flutter analyze`.

## Continuous Integration

GitHub Actions runs two jobs on pushes to `main` and on pull requests:

- `Build & lint`: installs dependencies, checks formatting, runs
  `flutter analyze`, and builds the web target.
- `Unit test`: installs dependencies and runs `flutter test`.
