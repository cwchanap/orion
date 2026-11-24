# HPA-927 — Last Hearth SFX validation (2026-11-23)

Scope: assets, generator, Python contract and `pubspec.yaml` only. No `lib/`, `test/` or game image-asset changes (`git diff --name-only main...HEAD`); the only image added is the screenshot below.

## Commands (local, branch head)

| Check | Result |
| --- | --- |
| `python3 -m unittest discover -s scripts -p 'test_*.py'` | 10 tests OK; 1 skipped (music regeneration, `music_sources/` is private). The SFX regeneration, corrupt-last-source fail-before-write and duration-exceeds-source tests **ran** with the private sources present. |
| `dart format --output=none --set-exit-if-changed .` | exit 0 |
| `flutter analyze` | No issues found |
| `flutter test` | 1981 tests, all passed |
| `flutter build web --release` | built; `build/web/assets/assets/audio/` holds 30 WAVs (26 SFX + 4 music) |
| `confirm.wav`, `clear.wav`, 4 × `music_*.wav` | byte-identical to `main` (`git diff --quiet`) |

Final-head PR CI: pending push (see below).

## MCP web check (Playwright, real release build served on localhost, 390×844)

- Title → Continue → Start Mission → Start Wave on Outpost Alpha. The wave ran; the log shows `wave_start.wav` fetched at wave start and the replaced combat WAVs (`fire_*`, `impact_*`, `enemy_destroyed`, `core_hit`) fetched by the feedback warm-up, all `200`.
- In-page `fetch` + `AudioContext.decodeAudioData` of all 26 SFX: every file `200`, 1 channel, 44,100 Hz, durations as then mastered (`flare_launch` 750 ms, `recruit_reveal` 510 ms, `recruit_reveal_rare` 1020 ms, `level_up` 1320 ms, `scrip_gain` 1500 ms for the five new files, which gameplay does not trigger until HPA-926). This decode ran before the `861d577` re-master that shortened `recruit_reveal_rare` to 0.99 s (see below); the shipped WAV header and `sfx_provenance.json` both record 0.99 s.
- One battle screenshot: [`hpa-927-battle-390x844.png`](hpa-927-battle-390x844.png). It renders normally. No UI, image or Dart file changed in this PR, so any difference from the current baseline is outside it by construction. Compared against the HPA-921 battle mockup (Linear attachment "UI mockup overview", screen 15): every difference is the pending Last Hearth re-theme — the mockup's squad deploy bar, dark grid board, placed chibi characters, hearth styling and BUILD-phase HUD versus the current sci-fi lane, wave banner and speed controls — which is HPA-926 scope. No unexpected differences and no rendering defects.

## Not verified

- **Perceptual quality and 1×/3× readability are unverified.** One take per cue was generated and chosen by objective measures only (onset, decay, headroom); nobody listened to the masters or to a real wave.
- **Most cues are crops.** Takes run 1–18 s and durations are `active length + 50 ms` capped at the filename tier, so 17 of the 19 replacements and `scrip_gain` sit exactly at their tier cap and keep only the opening of a longer take, with a 25 ms fade (`boss_defeated` is an 18 s take cut to 500 ms). `fire_nanite` (180 ms) and `core_hit` (410 ms) are the exceptions. `recruit_reveal_rare` was shortened to 0.99 s because its 1.0 s source cannot supply more; the generator now refuses to pad a cue past its source.
- Distribution rights for the 26-file set were confirmed by the generating account owner on 2026-11-23 (recorded in the README); the MCP cannot prove the account plan.
