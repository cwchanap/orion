# HPA-526 Salvage Module Tuning and Campaign Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate Orion's current seven-module Salvage Module catalog and full seven-stage campaign at ordinary 1× play, finishing HPA-526 without runtime changes unless a concrete player-facing defect is observed.

**Architecture:** Preserve the current `GameSession` → `GameSnapshot` → Flutter/Flame boundaries and treat the seven-module catalog as the candidate final state. HPA-526 is an evidence-and-triage task: close the outstanding HPA-528 human product proof, verify current main, perform one seven-stage human pass, then either finish with zero code or open narrowly scoped follow-up issues for observed problems. Do not speculate a runtime implementation before the defect exists.

**Tech Stack:** Flutter, Dart 3.12+, Flame, `flutter_test`, Linear for human validation notes and focused follow-up issues.

## Global Constraints

- Keep the current seven-module catalog unchanged unless the human pass identifies a concrete player-facing need.
- Do not target a mandatory 10–12 module count.
- Do not add picker history, weighting, pity, deterministic seeds, offer fingerprints, or statistical sweeps without an observed picker defect.
- Do not add a generic event/effect system or a new persistence model.
- Additional blueprint rewards require an HPA-528 **Proceed** verdict and a specific progression reason.
- Do not add a Modules Codex unless observed comprehension problems justify it.
- Record human notes directly in HPA-526; do not create an evidence-export subsystem or permanent run-log schema.
- Open a separate focused Linear issue for each concrete bug/readability/balance problem worth fixing.
- Rerun only stages materially affected by an accepted follow-up fix.
- Normal campaign completion must remain comfortable, offline, and free of grind/daily-engagement mechanics.

---

### Task 1: Close the HPA-528 Human Blueprint Product Gate

**Files:**
- Modify: none
- Record result: Linear `HPA-526`

**Interfaces:**
- Consumes: existing HPA-528 first-clear reward implementation, `RunModuleUnlocks.availableFor(CampaignProgress)`, same-object Replay flow in `OrionGamePage`.
- Produces: one recorded `Proceed`, `Narrow`, or `Stop` verdict controlling whether another boss-blueprint reward may even be considered.

- [ ] **Step 1: Start from an uncleared Outpost Alpha campaign state**

Use the normal app flow on a simulator/device. Reset campaign progress if needed, then launch Outpost Alpha. Do not inject progress or mutate the save directly.

Expected starting state:

```text
Outpost Alpha not cleared
Relay Calibration not eligible for the active attempt
Blueprint surface reports the reward as unrecovered/locked
```

- [ ] **Step 2: Clear Outpost Alpha normally at 1×**

Play through all eight waves and reach the Mission Report.

Expected terminal state before save commit:

```text
Mission result: victory
Blueprint reward: pending while the improved result is saving
Completed attempt: still uses its frozen pre-clear eligible-module set
```

- [ ] **Step 3: Confirm the committed reward transition**

Wait for the existing mission save to succeed.

Expected state:

```text
Mission Report reward changes from pending to recovered
Committed CampaignProgress contains the Outpost Alpha clear
No separate blueprint collection is created
```

If persistence fails, use the existing Retry Save flow. A failed save must not count as blueprint recovery.

- [ ] **Step 4: Replay on the same page/game shell**

Choose **Replay Mission** rather than returning to the map and reconstructing the app.

Verify the new attempt refreshes committed run inputs and Relay Calibration is in the eligible module set. Do **not** require it to appear in the first random three-card offer.

Expected contract:

```text
previous attempt: Relay Calibration unavailable
successful committed clear
same-object Replay
new attempt: Relay Calibration eligible
```

- [ ] **Step 5: Record the product verdict in HPA-526**

Post one concise Linear comment titled `HPA-528 blueprint product gate`. It must include six bullets:

1. First clear → pending reward: `Pass` or `Fail`.
2. Save → recovered reward: `Pass` or `Fail`.
3. Same-object Replay → Relay Calibration eligible: `Pass` or `Fail`.
4. Retroactive unlock in completed attempt: `No` or `Yes`.
5. Verdict: exactly one of `Proceed`, `Narrow`, or `Stop`.
6. Reason: one sentence stating whether the unlock was understandable and rewarding.

Use the verdicts as follows:

- `Proceed`: another blueprint could be considered later only if the campaign pass identifies a reason.
- `Narrow`: keep Relay Calibration as the one proof and do not expand blueprint progression in HPA-526.
- `Stop`: do not add more blueprint rewards; continue only with campaign/module validation.

- [ ] **Step 6: Freeze later blueprint scope**

For `Narrow` or `Stop`, append exactly: `HPA-526 will not add another boss blueprint.`

For `Proceed`, append exactly: `Additional blueprints remain optional and still require a specific need from the seven-stage pass.`

No repository commit is required for this task.

---

### Task 2: Establish a Clean Current-Main Baseline

**Files:**
- Modify: none
- Verify: `lib/game/models/game_models.dart`
- Verify: `lib/game/rules/game_session.dart`
- Verify: `lib/game/rules/module_offer_picker.dart`
- Verify: `lib/game/rules/run_module_rules.dart`
- Verify: `lib/game/rules/run_module_unlocks.dart`
- Test: `test/game/game_session_test.dart`
- Test: `test/game/module_offer_picker_test.dart`
- Test: `test/game/run_module_rules_test.dart`
- Test: `test/game/game_balance_test.dart`

**Interfaces:**
- Consumes: the current seven-module production catalog and current eligibility/picker rules.
- Produces: a known-green software baseline so human observations are not mixed with an existing lint/test failure.

- [ ] **Step 1: Confirm the candidate catalog**

Inspect `RunModuleId` and `runModuleCatalog`. Verify the catalog contains exactly:

```text
Heavy Caliber
Overclock Relay
Long Sight
Emergency Salvage
Cryo Reservoir
Rocket Fusing
Relay Calibration
```

Also confirm:

```dart
GameBalance.moduleDraftWaves == [2, 4, 6]
```

Do not edit values merely to make the validation pass more interesting.

- [ ] **Step 2: Confirm current offer policy**

Inspect `GameSession._moduleCandidates()` and verify the policy remains:

```text
1. available + unacquired modules only
2. universal modules and affinities for already placed tower families
3. if fewer than three, affinities for unlocked tower families
4. if still fewer than three, remaining available modules
```

Inspect `RandomModuleOfferPicker` and verify it remains a policy-free shuffle/take picker.

- [ ] **Step 3: Run the format check**

```bash
dart format --output=none --set-exit-if-changed .
```

Expected: exit 0 and no files changed.

- [ ] **Step 4: Run static analysis**

```bash
flutter analyze
```

Expected: no issues.

- [ ] **Step 5: Run focused Salvage Module tests**

```bash
flutter test \
  test/game/game_session_test.dart \
  test/game/module_offer_picker_test.dart \
  test/game/run_module_rules_test.dart \
  test/game/game_balance_test.dart
```

Expected: all tests pass, including baseline/Relay Calibration eligibility and attempt-freeze coverage.

- [ ] **Step 6: Run the full suite**

```bash
flutter test
```

Expected: all tests pass.

If unchanged main fails, treat that as a separate pre-existing defect. Do not tune Salvage Modules to hide an unrelated failure.

No repository commit is required for this task.

---

### Task 3: Run the Seven-Stage 1× Product Validation

**Files:**
- Modify: none
- Record result: Linear `HPA-526`

**Interfaces:**
- Consumes: the known-green seven-module build from Task 2 and the blueprint verdict from Task 1.
- Produces: one compact qualitative observation row for every campaign stage.

- [ ] **Step 1: Use one observation schema for every run**

Record exactly these fields for each stage:

```text
Result: Clear, or Loss plus failed wave
Length: Short / Comfortable / Long
Difficulty: 1–5
Modules: selected module names
Offers: concise note on understandability/usefulness
Cards: dead / mandatory / repetitive / confusing, or None
Identity: whether environmental modifier and boss were noticeable
Mobile UX: readability/control problem, or None
Comfort: one sentence on comfortable clearability
```

Do not add per-wave economy tables, seeds, screenshots for every wave, or generated evidence files.

- [ ] **Step 2: Play Outpost Alpha at 1×**

Use normal player inputs and normal random module offers. Record the observation row. Pay particular attention to whether the baseline stage still teaches the module loop cleanly now that the broader reward/feedback loop is present.

- [ ] **Step 3: Play Nebula Relay at 1×**

Record the row. Check whether shield recharge remains noticeable and whether module choices encourage a reasonable build rather than a mandatory one.

- [ ] **Step 4: Play Salvage Rift at 1×**

Record the row. Check whether swarm bounty and the side-stage reward feel distinct without making Emergency Salvage obviously mandatory or irrelevant.

- [ ] **Step 5: Play Asteroid Foundry at 1×**

Record the row. Check whether reinforced armor is noticeable and whether more than one sensible damage strategy remains viable.

- [ ] **Step 6: Play Aurora Gate at 1×**

Record the row. Check whether regen pressure pulses remain understandable and whether module intermissions improve rather than disrupt mixed-pressure pacing.

- [ ] **Step 7: Play Void Bastion at 1×**

Record the row. Check the reduced-health/enhanced-clear-bonus combination for comfort and whether the module loop offers interesting choices rather than one required card.

- [ ] **Step 8: Play Singularity Core at 1×**

Record the row. Check final-stage length, visual density, boss clarity, environmental-modifier visibility, and whether the current module pool still creates meaningful choice under the hardest mixed pressure.

- [ ] **Step 9: Post one complete seven-row Linear table**

Create one Markdown table in HPA-526 with these columns, in this order:

```text
Stage | Result | Length | Difficulty | Modules | Offers | Card problems | Modifier/Boss | Mobile UX | Comfort
```

The table must contain exactly these seven stage rows, in campaign order:

```text
Outpost Alpha
Nebula Relay
Salvage Rift
Asteroid Foundry
Aurora Gate
Void Bastion
Singularity Core
```

Populate every cell from the actual run before posting. Do not post a partially filled table.

No repository commit is required for this task.

---

### Task 4: Apply the HPA-526 Triage Rules

**Files:**
- Modify: none in HPA-526 itself
- Create: focused Linear follow-up issues only when a concrete problem meets the criteria below

**Interfaces:**
- Consumes: all seven observation rows from Task 3 and the HPA-528 verdict from Task 1.
- Produces: either a deliberate no-code final catalog decision or a small set of independently actionable follow-up issues.

- [ ] **Step 1: Check whether catalog expansion is justified**

Across all seven rows, answer only these questions:

```text
Did the player repeatedly lack a meaningful strategic choice?
Did multiple offers collapse into the same practical decision?
Is there a tower/build pattern with no useful run-level support that is not already covered by specialization or tech?
```

If all answers are `No`, record exactly:

```text
Catalog decision: keep the current seven modules. No expansion justified.
```

Do not brainstorm extra cards for variety.

- [ ] **Step 2: Create one issue per concrete module-value defect**

A balance follow-up is justified only when a named module is observed as repeatedly weak, repeatedly mandatory, materially confusing, or an obvious comfort/clearability problem.

Each issue must include:

- the actual affected stage names;
- the actual module name;
- the observed symptom in one or two sentences;
- the minimal run/build context needed to reproduce it;
- a smallest-change expectation: tune existing `RunModuleDefinition`/`RunModuleRules` behavior without new architecture;
- validation: focused rule/catalog coverage, format, analyze, full tests, and only materially affected 1× stage reruns.

Do not combine unrelated module problems into one issue.

- [ ] **Step 3: Create an offer-policy issue only for a concrete bad offer state**

Examples that qualify: repeated impossible/pivot-only choices or a clearly harmful repetition pattern recorded during actual runs.

The follow-up must prefer this repair order:

```text
1. candidate eligibility in GameSession
2. picker behavior only if the defect is genuinely random-selection policy
```

Explicitly exclude complete offer history, weighted ranking, deterministic protocols, and seed sweeps.

- [ ] **Step 4: Create a new-module issue only for a distinct missing player purpose**

Before opening it, compare the observed gap against:

```text
current seven run modules
all tower specializations
campaign tech upgrades
side-stage rewards
```

If a distinct gap remains, describe the missing **player-facing purpose**, not a preselected mechanism. The issue must require reuse of existing `RunModuleDefinition` stat fields when possible. If the useful effect requires a new combat/event seam, the issue must require a focused design before implementation rather than silently broadening HPA-526.

- [ ] **Step 5: Apply the blueprint verdict**

For `Narrow` or `Stop`, create no additional blueprint issue.

For `Proceed`, still create no blueprint issue unless Task 3 reveals a specific progression reason for another permanent option unlock. “Reward every boss” alone is insufficient.

- [ ] **Step 6: Check Codex need**

If no repeated comprehension problem appears, record exactly:

```text
Codex Modules section: not justified.
```

Only create a Codex follow-up if actual runs show players cannot understand or remember module options using the current draft and Mission Report surfaces.

No repository commit is required for this task.

---

### Task 5: Publish the Final HPA-526 Decision and Close the Slice

**Files:**
- Modify: none unless a separately accepted follow-up issue later changes runtime code
- Record result: Linear `HPA-526`

**Interfaces:**
- Consumes: Task 1 blueprint verdict, Task 2 software baseline, Task 3 seven-stage table, Task 4 follow-up links.
- Produces: the final M2 product decision and bounded handoff for any remaining work.

- [ ] **Step 1: Record the overall comfort verdict**

Write a short paragraph answering both questions:

```text
Is the current campaign comfortably clearable at normal 1× play?
Does the Salvage Module loop still improve run identity across the full campaign?
```

Do not turn this into a release-certification report.

- [ ] **Step 2: Record cross-stage module findings**

Add four bullets named `Weak`, `Mandatory`, `Repetitive`, and `Confusing`. Each bullet lists the actual module names that mattered across runs, or `None` when the pass does not support a complaint.

- [ ] **Step 3: Record material stage findings**

List only stages that were materially too long, too easy, too hard, or visually/readability dense. Link each item to its focused follow-up issue when one exists.

- [ ] **Step 4: State one final catalog outcome**

Use exactly one of these outcomes:

```text
A. Keep seven modules; no expansion justified.
B. Keep seven for now; focused balance/offer follow-ups must be validated before reconsidering expansion.
C. A distinct missing module purpose was observed; follow the linked focused feature issue/design before changing the catalog.
```

Then state the HPA-528 `Proceed`, `Narrow`, or `Stop` verdict separately so blueprint progression is not conflated with catalog size.

- [ ] **Step 5: Reconfirm repository health if main changed during manual validation**

If main has not changed since Task 2, reuse Task 2's green baseline. If main moved, rerun:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Expected: all pass.

- [ ] **Step 6: Complete HPA-526**

Once the seven-stage table, final verdict, and follow-up links are present, move HPA-526 to Done even if focused follow-up issues remain open. Those issues own their own fixes and targeted retests; HPA-526 must not become an indefinite balance bucket.

If the final outcome is `A`, no runtime commit is expected. Finishing with the planning docs plus Linear validation evidence is intentional.

---

## Self-Review Against the Design

- HPA-528 human proof is the first execution gate rather than assumed complete.
- The current seven-module catalog is explicitly the candidate final catalog.
- All seven campaign stages get one human 1× attempt.
- The required difficulty, length, module, offer, boss/modifier, mobile-readability, and clearability observations are recorded.
- No code change is invented without a concrete observation.
- Concrete problems are split into focused follow-up issues as HPA-526 requires.
- Picker, persistence, Codex, blueprint, and new-effect expansion remain evidence-gated.
- Formatting, analysis, focused tests, and the full suite remain the software verification baseline.
- The plan has a legitimate zero-runtime-code completion path.
