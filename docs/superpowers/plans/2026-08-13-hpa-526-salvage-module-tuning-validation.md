# HPA-526 Salvage Module Tuning and Campaign Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate Orion's current seven-module Salvage Module catalog as one assembled seven-stage campaign at ordinary 1× play, finishing HPA-526 without runtime changes unless a concrete player-facing defect is observed.

**Architecture:** Preserve the current `GameSession` → `GameSnapshot` → Flutter/Flame boundaries and treat the seven-module catalog as the candidate final state. HPA-526 is primarily a verification, human-product-validation, and triage task: prove the existing hidden unlock/replay contracts with tests, run one continuous campaign save with normal tech/reward stacking, then either finish with zero code or open narrowly scoped follow-up issues for observed problems.

**Tech Stack:** Flutter, Dart 3.12+, Flame, `flutter_test`, Linear for human validation notes and focused follow-up issues.

## Global Constraints

- Keep the current seven-module catalog unchanged unless the campaign pass identifies a concrete player-facing need.
- Use one continuous campaign save for the human pass. Reset at most once before Outpost Alpha; never reset between validation stages.
- Play at ordinary 1× speed with normal player inputs and normal random offers.
- Tech purchases are allowed when the player would normally make them; side-stage rewards must stack naturally through the same save.
- The first attempt is always the authoritative row. Allow at most one comfort retry after a first-attempt loss.
- Do not target a mandatory 10–12 module count.
- Do not add picker history, weighting, pity, deterministic seeds, offer fingerprints, or statistical sweeps without an observed picker defect.
- Do not add a generic event/effect system or new persistence model.
- Additional blueprint rewards require an HPA-528 **Proceed** verdict and a specific progression reason.
- Do not add a Modules Codex unless observed comprehension problems justify it.
- Record human notes directly in HPA-526; do not create an evidence-export subsystem or permanent run-log schema.
- Open a separate focused Linear issue for each concrete bug/readability/balance problem worth fixing.
- Rerun only stages materially affected by an accepted follow-up fix.
- Normal campaign completion must remain comfortable, offline, and free of grind/daily-engagement mechanics.

---

### Task 1: Establish the Software Baseline and Credit Existing Unlock/Replay Proof

**Files:**
- Modify: none
- Test: `test/game/game_session_test.dart`
- Test: `test/game/run_module_unlocks_test.dart`
- Test: `test/game/module_offer_picker_test.dart`
- Test: `test/game/run_module_rules_test.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: the current seven-module production implementation.
- Produces: a known-green baseline plus automated proof for the hidden attempt-freeze and same-object Replay eligibility contracts that the human HUD cannot directly inspect.

- [ ] **Step 1: Run the format check**

```bash
dart format --output=none --set-exit-if-changed .
```

Expected: exit 0 and no files changed.

- [ ] **Step 2: Run static analysis**

```bash
flutter analyze
```

Expected: no issues.

- [ ] **Step 3: Run the focused module/unlock rule tests**

```bash
flutter test \
  test/game/game_session_test.dart \
  test/game/run_module_unlocks_test.dart \
  test/game/module_offer_picker_test.dart \
  test/game/run_module_rules_test.dart
```

Expected: all tests pass, including:

```text
eligible module set stays frozen during one attempt
committed Outpost Alpha clear unlocks Relay Calibration
default session excludes the locked blueprint
explicit unlocked eligibility can offer Relay Calibration
```

- [ ] **Step 4: Run the existing same-object Replay lifecycle regression**

```bash
flutter test test/widget_test.dart \
  --plain-name "first-clear commit then same-game Replay refreshes module eligibility"
```

Expected: pass. This is the authoritative proof that the committed first clear refreshes Relay Calibration eligibility on the same game object after Replay.

- [ ] **Step 5: Run the full suite**

```bash
flutter test
```

Expected: all tests pass.

If unchanged main fails, treat that as a separate pre-existing defect. Do not tune Salvage Modules to hide an unrelated failure.

No repository commit is required for this task.

---

### Task 2: Run One Continuous Seven-Stage 1× Campaign

**Files:**
- Modify: none
- Record result: Linear `HPA-526`

**Interfaces:**
- Consumes: Task 1's green software baseline and the normal persisted campaign flow.
- Produces: one complete qualitative row per stage from one campaign save, plus the human HPA-528 Proceed / Narrow / Stop verdict.

#### Recording contract

For every stage, record these fields:

```text
First attempt: Clear, or Loss plus failed wave
Retry: Not used, or the one comfort-retry result
Length: Short / Comfortable / Long
Difficulty: 1–5 for the first attempt
Towers: tower types used plus any level-3 specializations
Tech at launch: purchased campaign tech owned when the stage started
Modules: selected Salvage Module names
Offers: concise note on understandability/usefulness
Card problems: dead / mandatory / repetitive / confusing, or None
Modifier/Boss: whether the environmental modifier and boss were noticeable
Mobile UX: readability/control problem, or None
Comfort: one sentence interpreting first-attempt comfort and any retry
```

Record tower types used at any point in the attempt and name every level-3 specialization reached. `Tech at launch` is a snapshot of purchased tech before the stage begins; purchases made after the run belong to the next stage's context.

Do not add per-wave economy tables, run seeds, generated evidence files, or screenshots for every wave.

#### Retry contract

Apply these rules consistently:

```text
The first attempt always remains the primary row.
A first-attempt loss may receive one comfort retry after a small ordinary strategy adjustment.
Never silently replace a loss with the retry clear.
A first-attempt main-path loss is a focused follow-up candidate even if the retry clears.
If the retry clears, continue the same save and describe the stage as clearable after a small adjustment.
If the retry also loses on a main-path stage, stop brute-force play and open a blocking focused follow-up before continuing HPA-526.
If the retry also loses on an optional side stage, continue the main path without that side-stage reward.
```

- [ ] **Step 1: Prepare the single validation save**

Use the normal app flow on a simulator/device. If Outpost Alpha is already cleared, reset campaign progress **once** before starting. Do not inject progress, tech, resources, or module offers.

From this point until all seven rows are recorded, do not reset campaign progress.

- [ ] **Step 2: Play Outpost Alpha at 1× and use it as both Alpha row and HPA-528 human gate**

Play all eight waves normally. Record the first-attempt Alpha row using the recording contract.

For the blueprint product gate, verify only player-visible behavior:

```text
Mission Report shows Blueprint recovery pending while the improved result is saving.
Successful save changes the reward to Blueprint recovered: Relay Calibration.
The pending → recovered → future-run story is understandable from the UI.
```

Do not ask the human to verify `availableRunModules`; Task 1 already proves the hidden eligibility refresh and attempt-freeze contracts.

If Outpost Alpha is lost, apply the one-retry contract. A blueprint verdict cannot be recorded until a first committed clear is achieved.

- [ ] **Step 3: Start same-object Replay as a visible lifecycle check, then return to the map**

After the committed Outpost Alpha clear, choose **Replay Mission** from the Mission Report.

Verify only:

```text
Replay starts a clean new Outpost Alpha run normally.
The page/game shell does not need reconstruction.
No player-facing save/reward error remains visible.
```

Do not play the second Alpha attempt to completion. Return to the world map and continue using the same campaign save.

Record the HPA-528 human verdict in HPA-526 with these six bullets:

1. First clear → pending reward: `Pass` or `Fail`.
2. Save → recovered reward: `Pass` or `Fail`.
3. Same-object Replay starts a clean run: `Pass` or `Fail`.
4. Player-visible blueprint story understandable: `Pass` or `Fail`.
5. Verdict: exactly one of `Proceed`, `Narrow`, or `Stop`.
6. Reason: one sentence stating whether the unlock felt understandable and rewarding.

Use the verdicts as follows:

- `Proceed`: another blueprint could be considered later only if the campaign pass identifies a specific progression reason.
- `Narrow`: keep Relay Calibration as the one proof and do not expand blueprint progression in HPA-526.
- `Stop`: do not add more boss-blueprint rewards; continue only with campaign/module validation.

- [ ] **Step 4: Continue to Nebula Relay on the same save**

Before launch, buy tech only if it is a normal choice you would actually make, then record `Tech at launch`.

Play the first attempt at 1× and record the row. Check shield-recharge visibility and whether module choices encourage a reasonable build rather than a mandatory one. Apply the one-retry contract on loss.

- [ ] **Step 5: Continue to Salvage Rift on the same save**

Record `Tech at launch`, play the first attempt at 1×, and record the row. Check whether swarm bounty and the optional-stage reward feel distinct without making Emergency Salvage obviously mandatory or irrelevant.

If the stage clears, its committed bonus gold must remain in this same save and therefore affect Foundry and later stages. If the one allowed retry also loses, continue without that reward and record that fact in the Comfort note.

- [ ] **Step 6: Continue to Asteroid Foundry on the same save**

Record `Tech at launch`, play the first attempt, and record the row. Check whether reinforced armor is noticeable and whether more than one sensible damage strategy remains viable.

If Salvage Rift was cleared, this run naturally includes its bonus starting gold. Apply the one-retry contract on loss.

- [ ] **Step 7: Continue to Aurora Gate on the same save**

Record `Tech at launch`, play the first attempt, and record the row. Check whether regen pressure pulses remain understandable and whether module intermissions improve rather than disrupt mixed-pressure pacing. Apply the one-retry contract on loss.

- [ ] **Step 8: Continue to Void Bastion on the same save**

Record `Tech at launch`, play the first attempt, and record the row. Check the reduced-health/enhanced-clear-bonus combination for comfort and whether the module loop offers interesting choices rather than one required card.

If the stage clears, its committed bonus health must remain in the same save and therefore affect Singularity Core. If the one allowed retry also loses, continue without that reward and record that fact in the Comfort note.

- [ ] **Step 9: Continue to Singularity Core on the same save**

Record `Tech at launch`, play the first attempt, and record the row. Check final-stage length, visual density, boss clarity, environmental-modifier visibility, and whether the current module pool still creates meaningful choice under the hardest mixed pressure.

If Void Bastion was cleared, this run naturally includes its bonus starting health. Apply the one-retry contract on loss.

- [ ] **Step 10: Confirm all seven primary rows are first-attempt observations**

Before triage, verify that every stage has one primary first-attempt result and that any retry is recorded separately rather than replacing it.

The seven stages must be present in this order:

```text
Outpost Alpha
Nebula Relay
Salvage Rift
Asteroid Foundry
Aurora Gate
Void Bastion
Singularity Core
```

If a twice-failed main-path stage prevented later stages from unlocking, Task 2 is blocked at that stage and HPA-526 remains open until the focused defect is fixed/retested.

No repository commit is required for this task.

---

### Task 3: Apply the HPA-526 Triage Rules

**Files:**
- Modify: none in HPA-526 itself
- Create: focused Linear follow-up issues only when a concrete problem meets the criteria below

**Interfaces:**
- Consumes: Task 2's seven stage rows, tower/specialization context, tech-at-launch context, and HPA-528 verdict.
- Produces: either a deliberate no-code final catalog decision or a small set of independently actionable follow-up issues.

- [ ] **Step 1: Decide whether catalog expansion is justified**

Across all seven rows, answer only:

```text
Did the player repeatedly lack a meaningful strategic choice?
Did multiple offers collapse into the same practical decision?
Is there a tower/build pattern with no useful run-level support that is not already covered by specialization, tech, or side-stage rewards?
```

If all answers are `No`, record exactly:

```text
Catalog decision: keep the current seven modules. No expansion justified.
```

Do not brainstorm extra cards for variety.

- [ ] **Step 2: Create one issue per concrete module-value defect**

A balance follow-up is justified only when a named module is repeatedly weak, repeatedly mandatory, materially confusing, or causes an obvious comfort/clearability problem.

Each issue must include:

- actual affected stage names;
- actual module name;
- first-attempt symptom;
- tower types and specializations used in the affected row;
- tech owned at stage launch;
- minimal context needed to reproduce the behavior;
- smallest-change expectation: tune existing `RunModuleDefinition`/`RunModuleRules` behavior without new architecture;
- validation: focused rule/catalog coverage, format, analyze, full tests, and only materially affected 1× stage reruns.

Do not combine unrelated module problems into one issue.

- [ ] **Step 3: Create an offer-policy issue only for a concrete bad offer state**

Qualifying examples are impossible/pivot-only choices or a clearly harmful repetition pattern observed during actual play.

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

If a distinct gap remains, describe the missing **player-facing purpose**, not a preselected mechanism. Require reuse of existing `RunModuleDefinition` stat fields when possible. If the useful effect requires a new combat/event seam, require a focused design before implementation rather than silently broadening HPA-526.

- [ ] **Step 5: Apply the blueprint verdict**

For `Narrow` or `Stop`, create no additional blueprint issue.

For `Proceed`, still create no blueprint issue unless Task 2 reveals a specific progression reason for another permanent option unlock. “Reward every boss” alone is insufficient.

- [ ] **Step 6: Check Codex need**

If no repeated comprehension problem appears, record exactly:

```text
Codex Modules section: not justified.
```

Only create a Codex follow-up if actual play shows the current draft + Mission Report surfaces are insufficient for understanding or remembering module options.

- [ ] **Step 7: Handle a twice-failed main-path blocker**

If Task 2 stopped because one main-path stage lost twice, create that focused issue immediately and leave HPA-526 open. After the accepted fix lands, rerun only that blocked stage first; when it clears comfortably enough to proceed, continue the same campaign validation into the previously locked later stages.

Do not brute-force retries merely to complete the table.

No repository commit is required for this task.

---

### Task 4: Publish the Final HPA-526 Decision and Close the Slice

**Files:**
- Modify: none unless a separately accepted follow-up later changes runtime code
- Record result: Linear `HPA-526`

**Interfaces:**
- Consumes: Task 1 software baseline, Task 2 continuous-campaign rows and HPA-528 verdict, Task 3 follow-up links.
- Produces: the final M2 product decision and bounded handoff for remaining work.

- [ ] **Step 1: Post the complete seven-row observation table**

Use these columns, in this order:

```text
Stage | First attempt | Retry | Length | Difficulty | Towers | Tech at launch | Modules | Offers | Card problems | Modifier/Boss | Mobile UX | Comfort
```

The table must contain all seven stages in campaign order and every cell must come from the actual validation run. Do not post a partial table as the final deliverable.

- [ ] **Step 2: Record the overall comfort verdict**

Write a short paragraph answering both questions:

```text
Is the current campaign comfortably clearable at normal 1× play on one continuous save?
Does the Salvage Module loop still improve run identity across the full campaign?
```

Distinguish first-attempt comfort from “clearable after one small adjustment” when retries occurred. Do not turn this into a release-certification report.

- [ ] **Step 3: Record cross-stage module findings**

Add four bullets named `Weak`, `Mandatory`, `Repetitive`, and `Confusing`. Each bullet lists actual module names that mattered across runs, or `None` when the pass does not support a complaint.

- [ ] **Step 4: Record material stage findings**

List only stages that were materially too long, too easy, too hard, or visually/readability dense. Link each item to its focused follow-up issue when one exists.

- [ ] **Step 5: State one final catalog outcome**

Use exactly one of:

```text
A. Keep seven modules; no expansion justified.
B. Keep seven for now; focused balance/offer follow-ups must be validated before reconsidering expansion.
C. A distinct missing module purpose was observed; follow the linked focused feature issue/design before changing the catalog.
```

State the HPA-528 `Proceed`, `Narrow`, or `Stop` verdict separately so blueprint progression is not conflated with catalog size.

- [ ] **Step 6: Reconfirm repository health if main moved during the human pass**

If main has not changed since Task 1, reuse Task 1's green baseline. If main moved, rerun:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Expected: all pass.

- [ ] **Step 7: Complete HPA-526**

Move HPA-526 to Done once all seven rows, final verdict, and follow-up links are present.

Focused non-blocking follow-up issues may remain open; they own their fixes and targeted retests. The exception is a twice-failed main-path blocker: HPA-526 cannot complete until that blocker is fixed/retested enough to finish the seven-stage pass.

If the final outcome is `A`, no runtime commit is expected. Finishing with the planning docs plus Linear validation evidence is intentional.

---

## Self-Review Against the Design

- The current seven-module catalog is explicitly the candidate final catalog.
- Hidden attempt-freeze and same-object Replay eligibility are credited to existing automated tests, not guessed from human UI.
- One campaign save is used from Outpost Alpha through Singularity Core.
- Salvage Rift gold, Void Bastion health, and normal tech purchases naturally affect later stages.
- Outpost Alpha's first clear is both the HPA-528 human product check and the first validation row.
- Every row records tower/specialization and tech-at-launch context needed for triage.
- First-attempt results are never overwritten by retries; at most one comfort retry is allowed.
- A twice-failed main-path gate stops brute-force play and blocks HPA-526 completion until addressed.
- No code change is invented without a concrete observation.
- Concrete problems are split into focused follow-up issues.
- Picker, persistence, Codex, blueprint, and new-effect expansion remain evidence-gated.
- Format, analysis, focused unlock/replay tests, and the full suite are the software verification baseline.
- The plan has a legitimate zero-runtime-code completion path.