# HPA-528 One Boss Blueprint Design Specification

## Decision

HPA-528 is Orion's next M1 reward-loop proof after the Salvage Module vertical slice and Mission Report.

Ship exactly one blueprint:

- **Source stage:** Outpost Alpha (`OrionCampaign.stageOneId`)
- **Source boss:** Relay Breaker
- **Module:** **Relay Calibration**
- **Effect:** all towers gain **8% range** and their **attack interval drops 8%**
- **Ownership:** derived from a committed Outpost Alpha clear
- **Availability:** locked on the first attempt; eligible on attempts started after that clear commits

The feature adds no save field, ownership collection, reward registry, event bus, combat event plumbing, Codex section, or generalized blueprint system.

## Product goal

The first boss clear should create one obvious, durable new option without turning Orion into a progression grind.

The intended flow is:

```text
Fresh campaign
→ Outpost Alpha uses the normal module pool
→ first victory shows blueprint recovery pending while saving
→ successful save changes the report to "Blueprint recovered: Relay Calibration"
→ Replay Mission or a later mission starts with Relay Calibration eligible
→ campaign reset removes the unlock because Outpost Alpha is no longer cleared
```

The completed attempt never gains the module retroactively.

## Blueprint effect

Relay Calibration reuses stat seams that already exist:

```dart
rangeMultiplier: 1.08,
fireIntervalMultiplier: 0.92,
```

Player-facing copy:

```text
All towers gain 8% range; attack interval drops 8%.
```

This choice stays deliberately modest:

- `RunModuleRules.applyTowerStats` already applies both multipliers generically.
- It is universal, so the first permanent reward does not become a dead card for an unbuilt tower family.
- Long Sight remains the stronger dedicated range choice.
- Overclock Relay remains the stronger dedicated speed choice and still carries its damage trade-off.
- The campaign tech tree currently boosts Laser damage and Cryo slow duration, so Relay Calibration does not duplicate those upgrades.

### Rejected: tower-affinity blueprint

A Railgun- or Ion-specific module could use existing stats, but it would be less useful as the first permanent reward and would require another affinity branch.

### Rejected: shield/armor counter blueprint

The theme fits Relay Breaker, but shield/armor multipliers are not propagated uniformly through every attack path. Making such a reward truthful would widen damage plumbing for a one-blueprint proof.

## Single-source unlock rule

Do not add a hand-maintained `initialRunModuleIds` list beside `runModuleCatalog`.

Instead, keep the catalog as the definition source and put only **locked-module metadata** in the focused unlock rule:

```dart
const _unlockStageByModule = <RunModuleId, String>{
  RunModuleId.relayCalibration: OrionCampaign.stageOneId,
};

abstract final class RunModuleUnlocks {
  static bool hasFirstBlueprint(CampaignProgress progress) =>
      progress.isCleared(OrionCampaign.stageOneId);

  static Set<RunModuleId> availableFor(CampaignProgress progress) =>
      Set<RunModuleId>.unmodifiable(
        runModuleCatalog
            .map((definition) => definition.id)
            .where((id) {
              final unlockStageId = _unlockStageByModule[id];
              return unlockStageId == null ||
                  progress.isCleared(unlockStageId);
            }),
      );

  static final Set<RunModuleId> baseModules =
      availableFor(CampaignProgress());
}
```

This keeps one fact per locked module:

```text
Relay Calibration → Outpost Alpha
```

Any future ordinary module added by HPA-526 is automatically part of the base pool unless it receives an unlock-map row. A future blueprint adds one map row rather than synchronizing catalog, base-list, and unlock branches.

The rule belongs in `rules/run_module_unlocks.dart`. Widgets never infer locked modules by subtracting catalog entries.

## Run-boundary semantics

### One attempt freezes its inputs

An active mission attempt freezes:

- campaign modifiers derived from committed campaign progress + committed tech tree;
- eligible Salvage Module IDs derived from committed campaign progress.

Neither changes while that attempt is active, including while its Mission Report is saving.

### Replay/Retry is a new attempt

The merged Mission Report deliberately reuses the same `OrionDefenseGame` and calls `restart()` instead of constructing a new game. That restart is a **new attempt boundary**.

At that boundary Orion must refresh **both** progress-derived run inputs from the same committed state:

```dart
final committedModifiers = CampaignModifiers.fromProgress(
  _committedProgress,
  OrionCampaign.stages,
  _committedTechTree,
);
final availableModules = RunModuleUnlocks.availableFor(_committedProgress);

game.restart(
  campaignModifiers: committedModifiers,
  availableRunModules: availableModules,
);
```

Do not refresh only the blueprint pool. Doing so would make a newly recovered blueprint apply on Replay while an existing side-stage reward earned by the same save remained stale.

This deliberately fixes that existing inconsistency. For example:

```text
clear Salvage Rift
→ save commits its +starting-gold reward
→ Replay Mission
→ replay starts with the newly earned gold bonus
```

No new wrapper type is required. The existing `CampaignModifiers` value and eligible-ID set are refreshed together in the same restart call from the same committed snapshot.

## GameSession restart changes

`GameSession` currently stores `campaignModifiers`, `startingGold`, and `startingBaseHealth` as final attempt inputs. To support a same-object new attempt, make those values refreshable only when `restart(...)` receives new campaign modifiers.

Conceptually:

```dart
void restart({
  CampaignModifiers? campaignModifiers,
  Iterable<RunModuleId>? availableRunModules,
}) {
  if (campaignModifiers != null) {
    _campaignModifiers = campaignModifiers;
    _startingGold = campaignModifiers.adjustedStartingGold;
    _startingBaseHealth = StageModifierRules.effectiveStartingBaseHealth(
      campaignAdjustedBaseHealth:
          campaignModifiers.adjustedStartingBaseHealth,
      stageModifiers: stage.modifiers,
    );
  }

  if (availableRunModules != null) {
    _availableRunModules =
        Set<RunModuleId>.unmodifiable(availableRunModules);
  }

  _gold = _startingGold;
  _baseHealth = _startingBaseHealth;
  // existing reset work follows
}
```

`null` continues to mean "keep the current attempt configuration" for existing callers/tests that restart without a campaign refresh.

`resolveTowerStats` and clear-bonus calculation use the refreshed campaign modifiers on the new attempt.

## Construction defaults

Because `RunModuleUnlocks.baseModules` is derived rather than a compile-time const, construction accepts nullable eligibility:

```dart
GameSession.initial({
  ...,
  Iterable<RunModuleId>? availableRunModules,
})
```

and resolves:

```dart
availableRunModules ?? RunModuleUnlocks.baseModules
```

`OrionDefenseGame` threads the same nullable construction input into `GameSession.initial`.

Normal production stage launch always passes eligibility derived from `_committedProgress`; the default primarily preserves simple direct construction in tests and lower-level callers.

## Committed progress is the run truth

All mission-run inputs use committed state:

```text
campaign modifiers  ← _committedProgress + _committedTechTree
module eligibility  ← _committedProgress
prior saved result  ← _committedProgress.resultFor(stage.id)
```

`_progress` remains the visible UI projection, but it is not the authority for run ownership/reward truth.

This also fixes the Mission Report first-clear fact. At launch/restart capture:

```dart
_missionPriorResult = _committedProgress.resultFor(stage.id);
```

The captured value stays stable while the first-clear save runs:

- before commit: `null` → this attempt did not own the blueprint when it began;
- after commit: still `null` for the completed attempt, so the report can change from pending to recovered;
- on Replay: recapture from committed progress → non-null, so later victories do not repeat the recovery message.

No separate `_missionPriorCommittedClear` boolean is needed.

## Mission Report reward flow

Reuse the existing `MissionRewardFact` slot. Add one private projector in `OrionGamePage`; do not create a registry.

A reward fact exists only when:

```text
mission stage == Outpost Alpha
AND captured prior committed result == null
```

### Saving first clear

- **Title:** `Blueprint recovery pending`
- **Detail:** `Relay Calibration unlocks after this result is saved.`

### Saved first clear

- **Title:** `Blueprint recovered: Relay Calibration`
- **Detail:** `Available in Salvage Module drafts on future runs.`

### Failed first clear

- **Title:** `Blueprint not recovered`
- **Detail:** `Retry Save to keep this first-clear reward.`

### Replay

No reward fact. The prior committed result was recaptured at the new attempt boundary.

Retry Save needs no additional state machine: the captured prior result remains null while the original terminal attempt moves failed → saving → saved.

## Campaign presentation

Keep permanent presentation small and specific.

### World map

Only Outpost Alpha gets one small status row:

```text
Blueprint • Locked
```

before committed clear and:

```text
Blueprint • Recovered
```

after committed clear.

Reuse the same small `FittedBox(fit: BoxFit.scaleDown)` treatment already used by side-stage reward rows. Do not route this through `CampaignReward` or `stageRewardLabel`.

The existing reward-bearing side-stage nodes already render four rows (icon, label, status, reward) inside `nodeHeight = 124`. Alpha will also render four rows, so **do not pre-authorize a global node-height change**. Keep the 360×640 regression; if Alpha alone overflows, fix its row to match the existing reward-row treatment rather than perturbing all node placement.

### Stage briefing

After committed recovery, Outpost Alpha shows one line:

```text
Blueprint recovered: Relay Calibration
```

The full effect sentence remains on the draft card.

## Error and reset behavior

- **Save pending:** the finished attempt stays on its original module pool and original campaign modifiers.
- **Save failure:** `_committedProgress` does not advance; the report says the blueprint was not recovered.
- **Retry Save:** success advances committed progress and the report becomes recovered.
- **World Map (Unsaved):** returns with no blueprint ownership.
- **Replay after success:** refreshes both campaign modifiers and module eligibility from committed state.
- **Replay of an already-cleared stage:** no duplicate recovery message.
- **Campaign reset:** existing reset clears committed progress, which removes the blueprint automatically.
- **Process death while saving:** same residual risk as HPA-525; do not add durable recovery.

## Testing strategy

### Unlock/model tests

Prove:

- `runModuleCatalog` covers every `RunModuleId` exactly once;
- `RunModuleUnlocks.baseModules` excludes Relay Calibration;
- Outpost Alpha committed progress adds Relay Calibration;
- unrelated progress does not add it;
- reset/empty progress removes it;
- Relay Calibration changes only range and fire interval through existing rules.

Avoid a hard-coded catalog length that must change whenever HPA-526 adds an ordinary module.

### Session/game tests

Prove:

- default construction uses `RunModuleUnlocks.baseModules`;
- unlocked construction can offer Relay Calibration;
- the eligible set is frozen for an active attempt;
- restart can refresh module eligibility;
- restart with refreshed `CampaignModifiers` recomputes starting gold/base health and uses the refreshed modifiers for the new attempt;
- restart with no new inputs preserves current lower-level behavior.

The attempt-freeze test is a guardrail, not the primary lifecycle proof.

### Page/persistence tests

Automate the risky paths:

1. **Outpost Alpha first clear → pending → commit → Replay Mission**
   - same game object;
   - six/base IDs before commit;
   - still base IDs while saving;
   - recovered copy after commit;
   - Replay refreshes the same game to include Relay Calibration.
2. **Save failure / Retry Save**
   - not-recovered copy on failure;
   - no availability change;
   - successful retry then unlocks.
3. **Already-cleared replay**
   - no duplicate recovery fact.
4. **Salvage Rift clear → commit → Replay Mission**
   - replay starting gold includes the newly committed side-stage reward.
5. **Reset**
   - map returns to locked;
   - new Outpost Alpha attempt excludes Relay Calibration.

### Campaign UI tests

Prove:

- exactly one map node shows a blueprint row;
- locked/recovered copy follows progress;
- recovered briefing line appears after committed clear;
- 360×640 has no overflow with the existing `nodeHeight = 124`.

## Product risk

Relay Calibration is one random card in the eligible pool. A player can recover the blueprint and then finish a later run without being offered that exact card.

That is acceptable for this proof because ownership is still made explicit on the Mission Report, Outpost Alpha node, and recovered briefing. The picker remains ordinary 3-card randomness.

If the human proof says the reward feels invisible, the allowed first response is:

1. improve the wording/placement on those existing surfaces; or
2. conclude the blueprint proof is not strong enough and do not expand it yet.

Do **not** add pity, forced-first-offer, priority weighting, rerolls, or unlock-aware behavior to `ModuleOfferPicker` in HPA-528.

## Non-goals

- Blueprints for other stages
- Full Modules/Blueprints Codex section
- Persistent blueprint ownership fields
- General reward/unlock registry
- New save schema or migration
- Rarity, decks, rerolls, crafting, currencies, or module upgrades
- New combat events or shield/armor plumbing
- Telemetry or deterministic seed protocol
- Sound, haptics, screen shake, or reward animation
- Broader module catalog tuning; that remains HPA-526

## Acceptance criteria

HPA-528 is complete when:

1. exactly one module is derived from one committed Outpost Alpha clear;
2. the unlock mapping is single-source and ordinary future catalog additions do not require a second base-module list;
3. pending/saved/failed report copy matches committed ownership truth;
4. the completed attempt never gains the module retroactively;
5. Replay refreshes both campaign modifiers and module eligibility from the same committed snapshot;
6. the same-game first-clear → commit → Replay path is automated;
7. an existing side-stage reward also refreshes on Replay, proving the run-boundary rule is consistent;
8. replay does not repeat recovery messaging;
9. reset removes the unlock without save migration;
10. the map/briefing surfaces fit the existing mobile layout without changing the global node height for this row;
11. focused tests, full tests, and one human first-clear → next-attempt proof pass.
