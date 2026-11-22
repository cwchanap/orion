# HPA-927 — Last Hearth Sound Effects: Design Specification

**Linear:** [HPA-927](https://linear.app/cwchanap/issue/HPA-927/orion-produce-last-hearth-sound-effects)  
**Parent:** [HPA-921 — Last Hearth](https://linear.app/cwchanap/issue/HPA-921/orion-pivot-to-last-hearth-an-anime-character-tower-defense)  
**Downstream:** [HPA-926 — final retheme and playback wiring](https://linear.app/cwchanap/issue/HPA-926/orion-re-theme-the-game-to-last-hearth)  
**Baseline inspected:** `main` at `58b1e2c5e90d8806cb5d40df6fb0b0f3f1e3bdda` (2026-11-22)  
**Status:** design for review; audio generation, code/test changes and validation are NOT implemented in this planning draft.

## Goal and scope

Make Orion's existing combat feedback sound like *Last Hearth*: survivors defending the warm Orion Hearth against the Frostbitten in a post-war Hokkaido winter. Preserve combat timing and readability at 1× and 3×. Audio texture should be hopeful but harsh: practical survivor weapons, ice, wind, fire and camp signals, not space lasers or digital bleeps.

This is **one asset-only ticket and one PR**, including these planning documents, generated WAVs, deterministic offline mastering updates, audio tests, manifest, provenance and validation evidence. HPA-926 owns all new cue playback call sites and UI/copy changes. No `lib/` production changes, new mechanics, music changes, voice acting, new audio system or new sound preference.

## Verified baseline and decisions

- `assets/audio/` currently contains 17 ElevenLabs combat WAVs plus four feedback WAVs, and four separate music tracks. `confirm.wav` and `clear.wav` are neutral procedural sounds and must remain **byte-identical**.
- `scripts/generate_feedback_audio.py` currently synthesizes all four feedback stingers and masters 17 generated combat source takes from private, gitignored `assets/audio/sources/`. **Remove `victory.wav` and `defeat.wav` from its procedural `CUES` map** once their generated replacements exist, or regeneration would overwrite them with the old sounds.
- `scripts/test_generate_feedback_audio.py` pins the exact non-music WAV names and hashes the four original procedural stingers; split this into two unchanged procedural hashes plus explicit new selected-output stinger hashes.
- `test/feedback/audio_asset_contract_test.dart` reads production feedback filenames plus declared assets. Since the five *new* sounds are not yet referenced by production code, test them with a small, explicit **test-only** list. Do not falsely add them to `PlatformGameFeedback.sounds` before HPA-926 wires playback.
- Existing combat limiters, `GameFeedback`, `FlameAudio`, `lib/` sound filename mappings and four music WAVs remain unchanged.
- Public `assets/audio/README.md` documents the production masters. Private `assets/audio/sources/provenance.json` contains source takes, prompt/model/generation metadata, hashes and mastering settings. `sources/` is deliberately gitignored and must not be committed. Mastered game WAVs are committed only subject to the generating account's applicable distribution/commercial rights; do not claim a blanket CC0 license.

## Exact sound inventory

**Replace the existing 17 combat filenames in place.** The last column is the current per-file peak **ceiling** from `assets/audio/README.md`; retain these for predictable mix levels. Frequent fire, impact and death cues must be at most 250 ms. Other combat cues must be at most 500 ms.

| File (all under `assets/audio/`) | Last Hearth sound / design brief | Max duration | Peak ceiling |
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

**Replace two existing UI stingers in place**, keeping their current filename mappings and a compact ≤500 ms duration. Suggested ceilings are mix targets and may be reduced if the current UI playback is too prominent.

| File | Sound | Max duration | Peak ceiling |
| --- | --- | ---: | ---: |
| `victory.wav` | Warm horn with camp bell | 500 ms | −14 dBFS |
| `defeat.wav` | Cold wind over a dying flame | 500 ms | −16 dBFS |

**Add five new, currently unplayed files** for HPA-926 to wire later. Cap at 1.5 seconds each, not at the existing 500 ms combat limit.

| File | Intended downstream moment | Max duration | Peak ceiling |
| --- | --- | ---: | ---: |
| `flare_launch.wav` | Signal flare firing skyward | 1500 ms | −16 dBFS |
| `recruit_reveal.wav` | E–B-rank recruit introduction | 1500 ms | −18 dBFS |
| `recruit_reveal_rare.wav` | A/S-rank recruit, longer/brighter lift | 1500 ms | −15 dBFS |
| `level_up.wav` | Character level-up | 1500 ms | −17 dBFS |
| `scrip_gain.wav` | Scrip award | 1500 ms | −20 dBFS |

**Preserve exactly:** `confirm.wav`, `clear.wav`, all four `music_*.wav`. Total after delivery: **26 non-music WAVs** (17 combat + 2 replaced stingers + 2 unchanged UI clicks + 5 new) and 4 unchanged music WAVs.

## Generation, mastering and reproducibility

1. Generate original one-shot takes with ElevenLabs Sound Effects, using project-authored prompts without external reference recordings. Keep the source recording, model identifier, prompt, generation ID and chosen take under the owner's **private** `assets/audio/sources/` backup.
2. Normalize the source to 44,100 Hz, signed 16-bit, mono PCM WAV (FFmpeg only for initial source conversion if needed); record source SHA-256. Each final master is produced offline by the existing Python stdlib generator, not regenerated from ElevenLabs during CI.
3. Reuse its current preflight SHA/format validation, low-pass/DC removal, trim, attack/release fade and peak normalization. Generalize the mastering routine **minimally** for the 19 replaced/generated filenames and five added files. Allow 1.5 s **only** for the five explicitly listed new cues, while retaining the 250/500 ms public contract and peak ceilings above.
4. Prevalidate **all** private source files, names and mastering settings before any tracked WAV is modified. A missing/corrupt source must fail without overwriting good masters. The existing generator test already guards corruption; extend it to cover the new inventory.
5. `confirm.wav` and `clear.wav` remain procedural, preserving exact original bytes and test hashes. Generated `victory.wav` and `defeat.wav` must never be silently re-synthesized by the old `CUES` entries. Pin their new final checksums in public tests; compare all generated masters byte-for-byte to offline regeneration when the private bundle is available.
6. Every master must have nonzero audible signal, zero-valued first/last PCM samples, appropriate duration/encoding and peak **not above** the documented ceiling. Avoid unnecessary extra processing stages or dependencies.

No asset source bundle, raw ElevenLabs downloads, temp output or standalone audio library goes into this public repository. Keep an accurate public method/rights summary in `assets/audio/README.md`, and private full provenance in `assets/audio/sources/provenance.json`.

## Test and delivery boundaries

- `scripts/test_generate_feedback_audio.py`: exact set of 26 non-music WAV names; hashes for unchanged `confirm/clear` and the replaced stingers; per-category WAV duration, peak, non-silence and silent endpoints; offline regeneration byte equality when private source bundle is present; corrupt-source atomicity. CI must always run the *public* asset checks even without private sources.
- `test/feedback/audio_asset_contract_test.dart`: preserve the existing 17 combat filename checks; additionally assert the five new cue paths exist, appear in `pubspec.yaml`, and decode as RIFF 44.1 kHz/16-bit mono PCM with duration ≤1.5 s. Verify both replacement stingers and unchanged UI clicks continue to load by existing production names. No new production playback API in this PR.
- `pubspec.yaml`: register only the five new WAV paths; the 19 replacements are already registered. Do not change unrelated assets or dependencies.
- **MCP E2E acceptance:** build/serve the web app and use an MCP-controlled browser to enter a real stage, start a wave, observe legacy combat cues being requested/played and Sound Effects off muting subsequent starts; inspect network/audio decode for the new five bundles via the built asset manifest (they are intentionally unplayed until HPA-926). Capture **real** title/map/battle screenshots at 390×844 and 320×568. Compare the already-implemented artwork against the HPA-921 approved mockup, documenting any existing *copy/layout* differences as HPA-926 scope rather than retheming them here. No human/manual/native acceptance gate.
- Final-head `python3 -m unittest discover -s scripts -p 'test_*.py'`, `flutter analyze`, `flutter test`, `flutter build web --release`, and repository PR CI pass. Do not claim the tests have passed in this **planning-only** PR.

## Explicit non-goals and handoff

HPA-926 will add the flare/recruit/rare-recruit/level-up/Scrip playback call sites, art display, screen names and board/rendering fixes. HPA-927 must not touch those features or the existing music. Do not split this issue across multiple implementation PRs; extend this planning PR with its assets and tests when executing the work.
