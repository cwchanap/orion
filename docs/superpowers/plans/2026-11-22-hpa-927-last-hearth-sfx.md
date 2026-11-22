# HPA-927 — Last Hearth Sound Effects: Implementation Plan

**Linear:** [HPA-927](https://linear.app/cwchanap/issue/HPA-927/orion-produce-last-hearth-sound-effects)  
**Design:** [HPA-927 specification](../specs/2026-11-22-hpa-927-last-hearth-sfx-design.md)  
**Downstream integration:** [HPA-926](https://linear.app/cwchanap/issue/HPA-926/orion-re-theme-the-game-to-last-hearth)  
**Status:** planning draft only. All tasks below are **pending**, not implemented.

## Delivery approach

**One Linear issue → one draft PR → one eventual merged PR.** Add the generated masters, script changes, asset declarations, tests, provenance documentation and objective E2E evidence **on this same PR branch**. No code/art splitting, no companion audio PR, no `lib/` production changes and no new external runtime dependency.

This PR concerns **SFX assets**; HPA-926 is the separate *coding* ticket for playback integration and Last Hearth UI retheme. Existing HPA-924/925 image assets are not modified. Use ElevenLabs MCP sound-effects generation on the owner's available generating account; do not put generation into CI or expect exact stochastic re-generation.

## Task 1 — Freeze the current audio baseline

- Verify `main` is current before production work. Enumerate the 21 non-music filenames already in `assets/audio/`, their durations/ceilings, registered `pubspec.yaml` entries and source/provenance availability.
- Record SHA-256 for `confirm.wav`, `clear.wav` and the four `music_*.wav` so preservation is independently checkable; also record 17 current combat filename mappings.
- Treat `assets/audio/README.md`, `scripts/generate_feedback_audio.py`, `scripts/test_generate_feedback_audio.py` and `test/feedback/audio_asset_contract_test.dart` as the existing contract. Never create dummy WAVs.

**Done:** one consolidated 24-sound change list (19 replacements and five additions), no missing filenames, and baseline bytes for unchanged cues pinned.

## Task 2 — Generate and curate the Last Hearth takes (asset production only)

- Create 19 replacement sounds and five new sounds according to the spec's exact filename/texture table, using project-authored ElevenLabs prompts. Keep high-frequency attacks dry and short for the existing 3× limiter.
- Save original downloaded takes in gitignored `assets/audio/sources/` plus a private durable backup. Record prompts, model, generation IDs, chosen takes, initial download and decoded-source hashes, and any FFmpeg source conversion.
- Avoid third-party sound samples, reuse of copyrighted recordings, and uploading private takes to GitHub. Preserve the 17 originals in the private backup if needed to revert.
- Keep `confirm` and `clear` exactly untouched. Leave four music loops untouched.

**Done:** exactly 24 selected source takes with verifiable private provenance, converted to 44.1 kHz/16-bit mono PCM ready for offline mastering.

## Task 3 — Extend the existing mastering script, minimally

File: `scripts/generate_feedback_audio.py`.

- Keep the existing stdlib WAV/mastering path; read a 24-entry private generated-source provenance inventory rather than creating another audio pipeline.
- Remove the procedural `victory`/`defeat` entries from `CUES`; keep only `confirm`/`clear`, preserving their original output bytes.
- Update filename validation and duration checks: ≤250 ms for 8 fire + 3 impact + death; ≤500 ms for the other five combat cues and both replaced stingers; ≤1500 ms only for the five newly added UI cues.
- Apply documented individual peak ceilings, endpoint fades, and silence checks. Validate all 24 source checksums and mastering arguments before writing any of the 26 non-music final WAVs. No fallback to the previous sci-fi sounds on error.

**Done:** offline replay with the authorized private source bundle recreates every selected master identically; corrupt/missing source aborts before output replacement.

## Task 4 — Ship masters, manifest and provenance summary

- Replace 17 `fire_*` / combat WAVs plus `victory.wav` and `defeat.wav` at existing paths; create `flare_launch.wav`, `recruit_reveal.wav`, `recruit_reveal_rare.wav`, `level_up.wav` and `scrip_gain.wav`.
- Register the five new entries (only) under Flutter assets in `pubspec.yaml`; no `lib/` code change.
- Update `assets/audio/README.md`: all new textures, duration/peak ceilings, the two preserved procedural cues, asset inventory, private source/provenance regeneration instructions and the actual generation/commercial-rights basis. Keep full take provenance inside `assets/audio/sources/provenance.json` and preserve the gitignore.
- Do not commit scratch WAVs, private sources, generated previews, or test screenshots not needed for final evidence.

**Done:** repository has exactly **26 non-music** tracked WAVs, all five new files registered, and only the four existing music WAVs remain unchanged.

## Task 5 — Update both asset contracts (not production playback)

Files: `scripts/test_generate_feedback_audio.py`, `test/feedback/audio_asset_contract_test.dart`.

- Python: exact 26-file non-music set; preserve and verify old `confirm`/`clear` hashes, pin new `victory`/`defeat` SHA-256; assert 44.1 kHz, mono, 16-bit PCM, duration tiers, peak ceilings, non-silence and zero endpoints for all 24 generated files. Do not skip public shipped-asset checks when private `sources/` is absent.
- Python private-source path: regenerate into a temporary directory and assert exact byte equality for all 26 outputs, then deliberately corrupt one source and verify the script exits without modifying any outputs. This private-source test may **skip with an explicit reason** on public CI, as it does today.
- Dart: leave `PlatformGameFeedback.sounds` and current 17 combat names alone. Add a fixed test-only list of five deferred HPA-927 names; verify all five exist in `pubspec.yaml` and read RIFF PCM parameters, duration ≤1500 ms. Keep all current 17-combat, four-feedback and four-music checks.
- Avoid new mocks, audio frameworks or generic event registries.

**Done:** permanent in-repo tests fail on missing/incorrect WAVs, an accidental sci-fi stinger rewrite, or wrong asset declarations.

## Task 6 — End-to-end acceptance and evidence (MCP)

1. Run `python3 -m unittest discover -s scripts -p 'test_*.py'`, `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test` and `flutter build web --release`. Confirm all PR CI jobs on final head.
2. With an MCP-controlled Chrome/web session, load the real app and navigate title → world map → stage briefing → battle → wave. Assert the original combat event→existing filename playback still occurs and the Sound Effects setting suppresses **new** requests when off; inspect DevTools/network or browser audio APIs, rather than relying on a person's ears.
3. In the same browser, load/decode each of the **five new bundled assets** using the emitted Flutter manifest paths and browser audio decoding. Check successful decode, duration and channel count. **Do not pretend flare/recruit/level/Scrip event wiring exists yet; HPA-926 owns that.**
4. Capture real browser screenshots of title, map and battle at **390×844** and **320×568**; compare applicable visual structure/art to the [approved HPA-921 UI mockup](https://linear.app/cwchanap/issue/HPA-921/orion-pivot-to-last-hearth-an-anime-character-tower-defense) and current `main`. Record unchanged layouts and deferred HPA-926 copy/cyan-lane issues as known differences, not blockers for audio-only work.
5. Put a short reproducible evidence note under `docs/superpowers/validation/` with commands, CI URLs, audio decode/network observations and representative screenshot paths or links. Avoid committing raw screenshots in bulk.

**Done:** an MCP-controlled browser E2E verifies asset delivery and existing playback without regression; visual comparison and objective audio contract tests are recorded. No human sign-off or separate native-device acceptance requirement.

## End-to-end acceptance checklist

- [ ] 17 combat + 2 existing stinger filenames replaced with themed WAVs, five new stingers added, two UI clicks and four music WAVs byte-for-byte unchanged.
- [ ] All 26 non-music WAVs satisfy exact filename/encoding/duration/peak/endpoint checks, including ≤250/500/1500 ms categories.
- [ ] New five WAVs bundled by `pubspec.yaml`, with none wired into production `lib/` until HPA-926.
- [ ] `generate_feedback_audio.py` never overwrites the new victory/defeat masters with procedural legacy stingers; regenerated output matches byte-for-byte with authorized private source takes; a bad source fails atomically.
- [ ] Public Python + Dart asset tests always enforce tracked-file contracts; private-source regeneration tests skip explicitly (not silently) when unavailable in CI.
- [ ] Public README and private full provenance describe the selected original ElevenLabs takes accurately; no raw source bundle or temporary artifacts committed.
- [ ] Final-head static analysis, unit tests, web build and GitHub CI pass.
- [ ] MCP Chrome E2E verifies real battle playback and SFX toggle, and browser decoding of all five newly bundled files.
- [ ] MCP screenshots at 390×844 and 320×568 confirm no UI regressions and are checked against applicable HPA-921 mockup/reference art, with final retheme differences assigned to HPA-926.
- [ ] One implementation PR for HPA-927; no platform-specific or manual/human acceptance gate.

## Risks kept intentionally small

- **Missing private source bundle:** must obtain the authorized owner's backup before producing deterministic masters; public files still test in CI. Do not fake provenance or build arbitrary replacement sounds silently.
- **Themed stingers sound too long or loud:** hold the spec's duration/peak ceilings and existing limiter behavior; tune source selection/target levels rather than adding runtime mixer or buffering.
- **Current HPA-926 UI remains sci-fi:** this is expected and out of scope; check only for regressions in the already-merged visuals and playable flow.
- **Generation/account rights:** verify the generating plan's game-embedding rights before public commit and document precisely; retain private source takes outside Git.
