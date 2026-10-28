# HPA-303 — Integrated acceptance design

**Linear:** [HPA-303](https://linear.app/cwchanap/issue/HPA-303/product-make-orion-welcoming-worth-replaying-and-audible)  
**Status:** Proposed; no human cross-feature/device acceptance has been claimed.  
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
| First-mission learning | Clean app data, Alpha briefing → tap/drag build → start Wave 1 → upgrade after a clear → first module draft after Wave 2; repeat with Skip | Callouts follow the live actions, don't cover required controls, Skip never blocks play; completion/skip persists |
| Later first-time explanations | On the same or a second run, observe tower unlocks through Wave 6, specialization, targeting, boss preview, and first modified stage briefing | Once-only tips point at usable anchors, never block Wave, never overlay the HPA-412 guide; Replay Tutorial restores them |
| Seven blueprints | Inspect the already-existing catalog/unlock tests, then clear Alpha's boss and a later boss on device | One first-committed-clear unlock per stage; visible in map/briefing/report; repeat clear adds no duplicate; no unlock on failed/uncommitted save; other five verified by table tests |
| Combat SFX | At 1× listen for firing, impact, kill, leak, wave and boss moments, then a populated fight at 3× | Recognizable but not continuous noisy clutter; off means silent; no obvious input lag or frame stutter |
| Independent music | Map → build → wave → boss, victory/defeat, settings combinations Music on/off × SFX on/off, pause/resume, background/foreground | Appropriate loop transitions, no audible click, no music after OFF, both channels independent and preferences survive restart |
| Whole-device playthrough | One real-device Alpha fresh start plus one later modified stage, portrait short-screen observation | Record device/platform/build, actual outcome, defects, and evidence; only label checks Pass after observation |

**Test environment:** At least one representative physical device is the parent's minimum. iOS silent switch / audio mixing and Android native playback remain distinct, unverified HPA-417 checks until each platform is actually tested; never infer one platform from the other. When device access remains unavailable or owner waives listening again, label those rows **Skipped (owner decision)** or **Blocked** with the reason, not Passed.

## Setup and repeatability

- Use an expendable local installation/save. For a truly new player use a clean install/app-data state. **Reset Campaign alone is not a tutorial reset**; for guidance replay use Settings → Replay Tutorial, which resets both the HPA-412 guide and HPA-413 tips.
- Capture the commit SHA, platform, OS, hardware class, speed, audio switches and volume, test date, and whether the stage is fresh or replayed. Avoid personal device identifiers in committed documentation.
- Run the later-stage modifier and second boss in ordinary progression where practical; use existing tests for the five remaining blueprint mappings. Never change balance/save code merely to make manual testing convenient.
- A separate [integration smoke test](../../../integration_test/app_smoke_test.dart) verifies basic UI/gameplay wiring, but intentionally disables **all three** feedback channels to avoid player timers at teardown. It **cannot** substantiate audio acceptance.

## Evidence and decision

Create `docs/superpowers/validation/2026-10-28-hpa-303-integrated-acceptance.md` while executing the plan, with one row per criterion: **Pass / Fail / Blocked / Skipped**, observation, test environment, and follow-up issue if needed. Include automated command results and exact SHA, without copying full logs into Git.

Close HPA-303 only when parent requirements have been checked successfully **or the owner explicitly accepts documented unverified exceptions**. Even when waived, describe skipped device checks accurately; do not claim native audio or UX passed. For an observed defect, provide minimal reproduction steps and expected/actual behavior; decide whether it can be fixed narrowly in this PR or needs a new issue.

## Out of scope

New game modes, balance or economy changes, expanded module catalog, new audio/art, per-platform audio abstraction, analytics, broad refactoring, new automated end-to-end orchestration, and backward compatibility for nonexistent production saves. If art/SFX rework proves necessary, create an **independent asset task** instead of combining it with code work.
