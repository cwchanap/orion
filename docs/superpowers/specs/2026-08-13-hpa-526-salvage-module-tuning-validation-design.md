# HPA-526 Salvage Module Tuning and Campaign Validation Design Specification

## Decision

Treat the current seven-module catalog as the **candidate final catalog** and make HPA-526 validation-first.

Do not add modules, picker rules, blueprint rewards, Codex surfaces, or new stat/effect seams up front. HPA-527 already recorded two positive human 1× runs with no mandatory, dead-card, or repetition problem. Expanding merely because HPA-526 allows 10–12 modules would manufacture scope rather than answer an observed need.

HPA-526 is one continuous assembled-product check:

```text
prove existing hidden contracts with tests
→ reset campaign progress once if needed
→ play one continuous campaign save at 1×
→ record first-attempt rows with offers/build/tech context
→ no concrete problem? keep seven and finish with zero runtime code
→ concrete problem? create a focused follow-up with the smallest deterministic regression
```

The planning PR remains documentation-only. Runtime changes require a concrete observation first.

This specification is the normative product/validation contract. The implementation plan repeats only the operational rules needed to execute it safely without requiring an implementer to reconstruct the protocol from multiple files.

## Product question

The remaining question is not “what else can we add?” It is:

> Is the current assembled campaign varied, readable, and comfortably clearable while the Salvage Module loop creates useful run identity?

The current product already includes:

- six starter Salvage Modules from HPA-527;
- Relay Calibration as the first committed-progress blueprint reward from HPA-528;
- the Mission Report from HPA-525;
- stage modifiers, side-stage rewards, tech purchases, bosses, and feedback polish.

The validation must exercise those systems together rather than as isolated stage sandboxes.

## Existing architecture to preserve

### Module catalog and effects

`lib/game/models/game_models.dart` owns the seven current modules:

1. Heavy Caliber
2. Overclock Relay
3. Long Sight
4. Emergency Salvage
5. Cryo Reservoir
6. Rocket Fusing
7. Relay Calibration

`lib/game/rules/run_module_rules.dart` applies their stat effects. Do not split this into a registry or generalized effect engine.

### Unlocks

`lib/game/rules/run_module_unlocks.dart` derives Relay Calibration availability from committed Outpost Alpha progress. There is no blueprint collection and no persistence migration to add.

### Offer selection

`GameSession._moduleCandidates()` owns candidate policy: available/unacquired modules, placed-family preference, unlocked-family fallback, then remaining candidates. `ModuleOfferPicker` remains a policy-free injectable shuffle/take seam.

No anti-repeat history, weighting, pity, offer fingerprint, or seeded protocol is justified by this pass.

### Campaign stacking

`CampaignSave` stores stage progress and tech purchases together. `CampaignModifiers.fromProgress(...)` derives side-stage and tech effects from committed state.

Use one save in this order:

```text
Outpost Alpha (main)
→ Nebula Relay (main)
→ Salvage Rift (side)
→ Asteroid Foundry (main)
→ Aurora Gate (main)
→ Void Bastion (side)
→ Singularity Core (main)
```

This deliberately exercises:

- Relay Calibration after committed Outpost Alpha progress;
- Salvage Rift bonus gold on later stages when earned;
- Void Bastion bonus health on Singularity Core when earned;
- normal player-selected tech purchases.

Reset at most once before Outpost Alpha. Do not reset between validation stages.

## Credit existing automation instead of re-testing it by eye

The human pass must not reproduce facts the existing tests already prove.

Existing automated coverage owns these contracts:

- `game_session_test.dart`: the eligible module set stays frozen during one attempt;
- `run_module_unlocks_test.dart`: a committed Outpost Alpha clear unlocks Relay Calibration;
- `widget_test.dart`: the first-clear delayed-save journey renders **Blueprint recovery pending**, then **Blueprint recovered: Relay Calibration**, and same-game Replay refreshes eligibility;
- `widget_test.dart`: a first-clear save failure renders **Blueprint not recovered**;
- `widget_test.dart`: Retry Save can transition that failure to **Blueprint recovered: Relay Calibration**.

The pending state is intentionally tested with a delayed store. A real local save may finish too quickly for a human to see the transient pending copy. Missing that transient frame is therefore **not** a human failure.

### Human HPA-528 verdict

Outpost Alpha's first clear is also the first HPA-526 validation row. The human records only the product judgment automation cannot provide:

```text
Blueprint reward understandable/rewarding: Yes / No
Verdict: Proceed / Narrow / Stop
Reason: one sentence
```

Meanings:

- **Proceed** — another blueprint may be considered later only if the campaign pass exposes a specific progression reason.
- **Narrow** — keep Relay Calibration as the one proof and do not expand blueprint progression in HPA-526.
- **Stop** — do not add more boss-blueprint rewards.

Do not require the human to verify `availableRunModules`, see a transient pending frame, or observe Relay Calibration in a random offer.

## Human campaign protocol

Run one continuous campaign at ordinary **1×** with normal player inputs and random offers.

- Do not inject progress, gold, health, tech, wave results, or preferred offers.
- Tech purchases are allowed when they are choices the player would normally make.
- Side-stage rewards remain in the same save and affect later stages naturally.
- The first attempt is always the authoritative observation.

### Retry contract

A loss is product evidence and must not be overwritten by a later clear.

- Record the first-attempt loss and failed wave.
- Allow at most **one** comfort retry after a small ordinary strategy adjustment.
- Record the retry separately.
- A first-attempt main-path loss is a focused follow-up candidate even if the retry clears.
- If the retry clears, continue the same campaign and describe the stage as “clearable after a small adjustment,” not “comfortable first try.”
- If a main-path stage loses twice, stop brute-force play and open a blocking focused follow-up before later locked stages can be validated.
- If a side stage loses twice, continue the main path without its reward; that missing reward is part of the actual later campaign context.

## Observation contract

Each stage row records:

| Field | What to record |
| --- | --- |
| First attempt | Clear, or loss with failed wave |
| Retry | Not used, or the one comfort-retry result |
| Length | Short / comfortable / long |
| Difficulty | 1–5 perceived difficulty on the first attempt |
| Towers | Tower types used plus any level-3 specializations |
| Tech at launch | Purchased campaign tech when the stage started |
| Offers seen | All three drafts, e.g. `D1 Heavy/Long/Cryo → Long; D2 ...; D3 ...` |
| Modules | Selected Salvage Modules |
| Offer quality | Concise note on whether the offers were understandable/useful |
| Card problems | Dead / mandatory / repetitive / confusing card, or None |
| Stage identity | Whether the modifier and boss were noticeable |
| Mobile UX | Readability/control problem, or None |
| Comfort | First-attempt interpretation plus explicit confound check |

### Why `Offers seen` is required

Offers are random and cannot be reconstructed after the run. Selected modules alone cannot answer whether multiple offers collapsed into the same decision or whether a harmful repetition occurred.

Recording the three card names shown in each draft is direct observation, not offer-history infrastructure.

### Comfort/confound sentence

Every Comfort entry must explicitly answer:

> Could the tower/specialization or tech choice, rather than the module itself, explain the observed weakness/strength/mandatory feeling?

Use `Confound: No`, `Confound: Yes`, or `Confound: Unclear` with a short reason.

A module balance issue may be opened only when the observed signal cannot reasonably be explained by build/tech context. If the answer is Yes or Unclear, preserve it as an observation rather than spending the n=1 qualitative signal as a tuning change.

Do not capture per-wave economy tables, seeds, generated evidence files, exhaustive screenshots, or statistical claims.

## Triage rules

### Keep seven by default

If the campaign remains comfortably clearable and no evidence-backed module/offer problem appears:

- keep all seven module values unchanged;
- keep `GameSession._moduleCandidates()` and `ModuleOfferPicker` unchanged;
- keep Relay Calibration as the only blueprint reward;
- do not add a Modules Codex;
- finish HPA-526 with zero runtime code.

### Module value problem

Open a focused balance issue only when a named module is repeatedly weak/mandatory/confusing **and** the recorded build/tech context does not plausibly explain it.

The issue records stage, module, first-attempt symptom, tower/specialization context, tech-at-launch context, and the smallest proposed rule/value change.

### Offer problem

Open an offer issue only when the recorded `Offers seen` data demonstrates an actual bad state such as impossible/pivot-only choices or clearly harmful repetition.

Repair order remains:

```text
1. GameSession candidate eligibility/policy
2. ModuleOfferPicker only when the defect is genuinely random-selection policy
```

Do not infer a picker problem from one ordinary repeated card.

### Missing strategic purpose

Before proposing a new module, compare the observed gap against:

- seven current run modules;
- all tower specializations;
- campaign tech upgrades;
- side-stage rewards.

Only a distinct missing player-facing purpose earns a focused feature issue. Reuse current `RunModuleDefinition` fields when possible. A new combat/event seam requires its own focused design.

### Blueprint and Codex expansion

Additional blueprints require both an HPA-528 **Proceed** verdict and a specific progression gap from the campaign pass. “Reward every boss” is not sufficient.

A Modules Codex requires an observed comprehension problem. Seven cards plus draft/Mission Report copy do not justify it by themselves.

## Post-fix validation and comparability

The original validation row is immutable evidence. A post-fix run never overwrites it.

### Deterministic regression first

Every accepted code fix owns a deterministic regression at the **smallest relevant layer**:

- module arithmetic/value contract → `run_module_rules_test.dart` or focused catalog/rule test;
- candidate eligibility/policy → `game_session_test.dart`;
- unlock/progression lifecycle → `run_module_unlocks_test.dart` and/or the focused widget lifecycle test;
- assembled stage/wave interaction → a focused `orion_defense_game_test.dart` journey, driving `game.update(dt)` where appropriate.

Do **not** require a headless full-game journey for a defect that a smaller pure-rule regression proves better.

### Human rerun only when product feel needs it

If an accepted fix changes player-facing balance/feel, rerun only the materially affected stage. Record it as a **new post-fix row/note** with its actual tech and reward context. Never replace the original first-attempt row or pretend the contexts are identical.

For a twice-failed main-path blocker, fix and regress the defect first, then rerun the blocked stage on the existing validation save so the campaign can continue. Record actual launch context again.

For nonblocking fixes discovered after later campaign progress, the deterministic regression is mandatory; a manual 1× rerun is optional unless the fix changes product feel enough to require human confirmation.

## Software baseline

Before the human pass run:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/game/game_session_test.dart test/game/run_module_unlocks_test.dart test/game/module_offer_picker_test.dart test/game/run_module_rules_test.dart
flutter test test/widget_test.dart --plain-name "first-clear commit then same-game Replay refreshes module eligibility"
flutter test test/widget_test.dart --plain-name "fresh first-clear save failure reports Blueprint not recovered"
flutter test test/widget_test.dart --plain-name "failed Retry Save then success reports Blueprint recovered"
flutter test
```

The focused tests explicitly credit hidden eligibility and reward-state behavior. The full suite remains mandatory.

## Final deliverable

Post one compact HPA-526 summary containing:

- all seven original stage rows from the continuous campaign;
- any separate post-fix rows/notes without overwriting originals;
- first-attempt/retry results;
- offers shown;
- tower/specialization and tech-at-launch context;
- overall comfort and clearability verdict;
- module/offer problems that survive the confound check;
- HPA-528 Proceed / Narrow / Stop verdict;
- focused follow-up links, if any;
- final catalog decision: keep seven or a separately justified future expansion.

## Risks and guardrails

### This is qualitative evidence

One player's continuous campaign is enough for this product gate but not for statistical balance claims. Do not tune from a signal that remains plausibly explained by build/tech choice.

### Random offers are unrecoverable

Record the cards shown while playing. Do not build runtime offer logging to solve this documentation problem.

### Validation can become endless tuning

Do not optimize for equal tower/module usage. HPA-526 closes after the complete pass and triage unless a twice-failed main-path stage blocks reaching later stages.

## Non-goals

- Mandatory growth to 10–12 modules
- All remaining boss blueprints
- Modules Codex without a comprehension problem
- Draft history, weighting, pity, deterministic seeds, or statistical sweeps
- Generic combat-event/effect architecture
- Persistent run history, telemetry, or evidence schema
- Rarity, decks, rerolls, consumables, module upgrades
- New tower families, maps, online services, daily modes
- Exhaustive balance certification
