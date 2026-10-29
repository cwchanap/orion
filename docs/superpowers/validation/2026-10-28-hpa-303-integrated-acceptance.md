# HPA-303 — Integrated acceptance evidence

**Linear:** [HPA-303](https://linear.app/cwchanap/issue/HPA-303/product-make-orion-welcoming-worth-replaying-and-audible) · **PR:** [#45](https://github.com/cwchanap/orion/pull/45)  
**Status:** Evidence template only; **no human simulator or hardware validation is claimed**.  
**Date / app commit / tester:** Not yet recorded.

## Automated verification (CI, not a listening or UX test)

The [CI workflow](../../../.github/workflows/ci.yml) already checks formatting, analysis, web build, Flutter tests, the Python audio asset contract and an **Android API 34 emulator smoke test with `-noaudio`**. [iOS](../../../.github/workflows/build-ios.yml) and [Android](../../../.github/workflows/build-android.yml) build workflows run on PRs. Check their conclusions against the **latest tested PR head** after any subsequent commit; older green checks do not prove the new head.

All three workflows below ran on `pull_request` events for the **latest tested head** `1bb4d68` (`1bb4d6870ae8ffe35b970e1856d6d6c0b01a4640`, branch `plan/hpa-303-integrated-acceptance`) and completed 2026-10-29 with conclusion **success** (machine-verified, 2026-10-29). The app under test is unchanged since the last code-bearing head: the commits on top are docs-only.

| Required run | Latest head SHA | Result | GitHub Actions link |
| --- | --- | --- | --- |
| CI (build/lint, tests, audio asset contract, emulator integration) | `1bb4d6870ae8ffe35b970e1856d6d6c0b01a4640` | Success | [run 40813451997](https://github.com/cwchanap/orion/actions/runs/40813451997) |
| build-ios (debug) | `1bb4d6870ae8ffe35b970e1856d6d6c0b01a4640` | Success | [run 40813451980](https://github.com/cwchanap/orion/actions/runs/40813451980) |
| build-android (debug) | `1bb4d6870ae8ffe35b970e1856d6d6c0b01a4640` | Success | [run 40813452002](https://github.com/cwchanap/orion/actions/runs/40813452002) |

For reference only, all three workflows succeeded on the **previous** head `baa90da` (`baa90dae2018b59fd7d2b1ce32b1c7c1459dc0fb`): [CI run 40803202404](https://github.com/cwchanap/orion/actions/runs/40803202404), [iOS run 40803204254](https://github.com/cwchanap/orion/actions/runs/40803204254), [Android run 40803202457](https://github.com/cwchanap/orion/actions/runs/40803202457). This is **not** validation of the current/final head or audible output.

## Manual criterion × environment

Use **Pass / Fail / Blocked / Skipped (owner decision) / Not run** in each relevant cell. Label all actual observations by environment; a simulator pass never satisfies a physical-device criterion. Put concrete observations, tested build/OS, and repro or Linear follow-up in the final column. **Not run is not Pass.**

| Criterion | iOS Simulator | Physical iPhone | Physical Android | Observations / follow-up |
| --- | --- | --- | --- | --- |
| Alpha fresh data: build, Wave 1, upgrade, Wave 2 module, Wave 3 scanner **Got it**, force-quit/relaunch **before Alpha result**, no guide | Not run | Not run | Not run | — |
| Independent fresh/replayed Alpha: **Skip**, force-quit/relaunch before Alpha result, no guide | Not run | Not run | Not run | — |
| Later hints (unlocks through Wave 6, specialization, targeting, boss preview, modifier); Replay Tutorial vs Reset Campaign | Not run | Not run | Not run | — |
| Alpha boss first-committed-clear blueprint in report; **relaunch** then map/briefing; replay adds no duplicate | Not run | Not run | Not run | — |
| Later-stage boss reward + modifier; seven mappings and failed-save case covered by unit tests | Not run | Not run | Not run | — |
| Music transitions/seams and Music × SFX switches; pause/background/relaunch persistence | Skipped (owner decision) | Skipped (owner decision) | Skipped (owner decision) | Audio listening waived by owner decision 2026-10-29; not verified. |
| Combat SFX recognizable at 1× / not overwhelming at populated 3× | Skipped (owner decision) | Skipped (owner decision) | Skipped (owner decision) | Simulator listens through Mac, not device speakers. SFX listening waived by owner decision 2026-10-29; not verified. |
| Real hardware input responsiveness/frame stutter and native audio balance at 3× | Not run | Skipped (owner decision) | Skipped (owner decision) | Physical-device evidence required; simulator result is not representative |
| iOS silent switch, external mixing and interruptions | Not run | Skipped (owner decision) | Skipped (owner decision) | iPhone-specific; do not infer from simulator |
| Android native playback and audio/lifecycle behavior | Not run | Skipped (owner decision) | Skipped (owner decision) | Android-specific; CI emulator runs with audio disabled |
| Physical-device Alpha fresh start **and** one modified later stage | Not run | Skipped (owner decision) | Skipped (owner decision) | At least one real device or explicit owner waiver required |

## Environment, blockers, and decision

- **Simulator availability:** re-enumerated at execution on 2026-10-29 via `xcrun simctl list devices available` and `flutter devices` (iOS 26.5 runtime): iPhone 17 — booted, UDID `4553E2C4-0B9D-416F-A36C-2F99E9EA48C6`; iPhone 16 — booted, UDID `00CA5728-2DD8-4317-A6DA-8FF8B6D2D67D`; HPA475-iPad — booted, UDID `DE515BB3-47E9-451F-8D9F-9105A4FD3364`; HPA475-SE — shutdown, UDID `248B0BE8-7437-4B6E-BC6B-4384AC7699A6`. A small portrait iPhone target is available (iPhone 17 / iPhone 16); for the plan §1 tap-safety check the small/short-viewport option is HPA475-SE (currently shutdown; boot when needed). This is an availability check only — no app install/run has been performed yet.
- **Physical iPhone:** known prior blocker: Developer Mode disabled (HPA-417). Attempt enabling it and launching the app; document updated observation. `flutter devices` on 2026-10-29 also listed macOS, Chrome (web), and one physical iPhone (4), iOS 27.0.1, wireless — observed only; Developer Mode status unconfirmed and no install/run attempted, so this is not validation.
- **Physical Android:** prior blocker: `adb` missing (HPA-417). Only install platform-tools if an Android device is available and needed.
- **Actual simulator/hardware build, OS, sound outputs, levels, exact app SHA:** Not recorded.
- **Owner decision (2026-10-29):** owner explicitly waived the hardware-only checks (physical iPhone and physical Android rows) and all audio-listening checks (simulator Mac-output music/SFX listening included). This waiver is an acceptance of unverified exceptions, **not** a pass: loop seams, 1×/3× balance, silent switch, external mixing/interruptions, and Android native playback remain unverified on real devices. Distinct from, and broader than scope-wise complementary to, the prior HPA-417 waiver, which never covered HPA-303.
- **Final disposition:** Hardware and audio-listening checks closed as Skipped (owner decision, 2026-10-29). The non-audio simulator walkthrough rows (guide/Skip persistence, later hints, boss and modified-stage reward persistence) remain **Not run** and still gate plan §5 and HPA-303 closure. Never mark hardware-only checks Pass from automated tests or simulator playback.

## Observed defects / follow-ups

None reported by this evidence template. Add only **observed** problems with stage/wave, repro, expected/actual, severity and fix PR or Linear issue. Keep new art/SFX work separate from code work.
