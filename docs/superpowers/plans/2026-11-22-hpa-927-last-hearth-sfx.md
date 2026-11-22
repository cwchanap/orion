# HPA-927 — Last Hearth Sound Effects: Implementation Plan

**Linear:** [HPA-927](https://linear.app/cwchanap/issue/HPA-927/orion-produce-last-hearth-sound-effects)  
**Design:** [HPA-927 specification](../specs/2026-11-22-hpa-927-last-hearth-sfx-design.md)  
**Downstream integration:** [HPA-926](https://linear.app/cwchanap/issue/HPA-926/orion-re-theme-the-game-to-last-hearth)  
**Status:** planning draft only. All tasks below are **pending**, not implemented.

## Delivery approach

**One Linear issue → this same draft PR → one final merged PR.** HPA-927 owns only the sound assets, reproducible mastering, tracked metadata, Python contracts and manifest. HPA-926 owns runtime playback wiring and Last Hearth UI/copy. No new engine, lib/ code changes, companion PR or new runtime dependency.

Baseline is `main`; the current code already pins `confirm`/`clear` hashes, prevalidates every existing source before writes and checks corruption atomicity. **Do not rebuild those capabilities or repeat a baseline inventory task.** At final verification, confirm `confirm.wav`, `clear.wav` and four music WAVs match main (git diff/byte check).

## Task 1 — Generate and select 24 source takes

- Use ElevenLabs MCP Sound Effects to produce **19 replacement** sounds and **five new** sounds with the exact textures/filenames in the [design spec](../specs/2026-11-22-hpa-927-last-hearth-sfx-design.md). Prioritize short dry attacks that coexist with the existing 3× combat limiter; avoid spending extra generation credits on an unneeded high-polish pass.
- Save the 24 selected takes as decoded 44,100 Hz/16-bit mono source WAVs in **gitignored** `assets/audio/sources/`; privately back them up. No old source bundle is needed, and previous masters remain in Git history.
- Create tracked **`assets/audio/sfx_provenance.json`** (same pattern as existing `music_provenance.json`) with 24 exact named records: authored prompt, model, generation ID/session when available, original/download and decoded source hashes, chosen `duration` and `peak_db`. **Omit generated-output hashes**; Git versions final WAVs and the private regeneration test compares bytes. Never commit raw takes, credentials or a private source bundle.
- Use the spec's per-cue peak values as **suggested mix levels** when curating. Only the global `-30 <= peak_db <= -13` dBFS bound and agreement between each mastered WAV and its **selected** `peak_db` in tracked JSON are CI-enforced. Duration tiers remain hard limits. Avoid adding another 24-entry ceiling table.

**Done:** exactly 24 project-authored selected takes, private source backups, and one reviewable 24-entry tracked metadata file without audio bytes.

## Task 2 — Update the stdlib generator, only where needed

File: `scripts/generate_feedback_audio.py`.

- Load tracked `assets/audio/sfx_provenance.json` instead of private `assets/audio/sources/provenance.json`; the metadata must be reviewable without private sources. **Update the old missing-source guard** from `(SOURCES / 'provenance.json').is_file()` to `SOURCES.is_dir()` with a helpful error before attempting source reads. Private takes are looked up by the existing cue basenames.
- Remove `victory` and `defeat` from the procedural `CUES` dictionary. Keep only `confirm` and `clear`, preserving their original bytes. The former stingers now use generated takes.
- Add one shared **`max_duration_for(name)` taking bare stems without `.wav`**, matching existing `cue['name']`: ≤250 ms (`fire_*`, `impact_*`, `enemy_destroyed`), ≤500 ms (other combat + two generated legacy stingers), ≤1500 ms (exactly five deferred UI cues). Reuse it in Python tests. Preserve the existing `-30 <= peak_db <= -13` validation rather than introducing per-cue peak ceiling mappings.
- Keep the existing SHA/PCM validation, low-pass, DC correction, attack/release, peak normalization and **all-source prevalidation before first write**; extend the inventory, not the architecture.

**Done:** script rebuilds the 26 non-music WAVs byte-for-byte from selected private takes and tracked metadata. Corrupt source input still aborts without modifying any outputs.

## Task 3 — Add final assets, registration and README

- Replace 17 existing combat files + `victory.wav` and `defeat.wav`; add `flare_launch.wav`, `recruit_reveal.wav`, `recruit_reveal_rare.wav`, `level_up.wav`, `scrip_gain.wav`. Existing 19 filenames do not change.
- Add exactly the **five new paths** to `pubspec.yaml`. Keep existing 19 registration entries and all production `lib/` feedback filenames unchanged.
- Update `assets/audio/README.md` with Last Hearth sound textures, generation/rights and reproducibility instructions. **Link** `sfx_provenance.json` for exact per-cue selected duration, peak, source hashes and generation metadata instead of duplicating them in another README table.
- Retain the README's explicit warning: automated checks cannot establish pleasantness, distinctness or masking under 1×/3× repeated playback. Confirm the applicable generation plan permits embedding/distributing all **26** mastered SFX as tracked public repo files; do not assume the earlier 21-file confirmation applies.

**Done:** exactly 26 non-music WAVs are tracked; unchanged `confirm`/`clear` and four `music_*.wav` retain their main-branch bytes; five new manifest entries; no source/audio scratch files committed.

## Task 4 — Update Python contracts; keep Dart test as-is

File: `scripts/test_generate_feedback_audio.py`. Do **not** edit `test/feedback/audio_asset_contract_test.dart`.

- Pin the expected canonical 24 generated names plus two procedural names independently of JSON. Check that `sfx_provenance.json` has exactly those 24 generated records.
- For **all 26** non-music paths, assert existence and a matching `- assets/audio/<name>` line in `pubspec.yaml`, just as `scripts/test_generate_music.py` already checks its manifest.
- Check generated PCM rate/channel/depth, selected duration and output peak against tracked `duration`/`peak_db` (allow PCM rounding tolerance), shared helper's filename duration tier, **global `-30 <= peak_db <= -13`** headroom, non-silence and zero endpoints. **Do not duplicate suggested per-file peak values or pin generated master hashes.** Retain hash pins only for the procedural `confirm` and `clear`.
- When private sources exist, copy the tracked JSON and script with sources into a temporary tree, regenerate all 26 outputs and assert byte equality. Corrupt one source and confirm fail-before-write. If sources are absent, **explicitly skip only this private regeneration test**, never the public asset and manifest checks.
- The existing Dart feedback tests already exercise runtime mappings and SFX-off behavior. Once HPA-926 wires the five new calls, its existing production-advertised-file contract will cover them automatically.

**Done:** CI rejects a missing/unregistered/wrong-format, over-duration, out-of-headroom or unexpectedly re-synthesized WAV; private source regeneration checks byte equality without duplicating master hashes in public metadata.

## Task 5 — Minimal MCP end-to-end and acceptance evidence

1. Run `python3 -m unittest discover -s scripts -p 'test_*.py'`, `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`, `flutter build web --release`; verify final-head PR CI.
2. Use an **MCP-controlled Chrome/web session** with the real built app: title → stage → wave. Confirm an existing replaced combat WAV is requested/decoded and that all **five new manifest entries** can be fetched and decoded (those five are intentionally **not** triggered by gameplay until HPA-926). Skip redundant browser checks of SFX toggle and cue mapping; existing Flutter tests cover those.
3. Capture **one** real battle screenshot at **390×844** and check for **unexpected** visual difference against the applicable approved [HPA-921 mockup](https://linear.app/cwchanap/issue/HPA-921/orion-pivot-to-last-hearth-an-anime-character-tower-defense)/current baseline. Do not catalog already known HPA-926 copy/cyan-lane differences. This one-screen parity check satisfies Orion's visual acceptance convention without a multi-screen or native-platform sweep.
4. Write a compact `docs/superpowers/validation/` note containing command/CI results, MCP asset-loading evidence, the screenshot comparison, and any qualitative audition notes. If an **optional** listen-through of 24 masters and real 1×/3× wave playback is available, include keep/reject notes; otherwise state explicitly that **perceptual sound quality and 1×/3× intelligibility remain unverified**. Neither human listening nor human sign-off is an acceptance gate.

**Done:** objective audio tests, CI and MCP web asset-delivery E2E pass, and the one required screenshot visual check is documented; no manual or second-platform acceptance requirement.

## End-to-end acceptance criteria (all automated)

- [ ] 17 combat + 2 stinger replacements and five added cues give **26 exact non-music WAV filenames**; `confirm`/`clear` and four music tracks byte-identical to `main`.
- [ ] `sfx_provenance.json` tracks 24 source prompts/IDs/source hashes and chosen `duration`/`peak_db` settings, **not generated-output hashes**; only decoded/raw source takes are private and gitignored.
- [ ] All tracked WAVs satisfy 44.1 kHz/16-bit mono PCM, selected duration/peak agreement, ≤250/500/1500 ms filename-tier limits, global `-30 <= peak_db <= -13` headroom and zero endpoints; all 26 registered in `pubspec.yaml`.
- [ ] Stdlib generator no longer procedurally creates `victory`/`defeat`; authorized private-source replay reproduces all 26 exactly and corrupt source fails before writing.
- [ ] Public Python contract runs on CI without the private bundle. Existing Dart contract stays unchanged. Static analysis, unit tests, web build and final-head CI pass.
- [ ] MCP-controlled web E2E starts one real wave, verifies a replaced combat asset loads/decodes and all five new files are bundled and decodable.
- [ ] MCP 390×844 real battle screenshot compared with the relevant HPA-921 UI mockup and current baseline for unexpected visual differences only; no UI/source code change or pre-existing HPA-926 issue inventory.
- [ ] README contains accurate per-cue description, links tracked JSON, confirms updated distribution rights and **preserves the listening limitation**. All evidence resides in this single HPA-927 PR.

**Not acceptance criteria:** human listening/sign-off, a subjective 1×/3× sound-quality claim, 320×568 screenshot sweeps, native-platform checks, or HPA-926 runtime integrations.

## Risks kept intentionally small

- **Quality/overlap:** Tests catch clipping/format/length, **not** whether a cue sounds good or remains intelligible in a crowded mix. Optional listening can inform take selection; if absent, explicitly disclose the limitation instead of claiming success.
- **ElevenLabs generation credits:** 24 selects can require multiple attempts. Prefer concise prompts and reuse good takes rather than adding elaborate processing.
- **Distribution rights:** the current README's confirmation describes the old 21 SFX; confirm rights covering 26 new masters before committing, document accurately, and keep raw takes private.
- **Downstream retheme:** existing sci-fi UI labels/overlays remain HPA-926 work; do not expand this SFX PR.
