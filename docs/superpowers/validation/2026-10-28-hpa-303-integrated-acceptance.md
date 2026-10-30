# HPA-303 — Integrated acceptance evidence

**Linear:** [HPA-303](https://linear.app/cwchanap/issue/HPA-303/product-make-orion-welcoming-worth-replaying-and-audible) · **PR:** [#45](https://github.com/cwchanap/orion/pull/45)  
**Status:** Closed on documented owner exceptions (2026-10-29); **no human simulator or hardware validation was performed or claimed**.  
**Date / tester:** Closed 2026-10-29; no manual test sessions performed — closed by owner waiver, not testing.

## Automated verification (CI, not a listening or UX test)

The [CI workflow](../../../.github/workflows/ci.yml), [iOS](../../../.github/workflows/build-ios.yml) and [Android](../../../.github/workflows/build-android.yml) workflows run on every pushed PR head — the job list and audio limitations are detailed in the [plan's automated baseline](../plans/2026-10-28-hpa-303-integrated-acceptance.md). A committed record can never name its own head (each fix creates a newer one), so the **PR checks tab is authoritative for the final head**; the runs below are the evidence observed at closure, and older green checks never prove a newer head.

The latest head with completed workflow runs when this record was closed is `61fdb08` (`61fdb08ea45695f0f6cdd72f3171aa6723572c52`, branch `plan/hpa-303-integrated-acceptance`): all three workflows completed 2026-10-29 with conclusion **success** (machine-verified, 2026-10-29). The app under test is unchanged since the last code-bearing head: every commit on this PR is docs-only. Any head pushed after this update must be read from the checks tab — this file cannot list its own successors.

| Required run | Head SHA | Result | GitHub Actions link |
| --- | --- | --- | --- |
| CI (build/lint, tests, audio asset contract, emulator integration) | `61fdb08ea45695f0f6cdd72f3171aa6723572c52` | Success | [run 40919395883](https://github.com/cwchanap/orion/actions/runs/40919395883) |
| build-ios (debug) | `61fdb08ea45695f0f6cdd72f3171aa6723572c52` | Success | [run 40919395892](https://github.com/cwchanap/orion/actions/runs/40919395892) |
| build-android (debug) | `61fdb08ea45695f0f6cdd72f3171aa6723572c52` | Success | [run 40919395940](https://github.com/cwchanap/orion/actions/runs/40919395940) |

Earlier heads `a57fe21`, `7648c2d`, `baa90da`, `1bb4d68`, `b6c768c`, `8ca4e12` and `683864e` also completed all three workflows green; runs on `9b32020` and `b7e6c01` were cancelled by newer pushes (not failures), and `ecd25bd`, `ac4e80a` and `792e1ca` were intermediate commits that were never a pushed PR head and have no runs. None of these is validation of a newer head or of audible output.

## Manual criterion × environment

Use **Pass / Fail / Blocked / Skipped (owner decision) / Not run** in each relevant cell. Label all actual observations by environment; a simulator pass never satisfies a physical-device criterion. Put concrete observations, tested build/OS, and repro or Linear follow-up in the final column. **Not run is not Pass.**

| Criterion | iOS Simulator | Physical iPhone | Physical Android | Observations / follow-up |
| --- | --- | --- | --- | --- |
| Alpha fresh data: build, Wave 1, upgrade, Wave 2 module, Wave 3 scanner **Got it**, force-quit/relaunch **before Alpha result**, no guide | Skipped (owner decision) | Skipped (owner decision) | Skipped (owner decision) | Waived by owner decision 2026-10-29; not verified. |
| Independent fresh/replayed Alpha: **Skip**, force-quit/relaunch before Alpha result, no guide | Skipped (owner decision) | Skipped (owner decision) | Skipped (owner decision) | Waived by owner decision 2026-10-29; not verified. |
| Later hints (unlocks through Wave 6, specialization, targeting, boss preview, modifier); Replay Tutorial vs Reset Campaign | Skipped (owner decision) | Skipped (owner decision) | Skipped (owner decision) | Waived by owner decision 2026-10-29; not verified. |
| Alpha boss first-committed-clear blueprint in report; **relaunch** then map/briefing; replay adds no duplicate | Skipped (owner decision) | Skipped (owner decision) | Skipped (owner decision) | Waived by owner decision 2026-10-29; not verified. |
| Later-stage boss reward + modifier; seven mappings and failed-save case covered by unit tests | Skipped (owner decision) | Skipped (owner decision) | Skipped (owner decision) | Waived by owner decision 2026-10-29; not verified. |
| Music transitions/seams and Music × SFX switches; pause/background/relaunch persistence | Skipped (owner decision) | Skipped (owner decision) | Skipped (owner decision) | Listening portions (transitions, seams, pause/background audibility) waived by owner decision 2026-10-29; not verified. Music × SFX toggle independence and relaunch persistence are covered by automated tests (`test/feedback/shared_preferences_feedback_store_test.dart`, `test/widget/game_music_page_test.dart`), not by this waiver. |
| Combat SFX recognizable at 1× / not overwhelming at populated 3× | Skipped (owner decision) | Skipped (owner decision) | Skipped (owner decision) | Simulator listens through Mac, not device speakers. SFX listening waived by owner decision 2026-10-29; not verified. |
| Real hardware input responsiveness/frame stutter and native audio balance at 3× | Skipped (owner decision) | Skipped (owner decision) | Skipped (owner decision) | Physical-device evidence required; simulator result is not representative |
| iOS silent switch, external mixing and interruptions | Skipped (owner decision) | Skipped (owner decision) | Skipped (owner decision) | iPhone-specific; do not infer from simulator |
| Android native playback and audio/lifecycle behavior | Skipped (owner decision) | Skipped (owner decision) | Skipped (owner decision) | Android-specific; CI emulator runs with audio disabled |
| Physical-device Alpha fresh start **and** one modified later stage | Skipped (owner decision) | Skipped (owner decision) | Skipped (owner decision) | At least one real device or explicit owner waiver required |

## Environment, blockers, and decision

- **Simulator availability:** re-enumerated at execution on 2026-10-29 via `xcrun simctl list devices available` and `flutter devices` (iOS 26.5 runtime): two booted portrait iPhone simulators (iPhone 17, iPhone 16), one booted iPad simulator, and one small SE-class simulator (shutdown — the plan §1 short-viewport option; boot when needed). UDIDs and custom simulator names are omitted per the spec's no-personal-identifiers rule. This is an availability check only — no app install/run has been performed.
- **Physical iPhone:** known prior blocker: Developer Mode disabled (HPA-417). `flutter devices` on 2026-10-29 also listed macOS, Chrome (web), and one paired physical iPhone over wireless (iOS 27.0.1) — observed only; Developer Mode status unconfirmed and no install/run attempted, so this is not validation. The hardware-only rows were subsequently closed by the owner waiver below.
- **Physical Android:** prior blocker: `adb` missing (HPA-417). Only install platform-tools if an Android device is available and needed.
- **Actual simulator/hardware build, OS, sound outputs, levels, exact app SHA:** Not recorded.
- **Owner decision (2026-10-29):** owner explicitly waived three groups of checks: (1) the hardware-only checks (physical iPhone and physical Android rows), (2) all audio-listening checks (simulator Mac-output music/SFX listening included), and (3) the non-audio iOS Simulator walkthrough rows (Alpha first-run guide and Skip persistence, later first-time hints, boss/modified-stage blueprint and reward persistence). This waiver is an acceptance of unverified exceptions, **not** a pass: guide/hint behavior, blueprint persistence in the UI, loop seams, 1×/3× balance, silent switch, external mixing/interruptions, and Android native playback remain unverified by human observation. Distinct from, broader in scope than, and complementary to, the prior HPA-417 waiver, which never covered HPA-303.
- **Final disposition (2026-10-29): closed on documented owner exceptions.** All manual criteria — hardware-only checks, audio-listening checks, and the non-audio simulator walkthrough rows — are Skipped (owner decision); no human playthrough, listening, or device test was performed. Automated verification (CI incl. unit, integration and audio-contract tests, iOS/Android debug builds) is recorded per pushed head above: every head whose workflows ran to completion is green. This closure never claims the played experience, audible output, or device behavior was validated.

## Observed defects / follow-ups

None reported by this evidence template. Add only **observed** problems with stage/wave, repro, expected/actual, severity and fix PR or Linear issue. Keep new art/SFX work separate from code work.
