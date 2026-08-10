# HPA-528 One Boss Blueprint Design Specification

## Decision

HPA-528 is Orion's next actionable reward-loop task. HPA-527 has shipped the six-module Salvage Module loop and HPA-525 has shipped the save-aware Mission Report, so the smallest remaining M1 proof is one permanent boss-derived module unlock before any catalog expansion.

Ship one blueprint:

- **Source stage:** Outpost Alpha (`OrionCampaign.stageOneId`)
- **Source boss:** Relay Breaker
- **Module:** **Relay Calibration**
- **Effect:** All towers gain **8% range** and their **attack interval drops 8%**.
- **Availability:** original six modules before the first committed Outpost Alpha clear; seven modules on runs started after that clear commits.

The feature derives ownership from committed campaign progress. It adds no ownership collection, save migration, blueprint registry, event bus, analytics, Codex section, or generalized reward system.

## Why this task is next

The current M1 dependency chain is complete:

1. HPA-527 supplies the playable three-draft Salvage Module loop.
2. HPA-525 supplies the Mission Report, explicit `saving` / `saved` / `failed` states, and the optional typed reward slot.
3. HPA-528 now proves whether one permanent unlock makes finishing a boss feel meaningfully rewarding.

HPA-528 blocks HPA-526, which intentionally defers catalog expansion until this proof exists. Doing M2 tuning or polish first would skip the product decision gate defined by the Orion reward-loop roadmap.

## Product goal

The first boss clear should create one obvious, durable new option without turning Orion into a progression grind.

A player should be able to observe this sequence:

```text
Fresh campaign
→ Outpost Alpha run uses the original six-module pool
→ first victory shows blueprint recovery pending while saving
→ successful save changes the report to "Blueprint recovered: Relay Calibration"
→ Replay Mission or a later mission starts with Relay Calibration eligible
→ campaign reset removes the unlock because Outpost Alpha is no longer cleared
```

The just-completed run never changes its module pool retroactively.

## Blueprint effect choice

### Recommended: Relay Calibration

```text
All towers gain 8% range; attack interval drops 8%.
```

Implementation values:

```dart
rangeMultiplier: 1.08,
fireIntervalMultiplier: 0.92,
```

This is deliberately a modest hybrid rather than a new combat mechanic:

- `rangeMultiplier` and `fireIntervalMultiplier` already flow end-to-end through `RunModuleDefinition`, `RunModuleRules`, `TowerStats.copyWith`, and live tower refresh.
- It is thematically tied to the Relay Breaker / Outpost Alpha reward source.
- It is useful with every tower family, so the first permanent unlock is easy to notice and does not become a dead card.
- It does not overlap the campaign tech tree, whose combat upgrades are laser damage and Cryo slow duration.
- It does not strictly replace the dedicated modules: Long Sight remains the stronger range choice at +15%, while Overclock Relay remains the stronger speed choice at -15% interval but carries a damage trade-off.

### Rejected alternative: tower-affinity blueprint

A Railgun- or Ion-specific damage module would also use existing stat fields, but it would require a new affinity branch and would frequently be irrelevant in early drafts when that tower is not placed. That is a weaker first proof of the reward loop.

### Rejected alternative: shield/armor counter blueprint

A Relay Breaker reward that boosts shield or armor damage is thematically attractive, but current projectile paths only propagate those multipliers for selected chain/pierce mechanics. Making the effect truthful for all towers would broaden damage plumbing across normal, splash, corrosion, drone, and field paths. That is unjustified architecture for a one-blueprint proof.

## Ownership and availability

### Single source of truth

The unlock is derived directly from committed stage progress:

```text
Relay Calibration available = committed CampaignProgress.isCleared(outpost-alpha)
```

No persisted blueprint flag exists.

Add a focused pure rule module, `run_module_unlocks.dart`, that owns only this derivation:

```dart
abstract final class RunModuleUnlocks {
  static const RunModuleId firstBlueprintModuleId =
      RunModuleId.relayCalibration;

  static bool hasFirstBlueprint(CampaignProgress progress) =>
      progress.isCleared(OrionCampaign.stageOneId);

  static Set<RunModuleId> availableFor(CampaignProgress progress) =>
      Set.unmodifiable({
        ...initialRunModuleIds,
        if (hasFirstBlueprint(progress)) firstBlueprintModuleId,
      });
}
```

`initialRunModuleIds` is the explicit original-six set/list. `runModuleCatalog` contains all seven definitions so existing definition lookup and rule application continue to work.

Do not infer locked modules by subtracting catalog entries in widgets. The rule above is the only campaign-to-module availability bridge.

### Run boundary

A `GameSession` receives the eligible module IDs for the current run. `_moduleCandidates()` filters the catalog to those IDs before applying the existing acquired/affinity preference logic.

The eligible set is stable during one attempt. A save completing while the Mission Report is open does **not** mutate the finished attempt.

However, the merged HPA-525 Replay action calls `game.restart()` on the same `OrionDefenseGame`. That restart is a new run and must see newly committed progress. Therefore `restart()` accepts an optional refreshed eligible-module collection and replaces the session's eligible set only as part of the restart reset.

This gives the intended semantics:

- first-clear attempt: six IDs for the whole attempt;
- save commits: campaign progress now owns the blueprint, but the terminal session is unchanged;
- Replay Mission: restart refreshes eligibility from committed progress and starts with seven IDs;
- loss Retry: restart refreshes from the same committed progress, so previously earned blueprints remain available;
- normal map launch: new game is constructed from committed progress;
- reset: empty committed progress produces the original six again.

## Architecture

### `game_models.dart`

Add `RunModuleId.relayCalibration`, its `RunModuleDefinition`, and the exact initial-six ID collection. Extend `RunModuleDefinition.effectText` with the one-sentence copy.

No new stat field is required.

### `run_module_unlocks.dart`

Add the pure `CampaignProgress` → available module IDs rule described above. This file knows the one stage-to-one-module mapping and nothing about Flutter, Flame, persistence, or report state.

Do not introduce `BlueprintDefinition`, `BlueprintRepository`, a generalized unlock graph, or a collection on `CampaignSave`.

### `GameSession`

Add an `availableRunModules` input with the original six as the default. Store a private eligible set, filter `_moduleCandidates()` by it, and refresh that set only when `restart(availableRunModules: ...)` explicitly receives a new value.

Existing draft behavior stays unchanged:

- still exactly three distinct cards;
- acquired modules remain excluded;
- placed/buildable affinity preference remains intact;
- ordinary randomness remains the production picker;
- module effects still apply through `TowerStatsResolver`.

### `OrionDefenseGame`

Thread `availableRunModules` from construction to `GameSession.initial` and from `restart(...)` to `GameSession.restart(...)`. Flame does not decide unlock ownership.

### `OrionGamePage`

Use `_committedProgress`, not an optimistic projection, when deriving module availability for a new/restarted run:

```dart
RunModuleUnlocks.availableFor(_committedProgress)
```

This makes the "saved means owned" rule explicit even if another persistence path becomes optimistic later.

Normal stage launch passes the derived IDs into `OrionDefenseGame`.

Mission Report Replay refreshes the same game before restarting:

```dart
game.restart(
  availableRunModules: RunModuleUnlocks.availableFor(_committedProgress),
);
```

No new persistence callback or writer is needed. HPA-525 already advances `_committedProgress` before its mission `onCommitted` callback publishes the saved result.

## Mission Report reward flow

Reuse the existing `MissionRewardFact` slot. Add one private projection/helper in `orion_game_page.dart`; do not turn reward facts into a registry.

A reward fact exists only when:

```text
mission stage == Outpost Alpha
AND prior saved result == null
```

That condition distinguishes the first clear from every replay.

Copy by save state:

### Saving first clear

- **Title:** `Blueprint recovery pending`
- **Detail:** `Relay Calibration unlocks after this result is saved.`

The active run still has only the original six IDs.

### Saved first clear

- **Title:** `Blueprint recovered: Relay Calibration`
- **Detail:** `Available in Salvage Module drafts on future runs.`

The next run/restart derives seven IDs from `_committedProgress`.

### Failed first clear

- **Title:** `Blueprint not recovered`
- **Detail:** `Retry Save to keep this first-clear reward.`

Prior campaign progress remains untouched, so availability stays at six.

### Replay improvement/retained result

No reward fact is rendered. The existing module summary remains visible, but there is no duplicate recovery celebration.

Retry Save uses the same first-clear mission state, so failure → success naturally changes `Blueprint not recovered` into `Blueprint recovered: Relay Calibration` without another reward state machine.

## Campaign presentation

Keep the permanent surface intentionally small.

### World map

Only the Outpost Alpha node gets a compact blueprint status line:

- before committed clear: `Blueprint • Locked`
- after committed clear: `Blueprint • Recovered`

Derive it from `progress.isCleared(OrionCampaign.stageOneId)`. Do not add locked silhouettes or blueprint markers to the other six stages.

### Stage briefing

After Outpost Alpha is cleared, add one line:

```text
Blueprint recovered: Relay Calibration
```

Before recovery, the briefing does not need a full locked-module description. The draft card remains the place where the complete effect sentence is explained.

## Data flow

```text
OrionGamePage committed progress
        │
        ├─ normal launch ───────────────┐
        │                               ▼
        │                    RunModuleUnlocks.availableFor
        │                               │
        │                               ▼
        │                    OrionDefenseGame / GameSession
        │                    eligible IDs frozen for attempt
        │
        └─ Mission Report first clear
               │
               ├─ saving → pending reward copy; no ownership change
               │
               ├─ failed  → not-recovered copy; committed progress unchanged
               │
               └─ saved   → committed progress includes Outpost Alpha
                                  │
                                  ├─ World Map / briefing show recovered
                                  └─ Replay restart refreshes eligible IDs
```

The existing campaign save remains the only persistence transaction.

## Error and reset behavior

- **Save failure:** no unlock because `_committedProgress` did not advance; report says the blueprint was not recovered.
- **Retry Save:** same mission result retries through HPA-525's existing writer; success then unlocks it.
- **World Map (Unsaved):** returns without ownership; later runs still use the original six.
- **Retained replay:** no save and no celebration; ownership was already derived from prior committed progress.
- **Campaign reset:** existing reset replaces committed progress with empty progress, automatically removing the blueprint.
- **Repeated taps/rebuilds:** no separate reward mutation exists to duplicate.
- **Process death while saving:** same residual risk as HPA-525; the uncommitted first clear and blueprint can be lost. Do not add durable recovery.

## Testing strategy

### Pure unlock and module rules

Prove:

- fresh progress returns exactly the original six IDs;
- committed Outpost Alpha progress adds exactly Relay Calibration;
- unrelated clears do not add it;
- empty/reset progress removes it;
- Relay Calibration applies only the existing +8% range / -8% interval fields and composes through the current resolver.

### Session/game eligibility

Prove:

- default sessions never offer the seventh catalog entry;
- a session constructed with the unlocked ID can offer it;
- offers remain three distinct valid cards;
- eligibility does not change mid-attempt;
- restart can refresh eligibility for the next run and still clears acquired modules/pending offers.

### Mission/persistence integration

Prove:

- first clear shows pending while the write is unresolved;
- pending state does not make Relay Calibration eligible;
- save success shows recovered;
- immediate Replay refreshes the same game to the seven-ID pool;
- save failure shows not recovered and leaves six-ID availability;
- Retry Save success then unlocks it;
- a later replay produces no duplicate recovery fact.

### Campaign UI

Prove:

- Outpost Alpha shows locked/recovered blueprint status from progress;
- recovered briefing line appears only after committed clear;
- reset returns the node/availability to locked/base-six state;
- compact surfaces do not overflow at the existing 360×640 target.

### Final validation

Run:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Then perform one human flow:

```text
fresh save → clear Outpost Alpha → observe pending → observe recovered
→ Replay Mission → reach first module draft → confirm Relay Calibration can appear and is understandable
```

The human check is product validation, not a statistical balance suite.

## Non-goals

- Blueprints for the other six stages
- Full Modules/Blueprints Codex section
- General unlock or reward registry
- Save schema changes or a blueprint ownership collection
- Unlock currencies, crafting, rarity, upgrades, rerolls, decks, or inventory
- Event-triggered combat effects or a semantic event bus
- New damage propagation solely for shield/armor blueprint mechanics
- Telemetry, release evidence export, deterministic seed protocol, or thousand-seed sweeps
- Sound, haptics, animation, or screen shake
- Broader Salvage Module catalog tuning; that remains HPA-526

## Acceptance mapping

HPA-528 is complete when:

1. exactly one module is derived from one committed Outpost Alpha clear;
2. first-clear pending/saved/failed copy matches actual persistence state;
3. the completed attempt never gains the module retroactively;
4. Replay Mission and future launches can use it after commit;
5. replay does not repeat recovery messaging;
6. reset removes it without a save migration;
7. the unlocked module is implemented entirely through existing range/fire-interval rules;
8. the Mission Report plus one compact campaign surface make the reward visible;
9. focused tests, full tests, and one human first-clear → next-run flow pass.
