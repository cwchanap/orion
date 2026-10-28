# HPA-303 — Integrated acceptance implementation plan

> **One ticket, one PR.** Use `plan/hpa-303-integrated-acceptance` for the design, this plan, final validation record, and any tiny directly related corrections. Do not open a second PR for HPA-303. This initial draft contains plans only; no validation has been performed.

**Issue:** [HPA-303](https://linear.app/cwchanap/issue/HPA-303/product-make-orion-welcoming-worth-replaying-and-audible)  
**Design:** [Integrated acceptance design](../specs/2026-10-28-hpa-303-integrated-acceptance-design.md)

## 0. Baseline before testing

- [x] Verify all five implementation tickets HPA-412/413/415/416/417 are Done and their feature PRs merged; HPA-168 music assets also merged.
- [x] Identify the unresolved physical-device gap in [HPA-417's validation record](../validation/2026-10-27-hpa-417-music-ambience.md).
- [x] Reuse existing docs and test suites, not a new validation framework.
- [ ] Freeze current `main` commit SHA when executing, record device/build/platform and any active owner waivers.
- [ ] Confirm existing automated coverage for seven boss-module mappings, duplicate first-clear prevention, failed saves, context tips, guide skip/replay and feedback/music preferences. Only add a focused regression test if a genuine gap is found.

**Evidence:** prior merge reports recorded a full 1,286-test pass after HPA-417/168 integration. This plan does not assert that the tests were rerun on the eventual validation commit.

## 1. Run automated baseline (no code changes expected)

From an up-to-date checkout:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release
```

Run `flutter test integration_test/app_smoke_test.dart -d <connected-device>` where the local integration runner supports it. This smoke test forces sound effects, haptics, and music off; do **not** treat it as audio verification.

Record each command as Pass / Fail / Not run with reason. Avoid altering production rules or slowing CI just to make a manual acceptance checklist automatic.

## 2. Human Alpha run — clean onboarding and rewards

- [ ] **Restore physical-device access first:** enable iOS Developer Mode on the test iPhone, or install Android platform-tools (`adb`) for an available Android device; then confirm `flutter devices` lists a usable target and the app can launch. If neither path works, obtain and record the owner's explicit **waiver or blocked-status decision before proceeding with §§2–3**; never interpret an unavailable device as successful acceptance.
- [ ] Make an expendable truly fresh app-data state (or a clean install). Prefer the physical device; avoid accidentally evaluating a previously acknowledged tutorial.
- [ ] Enter Alpha from the world map, read briefing, tap a free board cell, select Laser, start Wave 1, upgrade between waves, pick one Salvage Module after Wave 2. Check skip independently in a fresh/replayed guide flow.
- [ ] At a small portrait viewport check that Got it / Skip, tower cards, radial actions, scanner, module picker, and Start Wave can all be tapped; probe tap and drag paths. No permanent tutorial overlays after completion.
- [ ] Continue to Wave 6: verify tower-unlock hints, specialization and targeting tips at the actual anchor. Check boss preview before Wave 8 without blocking Start Wave. Replay Tutorial should restore both layers of guidance, while Reset Campaign should not silently reset them.
- [ ] Clear Alpha's named boss, observe module blueprint in Mission Report and world map/briefing, then replay to confirm no duplicate reward. Capture the post-save state (not an in-memory pre-commit impression).

## 3. Later-stage run and sound pass

- [ ] Enter a later stage with a modifier (e.g. Nebula Relay), verify a once-only modifier briefing hint and continued access to real controls. Clear the boss if feasible and verify its blueprint.
- [ ] At 1×, with SFX on, listen for shots, impacts, kills, core leak, wave start, boss arrival and defeat. Raise to 3× on a reasonably populated board and check for distinguishability, excessive repeated sound, input lag, or perceptible stutter.
- [ ] Listen separately for music on map, build, wave and boss; inspect loop boundaries and navigation/mission-result stops. Test pause/resume, app background/return, settings persistence across relaunch and all four Music × Sound Effects combinations. Verify Haptics as a separate toggle.
- [ ] If possible check iOS silent mode/mixing and Android native playback independently. Never promote a desktop/browser or one-platform result to a second-platform claim.
- [ ] If hardware cannot run the app (known HPA-417 iOS Developer Mode and missing Android `adb` blockers), do **not** mark audio/whole-playthrough checks passed. Record Blocked or owner-approved Skipped and move to the decision step.

## 4. Record findings, triage only observed issues

Create `docs/superpowers/validation/2026-10-28-hpa-303-integrated-acceptance.md` after executing checks. Suggested compact table:

| Criterion | Result | Evidence | Follow-up |
| --- | --- | --- | --- |
| Fresh onboarding + skip | Not run | — | — |
| Contextual tips | Not run | — | — |
| Seven first-clear blueprints | Not run | — | — |
| Combat SFX 1× / 3× | Not run | — | — |
| Independent music and lifecycle | Not run | — | — |
| Real-device Alpha + later stage | Not run | — | — |

For each failure, note reproduction (stage, wave, settings, action), expected/actual, and severity. Repair only clearly scoped integration problems in this **same PR**, with an appropriate focused test. Put unrelated improvements into a focused Linear ticket and its own PR; never expand HPA-303 into a polish backlog. Any fresh images/SFX must be produced under a separate asset task.

## 5. Completion gate

- [ ] Final validation record truthfully separates observed, automated-only, blocked and owner-waived acceptance; list exact commit tested and any device limitations.
- [ ] If production code changed, re-run the **full §1 command block** plus the **manual acceptance row(s) affected by the fix**; record results against the updated commit. If documents alone changed, disclose that no runtime tests were run for the docs commit.
- [ ] Keep the PR Draft while essential checks or owner decisions remain open. When complete, update this same PR with the evidence, request review, and link it to HPA-303 in Linear.
- [ ] Mark HPA-303 Done only after its actual parent acceptance conditions are satisfied or an explicit owner-approved exception is recorded. A waiver is **not** proof the audio passed.

**Not in this plan:** additional implementation phases, arbitrary integration-test frameworks, new assets, music generation, gameplay tuning, broad cross-platform rewrites, or a second PR tied to HPA-303.
