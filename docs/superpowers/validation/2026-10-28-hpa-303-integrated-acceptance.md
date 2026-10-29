# HPA-303 — Integrated acceptance evidence

**Linear:** [HPA-303](https://linear.app/cwchanap/issue/HPA-303/product-make-orion-welcoming-worth-replaying-and-audible) · **PR:** [#45](https://github.com/cwchanap/orion/pull/45)  
**Status:** Evidence template only; **no human simulator or hardware validation is claimed**.  
**Date / app commit / tester:** Not yet recorded.

## Automated verification (CI, not a listening or UX test)

The [CI workflow](../../../.github/workflows/ci.yml) already checks formatting, analysis, web build, Flutter tests, the Python audio asset contract and an **Android API 34 emulator smoke test with `-noaudio`**. [iOS](../../../.github/workflows/build-ios.yml) and [Android](../../../.github/workflows/build-android.yml) build workflows run on PRs. Check their conclusions against the **latest tested PR head** after any subsequent commit; older green checks do not prove the new head.

| Required run | Latest head SHA | Result | GitHub Actions link |
| --- | --- | --- | --- |
| CI (build/lint, tests, audio asset contract, emulator integration) | Not checked | Not checked | — |
| build-ios (debug) | Not checked | Not checked | — |
| build-android (debug) | Not checked | Not checked | — |

For reference only, all three workflows succeeded on the **previous** head `7648c2d`: [CI run 40743300548](https://github.com/cwchanap/orion/actions/runs/40743300548), [iOS run 40743300875](https://github.com/cwchanap/orion/actions/runs/40743300875), [Android run 40743300719](https://github.com/cwchanap/orion/actions/runs/40743300719). This is **not** validation of the current/final head or audible output.

## Manual criterion × environment

Use **Pass / Fail / Blocked / Skipped (owner decision) / Not run** in each relevant cell. Label all actual observations by environment; a simulator pass never satisfies a physical-device criterion. Put concrete observations, tested build/OS, and repro or Linear follow-up in the final column. **Not run is not Pass.**

| Criterion | iOS Simulator | Physical iPhone | Physical Android | Observations / follow-up |
| --- | --- | --- | --- | --- |
| Alpha fresh data: build, Wave 1, upgrade, Wave 2 module, Wave 3 scanner **Got it**, force-quit/relaunch **before Alpha result**, no guide | Not run | Not run | Not run | — |
| Independent fresh/replayed Alpha: **Skip**, force-quit/relaunch before Alpha result, no guide | Not run | Not run | Not run | — |
| Later hints (unlocks through Wave 6, specialization, targeting, boss preview, modifier); Replay Tutorial vs Reset Campaign | Not run | Not run | Not run | — |
| Alpha boss first-committed-clear blueprint in report; **relaunch** then map/briefing; replay adds no duplicate | Not run | Not run | Not run | — |
| Later-stage boss reward + modifier; seven mappings and failed-save case covered by unit tests | Not run | Not run | Not run | — |
| Music transitions/seams and Music × SFX switches; pause/background/relaunch persistence | Not run | Not run | Not run | — |
| Combat SFX recognizable at 1× / not overwhelming at populated 3× | Not run | Not run | Not run | Simulator listens through Mac, not device speakers |
| Real hardware input responsiveness/frame stutter and native audio balance at 3× | Not run | Not run | Not run | Physical-device evidence required; simulator result is not representative |
| iOS silent switch, external mixing and interruptions | Not run | Not run | Not run | iPhone-specific; do not infer from simulator |
| Android native playback and audio/lifecycle behavior | Not run | Not run | Not run | Android-specific; CI emulator runs with audio disabled |
| Physical-device Alpha fresh start **and** one modified later stage | Not run | Not run | Not run | At least one real device or explicit owner waiver required |

## Environment, blockers, and decision

- **Simulator availability:** unverified for this execution. Run `xcrun simctl list devices available` and `flutter devices`; select a short portrait iPhone if available. Existing machine inventory mentioned in review is not proof of availability here.
- **Physical iPhone:** known prior blocker: Developer Mode disabled (HPA-417). Attempt enabling it and launching the app; document updated observation.
- **Physical Android:** prior blocker: `adb` missing (HPA-417). Only install platform-tools if an Android device is available and needed.
- **Actual simulator/hardware build, OS, sound outputs, levels, exact app SHA:** Not recorded.
- **Owner decision if hardware is still blocked:** Not requested/not recorded. Prior HPA-417 waiver does **not** automatically waive HPA-303.
- **Final disposition:** Pending. Never mark hardware-only checks Pass from automated tests or simulator playback.

## Observed defects / follow-ups

None reported by this evidence template. Add only **observed** problems with stage/wave, repro, expected/actual, severity and fix PR or Linear issue. Keep new art/SFX work separate from code work.
