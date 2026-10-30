# HPA-303 — Integrated acceptance design

**Linear:** [HPA-303](https://linear.app/cwchanap/issue/HPA-303/product-make-orion-welcoming-worth-replaying-and-audible)  
**Status:** Closed on documented owner exceptions (2026-10-29); no human cross-feature/device acceptance was performed.  
**Scope:** Final verification and handoff for the already-merged initiative; not another gameplay feature.

## Product question

Can a new player learn Orion's loop without instruction outside the app, feel a meaningful reward after a boss, and understand combat with audio on a real device?

The implementation tickets are complete: first-run guide [HPA-412 / PR #38](https://github.com/cwchanap/orion/pull/38), once-only contextual tips [HPA-413 / PR #42](https://github.com/cwchanap/orion/pull/42), seven boss blueprints [HPA-415 / PR #39](https://github.com/cwchanap/orion/pull/39), combat SFX [HPA-416 / PR #40](https://github.com/cwchanap/orion/pull/40), and contextual music [HPA-417 / PR #43](https://github.com/cwchanap/orion/pull/43). Music assets were delivered separately by [HPA-168 / PR #44](https://github.com/cwchanap/orion/pull/44). All are marked Done in Linear.

**Important limitation:** HPA-417 explicitly skipped physical-device listening on 2026-10-28 by owner decision. The [HPA-417 validation record](../validation/2026-10-27-hpa-417-music-ambience.md) reports that iOS Developer Mode prevented installation and `adb` was unavailable. Loop seams, audible mix at 1×/3×, silent-mode behavior, and interruptions were **not verified on hardware**. Passing automated tests is not evidence of these audible qualities.

## Design choice

One **manual cross-feature playthrough with a short recorded result matrix**, reusing the shipped UI and tests. No new event bus, tutorial engine, telemetry, game rules, save migration, assets, test harness, or hardware-dependent CI job. Keep this ticket and its single PR focused on an integrated acceptance record. Fix actual cross-feature defects in the same PR only when narrow and directly attributable; unrelated defects become separate tickets/PRs, not scope expansion.

The normal player path is the authority for experience checks, because unit tests cannot measure whether hints are understandable or overlapping, audio is audible, or controls remain comfortable to tap. Existing targeted automated tests are the authority for comprehensive per-stage reward data and deterministic gates; no need to play all seven stages on hardware.

## Acceptance matrix

| Parent criterion | Verification | Evidence / success |
| --- | --- | --- |
| First-mission learning | Clean Alpha app data → tap/drag build → start Wave 1 → upgrade → first module pick after Wave 2 → Wave 3 scanner → **Got it**; check Skip separately | Callouts do not block play; after Got it and separately after Skip, **force-quit/relaunch before Alpha has a committed result** and verify no guide reappears |
| Later first-time explanations | On the same or a second run, observe tower unlocks through Wave 6, specialization, targeting, boss preview, and first modified stage briefing | Once-only tips point at usable anchors, never block Wave, never overlay the HPA-412 guide; Replay Tutorial restores them |
| Seven blueprints | Inspect the already-existing catalog/unlock tests, then clear Alpha's boss and a later boss in simulator (physical spot-check if available) | One first-committed-clear unlock per stage; visible in map/briefing/report; **force-quit/relaunch** to check committed rewards in map/briefing; repeat clear adds no duplicate; failed saves and remaining five mappings verified by existing tests |
| Combat SFX | Listen on iOS Simulator at 1× for firing, impact, kills, leaks, waves and bosses, then a populated 3× fight | Simulator checks audible mix/clutter through Mac output and SFX OFF silence; input lag and stutter require physical hardware |
| Independent music | Map → build → wave → boss, victory/defeat, settings combinations Music on/off × SFX on/off, pause/resume, background/foreground | Simulator can check audible transitions/seams through Mac output, independent toggles and restart persistence; native silent switch, external mixing/interruptions and Android playback require hardware |
| Whole-device playthrough | iOS Simulator Alpha fresh start and later modified stage first, followed by one physical-device Alpha + later-stage playthrough | Record environment/outcomes separately; simulator success never counts as physical-device acceptance |

**Test environment:** Attempt iOS Simulator first and verify availability with `xcrun simctl list devices available` and `flutter devices` (the reviewer's inventory is not a guarantee). Simulator audio plays through the Mac and cannot prove hardware volume, performance, silent-switch, external mixing, interruptions, or Android playback. At least one physical device remains the parent's minimum; try enabling Developer Mode on the paired iPhone before installing Android tools. When unavailable or owner-waived, mark physical checks **Blocked** or **Skipped (owner decision)**, not Passed. Never infer one platform from another.

## Setup and repeatability

- Use an expendable local installation/save. For a truly new player use a clean install/app-data state. **Reset Campaign alone is not a tutorial reset**; for guidance replay use Settings → Replay Tutorial, which resets both the HPA-412 guide and HPA-413 tips. Tutorial persistence is written by Skip, by **Got it** on the Wave 3 scanner callout, or by starting Wave 3 while that scanner lesson is active — *not* by choosing the Wave 2 module. Test relaunch **before any committed Alpha result**, because the app otherwise infers tutorial completion from campaign progress.
- Capture the commit SHA, platform, OS, hardware class, speed, audio switches and volume, test date, and whether the stage is fresh or replayed. Avoid personal device identifiers in committed documentation.
- Run the later-stage modifier and second boss in ordinary progression where practical; use existing tests for the five remaining blueprint mappings. Force-quit/relaunch after a committed boss clear and check map/briefing from persisted data. Never change balance/save code merely to make manual testing convenient.
- A separate [integration smoke test](../../../integration_test/app_smoke_test.dart) verifies basic UI/gameplay wiring, but intentionally disables **all three** feedback channels to avoid player timers at teardown. It **cannot** substantiate audio acceptance.

## Evidence and decision

Use the committed [platform-specific validation record](../validation/2026-10-28-hpa-303-integrated-acceptance.md) during execution: each criterion has separate **iOS Simulator / iPhone / Android** results plus evidence and follow-up. Mark **Pass / Fail / Blocked / Skipped (owner decision) / Not run** and include exact head SHA plus CI/build-run links. Automated success cannot substitute for an unobserved human/audio result.

Close HPA-303 only when parent requirements have been checked successfully **or the owner explicitly accepts the specific unverified exceptions documented in the validation record** — for this closure: the hardware-only physical-device checks, all audio-listening observations, and the non-audio simulator walkthrough rows. Any criterion outside that documented list must pass, or have its observed failure resolved, before the initiative is marked complete. Even when waived, describe skipped checks accurately; do not claim native audio, UX, or played experience passed. For an observed defect, provide minimal reproduction steps and expected/actual behavior; decide whether it can be fixed narrowly in this PR or needs a new issue.

## Out of scope

New game modes, balance or economy changes, expanded module catalog, new audio/art, per-platform audio abstraction, analytics, broad refactoring, new automated end-to-end orchestration, and backward compatibility for nonexistent production saves. If art/SFX rework proves necessary, create an **independent asset task** instead of combining it with code work.
