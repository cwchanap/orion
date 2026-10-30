# HPA-303 — Integrated acceptance implementation plan

> **One ticket / one PR:** keep the design, this plan, validation evidence and any narrow fixes on `plan/hpa-303-integrated-acceptance` / [PR #45](https://github.com/cwchanap/orion/pull/45). The validation record is now closed on documented owner exceptions; **no simulator or physical-device testing was performed** — the unchecked items below carry their outcomes.

**Linear:** [HPA-303](https://linear.app/cwchanap/issue/HPA-303/product-make-orion-welcoming-worth-replaying-and-audible)  
**Design:** [Integrated acceptance specification](../specs/2026-10-28-hpa-303-integrated-acceptance-design.md)  
**Single source of results:** [Platform-specific validation record](../validation/2026-10-28-hpa-303-integrated-acceptance.md)

## 0. Reuse the existing implementation and CI

- [x] Verify HPA-412/413/415/416/417 feature PRs and HPA-168 music assets are merged; do not duplicate them.
- [x] Confirm existing guide/tip stores, seven boss-blueprint rules/tests, independent Music/SFX toggles and audio contract.
- [x] Identify the known HPA-417 real-device limitations: iOS Developer Mode disabled and Android `adb` absent.
- [x] Create a criterion × platform validation table with **Not run** values, instead of scattering results across this plan and the PR checklist.

**Automated baseline:** reuse the existing [CI workflow](../../../.github/workflows/ci.yml) on PR pushes, which runs Dart formatting, `flutter analyze`, `flutter build web --release`, `flutter test --coverage`, Python audio contract tests and `flutter test integration_test` on an API 34 Android emulator. The emulator uses `-noaudio`, and the integration smoke test disables Music/SFX/Haptics, so **neither can establish audible acceptance**. Also reuse the existing [build-ios](../../../.github/workflows/build-ios.yml) and [build-android](../../../.github/workflows/build-android.yml) workflows.

- [x] Record links and conclusions of **all three green workflows** for each pushed head in the validation record — a committed file cannot name its own head, so the PR checks tab is authoritative for the final head. Older successful runs (including `7648c2d`) are background only, not evidence for a new head.
- [ ] If any required CI job is red/missing, investigate or rerun it before claiming a pass; don't add duplicate local invocations or a device-farm framework merely to restate CI. **Outcome: not triggered — every pushed head's required jobs were green or superseded.**
- [ ] Reuse existing blueprint isolation, committed/repeat-clear, guide/tips and preference tests. Add a focused regression test only if an actual uncovered defect is discovered. **Outcome: no defect discovered; no test added.**

## 1. Simulator-first Alpha walkthrough (independent of hardware access)

> **Outcome (2026-10-29):** every unchecked task in this section was **skipped by owner decision** — no simulator run was performed; see the validation record.

- [x] Verify a bootable iOS Simulator with `xcrun simctl list devices available` and `flutter devices`; select a small portrait iPhone. The review previously reported booted iPhone 16/17 Simulators, but **re-enumerate** at execution rather than assuming availability. If no simulator can run, record the blocker and only then choose another available local target.
- [ ] Start with **fresh app data**, not only Reset Campaign. Enter Alpha briefing, select a buildable cell, place Laser (tap/drag), start Wave 1, upgrade after a wave clear, and choose the first Salvage Module after Wave 2.
- [ ] Continue to **Wave 3 build**, deselect tower/cell, find the accessible scanner callout and tap **Got it** — starting the wave while that lesson is active writes completion too. The module pick alone is **not** completion.
- [ ] **Force-quit and relaunch before completing Alpha** (before any saved stage result can trigger inferred guide completion). Re-enter Alpha and verify the guided callout does not reappear. Separately test **Skip** from a fresh or deliberately replayed guide, then force-quit/relaunch **before Alpha has a result** and verify Skip persisted. Do not mistake a saved Alpha result for a successful tutorial-write test.
- [ ] Check Skip/Got it, tower cards, radial controls, scanner, module draft and Wave button are tap-safe on a short portrait viewport. Reuse the existing automated small-viewport tests; no new harness.
- [ ] Continue to waves 2–6 and the boss preview on Wave 8: inspect later tower-unlock, specialization, targeting and boss hints (one at a time, true target, no Wave obstruction). Replay Tutorial should restore the HPA-412 guide and HPA-413 tips; Reset Campaign alone should not.

## 2. Simulator-first rewards, modified stage, and audio

> **Outcome (2026-10-29):** every unchecked task in this section was **skipped by owner decision** — no simulator run was performed; see the validation record. The automated tests referenced below did run in CI.

- [ ] Clear Alpha's named boss. Verify Mission Report's blueprint reward, then **force-quit/relaunch and inspect the world map and Alpha briefing** to prove the committed unlock persisted. Replay Alpha and check there is no duplicate reward.
- [ ] Enter a later modified stage (e.g. Nebula Relay), verify the first modifier-tip anchor, and if feasible clear its boss and repeat the report → **relaunch** → map/briefing check. Rely on `test/game/run_module_unlocks_test.dart` for the other five mappings and the union-across-clears, and on `test/widget_test.dart` for failed/uncommitted saves and repeat-clear reward suppression; do not manually clear all seven stages.
- [ ] On the simulator, listen through the **Mac audio output** for map/build/wave/boss transitions and loop seams. Exercise Music × SFX combinations, settings persistence across relaunch, pause/resume, foreground/background, victory/defeat stops and SFX distinguishability at 1× and populated 3×. Note whether audio is actually audible; simulator playback is a useful iOS app-level observation **but is not physical-device proof**.
- [ ] In the [validation record](../validation/2026-10-28-hpa-303-integrated-acceptance.md), mark each observed simulator criterion **Pass (iOS Simulator)** or **Fail (iOS Simulator)** and record build/OS, output device, tested SHA and reproduction details. Leave unobserved checks Not run/Blocked; don't infer real-world frame time, speaker balance or hardware audio mixing from simulator performance.

## 3. Hardware-only gates and owner decision

> **Outcome (2026-10-29):** the paired-iPhone path was never attempted (Developer Mode status unconfirmed, no install/run) and no Android device was available; all hardware-only rows were **skipped by owner decision** — see the validation record.

- [ ] **Prefer the already-paired iPhone first:** enable Developer Mode in Settings → Privacy & Security, restart as prompted, confirm `flutter devices` and successful launch. Then perform the parent's Alpha-first-run and one later modified-stage physical playthrough; verify 1×/3× balance and responsiveness, iOS silent switch, mixing and interruption behavior.
- [ ] If an actual Android device is available and Android validation is desired, install Android platform-tools if needed, confirm `adb devices`, then check Android native playback/lifecycle separately. The no-audio CI emulator cannot replace this.
- [x] If the physical device remains blocked, obtain the **owner's explicit waiver or Blocked decision for these hardware-only rows**. This decision must not block the available simulator tasks above. The earlier HPA-417 listening waiver does **not** automatically waive HPA-303.
- [x] Record **Pass / Fail / Blocked / Skipped (owner decision)** independently for iOS Simulator, physical iPhone and physical Android. A simulator pass is **not** a physical-device pass, and a waiver never implies successful playback.

## 4. Evidence and defect triage

- [x] **Update the already-committed** [validation record](../validation/2026-10-28-hpa-303-integrated-acceptance.md); do **not** recreate or duplicate its results table here. Use the CI and environment sections plus one row per criterion, with separate iOS Simulator / iPhone / Android results and concrete observations.

For any observed failure, log the stage/wave/setting, exact reproduction steps, expected/actual behavior and severity. Fix only a narrow defect belonging to HPA-303 **within this same PR**, with a focused regression test. Move unrelated polish into its own focused ticket/PR; fresh art or SFX must be a separate asset task.

## 5. Completion gate

- [x] Verify **CI, build-ios and build-android green on the latest PR head** — read from the PR checks tab, since a committed record cannot name its own head (the validation record lists every pushed head's runs). If production code changes, wait for the newly triggered workflows to pass and **repeat the affected manual simulator/hardware rows**; record their actual updated-build outcome. Documentation-only changes likewise need the final CI confirmation, but do not pretend they were a manual run.
- [x] The evidence record accurately distinguishes simulator observations, physical results, blocked checks, owner waivers, and untouched rows.
- [x] Keep PR #45 Draft until the evidence and owner decisions justify review. Close HPA-303 only after its parent criteria actually pass or documented owner exceptions explicitly cover the unverified cases enumerated in the validation record (hardware-only, audio-listening, and non-audio simulator walkthrough rows).

**No new frameworks, CI jobs, feature development, new assets, save migrations, gameplay balance changes, or multiple PRs for HPA-303.**
