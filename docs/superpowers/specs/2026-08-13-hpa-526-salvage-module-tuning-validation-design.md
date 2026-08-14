# HPA-526 Salvage Module Tuning and Campaign Validation Design Specification

## Decision

Treat the current seven-module catalog as the **candidate final catalog** and make HPA-526 validation-first.

Do not add modules, picker rules, blueprint rewards, Codex surfaces, or new stat/effect seams up front. The two HPA-527 human runs already reported positive draft comprehension and pacing with no mandatory, dead, or repetition problem. Expanding from seven modules merely because the ticket permits 10–12 would manufacture scope rather than answer an observed player need.

HPA-526 therefore executes as:

```text
close the outstanding HPA-528 human product proof
→ verify current main is healthy
→ play all seven stages once at ordinary 1× speed
→ record the required compact observations
→ no concrete problem? keep the seven-module catalog unchanged and finish
→ concrete problem? create one focused follow-up issue and rerun only affected stages after that fix
```

The planning PR contains documentation only. Runtime changes require a concrete observation first.

## Why this is the next task

The product milestones have reached the point where another feature is less valuable than checking whether the assembled game still feels comfortable end to end:

- HPA-527 shipped the six starter Salvage Modules and recorded two human 1× wins.
- HPA-525 shipped the compact Mission Report.
- HPA-528 shipped the first blueprint-gated module, Relay Calibration.
- HPA-531 shipped the lightweight sound, haptics, and Reduced Motion pass.
- HPA-523's standalone seven-stage balance pass was intentionally merged into HPA-526.

That leaves HPA-526 as the only unfinished M2 gameplay child. The right next question is not “what else can we add?” but “is the current campaign varied, readable, and comfortably clearable?”

## Evidence entering M2

### Salvage Module vertical slice

The HPA-527 implementation PR recorded two live iOS Simulator runs at strict 1×:

- **Outpost Alpha**: victory after all eight waves, base 4/20; Heavy Caliber, Emergency Salvage, Long Sight.
- **Nebula Relay**: victory after all eight waves, base 9/20; Heavy Caliber, Emergency Salvage, Overclock Relay.

The recorded conclusion was positive draft comprehension and pacing, with no mandatory/dead-card or third-draft repetition issue observed.

That evidence is enough to reject speculative catalog expansion before the final campaign pass.

### Blueprint proof

HPA-528 is implemented and marked Done, but its merged implementation PR still records one human product check as pending: first clear of Outpost Alpha → pending reward → successful save → recovered blueprint → Replay on the same game object → Relay Calibration eligible.

HPA-526 starts by performing and recording that product check. The outcome is explicitly one of:

- **Proceed** — the permanent option unlock is understandable and rewarding;
- **Narrow** — keep the one proven blueprint but do not expand blueprint progression;
- **Stop** — do not add more boss-blueprint rewards.

This decision affects only future blueprint expansion. It does not justify adding picker bias or forcing Relay Calibration into the next random offer.

## Alternatives considered

### 1. Validation-first, current seven-module catalog — chosen

Keep the current catalog and picker unchanged while running the whole campaign. This is the cheapest way to learn whether the game actually has a variety, readability, or balance problem.

Benefits:

- directly follows HPA-526's “expand only when justified” gate;
- preserves the already-working session and picker architecture;
- gives later changes a concrete player-facing reason;
- can legitimately finish with zero runtime code.

### 2. Pre-author 3–5 additional modules — rejected

Growing to 10–12 now would optimize for catalog size rather than player value. It would also increase the chance of duplicating existing tower specializations or campaign tech without evidence that seven choices are insufficient.

### 3. Generalized draft/effect/evidence infrastructure — rejected

Versioned draft algorithms, offer fingerprints, seed sweeps, event/effect registries, analytics exports, and generalized evidence models are explicitly unnecessary for this stage. Human notes in HPA-526 are sufficient.

## Existing architecture to preserve

The current implementation already has the seams HPA-526 needs.

### Catalog and effect data

`lib/game/models/game_models.dart` defines seven `RunModuleId` values and `runModuleCatalog` entries:

1. Heavy Caliber
2. Overclock Relay
3. Long Sight
4. Emergency Salvage
5. Cryo Reservoir
6. Rocket Fusing
7. Relay Calibration

The first six are base-eligible. Relay Calibration is the first blueprint-gated option.

Do not split the catalog into a registry or configuration layer for HPA-526.

### Rule application

`lib/game/rules/run_module_rules.dart` applies current modules through existing tower stat fields. It already covers ordinary damage, Nanite corrosion damage, Drone Bay drone damage, attack interval, range, Rocket splash, and Cryo slow duration.

A future module belongs in this ticket only if an observed need can be expressed cleanly through these existing seams. If the useful effect requires a new combat-event model, command graph, recursion guard, or broad new stat plumbing, stop and design that as a separate focused feature instead.

### Unlocks

`lib/game/rules/run_module_unlocks.dart` derives available modules from the catalog and committed campaign progress. Relay Calibration is gated by Outpost Alpha; there is no separate persisted blueprint collection.

Do not add another save field or migration.

### Offer selection

`lib/game/rules/game_session.dart` already:

- excludes acquired and unavailable modules;
- prefers universal cards and affinities for already placed tower families;
- falls back to currently unlocked tower-family affinities when needed;
- guarantees a three-card offer when at least three candidates exist.

`lib/game/rules/module_offer_picker.dart` remains a tiny injectable picker: production shuffles normally; tests can inject exact behavior.

No anti-repeat history, weighted ranking, pity rule, or deterministic protocol should be added unless the seven-stage pass exposes a concrete offer problem.

## HPA-528 product gate

Before interpreting blueprint progression as proven, run one fresh product journey:

1. Start from campaign state where Outpost Alpha has not been cleared.
2. Clear Outpost Alpha.
3. Confirm the Mission Report shows the reward as pending while persistence is in flight.
4. Confirm successful save changes the reward to recovered.
5. Choose Replay without reconstructing the page/game shell.
6. Confirm Relay Calibration is now in the attempt's eligible module set.
7. Confirm the just-completed attempt did not gain the module retroactively.
8. Record Proceed / Narrow / Stop plus one sentence explaining why.

A random three-card draft not containing Relay Calibration is not a failure; eligibility, not guaranteed appearance, is the contract.

## Seven-stage validation pass

Run one ordinary human attempt at **1× speed** on each campaign stage:

1. Outpost Alpha
2. Nebula Relay
3. Salvage Rift
4. Asteroid Foundry
5. Aurora Gate
6. Void Bastion
7. Singularity Core

Use normal player behavior. Do not inject gold, health, kills, wave clears, or a preferred module offer. The purpose is product feel, not deterministic benchmarking.

Record one row per stage directly in HPA-526 using this schema:

| Field | What to record |
| --- | --- |
| Result | Clear, or loss with failed wave |
| Length | Short / comfortable / long |
| Difficulty | 1–5 perceived difficulty |
| Modules | The selected Salvage Modules |
| Offer quality | Whether each offer was understandable and useful |
| Card problems | Any dead, mandatory, repetitive, or confusing card |
| Stage identity | Whether the environmental modifier and boss were noticeable |
| Mobile UX | Any readability or control problem |
| Comfort | One sentence: comfortably clearable or why not |

Do not capture exact economy reconciliation, per-wave health tables, seeds, machine exports, or formal evidence artifacts.

## Decision rules after the pass

### No concrete problem

If the seven stages remain comfortably clearable and there is no repeated weak/mandatory/confusing module pattern:

- keep all seven module definitions and values unchanged;
- keep the picker unchanged;
- keep only the Relay Calibration blueprint;
- do not add a Codex Modules section;
- publish the compact HPA-526 summary and finish the ticket.

Zero runtime code is a successful HPA-526 outcome.

### Concrete value or balance problem

If a module is repeatedly too weak, too strong, or effectively mandatory, open a focused Linear follow-up containing:

- affected stage(s);
- exact module;
- observed symptom;
- minimal reproduction/context;
- smallest proposed value/copy change.

That follow-up should modify only the existing catalog/rule seam needed for the observed issue and add focused tests for the changed contract. Rerun only stages materially affected by the accepted fix.

### Concrete offer-quality problem

If players repeatedly receive impossible, pivot-only, or confusing offers, open a focused follow-up for the smallest candidate-selection correction. Prefer changing `GameSession` candidate filtering before changing `ModuleOfferPicker`; the picker should remain policy-free unless the defect is specifically about repeated random selection.

Do not add complete offer history or weighted ranking merely because one run happens to repeat a card.

### Genuine missing build pattern

If repeated play identifies a distinct missing strategic choice, first compare it against:

- the seven current run modules;
- all tower specializations;
- campaign tech upgrades;
- side-stage rewards.

Only then design one module around the missing player-facing purpose. Reuse current `RunModuleDefinition` fields if possible. If the desired effect needs a new rule seam, write a small focused design for that seam before implementation rather than broadening HPA-526 implicitly.

### Blueprint expansion

Additional boss blueprints are not part of the default plan. Consider one only if the HPA-528 human verdict is **Proceed** and the seven-stage pass provides a specific reason that another option unlock would improve progression.

Even then, ownership must still derive from committed stage clears and presentation must reuse the existing Mission Report/world-map pattern.

## Codex decision

Do not add a Modules section now.

Seven cards already have short effect copy in the draft and selected modules are repeated in the Mission Report. The HPA-527 playtests did not report comprehension problems. A Codex section becomes justified only if later catalog growth or repeated play shows that players cannot remember the available choices.

## Testing policy

If HPA-526 finishes without runtime changes, validation is:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/game/game_session_test.dart test/game/module_offer_picker_test.dart test/game/run_module_rules_test.dart
flutter test
```

If a focused follow-up changes code, that follow-up owns the failing test for its concrete defect plus the same final format/analyze/full-suite checks.

Do not add thousand-seed sweeps or release-certification matrices.

## Final deliverable

Post one compact HPA-526 summary containing:

- seven stage rows using the validation schema;
- overall comfort and clearability verdict;
- any module repeatedly perceived as weak, mandatory, repetitive, or confusing;
- stages that felt too long, too easy, too hard, or visually dense;
- the HPA-528 Proceed / Narrow / Stop verdict;
- links to focused follow-up issues, if any;
- explicit final catalog decision: **keep seven** or a separately justified future expansion.

## Risks and guardrails

### A single campaign pass is qualitative

One human run is enough for this product gate but not enough for statistical claims. Treat observations as concrete UX/balance signals, not proof of exact pick rates or win rates.

### Random offers can look repetitive by chance

One repeated card is not evidence for anti-repeat infrastructure. Require a repeated player-facing complaint or clearly bad offer state before changing picker behavior.

### Validation can become endless tuning

Do not optimize for equal usage among towers/modules. Open follow-ups only for problems that hurt clarity, comfort, or meaningful choice. HPA-526 ends after the compact pass and triage.

## Non-goals

- Mandatory growth to 10–12 modules
- Implementing all remaining boss blueprints
- A Modules Codex without a comprehension problem
- Versioned/deterministic draft protocol
- Cross-platform seed fixtures or statistical sweeps
- Generic combat-event/effect architecture
- Persistent run history or telemetry
- Rarity, decks, rerolls, consumables, or module upgrades
- New tower families, maps, online services, or daily modes
- Exhaustive balance certification
