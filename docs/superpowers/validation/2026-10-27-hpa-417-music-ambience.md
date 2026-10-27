# HPA-417 music and ambience: validation and acceptance

Date: 2026-10-27

## Discovery

- A paired physical iPhone (iOS 27.0.1, connected over Wi-Fi) was found. Flutter refused to install because Developer Mode is disabled. The spike did not launch, so it produced no playback or native-player observations.
- Android could not be enumerated because `adb` is not installed. No Android device spike ran.
- The installed dependency set is available offline: `flame_audio` 2.12.2 and transitive `audioplayers` 6.8.1. The app lockfile pins those versions.
- A disposable iOS spike and generated 2-second PCM tone were created under ignored `tmp/` and removed after the install attempt. No project assets or runtime files changed.

## Attempted commands

| Command | Result |
| --- | --- |
| `rtk proxy xcrun devicectl list devices` (sandbox) | Exit 1; CoreDeviceService initialization timed out. |
| `rtk flutter devices` (sandbox) | Exit 1; Flutter SDK cache writes failed with `Operation not permitted`. |
| `rtk proxy xcrun devicectl list devices` (escalated) | Exit 0; found a paired physical iPhone (`<device-id>`) as available. |
| `rtk flutter devices` (escalated) | Exit 0; found that iPhone wirelessly on iOS 27.0.1. |
| `rtk proxy adb devices -l` | Exit 1; `adb: No such file or directory`. |
| `rtk flutter pub get --offline` (disposable spike) | Exit 0; resolved `flame_audio` 2.12.2 and `audioplayers` 6.8.1 from local cache. |
| `rtk flutter run --no-pub --debug --device-id <device-id>` | Exit 1 before install: Flutter requires Developer Mode to be enabled on the phone. |

## Runtime implementation and review

The runtime implementation is at `5dddd0b` (`fix(audio): preserve shared context for game SFX`). It adds the independent Music preference and settings switch, a pure track selector and serialized controller with a lazy page-owned `Bgm`, a live read-only boss projection, page lifecycle/navigation synchronization, and startup audio context shared by music and SFX. The code-only asset contract test is present and gated on HPA-168 files.

The scoped diff from `54ddbe8` contains no music binaries, generator, `pubspec.yaml`/lockfile or dependency edits, and no gameplay or balance tuning. Boss activity is projected from live enemy components. Tasks 0–4 had separate implementation reviews and all passed; the Task 4 review reported no Critical or Important findings. Task 5 reviewed the exact source commit and found no code drift.

## Automated validation

| Check | Result |
| --- | --- |
| `rtk dart format --output=none --set-exit-if-changed lib/game/feedback lib/game/ui/orion_game_page.dart lib/game/orion_defense_game.dart lib/game/ui/feedback_settings_sheet.dart test` | Exit 0; 89 files checked, 0 changed. |
| `rtk flutter test test/game/feedback_preferences_test.dart test/feedback/shared_preferences_feedback_store_test.dart test/widget/feedback_settings_sheet_test.dart test/feedback/game_music_test.dart test/feedback/audio_asset_contract_test.dart` | Exit 0; 43 passed, 1 skipped for the four absent HPA-168 WAVs. |
| `rtk flutter analyze` | Reused Task 4 result at the exact same source commit: no issues found. |
| `rtk flutter test` | Reused Task 4 captured result at the exact same source commit: exit 0, 1,281 passed, 1 HPA-168 asset skip. |
| `rtk flutter test test/widget/mission_collapsible_test.dart` | Exit 0; 8 passed. It reproduces the probe tap warnings recorded in Task 4; the test and `MissionCollapsible` are unchanged from `54ddbe8`. |

Full-suite and analyzer checks were not rerun because the checkout was clean at `5dddd0b` and Task 5 changes only validation/status documentation. Durable, ignored command logs are in `.superpowers/sdd/2026-10-25-hpa-417-music-ambience/scratch/`; the full-suite log is `task-4-full-test.log`. The test runner's throwing audio-channel stubs still produce caught/logged native-player failures in page smoke tests; these are visible in the captured full log and did not escape as test failures.

The isolated mission-collapse test also passes while emitting Flutter's missed-hit-test warnings for its probe widgets. This test harness warning predates HPA-417; no unrelated component or input tests were changed.

## Acceptance gates — still pending

- [ ] HPA-168 merges all four music files and their explicit asset declarations; the asset-contract test runs without skipping and verifies format, duration, and size.
- [ ] Real-device listening verifies each loop seam, audibility relative to SFX, and stop/restart behavior.
- [ ] iOS Silent switch, external-audio mixing, and interruption behavior are verified on device.
- [ ] Android physical playback, lifecycle behavior, and calls/other-app audio behavior are verified on device.
- [ ] One documented iOS and Android listening pass completes the acceptance matrix.

The gates remain unchecked: `music_{map,build,wave,boss}.wav` are absent, the paired iPhone cannot install while Developer Mode is disabled, and `adb` is unavailable. The early iOS spike stopped before installation and did not instantiate `Bgm`; no audible behavior has been verified.
