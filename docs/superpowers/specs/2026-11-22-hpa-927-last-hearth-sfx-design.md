# HPA-927 — Last Hearth Sound Effects: Design Specification

**Linear:** [HPA-927](https://linear.app/cwchanap/issue/HPA-927/orion-produce-last-hearth-sound-effects)  
**Parent:** [HPA-921 — Last Hearth](https://linear.app/cwchanap/issue/HPA-921/orion-pivot-to-last-hearth-an-anime-character-tower-defense)  
**Downstream:** [HPA-926 — final retheme and playback wiring](https://linear.app/cwchanap/issue/HPA-926/orion-re-theme-the-game-to-last-hearth)  
**Baseline inspected:** `main` at `58b1e2c5e90d8806cb5d40df6fb0b0f3f1e3bdda` (2026-11-22)  
**Status:** implemented on this branch (see the plan and validation note); perceptual quality remains unverified.

## Goal and scope

Retheme the 24 changed/added one-shot SFX so combat evokes Last Hearth: survivor weapons, frost, wind, fire and camp signals rather than synthetic space sounds. Aim for short, recognizable cues and readable combat at 1× and 3×. **WAV format, peak and duration checks cannot establish whether a take sounds good or remains intelligible in a real mix.** Optional audition feedback can help choose takes; until it occurs, the final validation note must mark perceptual quality and 1×/3× listening quality as **unverified**, not as a passed gate.

One Linear ticket → one PR. The PR adds generated masters, the existing stdlib script's inventory updates, public provenance, Python asset contracts, five Flutter manifest entries and minimal MCP evidence. HPA-926 owns all playback integration and UI changes. No production `lib/` changes, gameplay changes, new audio engine, music, voice acting or additional PR.

## Verified baseline and design decisions

- Existing assets: 17 ElevenLabs combat WAVs, four feedback stingers and four music loops. `confirm.wav`, `clear.wav` and the four `music_*.wav` remain **byte-identical**. Keep the 19 replacement filenames unchanged because `CombatSoundCue` and existing playback refer to them.
- `scripts/generate_feedback_audio.py` currently masters 17 generated takes using private `assets/audio/sources/provenance.json` and synthesizes four feedback stingers. For HPA-927, **delete `victory` and `defeat` from `CUES`**, leaving only procedural `confirm` and `clear`. The former two become generated masters.
- Follow the existing music precedent: add a **tracked** `assets/audio/sfx_provenance.json` for the 24 selected takes. It holds the project-authored prompt, model, generation/session IDs when available, downloaded/decoded source SHA-256, per-file selected mastering `duration` and `peak_db` (no generated-output hash; Git tracks the masters and private-source regeneration checks byte equality). Actual mastering settings have **one source of truth** there. Only source WAV/download bytes stay private and gitignored under `assets/audio/sources/`; the old private `sources/provenance.json` is no longer an input to the updated generator.
- Keep the existing Dart `test/feedback/audio_asset_contract_test.dart` **unchanged**: its advertised paths come from production `GameFeedback`, which does not know the five deferred HPA-927 cues. The existing Python public asset contract will validate all 26 non-music files **and** their `pubspec.yaml` registration, including the five new cues. HPA-926 can extend production playback later.
- The existing preflight already masters every input before writing outputs; preserve its fail-before-write behavior. No new audio framework, queue, runtime mixer or duplicate registry.
- Mastered game WAVs can be committed only under the generating account's applicable game-embedding rights. The public metadata does not contain raw isolated audio, but the tracked master files still require rights confirmation. Do not call generated content CC0/public-domain or claim rights have been verified in this planning PR.


## Exact sound inventory

**Replace the existing 17 combat filenames in place.** The table's peak numbers are **authoring/mix guidance**, based on the original `assets/audio/README.md`, not another CI-enforced 24-entry ceiling mapping. Record each selected take's actual `duration` and `peak_db` exactly once in tracked `sfx_provenance.json`. The script and Python test enforce a single global `-30 <= peak_db <= -13` dBFS headroom range and verify the mastered WAV peak agrees with that selected `peak_db` (within PCM rounding tolerance); no separate per-file peak table in tests. Duration tiers **are enforced**: fire, impact and ordinary-death cues ≤250 ms; all other combat cues ≤500 ms.

| File (all under `assets/audio/`) | Last Hearth sound / design brief | Max duration | Suggested peak |
| --- | --- | ---: | ---: |
| `fire_laser.wav` | Short, dry survivor rifle shot | 250 ms | −18 dBFS |
| `fire_rocket.wav` | Thrown incendiary bottle, brief fire whoosh | 250 ms | −18 dBFS |
| `fire_cryo.wav` | Frost breath and small ice crackle | 250 ms | −18 dBFS |
| `fire_railgun.wav` | Bow release or heavy sniper crack | 250 ms | −18 dBFS |
| `fire_ion_chain.wav` | Compact electric arc | 250 ms | −18 dBFS |
| `fire_nanite.wav` | Serum dart hiss | 250 ms | −18 dBFS |
| `fire_gravity_well.wav` | Low, restrained gravity thrum | 250 ms | −18 dBFS |
| `fire_drone_bay.wav` | Small improvised drone launch buzz | 250 ms | −18 dBFS |
| `impact_splash.wav` | Compact fire burst | 250 ms | −19 dBFS |
| `impact_chain.wav` | Electric impact crackle | 250 ms | −19 dBFS |
| `impact_pierce.wav` | Arrow or rifle round hit | 250 ms | −19 dBFS |
| `enemy_destroyed.wav` | Frozen body shattering | 250 ms | −20 dBFS |
| `core_hit.wav` | Hearth struck; flame guttering | 500 ms | −14 dBFS |
| `wave_start.wav` | Camp alarm bell | 500 ms | −15 dBFS |
| `boss_arrival.wav` | Distant Frostbitten howl | 500 ms | −13 dBFS |
| `boss_defeated.wav` | Ice collapse, short rising accent | 500 ms | −14 dBFS |
| `tower_sold.wav` | Fighter recall: steps fading off field | 500 ms | −17 dBFS |

**Replace two existing UI stingers in place**, keeping their current filename mappings and a compact ≤500 ms duration. Suggested peaks are mix targets, not separate per-file CI ceilings, and may be reduced if playback is too prominent.

| File | Sound | Max duration | Suggested peak |
| --- | --- | ---: | ---: |
| `victory.wav` | Warm horn with camp bell | 500 ms | −14 dBFS |
| `defeat.wav` | Cold wind over a dying flame | 500 ms | −16 dBFS |

**Add five new, currently unplayed files** for HPA-926 to wire later. Cap at 1.5 seconds each, not at the existing 500 ms combat limit.

| File | Intended downstream moment | Max duration | Suggested peak |
| --- | --- | ---: | ---: |
| `flare_launch.wav` | Signal flare firing skyward | 1500 ms | −16 dBFS |
| `recruit_reveal.wav` | E–B-rank recruit introduction | 1500 ms | −18 dBFS |
| `recruit_reveal_rare.wav` | A/S-rank recruit, longer/brighter lift | 1500 ms | −15 dBFS |
| `level_up.wav` | Character level-up | 1500 ms | −17 dBFS |
| `scrip_gain.wav` | Scrip award | 1500 ms | −20 dBFS |

**Preserve exactly:** `confirm.wav`, `clear.wav`, all four `music_*.wav`. Total after delivery: **26 non-music WAVs** (17 combat + 2 replaced stingers + 2 unchanged UI clicks + 5 new) and 4 unchanged music WAVs.

## Generation, mastering and reproducibility

1. Generate original one-shot takes using ElevenLabs Sound Effects and project-authored prompts, without supplied third-party recordings. Save the 24 selected decoded source WAVs under private `assets/audio/sources/` and retain an owner-controlled private backup. No existing *old* source bundle is required to produce new takes; old mastered WAVs remain in Git history.
2. Record metadata for every selected take in **tracked** `assets/audio/sfx_provenance.json` following `music_provenance.json`: prompt/model/generation ID, source and download checksums, `duration` and `peak_db`. **Do not store generated master hashes**: Git already versions the output WAVs and the existing private-source test compares regenerated bytes. Preserve SHA pins only for the unchanged procedural `confirm` and `clear`. Do not track source WAV/MP3 bytes or credentials. Normalize downloads into 44,100 Hz, 16-bit mono PCM once using FFmpeg if needed.
3. Change the stdlib generator to load the tracked JSON. Replace the obsolete `(SOURCES / 'provenance.json').is_file()` guard with **`SOURCES.is_dir()`** and a clear missing-private-source error; otherwise missing takes would trigger an unhandled `FileNotFoundError`. Reuse SHA/format verification, low-pass/DC removal, trimming, 3 ms attack/25 ms release, and peak normalization. Add one small **`max_duration_for(name)` using bare stems without `.wav`**: ≤0.25 s for `fire_*`, `impact_*` and `enemy_destroyed`; ≤0.5 s for remaining combat plus `victory`/`defeat`; ≤1.5 s for exactly five deferred UI cues. Import/reuse the same helper in the Python test; avoid a duplicated tier table. Retain the existing global `-30 <= peak_db <= -13` headroom check rather than adding `max_peak_db_for` or a second per-file map.
4. Retain the **existing** preflight approach: master and validate all 24 generated sources before writing a single tracked output. The corruption test already exercises this; extend its inventory rather than adding another transaction layer. Bad input must never overwrite known-good masters.
5. Render `confirm.wav`/`clear.wav` procedurally and preserve their existing byte-hash pins. Delete `victory.wav`/`defeat.wav` from `CUES` so they cannot regress to synthetic originals. For generated sounds, use Git-tracked WAVs and the existing byte-exact offline regeneration check when private takes are available, **without output hashes in JSON**.
6. Enforce non-silent content, 44.1 kHz signed 16-bit mono PCM, zero-valued endpoints, duration within the filename tier and selected metadata, global `-30 <= peak_db <= -13` headroom, and measured output peak agreement with selected metadata (within integer PCM rounding tolerance). Per-file suggested mix levels in the table are curation guidance, **not** additional CI limits. Do not add a loudness-normalization subsystem.

`assets/audio/README.md` documents textures, source handling, rights and the listening limitation; link the tracked JSON for selected numeric settings rather than copying another per-cue mastering table. Private `sources/*.wav` remain gitignored.

## Test and delivery boundaries

- **Python public contract (`scripts/test_generate_feedback_audio.py`):** pin the canonical exact 26 non-music names independently of the provenance entries; assert the metadata has exactly 24 generated entries. Check manifest registration for each of the 26 filenames. Verify WAV PCM format, selected `duration` and `peak_db` from the **tracked JSON**, 250/500/1500 ms tier via the shared `max_duration_for(name)` helper (bare stems), global `-30 <= peak_db <= -13` headroom, PCM output peak agreement, non-silence, zero endpoints and the two original `confirm`/`clear` hash pins. **No generated master hash field or duplicate per-cue peak ceiling map.** Always run in CI without private sources.
- **Python private regeneration test:** copy the script, the **tracked** `sfx_provenance.json` and available private sources into a temporary tree. Reproduce all 26 outputs byte-for-byte; corrupt one source to prove existing fail-before-write behavior. If private sources are absent on public CI, skip this test **with an explicit reason** only; public asset checks cannot skip.
- **Dart tests:** leave `test/feedback/audio_asset_contract_test.dart` untouched. Its existing combat/stinger/music tests still pass and will naturally cover new cues after HPA-926 adds those cues to production feedback. HPA-927 changes only the Python asset contract and five `pubspec.yaml` lines.
- **Minimum MCP-controlled web E2E (retained for Orion's project-level acceptance):** build/serve the actual web app, start one real stage wave, verify one replaced combat WAV can load/decode and the five registered-but-not-yet-played new WAVs are available. Reuse existing Dart tests for the SFX switch and cue mappings. Capture **one** real 390×844 battle screenshot and compare against applicable approved HPA-921 art/mockup **only for unexpected visual differences**; do not inventory pre-existing HPA-926 labels/cyan-lane issues or undertake a multi-screen visual audit. This is intentionally the smallest project-compliant MCP E2E and visual check, not a second/native-platform gate.
- **Qualitative listening (optional feedback, never acceptance):** if available, audition the 24 masters sequentially and a real wave at 1×/3×; record which takes were kept or rejected as supplementary notes. If no listening is done, explicitly record **'perceptual sound quality and 1×/3× readability unverified'**. Objective tests cannot certify them, and no human sign-off is required.
- Run final-head `python3 -m unittest discover -s scripts -p 'test_*.py'`, `flutter analyze`, `flutter test`, `flutter build web --release` and PR CI. Capture results and the minimal MCP evidence in a short validation note. None are claimed complete by this docs-only draft.

## Explicit non-goals and handoff

HPA-926 will add the flare/recruit/rare-recruit/level-up/Scrip playback call sites, art display, screen names and board/rendering fixes. HPA-927 must not touch those features or the existing music. Do not split this issue across multiple implementation PRs; extend this planning PR with its assets and tests when executing the work.
