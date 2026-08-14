# HPA-526 Salvage Module Tuning and Campaign Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate Orion's current seven-module Salvage Module catalog and full seven-stage campaign at ordinary 1× play, finishing HPA-526 without runtime changes unless a concrete player-facing defect is observed.

**Architecture:** Preserve the current `GameSession` → `GameSnapshot` → Flutter/Flame boundaries and treat the seven-module catalog as the candidate final state. HPA-526 is an evidence-and-triage task: close the outstanding HPA-528 product proof, verify current main, perform one seven-stage human pass, then either finish with zero code or open narrowly scoped follow-up issues for observed problems. Do not speculate a runtime implementation before the defect exists.

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
- Produces: one recorded `Proceed`, `Narrow`, or `Stop` verdict that controls whether any additional boss-blueprint work may be considered.

- [ ] **Step 1: Start from an uncleared Outpost Alpha campaign state**

Use the normal app flow on a simulator/device. Reset campaign progress if needed, then launch Outpost Alpha. Do not inject progress or directly mutate the save.

Expected starting product state:

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
Current completed attempt: still uses its frozen pre-clear eligible-module set
```

- [ ] **Step 3: Confirm the committed reward transition**

Wait for the existing mission save to succeed.

Expected product state:

```text
Mission Report reward changes from pending → recovered
Committed CampaignProgress now contains the Outpost Alpha clear
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

Post one concise Linear comment with this exact structure:

```markdown
## HPA-528 blueprint product gate

- First clear → pending reward: Pass / Fail
- Save → recovered reward: Pass / Fail
- Same-object Replay → Relay Calibration eligible: Pass / Fail
- Retroactive unlock in completed attempt: No / Yes
- Verdict: Proceed / Narrow / Stop
- Reason: <one sentence describing whether the unlock was understandable and rewarding>
```

Use the meanings below without reinterpretation:

- `Proceed`: the unlock is understandable/rewarding enough that another blueprint could be considered later if the campaign pass identifies a reason.
- `Narrow`: keep Relay Calibration as the one proof but do not expand blueprint progression in HPA-526.
- `Stop`: do not add more blueprint rewards; continue only with campaign/module validation.

- [ ] **Step 6: Gate later scope**

If the verdict is `Narrow` or `Stop`, explicitly add this sentence to the Linear comment:

```text
HPA-526 will not add another boss blueprint.
```

If the verdict is `Proceed`, add:

```text
Additional blueprints remain optional and still require a specific need from the seven-stage pass.
```

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
- Produces: a known-green software baseline so later human observations are not mixed with an existing failing test/lint state.

- [ ] **Step 1: Confirm the catalog is still exactly the intended candidate set**

Inspect `RunModuleId` and `runModuleCatalog` and verify these seven entries are present:

```text
Heavy Caliber
Overclock Relay
Long Sight
Emergency Salvage
Cryo Reservoir
Rocket Fusing
Relay Calibration
```

Also confirm `GameBalance.moduleDraftWaves` remains:

```dart
[2, 4, 6]
```

Do not edit these values merely to make the validation pass more interesting.

- [ ] **Step 2: Confirm the current candidate policy before playtesting**

Inspect `GameSession._moduleCandidates()` and verify the current order of policy remains:

```text
1. available + unacquired modules only
2. universal modules and affinities for already placed tower families
3. if fewer than three, affinities for unlocked tower families
4. if still fewer than three, remaining available modules
```

Inspect `RandomModuleOfferPicker` and verify it remains a policy-free shuffle/take picker.

- [ ] **Step 3: Run format check**

Run:

```bash
dart format --output=none --set-exit-if-changed .
```

Expected: exit 0 and no files changed.

- [ ] **Step 4: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: no issues.

- [ ] **Step 5: Run focused Salvage Module tests**

Run:

```bash
flutter test \
  test/game/game_session_test.dart \
  test/game/module_offer_picker_test.dart \
  test/game/run_module_rules_test.dart \
  test/game/game_balance_test.dart
```

Expected: all tests pass, including the existing baseline/Relay Calibration eligibility and attempt-freeze coverage.

- [ ] **Step 6: Run the full suite**

Run:

```bash
flutter test
```

Expected: all tests pass.

If any command fails on unchanged main, treat that as a separate pre-existing defect. Do not tune Salvage Modules to make an unrelated failure disappear.

No repository commit is required for this task.

---

### Task 3: Run the Seven-Stage 1× Product Validation

**Files:**
- Modify: none
- Record result: Linear `HPA-526`

**Interfaces:**
- Consumes: the known-green seven-module build from Task 2 and the blueprint verdict from Task 1.
- Produces: one compact qualitative observation row for every campaign stage, sufficient to decide whether any follow-up work is justified.

- [ ] **Step 1: Use one fixed observation schema for all seven stages**

For every run, record exactly these fields:

```text
Result: Clear, or Loss + failed wave
Length: Short / Comfortable / Long
Difficulty: 1–5
Modules: selected module names
Offers: Understandable/useful? concise note
Cards: dead / mandatory / repetitive / confusing? concise note or None
Identity: environmental modifier noticeable? boss noticeable?
Mobile UX: readability/control issue or None
Comfort: one sentence on comfortable clearability
```

Do not add per-wave health/economy tables, seeds, screenshots for every wave, or generated evidence files.

- [ ] **Step 2: Play Outpost Alpha at 1×**

Use normal player inputs and normal random module offers. Record the observation row.

Pay particular attention to whether the baseline stage still teaches the module loop cleanly now that Relay Calibration and feedback polish exist in the broader product.

- [ ] **Step 3: Play Nebula Relay at 1×**

Record the observation row.

Check whether shield recharge remains noticeable and whether the available module choices encourage a reasonable build rather than feeling mandatory.

- [ ] **Step 4: Play Salvage Rift at 1×**

Record the observation row.

Check whether swarm bounty and the side-stage reward make the stage feel meaningfully different without making Emergency Salvage obviously mandatory or irrelevant.

- [ ] **Step 5: Play Asteroid Foundry at 1×**

Record the observation row.

Check whether reinforced armor is noticeable and whether the run still supports more than one sensible damage strategy.

- [ ] **Step 6: Play Aurora Gate at 1×**

Record the observation row.

Check whether regen pressure pulses remain understandable and whether module intermissions interrupt or improve the mixed-pressure pacing.

- [ ] **Step 7: Play Void Bastion at 1×**

Record the observation row.

Check the reduced-health/enhanced-clear-bonus combination for comfort and whether the module loop compensates through interesting choices rather than one required card.

- [ ] **Step 8: Play Singularity Core at 1×**

Record the observation row.

Check final-stage length, visual density, boss clarity, environmental-modifier visibility, and whether the current module pool still creates meaningful choice under the hardest mixed enemy pressure.

- [ ] **Step 9: Post one seven-row Linear summary**

Post the results to HPA-526 as one Markdown table with this exact column set:

```markdown
| Stage | Result | Length | Difficulty | Modules | Offers | Card problems | Modifier/Boss | Mobile UX | Comfort |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Outpost Alpha | ... |
| Nebula Relay | ... |
| Salvage Rift | ... |
| Asteroid Foundry | ... |
| Aurora Gate | ... |
| Void Bastion | ... |
| Singularity Core | ... |
```

The `...` markers above describe the Linear comment format only; replace every cell with the actual observation before posting.

No repository commit is required for this task.

---

### Task 4: Apply the HPA-526 Triage Rules

**Files:**
- Modify: none in HPA-526 itself
- Create follow-up Linear issues only when a concrete problem meets the criteria below

**Interfaces:**
- Consumes: all seven observation rows from Task 3 and the HPA-528 verdict from Task 1.
- Produces: either a deliberate no-code final catalog decision or a small set of independently actionable follow-up issues with evidence-backed scope.

- [ ] **Step 1: Check for catalog-expansion evidence**

Ask only these questions across the seven rows:

```text
Did players repeatedly lack a meaningful strategic choice?
Did multiple offers collapse into the same practical decision?
Is there a tower/build pattern that has no useful run-level support and is not already covered by specialization or tech?
```

If all answers are `No`, record:

```text
Catalog decision: keep the current seven modules. No expansion justified.
```

Do not brainstorm extra cards for variety.

- [ ] **Step 2: Check for module-value defects**

A focused balance follow-up is justified only when a named module is observed as one of:

```text
repeatedly weak
repeatedly mandatory
materially confusing
creating an obvious comfort/clearability problem
```

For each justified problem, create one Linear issue containing:

```markdown
## Observation
- Stage(s): <actual affected stage names>
- Module: <actual module name>
- Symptom: <actual observed behavior>
- Context: <minimal run/build context>

## Smallest expected change
Tune the existing module value/copy using the current `RunModuleDefinition` / `RunModuleRules` seam. Do not add new architecture.

## Validation
Add focused rule/catalog coverage, run format/analyze/full tests, and replay only materially affected stage(s) at 1×.
```

Do not combine unrelated module problems into one issue.

- [ ] **Step 3: Check for offer-policy defects**

Open an offer-quality follow-up only when the human notes show a concrete bad offer state, such as repeated impossible/pivot-only choices or a clearly harmful repetition pattern.

The issue must prefer this repair order:

```text
1. candidate eligibility in GameSession
2. only then picker behavior if the defect is genuinely random-selection policy
```

Explicitly exclude full offer history, weighted ranking, deterministic protocols, and seed sweeps.

- [ ] **Step 4: Check for a genuinely missing module purpose**

If Task 3 identifies a missing strategic purpose, compare it against:

```text
current seven run modules
all tower specializations
campaign tech upgrades
side-stage rewards
```

If a distinct gap remains, create one focused feature issue describing the missing **player-facing purpose**, not a preselected implementation mechanism.

The issue must state:

```text
Prefer existing RunModuleDefinition stat fields.
If the effect requires a new combat/event seam, write a focused design before implementation.
Do not silently broaden HPA-526.
```

- [ ] **Step 5: Apply the blueprint verdict**

If Task 1 was `Narrow` or `Stop`, create no additional blueprint issue.

If Task 1 was `Proceed`, still create no blueprint issue unless Task 3 reveals a specific progression reason for another permanent option unlock. A generic desire to reward every boss is insufficient.

- [ ] **Step 6: Check Codex need**

If no repeated comprehension issue appears, record:

```text
Codex Modules section: not justified.
```

Only open a Codex follow-up if actual runs show players cannot understand/remember module options using the current draft + Mission Report surfaces.

No repository commit is required for this task.

---

### Task 5: Publish the Final HPA-526 Decision and Close the Slice

**Files:**
- Modify: none unless a separately accepted follow-up issue later changes runtime code
- Record result: Linear `HPA-526`

**Interfaces:**
- Consumes: Task 1 blueprint verdict, Task 2 software baseline, Task 3 seven-stage table, Task 4 follow-up links.
- Produces: the final M2 product decision and a bounded handoff for any remaining work.

- [ ] **Step 1: Write the overall comfort verdict**

Add a short paragraph answering:

```text
Is the current campaign comfortably clearable at normal 1× play?
Does the Salvage Module loop still improve run identity across the full campaign?
```

Do not turn this into a release-certification report.

- [ ] **Step 2: Summarize cross-stage module findings**

List only module patterns that occurred often enough to matter:

```text
Weak: <names or None>
Mandatory: <names or None>
Repetitive: <names or None>
Confusing: <names or None>
```

“None” is a valid and preferred answer when the pass does not support a complaint.

- [ ] **Step 3: Summarize stage findings**

List only stages that were materially:

```text
too long
too easy
too hard
visually/readability dense
```

Link each item to its focused follow-up issue if one was created.

- [ ] **Step 4: State the final catalog/progression decision**

Use one of these bounded outcomes:

```text
A. Keep seven modules; no expansion justified.
B. Keep seven for now; focused balance/offer follow-ups exist and must be validated before reconsidering expansion.
C. A distinct missing module purpose was observed; follow the linked focused feature issue/design before changing the catalog.
```

Then restate the HPA-528 `Proceed / Narrow / Stop` verdict separately so blueprint progression is not conflated with catalog size.

- [ ] **Step 5: Confirm repository health if no runtime follow-up was applied yet**

Reuse Task 2's successful format/analyze/focused/full-suite results. If main changed during the human validation period, rerun:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Expected: all pass.

- [ ] **Step 6: Complete HPA-526**

When the seven-stage table, final verdict, and follow-up links are present, move HPA-526 to Done even if focused follow-up issues remain open. Those issues own their own fixes and targeted retests; HPA-526 must not become an indefinite balance bucket.

If the final outcome is `A`, no runtime commit is expected. Finishing with only the planning docs plus Linear validation evidence is intentional.

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
