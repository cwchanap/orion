# HPA-927 — Last Hearth SFX validation (2026-11-23)

Scope: assets, generator, Python contract and `pubspec.yaml` only. No `lib/`, `test/` or image changes (`git diff --name-only main...HEAD`).

## Commands (local, branch head)

| Check | Result |
| --- | --- |
| `python3 -m unittest discover -s scripts -p 'test_*.py'` | 9 tests OK; 1 skipped (music regeneration, `music_sources/` is private). The SFX regeneration + corrupt-source test **ran** with the private sources present. |
| `dart format --output=none --set-exit-if-changed .` | exit 0 |
| `flutter analyze` | No issues found |
| `flutter test` | 1981 tests, all passed |
| `flutter build web --release` | built; `build/web/assets/assets/audio/` holds 30 WAVs (26 SFX + 4 music) |
| `confirm.wav`, `clear.wav`, 4 × `music_*.wav` | byte-identical to `main` (`git diff --quiet`) |

Final-head PR CI: pending push (see below).

## MCP web check (Playwright, real release build served on localhost, 390×844)

- Title → Continue → Start Mission → Start Wave on Outpost Alpha. The wave ran; the log shows `wave_start.wav` fetched at wave start and the replaced combat WAVs (`fire_*`, `impact_*`, `enemy_destroyed`, `core_hit`) fetched by the feedback warm-up, all `200`.
- In-page `fetch` + `AudioContext.decodeAudioData` of all 26 SFX: every file `200`, 1 channel, 44,100 Hz, durations as mastered. This covers the five new files (`flare_launch` 750 ms, `recruit_reveal` 510 ms, `recruit_reveal_rare` 1020 ms, `level_up` 1320 ms, `scrip_gain` 1500 ms), which gameplay does not trigger until HPA-926.
- One battle screenshot: [`hpa-927-battle-390x844.png`](hpa-927-battle-390x844.png). It renders normally. No UI, image or Dart file changed in this PR, so any difference from the current baseline is outside it by construction. It was **not** pixel-diffed against the HPA-921 mockup; the remaining sci-fi copy and lane styling are HPA-926 work.

## Not verified

- **Perceptual quality and 1×/3× readability are unverified.** One take per cue was generated and chosen by objective measures only (onset, decay, headroom); nobody listened to the masters or to a real wave. Durations are `active length + 50 ms`, capped at the filename tier, so long takes (e.g. `boss_defeated`, an 18 s take cropped to 500 ms) keep only their opening.
- Distribution rights for the 26-file set are not yet confirmed by the generating account owner (README says so).
