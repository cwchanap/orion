# HPA-526 Salvage Module Tuning and Campaign Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate Orion's current seven-module Salvage Module catalog across one real continuous seven-stage campaign at ordinary 1× play, with zero runtime code as the expected happy path.

**Architecture:** Preserve the existing `GameSession` → `GameSnapshot` → Flutter/Flame boundaries. Credit existing automated tests for hidden unlock/save/replay contracts, record the random offers and player build context that cannot be recovered later, and create code only from a concrete observed defect.

**Tech Stack:** Flutter, Dart 3.12+, Flame, `flutter_test`, Linear.

## Global Constraints

- Current seven modules are the candidate final catalog.
- One continuous campaign save; reset at most once before Outpost Alpha.
- Campaign order: Outpost Alpha (main) → Nebula Relay (main) → Salvage Rift (side) → Asteroid Foundry (main) → Aurora Gate (main) → Void Bastion (side) → Singularity Core (main).
- Play human validation at ordinary 1× with normal random offers and normal player choices.
- Tech purchases are allowed; side-stage rewards stack naturally in the same save.
- First attempt is always the primary observation; at most one comfort retry after a loss.
- Original rows are immutable. Post-fix runs append new context; they never overwrite original evidence.
- No mandatory 10–12 module target.
- No picker history/weighting/pity/seeds, generic effect engine, new persistence model, telemetry/evidence schema, Modules Codex, or extra blueprint by default.
- Additional blueprints require HPA-528 `Proceed` plus a concrete progression gap.
- A module balance follow-up requires a signal that cannot reasonably be explained by tower/specialization or tech choice.

---

### Task 1: Establish the software baseline and credit existing blueprint-state coverage

**Files:**
- Modify: none
- Test: `test/game/game_session_test.dart`
- Test: `test/game/run_module_unlocks_test.dart`
- Test: `test/game/module_offer_picker_test.dart`
- Test: `test/game/run_module_rules_test.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: current production module/unlock/save/replay implementation.
- Produces: a green baseline plus automated proof for behavior that the human pass must not re-check by eye.

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

- [ ] **Step 3: Run focused module/unlock tests**

```bash
flutter test \
  test/game/game_session_test.dart \
  test/game/run_module_unlocks_test.dart \
  test/game/module_offer_picker_test.dart \
  test/game/run_module_rules_test.dart
```

Expected: all pass, including the existing contracts:

```text
eligible module set stays frozen during one attempt
committed Outpost Alpha clear unlocks Relay Calibration
default session excludes the locked blueprint
explicit unlocked eligibility can offer Relay Calibration
```

- [ ] **Step 4: Run the existing blueprint lifecycle/reward-state regressions**

Run each exact widget regression:

```bash
flutter test test/widget_test.dart \
  --plain-name "first-clear commit then same-game Replay refreshes module eligibility"

flutter test test/widget_test.dart \
  --plain-name "fresh first-clear save failure reports Blueprint not recovered"

flutter test test/widget_test.dart \
  --plain-name "failed Retry Save then success reports Blueprint recovered"
```

Expected: all pass.

The first regression deliberately delays persistence and proves both transient `Blueprint recovery pending` and committed `Blueprint recovered: Relay Calibration` copy. The latter two prove failure and retry-save recovery. Do not require the human pass to reproduce these timing-sensitive states.

- [ ] **Step 5: Run the full suite**

```bash
flutter test
```

Expected: all tests pass.

If unchanged main fails, separate that defect from HPA-526 rather than tuning modules around it.

No repository commit is required for this task.

---

### Task 2: Run one continuous seven-stage 1× campaign

**Files:**
- Modify: none
- Record result: Linear `HPA-526`

**Interfaces:**
- Consumes: Task 1 baseline and the normal persisted campaign flow.
- Produces: seven first-attempt rows, optional retry notes, exact offers shown, and the human HPA-528 product verdict.

#### Recording contract

For each stage record:

```text
First attempt: Clear, or Loss + failed wave
Retry: Not used, or the one comfort-retry result
Length: Short / Comfortable / Long
Difficulty: 1–5 for first attempt
Towers: tower types used + level-3 specializations
Tech at launch: purchased campaign tech before stage start
Offers seen: D1 a/b/c → picked x; D2 a/b/c → picked y; D3 a/b/c → picked z
Modules: selected module names
Offer quality: concise understandability/usefulness note
Card problems: dead / mandatory / repetitive / confusing, or None
Modifier/Boss: noticeable or not
Mobile UX: issue or None
Comfort: first-attempt interpretation + `Confound: No/Yes/Unclear — reason`
```

`Offers seen` is mandatory because random offers cannot be reconstructed after the run. This is direct human observation, not a runtime history system.

The Comfort confound clause answers:

> Could tower/specialization or tech choice, rather than the module, explain the observed weakness/strength/mandatory feeling?

If `Confound` is Yes or Unclear, preserve the signal as an observation but do not open a module-value tuning issue from it.

#### Retry contract

```text
First attempt always remains the primary row.
At most one comfort retry after a loss.
Never replace a loss with the retry clear.
A first-attempt main-path loss is a focused follow-up candidate even if retry clears.
If retry clears: continue same save; describe as clearable after a small adjustment.
If a main-path stage loses twice: stop brute-force play and open a blocking follow-up.
If a side stage loses twice: continue main path without that side-stage reward.
```

- [ ] **Step 1: Prepare the validation save**

Use the normal app flow on simulator/device. If Outpost Alpha is already cleared, reset campaign progress once. Do not inject progress, tech, resources, or offers.

Do not reset again until the validation pass is complete.

- [ ] **Step 2: Play Outpost Alpha (main) at 1×**

Record the Alpha row using the contract above.

After the first committed clear, record only the human judgment automation cannot provide:

```text
Blueprint reward understandable/rewarding: Yes / No
Verdict: Proceed / Narrow / Stop
Reason: one sentence
```

Do **not** score whether transient pending copy appeared, whether save/retry state transitioned correctly, whether the same object refreshed `availableRunModules`, or whether Relay Calibration appeared in a random draft. Task 1 owns those facts.

Use verdict meanings:

- `Proceed`: another blueprint remains optional and still needs a specific progression reason.
- `Narrow`: keep Relay Calibration as the one proof; no more blueprints in HPA-526.
- `Stop`: do not add more blueprint rewards.

Return to the map on the same save and continue.

- [ ] **Step 3: Play Nebula Relay (main)**

Before launch, buy tech only if it is a normal choice you would make. Record `Tech at launch`, all three offers, build/specializations, and the first-attempt row. Apply the retry contract on loss.

- [ ] **Step 4: Play Salvage Rift (side)**

Record the row and all offers. If cleared, its bonus gold remains in this save and affects later stages. If it loses twice, continue without the reward and state that in later Comfort context.

- [ ] **Step 5: Play Asteroid Foundry (main)**

Record the row. If Salvage Rift cleared, this run naturally includes its starting-gold reward. Apply the retry contract on loss.

- [ ] **Step 6: Play Aurora Gate (main)**

Record the row, all offers, build, tech, and comfort/confound judgment. Apply the retry contract on loss.

- [ ] **Step 7: Play Void Bastion (side)**

Record the row. If cleared, its bonus health remains in the save and affects Singularity Core. If it loses twice, continue without that reward.

- [ ] **Step 8: Play Singularity Core (main)**

Record the row, including final-stage length, visual density, modifier/boss clarity, all offers, build/tech context, and comfort/confound judgment. Apply the retry contract on loss.

- [ ] **Step 9: Verify the observation set before triage**

Every reached stage must have an immutable first-attempt row. Any retry is separate. All three offers must be recorded for every stage that reached the draft points.

If a main-path stage lost twice and blocked later stages, stop here and continue with Task 3's blocker path rather than manufacturing missing rows.

No repository commit is required for this task.

---

### Task 3: Triage concrete findings and define regression/rerun behavior

**Files:**
- Modify: none in HPA-526
- Create: focused Linear follow-up issues only for evidence-backed problems

**Interfaces:**
- Consumes: Task 2 rows with offers/build/tech/confound context.
- Produces: keep-seven decision or focused issues; deterministic regression scope for each accepted code fix.

- [ ] **Step 1: Decide whether catalog expansion is justified**

Ask:

```text
Did the player repeatedly lack a meaningful strategic choice?
Did recorded offers repeatedly collapse into the same practical decision?
Is there a build pattern with no useful run-level support not already covered by specialization, tech, or side-stage rewards?
```

If all are No, record:

```text
Catalog decision: keep the current seven modules. No expansion justified.
```

- [ ] **Step 2: Gate module-value follow-ups on the confound check**

A module balance issue requires:

- named module and affected stage(s);
- repeated or materially harmful signal;
- first-attempt symptom;
- towers/specializations used;
- tech at launch;
- Comfort entry with `Confound: No` and a short justification.

If `Confound` is Yes or Unclear, keep it as an observation only.

- [ ] **Step 3: Gate offer-policy follow-ups on `Offers seen`**

Open an offer issue only when the recorded drafts show a concrete bad state: impossible/pivot-only choices or clearly harmful repetition.

Repair order:

```text
1. candidate eligibility/policy in GameSession
2. ModuleOfferPicker only if the defect is genuinely random-selection policy
```

No history/weighting/pity/seed infrastructure.

- [ ] **Step 4: Gate new modules, blueprints, and Codex surfaces**

Before a new module, compare the gap against the seven modules, tower specializations, tech, and side-stage rewards. Describe a missing player-facing purpose, not a mechanism.

Additional blueprint issue: only HPA-528 `Proceed` + specific progression reason.

Modules Codex issue: only repeated comprehension problem from actual play.

- [ ] **Step 5: Require the smallest deterministic regression for every accepted code fix**

Choose the narrowest test seam:

```text
module arithmetic/value contract → run_module_rules_test.dart or focused rule/catalog test
candidate policy → game_session_test.dart
unlock/progression lifecycle → run_module_unlocks_test.dart and/or focused widget lifecycle test
assembled stage/wave interaction → focused orion_defense_game_test.dart journey, driving game.update(dt) when appropriate
```

Do not require a headless full-game journey when a pure-rule test proves the defect better.

- [ ] **Step 6: Preserve rerun comparability**

An original validation row is never replaced after a fix.

If a player-facing balance fix needs human confirmation, append a **post-fix row/note** with the actual tech and campaign-reward context of that rerun. Do not claim direct comparability when the save context differs.

For a twice-failed main-path blocker, fix + regression first, then rerun the blocked stage on the existing validation save and record launch context again. If it becomes clearable enough to proceed, continue the same campaign into later stages.

For nonblocking fixes discovered after later campaign progress, deterministic regression is mandatory; manual 1× rerun is required only when player feel needs revalidation.

No repository commit is required for HPA-526 itself.

---

### Task 4: Publish the final HPA-526 decision

**Files:**
- Modify: none unless a separately accepted follow-up later changes runtime code
- Record result: Linear `HPA-526`

**Interfaces:**
- Consumes: Task 1 baseline, Task 2 observations/HPA-528 verdict, Task 3 follow-up links.
- Produces: final M2 product decision.

- [ ] **Step 1: Post the original observation table**

Columns, in order:

```text
Stage | First attempt | Retry | Length | Difficulty | Towers | Tech at launch | Offers seen | Modules | Offer quality | Card problems | Modifier/Boss | Mobile UX | Comfort
```

Keep original rows unchanged. Append post-fix notes separately if any exist.

- [ ] **Step 2: Record the overall verdict**

Answer:

```text
Is the campaign comfortably clearable at 1× on one continuous save?
Does the Salvage Module loop improve run identity?
Which module/offer concerns survive the build/tech confound check?
```

- [ ] **Step 3: State one catalog outcome**

Use exactly one:

```text
A. Keep seven modules; no expansion justified.
B. Keep seven for now; focused follow-ups must be validated before reconsidering expansion.
C. A distinct missing module purpose was observed; follow the linked focused feature issue/design before changing the catalog.
```

Record the HPA-528 `Proceed` / `Narrow` / `Stop` verdict separately.

- [ ] **Step 4: Reconfirm repository health if main moved during the human pass**

If main changed since Task 1, rerun:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Expected: all pass.

- [ ] **Step 5: Complete HPA-526 when the campaign pass and triage are complete**

Move HPA-526 to Done after all reachable seven-stage evidence, final verdict, and follow-up links are recorded. Focused follow-ups own their fixes and regressions.

Exception: a twice-failed main-path stage that blocks later stages keeps HPA-526 open until the blocking fix/retest allows the continuous campaign pass to finish.

If outcome A is reached, no runtime commit is expected.

---

## Self-Review

- Hidden blueprint eligibility/save/retry facts are credited to existing tests rather than manual timing checks.
- The human HPA-528 gate contains only product judgment: understandable/rewarding, verdict, reason.
- One continuous save preserves normal tech and side-stage reward stacking.
- Main vs side stages are labeled explicitly wherever retry behavior differs.
- Every random draft is recorded before it becomes unrecoverable.
- Build/specialization and tech-at-launch context accompany each row.
- Every Comfort judgment includes a module-vs-build/tech confound answer.
- Original rows never get overwritten by post-fix reruns.
- Every accepted code fix gets a deterministic regression at the smallest useful layer; headless full-game driving is conditional, not mandatory.
- Zero-runtime-code completion remains the expected happy path.
