# HPA-526 Salvage Module Tuning and Campaign Validation Design Specification

## Decision

Treat the current seven-module catalog as the **candidate final catalog** and make HPA-526 validation-first.

Do not add modules, picker rules, blueprint rewards, Codex surfaces, or new stat/effect seams up front. The two HPA-527 human runs already reported positive draft comprehension and pacing with no mandatory, dead, or repetition problem. Expanding from seven modules merely because the ticket permits 10–12 would manufacture scope rather than answer an observed player need.

HPA-526 therefore executes as one continuous assembled-product check:

```text
verify the current implementation and hidden unlock/replay contracts
→ reset campaign progress once if needed
→ use that same campaign save for the entire validation
→ Outpost Alpha first clear doubles as the HPA-528 human product check and validation row
→ continue through all seven stages in campaign order at ordinary 1×
→ allow normal tech purchases and let side-stage rewards stack naturally
→ record first-attempt results plus enough build/tech context to interpret them
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

That leaves HPA-526 as the unfinished M2 gameplay child. The next question is not “what else can we add?” but “is the current assembled campaign varied, readable, and comfortably clearable?”

## Evidence entering M2

### Salvage Module vertical slice

The HPA-527 implementation PR recorded two live iOS Simulator runs at strict 1×:

- **Outpost Alpha**: victory after all eight waves, base 4/20; Heavy Caliber, Emergency Salvage, Long Sight.
- **Nebula Relay**: victory after all eight waves, base 9/20; Heavy Caliber, Emergency Salvage, Overclock Relay.

The recorded conclusion was positive draft comprehension and pacing, with no mandatory/dead-card or third-draft repetition issue observed.

That evidence is enough to reject speculative catalog expansion before the final campaign pass.

### Blueprint implementation proof

HPA-528 is implemented and the hidden lifecycle contract is already automated:

- `test/game/game_session_test.dart` proves the eligible module set stays frozen during one attempt.
- `test/game/run_module_unlocks_test.dart` proves a committed Outpost Alpha clear unlocks Relay Calibration.
- `test/widget_test.dart` proves first-clear commit then **same-game Replay** refreshes module eligibility.

The human HPA-528 check should therefore judge only player-visible behavior and product value. It must not ask the player to infer an internal eligible set that the HUD does not expose.

The human outcome is one of:

- **Proceed** — the permanent option unlock is understandable and rewarding;
- **Narrow** — keep the one proven blueprint but do not expand blueprint progression;
- **Stop** — do not add more boss-blueprint rewards.

This decision affects only future blueprint expansion. It does not justify picker bias or guaranteed appearance.

## Alternatives considered

### 1. Validation-first, current seven-module catalog — chosen

Keep the current catalog and picker unchanged while running the whole campaign on one save. This is the cheapest way to learn whether the game actually has a variety, readability, or balance problem.

Benefits:

- directly follows HPA-526's “expand only when justified” gate;
- validates the real campaign stacking behavior rather than isolated stage sandboxes;
- preserves the already-working session and picker architecture;
- gives later changes a concrete player-facing reason;
- can legitimately finish with zero runtime code.

### 2. Pre-author 3–5 additional modules — rejected

Growing to 10–12 now would optimize for catalog size rather than player value. It would also increase the chance of duplicating existing tower specializations or campaign tech without evidence that seven choices are insufficient.

### 3. Generalized draft/effect/evidence infrastructure — rejected

Versioned draft algorithms, offer fingerprints, seed sweeps, event/effect registries, analytics exports, and generalized evidence models are unnecessary for this stage. Human notes in HPA-526 are sufficient.

## Existing architecture to preserve

### Catalog and effect data

`lib/game/models/game_models.dart` defines the seven current `RunModuleId` values and `runModuleCatalog` entries:

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

A future module belongs only in a focused follow-up when an observed need can be expressed cleanly through these existing seams. If the useful effect requires a new combat-event model, command graph, recursion guard, or broad new stat plumbing, stop and design that separately.

### Unlocks

`lib/game/rules/run_module_unlocks.dart` derives available modules from the catalog and committed campaign progress. Relay Calibration is gated by Outpost Alpha; there is no separate persisted blueprint collection.

Do not add another save field or migration.

### Offer selection

`lib/game/rules/game_session.dart` already:

- excludes acquired and unavailable modules;
- prefers universal cards and affinities for already placed tower families;
- falls back to currently unlocked tower-family affinities when needed;
- produces a three-card offer when at least three candidates exist.

`lib/game/rules/module_offer_picker.dart` remains a tiny injectable picker: production shuffles normally; tests can inject exact behavior.

No anti-repeat history, weighted ranking, pity rule, or deterministic protocol should be added unless the campaign pass exposes a concrete offer problem.

### Campaign stacking

The validation must exercise the real persisted campaign rather than seven unrelated stage runs.

`CampaignSave` stores stage progress and tech purchases together. `CampaignModifiers.fromProgress(...)` derives campaign-wide effects from that committed state, including side-stage rewards and purchased tech.

Use one save and the normal campaign order:

```text
Outpost Alpha
→ Nebula Relay
→ Salvage Rift
→ Asteroid Foundry
→ Aurora Gate
→ Void Bastion
→ Singularity Core
```

This order deliberately exercises:

- Relay Calibration after the committed Outpost Alpha clear;
- Salvage Rift bonus gold on Foundry and later stages if Rift is cleared;
- Void Bastion bonus health on Singularity Core if Bastion is cleared;
- any tech upgrades purchased through normal play.

Reset at most once before Outpost Alpha. Do not reset between stages or between the HPA-528 check and the seven-stage pass.

## Human HPA-528 product gate

Outpost Alpha's first-clear attempt is also the first HPA-526 validation row.

The human checks only player-visible behavior:

1. Start from an uncleared Outpost Alpha state on the validation save.
2. Clear Outpost Alpha at 1×.
3. Confirm the Mission Report shows **Blueprint recovery pending** while persistence is in flight.
4. Confirm successful save changes the reward to **Blueprint recovered: Relay Calibration**.
5. Choose Replay on the same page/game shell and confirm a clean new run starts normally.
6. Judge whether the pending → recovered → future-run story is understandable and rewarding.
7. Record Proceed / Narrow / Stop plus one sentence explaining why.
8. Return to the world map and continue the same campaign save.

Do not require the human to verify `availableRunModules`; it is not published through `GameSnapshot` or a player-facing eligible-pool UI. Do not require Relay Calibration to appear in the first random offer.

If Relay Calibration naturally appears in a later validation draft, note it as ordinary observation only.

## Seven-stage validation pass

Run one continuous human campaign at **1× speed** using normal player behavior.

- Do not inject gold, health, kills, wave clears, progress, tech, or preferred module offers.
- Tech purchases are allowed when the player would normally choose them.
- Side-stage rewards remain in the same save and affect later stages naturally.
- The first attempt is always the authoritative observation row.

### Retry contract

A first-attempt loss is meaningful product evidence; never replace it silently with a later clear.

- Record the first-attempt loss and failed wave in the row.
- Allow at most **one** comfort retry after a small ordinary strategy adjustment.
- Record the retry outcome separately; the row's primary result remains the first attempt.
- A first-attempt loss on a main-path stage is automatically a focused follow-up candidate.
- If the one retry clears, continue the same campaign save and describe the stage as “clearable after a small adjustment,” not “comfortable first try.”
- If the one retry also loses on a main-path stage, stop brute-force play. Open a blocking focused follow-up; HPA-526 remains open until that gate is fixed/retested and the campaign can continue.
- If the one retry also loses on an optional side stage, continue the main path without that side-stage reward. That missing reward is part of the actual campaign state and should be reflected in later observations.

## Observation schema

Record one row per stage directly in HPA-526 using these fields:

| Field | What to record |
| --- | --- |
| First attempt | Clear, or loss with failed wave |
| Retry | Not used, or the one comfort-retry result |
| Length | Short / comfortable / long |
| Difficulty | 1–5 perceived difficulty for the first attempt |
| Towers | Tower types used plus any level-3 specializations |
| Tech at launch | Purchased campaign tech owned when the stage started |
| Modules | Selected Salvage Modules |
| Offer quality | Whether each offer was understandable and useful |
| Card problems | Any dead, mandatory, repetitive, or confusing card |
| Stage identity | Whether the environmental modifier and boss were noticeable |
| Mobile UX | Any readability or control problem |
| Comfort | One sentence interpreting first-attempt comfort and any retry |

The Towers + Tech context is required because triage compares module complaints against existing specializations and campaign tech. Without it, “mandatory Emergency Salvage” and “no economy tech purchased” or “Cryo Reservoir duplication” and “Cryo-only build with Cryo Coolant” are not distinguishable from the row itself.

Do not capture exact economy reconciliation, per-wave health tables, seeds, machine exports, screenshots for every wave, or formal evidence artifacts.

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

If a module is repeatedly too weak, too strong, effectively mandatory, or confusing, open a focused Linear follow-up containing:

- affected stage(s);
- exact module;
- first-attempt symptom;
- tower/specialization context;
- tech-at-launch context;
- smallest proposed value/copy change.

That follow-up should modify only the existing catalog/rule seam needed for the observed issue and add focused tests for the changed contract. Rerun only stages materially affected by the accepted fix.

### Concrete offer-quality problem

If the pass records impossible, pivot-only, or clearly harmful repetition, open a focused follow-up for the smallest candidate-selection correction. Prefer changing `GameSession` candidate filtering before changing `ModuleOfferPicker`; the picker should remain policy-free unless the defect is specifically about random selection behavior.

Do not add complete offer history or weighted ranking merely because one run happens to repeat a card.

### Genuine missing build pattern

If the pass identifies a distinct missing strategic choice, first compare it against:

- the seven current run modules;
- all tower specializations;
- campaign tech upgrades;
- side-stage rewards.

Only then create one focused feature issue around the missing player-facing purpose. Reuse current `RunModuleDefinition` fields if possible. If the desired effect needs a new rule seam, write a small focused design for that seam before implementation rather than broadening HPA-526 implicitly.

### Blueprint expansion

Additional boss blueprints are not part of the default plan. Consider one only if the human HPA-528 verdict is **Proceed** and the campaign pass provides a specific progression reason that another option unlock would improve.

Even then, ownership must still derive from committed stage clears and presentation must reuse the existing Mission Report/world-map pattern.

## Codex decision

Do not add a Modules section now.

Seven cards already have short effect copy in the draft and selected modules are repeated in the Mission Report. The HPA-527 playtests did not report comprehension problems. A Codex section becomes justified only if repeated validation shows that players cannot understand or remember the choices.

## Testing policy

The software baseline should prove the contracts this ticket actually depends on rather than rely on a manual source audit.

Run:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/game/game_session_test.dart test/game/run_module_unlocks_test.dart test/game/module_offer_picker_test.dart test/game/run_module_rules_test.dart
flutter test test/widget_test.dart --plain-name "first-clear commit then same-game Replay refreshes module eligibility"
flutter test
```

The focused tests cover attempt freeze, unlock derivation, offer behavior, module rules, and same-object Replay eligibility refresh. The full suite remains mandatory.

If a focused follow-up changes code, that follow-up owns the failing test for its concrete defect plus final format/analyze/full-suite checks.

Do not add thousand-seed sweeps or release-certification matrices.

## Final deliverable

Post one compact HPA-526 summary containing:

- seven stage rows from the one continuous campaign save;
- first-attempt result and optional one-retry outcome;
- tower/specialization and tech-at-launch context for each row;
- overall comfort and clearability verdict;
- any module repeatedly perceived as weak, mandatory, repetitive, or confusing;
- stages that felt too long, too easy, too hard, or visually dense;
- the HPA-528 Proceed / Narrow / Stop verdict;
- links to focused follow-up issues, if any;
- explicit final catalog decision: **keep seven** or a separately justified future expansion.

## Risks and guardrails

### A single campaign pass is qualitative

One human campaign is enough for this product gate but not enough for statistical claims. Treat observations as concrete UX/balance signals, not proof of exact pick rates or win rates.

### Random offers can look repetitive by chance

One repeated card is not evidence for anti-repeat infrastructure. Require a clearly harmful offer state or repeated player-facing complaint before changing picker behavior.

### Validation can become endless tuning

Do not optimize for equal usage among towers/modules. Open follow-ups only for problems that hurt clarity, comfort, or meaningful choice. HPA-526 ends after the complete campaign pass and triage, except when a twice-failed main-path stage blocks reaching later stages.

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