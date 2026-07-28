# Orion Stage Environmental Modifiers Design

## Context

Orion's campaign has seven fixed stages whose paths and wave compositions
already differ, but every stage still follows the same mission rules. HPA-101
adds environmental modifiers so the six non-baseline stages require distinct
strategies.

The current architecture separates pure game rules from Flame simulation and
Flutter presentation:

- `StageDefinition` owns static campaign-stage data.
- `GameSession` owns mission economy, base health, waves, and phase changes.
- `EnemyLogic` owns deterministic enemy combat and movement state.
- `OrionDefenseGame` owns spawning and bridges pure rules to Flame components.
- `GameSnapshot` is the mission UI's state source.
- `WorldMapView` and `OrionGamePage` own campaign selection and presentation.

The modifier design preserves these boundaries. It does not mutate shared
`EnemyStats`, duplicate modified wave definitions, or branch on stage IDs
inside mission logic.

## Goal

Give every non-baseline campaign stage a visible, mechanically distinct
environmental identity:

- Nebula Relay: shield recharge.
- Salvage Rift: bonus gold from swarm enemies.
- Asteroid Foundry: reinforced armored enemies.
- Aurora Gate: regen-enemy pressure pulses.
- Void Bastion: lower starting health in exchange for larger wave-clear
  rewards.
- Singularity Core: faster enemies and stronger Gravity Wells.

Outpost Alpha remains the unmodified reference stage.

## Scope

This ticket includes:

- An immutable zero-or-more modifier list on `StageDefinition`.
- Atomic, typed modifier values that compose without depending on list order.
- All six non-baseline stage themes implemented end-to-end.
- A pre-mission stage briefing opened from the world map.
- A compact environment reminder in the build-phase enemy-intel panel.
- Pure rule, game-layer, campaign-validation, and widget coverage.
- Migration of existing stage-selection tests to the new briefing interaction.
- A manual balance and clearability pass across the baseline and modified
  stages.

## Non-Goals

- New campaign stages, paths, waves, enemies, towers, or artwork.
- Procedural or randomly selected modifiers.
- Persisting modifiers in campaign saves.
- Rebalancing existing base enemy or tower definitions.
- Changing the existing side-stage completion rewards.
- Adding a generic runtime plug-in system for third-party modifiers.

## Modifier Data Model

Add an atomic `StageModifier` enum beside Orion's other gameplay enums in
`lib/game/models/game_models.dart`:

```dart
enum StageModifier {
  shieldRecharge,
  swarmBounty,
  reinforcedArmor,
  regenPressurePulses,
  reducedStartingHealth,
  enhancedClearBonus,
  enemySpeedSurge,
  amplifiedGravityWells,
}
```

`StageDefinition` gains an immutable list:

```dart
StageDefinition({
  // Existing fields...
  List<StageModifier> modifiers = const [],
}) : modifiers = List.unmodifiable(modifiers);

final List<StageModifier> modifiers;
```

The list, rather than a nullable single value, makes both the zero-modifier
fallback and trade-off stages explicit. Static campaign assignments are:

| Stage | Modifiers |
| --- | --- |
| Outpost Alpha | none |
| Nebula Relay | `shieldRecharge` |
| Salvage Rift | `swarmBounty` |
| Asteroid Foundry | `reinforcedArmor` |
| Aurora Gate | `regenPressurePulses` |
| Void Bastion | `reducedStartingHealth`, `enhancedClearBonus` |
| Singularity Core | `enemySpeedSurge`, `amplifiedGravityWells` |

Modifier values are static campaign data. Campaign progress continues storing
only results and tech purchases, so this feature requires no save migration or
codec version change.

## Shared Modifier Metadata

Add `lib/game/campaign/stage_modifier_metadata.dart` with a shared typed
presentation mapping for each `StageModifier`. The file depends only on the
gameplay enum and has no Flutter dependency. It provides:

- A short title for the briefing and build-phase reminder.
- One exact player-facing description.

The accepted copy is:

| Modifier | Title | Description |
| --- | --- | --- |
| `shieldRecharge` | Shield Recharge | Shielded enemies recharge 10% max shields per second after 3 seconds without damage. |
| `swarmBounty` | Swarm Bounty | Swarm enemies grant 50% more kill gold, rounded to whole gold. |
| `reinforcedArmor` | Reinforced Armor | Armored enemies gain 10 percentage points of armor. |
| `regenPressurePulses` | Pressure Pulses | Regen enemies arrive in bursts of three. |
| `reducedStartingHealth` | Fragile Base | Begin with 5 less base health. |
| `enhancedClearBonus` | Salvage Reserves | Wave clear bonuses are increased by 50%. |
| `enemySpeedSurge` | Temporal Surge | Enemies move 15% faster. |
| `amplifiedGravityWells` | Amplified Wells | Gravity Well fields gain 20% radius and 25% duration. |

Both the stage briefing and mission reminder use this mapping. Mechanics and
copy therefore share typed modifier identities instead of duplicating
stage-specific strings. The mapping also owns a named `Standard Conditions`
title/description pair for the no-modifier fallback so the briefing and intel
panel do not duplicate those strings.

Numeric description text is formatted from the corresponding `GameBalance`
constant rather than hard-coded independently in the metadata mapping. This
keeps the displayed promise aligned when tuning changes.

## Balance Constants

All new tuning values live in `GameBalance`, Orion's existing single source of
truth for gameplay tuning:

```dart
static const double shieldRechargeDelay = 3.0;
static const double shieldRechargeRatePerSecond = 0.10;
static const double swarmBountyMultiplier = 1.50;
static const double reinforcedArmorBonus = 0.10;
static const int regenPulseBurstSize = 3;
static const double regenPulseInterval = 0.20;
static const double regenPulseGap = 2.0;
static const int reducedStartingHealthPenalty = 5;
static const double enhancedClearBonusMultiplier = 1.50;
static const double enemySpeedSurgeMultiplier = 1.15;
static const double amplifiedGravityWellRadiusMultiplier = 1.20;
static const double amplifiedGravityWellDurationMultiplier = 1.25;
```

Rules and metadata both consume these constants. No modifier mechanic or
player-facing numeric description owns a second tuning literal.

## Pure Rules Boundary

Add `lib/game/rules/stage_modifier_rules.dart`. `StageModifierRules` exposes
narrow deterministic helpers for:

- Effective starting base health.
- Effective kill reward.
- An immutable resolved enemy-modifier profile.
- Regen-group spawn timing.
- Effective wave-clear bonus.
- Stage-adjusted tower stats.

Helpers receive modifier collections and the smallest relevant inputs. They do
not receive a stage ID and do not mutate their inputs.

API names distinguish the two modifier concepts everywhere this ticket
touches:

- `campaignModifiers` means persistent side-stage rewards and tech purchases.
- `stageModifiers` means the selected stage's environmental effects.

Existing generic `modifiers` fields and parameters in `OrionDefenseGame`,
`GameSession`, `TowerComponent`, and `TowerStatsResolver` are renamed to
`campaignModifiers` as part of this work. New environmental parameters use
`stageModifiers`. `StageDefinition.modifiers` remains the canonical static-data
field; no runtime constructor, field, or resolver argument uses an unqualified
`modifiers` name.

Base and persistent values compose in this order:

1. `GameBalance` base value.
2. Persistent campaign rewards and purchased tech.
3. Active stage modifiers.

Empty modifier collections return the input unchanged. Multiple modifiers
produce the same result regardless of list order.

`StageModifierRules.enemyProfile()` accepts an `EnemyStats` value and the
active stage modifiers, then returns an immutable `EnemyModifierProfile` with:

- An effective movement-speed multiplier.
- An armor-reduction bonus.
- An optional `ShieldRechargePolicy` containing the delay and recharge rate.

Trait filtering happens while resolving the profile. `EnemyLogic` receives the
resolved profile, defaulting to an identity profile for existing focused
callers. It does not know about `StageModifier` values or repeatedly derive
static effects during ticks.

## Modifier Mechanics

### Nebula Relay: Shield Recharge

Enemies with the `shielded` trait recharge when Nebula Relay's
`shieldRecharge` modifier is active:

- Recharge delay: 3 seconds after the last successful damage application.
- Recharge rate: 10% of `stats.shieldHealth` per second.
- Maximum: the enemy's original `stats.shieldHealth`.
- Direct and status damage both reset the delay.
- An undamaged enemy whose shield is already full tracks the delay but does not
  exceed its maximum.
- The Shield Matriarch is affected because it has the `shielded` trait. With
  its current 200 maximum shield, it recharges 20 shield per second.
- Enemies without the trait and enemies in other stages do not recharge
  shields.

`EnemyLogic` receives a resolved immutable `EnemyModifierProfile` through its
constructor, defaulting to the identity profile for existing callers and
focused tests. It owns the per-enemy `_timeSinceDamage` state. `applyDamage`
resets the timer whenever a positive damage application changes health or
shield, so projectile, Gravity Well, drone, and corrosion damage share one
reset path.

Shield recharge runs in `tick()` after existing corrosion and health
regeneration, but before movement. During a tick that crosses the three-second
boundary, recharge applies only to the portion of the tick after the boundary.
Corrosion damage resets the timer before recharge, so a corrosion tick cannot
also allow shield recharge. A recharge tick that changes shield sets
`EnemyTickResult.overlayDirty` so the rendered shield bar visibly regrows.

### Salvage Rift: Swarm Bounty

When `swarmBounty` is active, enemies with the `swarm` trait award:

```text
round(base gold reward * 1.50)
```

The calculation occurs once when the kill is resolved, before
`GameSession.rewardKill`. The Swarm Queen is affected because it has the
`swarm` trait. Non-swarm enemies and kills in other stages retain their base
reward.

Integer rounding is an accepted part of the effect: the common 5-gold swarm
reward becomes 8 gold, an effective 60% increase for that archetype. Across
Salvage Rift's current 66 regular swarm enemies and the Swarm Queen, the
modifier adds 253 gold to the stage's total available kill economy. The manual
balance gate must confirm this does not trivialize later waves.

### Asteroid Foundry: Reinforced Armor

When `reinforcedArmor` is active, an enemy with the `armored` trait uses:

```text
clamp(base armor reduction + 0.10 - active armor shred, 0.0, 0.75)
```

The additional 0.10 is ten percentage points, not a ten-percent multiplier.
Armor shred remains fully effective, and the existing final 0.75 cap remains
unchanged. The Armored Excavator is affected because it has the `armored`
trait.

`EnemyStats` stays immutable. `EnemyLogic` derives one stage-adjusted base
armor value from its resolved profile. Its `armorReduction` getter subtracts
active shred from that value, while `applyDamage` passes the same
stage-adjusted base value to `DamageInput.armorReduction` and passes shred
separately. Damage resolution and exposed runtime armor state therefore cannot
disagree. No new armor overlay is introduced by this ticket.

### Aurora Gate: Regen Pressure Pulses

When `regenPressurePulses` is active, a multi-enemy group whose stats include
the `regen` trait uses this spawn cadence:

- Burst size: 3 enemies.
- Intra-burst interval: 0.20 seconds.
- Inter-burst gap: 2.0 seconds.

The group's existing `initialDelay` remains intact. A final partial burst uses
the same intra-burst timing. Once the group is complete, the next group's
existing initial delay takes precedence; no unused pulse gap is carried into
the next group. Single-enemy groups, including the Regen Warden boss group,
spawn normally. Non-regen groups and other stages retain their original
intervals.

`OrionDefenseGame` retains group and within-group spawn counters. It asks the
pure modifier rule for the next delay after each spawn instead of rewriting
the stage's `WaveDefinition`. The rule is called only while another enemy
remains in the current group. Completing a group bypasses the pulse rule and
uses the existing next-group `initialDelay` branch.

The following timestamps are relative to the first spawn of the regen group,
not absolute wave time. Six regen enemies spawn at
`0.0, 0.2, 0.4, 2.4, 2.6, 2.8` seconds instead of `0, 1, 2, 3, 4, 5`; eight
spawn at `0.0, 0.2, 0.4, 2.4, 2.6, 2.8, 4.8, 5.0` instead of
`0, 1, 2, 3, 4, 5, 6, 7`. The shorter, clustered pressure window is
intentional: Aurora Gate asks the player to control bursts rather than a
uniform stream.

In Aurora Gate's final wave, the existing Regen Warden boss group retains its
2.5-second initial delay after the preceding group completes. Compressing that
preceding group's last spawn from 5.0 to 2.8 seconds therefore moves the boss
from 7.5 to 5.3 seconds after the first regen spawn. The resulting 2.2-second
earlier overlap is intentional and receives explicit attention in the manual
balance pass.

### Void Bastion: Fragile Base and Salvage Reserves

`reducedStartingHealth` applies after persistent campaign and tech bonuses:

```text
max(1, campaign-adjusted starting base health - 5)
```

`GameSession.initial` is the single starting-health resolution boundary. It
first resolves the selected stage, then chooses the campaign-adjusted input:
an explicit `baseHealth` override when supplied, otherwise
`campaignModifiers.adjustedStartingBaseHealth`. It finally applies
`StageModifierRules.effectiveStartingBaseHealth` using the resolved stage's
modifier list. Both `startingBaseHealth` and `_baseHealth` receive that one
resolved value.

This keeps direct `GameSession.initial(stage: ...)` construction consistent
with missions launched through `OrionDefenseGame`. The resolved value becomes
`GameSession.startingBaseHealth`; restart restores the same reduced maximum,
damage clamps against it, snapshots expose it, and stage-medal calculation uses
it as the no-damage denominator. `OrionDefenseGame.restart()` reuses the
existing session, and `GameSession.restart()` restores the stored resolved
value; it does not reconstruct the session or re-derive campaign bonuses.

Gold remains relative to the resolved starting health: the player must take no
damage. Silver deliberately remains the existing absolute
`GameBalance.silverMedalThreshold` of 10 HP. Fragile Base therefore makes a
Silver medal harder to earn rather than redefining campaign-wide medal rules
for one stage.

`enhancedClearBonus` applies only when the existing session would award a
positive non-final wave-clear bonus. Composition is:

```text
campaignAdjusted = round(base clear bonus * (1 + tech clear-bonus fraction))
stageAdjusted = round(campaignAdjusted * 1.50)
```

The final wave still grants no clear bonus because victory currently ends the
mission before a post-wave build phase. Void Bastion's existing persistent
`+5 HP` campaign reward remains unchanged and still applies globally. On a
replay in the same campaign state, Void Bastion remains five health below an
unmodified stage because both missions receive the persistent reward before
the stage penalty.

`GameSession.snapshot()` uses this same two-step calculation for the active
wave's preview. It passes the effective value into `GameBalance.wavePreview`
through an explicit effective-clear-bonus argument, and
`WavePreview.clearBonus` displays the amount the session will actually award.
The preview and payout must not calculate the value through separate formulas.
This intentionally also fixes the pre-existing preview mismatch on every stage
when the Salvage Crew campaign tech is active: the old preview showed the base
bonus while payout included the tech adjustment.

### Singularity Core: Temporal Surge and Amplified Wells

When `enemySpeedSurge` is active, all enemies use:

```text
effective speed = base speed * 1.15
```

This includes the Singularity Core boss. `EnemyStats.speed` remains unchanged;
`EnemyLogic` applies the multiplier during movement. Spawn intervals stay
unchanged intentionally, so faster traversal creates more simultaneous path
pressure; the stronger Gravity Well fields are the stage-specific tool for
controlling that concurrency.

When `amplifiedGravityWells` is active, Gravity Well tower stats use:

```text
effective field radius = resolved field radius * 1.20
effective field duration = resolved field duration * 1.25
```

The change applies at every Gravity Well level and to both specializations.
Other tower types are unchanged. Costs, range, fire interval, direct damage,
unlock timing, and specialization rules do not change. Longer field lifetime
naturally allows more existing field ticks rather than applying a separate
damage multiplier. `TowerStats.copyWith` gains only the additional
`fieldRadius` and `fieldDuration` overrides required by this resolver path.

## Runtime Data Flow

The mission flow remains:

```text
StageDefinition
  -> OrionDefenseGame / GameSession
  -> StageModifierRules
  -> EnemyLogic, spawn scheduling, reward/session/tower resolution
  -> GameSnapshot
  -> Flutter UI
```

Specific integration points:

- `OrionGamePage._startStage` continues deriving persistent
  `CampaignModifiers`.
- `OrionDefenseGame` passes the selected stage and `campaignModifiers` into
  `GameSession.initial`; it does not pre-resolve starting health.
- `GameSession.initial` resolves stage-adjusted starting health, and the session
  applies the adjusted wave-clear bonus by reading the same
  `stage.modifiers`. It does not accept a second, potentially divergent
  environmental modifier collection.
- `OrionDefenseGame` asks `StageModifierRules` for an
  `EnemyModifierProfile` whenever it creates a normal enemy or boss minion and
  passes that resolved profile into `EnemyLogic`.
- `EnemyLogic` handles effective armor, movement speed, damage-reset tracking,
  and shield recharge from the profile without depending on the stage-modifier
  enum.
- `OrionDefenseGame` asks the modifier rule for regen-group spawn timing and
  kill rewards.
- `TowerStatsResolver` applies campaign tech first and stage-specific Gravity
  Well adjustments second. Its inputs are named `campaignModifiers` and
  `stageModifiers`.
- `OrionDefenseGame` passes active stage modifiers into every `TowerComponent`;
  construction and `updateTower` both re-run `TowerStatsResolver`, so upgrades
  and specializations retain the stage adjustment.
- `GameSnapshot` carries an immutable active modifier list for mission UI.

The UI never reads mutable game internals. It receives the stage's active
modifier values through `GameSnapshot`. `GameSession.snapshot()` is the single
production construction path and always includes the modifier list;
`OrionDefenseGame.overrideFeedback()` republishes through that path. Tests that
construct snapshots directly must provide the new required field.

## World Map and Mission UI

### Stage Briefing

Tapping an unlocked or cleared world-map node opens a portrait-friendly modal
bottom sheet instead of starting the mission immediately.

`WorldMapView.onStageSelected` calls
`OrionGamePage._showStageBriefing(StageDefinition)`. That method opens a new
private `_StageBriefingSheet` widget in `orion_game_page.dart` with
`showModalBottomSheet<bool>`. The sheet's start/replay button closes the sheet
with `true`; after dismissal, `_showStageBriefing` checks `mounted` and
delegates to the existing guarded `_startStage(stage)` path. The sheet is safe
area-aware and vertically scrollable so long modifier descriptions remain
usable on compact portrait screens.

The briefing shows:

- Stage name.
- Existing stage description.
- Every modifier title and description.
- `Standard Conditions — No environmental modifiers` for Outpost Alpha.
- Existing side-stage completion reward, when present.
- Existing best medal and base-health result for a cleared stage.
- `Start Mission` for an uncleared stage or `Replay Mission` for a cleared
  stage.
- A dismiss action.

The sheet's start/replay action calls the existing guarded stage-start path.
Locked stages preserve their current behavior: tapping one shows short locked
feedback and does not open a briefing or launch a mission. Stage selection
remains disabled while progress is saving or resetting. The locked/unlocked
branch stays in `WorldMapView`; `_showStageBriefing` is wired only to
`onStageSelected`, never to `onLockedStageSelected`.

### Build-Phase Reminder

When `GameSnapshot.nextWavePreview` is present, `_NextWavePanel` adds a compact
environment row listing the active modifier titles. It does not repeat the
long descriptions. Outpost Alpha shows `Environment: Standard Conditions`.
The caller derives the titles from `snapshot.stageModifiers` and passes them
through a new `_NextWavePanel` parameter alongside the existing
`WavePreview`; modifier presentation data does not become part of
`WavePreview`.

The reminder follows the panel's existing visibility rules: it appears during
build phases and hides during an active wave, win, or loss. The combat HUD and
bottom controls are otherwise unchanged.

## Campaign Validation

`StageDefinition` accepts zero or more modifiers, and modifier lists are made
unmodifiable.

`OrionCampaign.validateStages` adds only one generic modifier error: a stage
cannot contain the same atomic modifier more than once. Existing custom test
stages with no modifiers remain valid, so modifier support does not invalidate
the current stage-validation contract.

Campaign-definition tests separately assert the exact assignments for all
seven Orion stages. This guards the product requirement that Outpost Alpha is
the baseline and all six other stages have their accepted identities without
making the generic validator campaign-specific.

## Error Handling and Edge Cases

- Empty modifier lists are identity operations at every rule boundary.
- Duplicate modifiers fail campaign validation rather than double-applying an
  effect.
- Shield recharge clamps to the original maximum and is disabled after enemy
  resolution.
- Armor remains clamped between 0 and 0.75 after bonus and shred.
- Reduced starting health clamps to at least 1.
- Zero clear bonuses remain zero.
- A single-enemy regen group does not enter pulse scheduling.
- Large frame deltas may spawn multiple due enemies through the existing spawn
  loop, while the burst and gap counters remain deterministic.
- Restart clears per-enemy and per-wave runtime state but retains the selected
  stage and its resolved starting values.
- Stage modifiers do not alter saved campaign results or tech purchases.

## Testing Strategy

### Pure Rules and Models

Add focused coverage for:

- Empty-modifier identity behavior for every helper.
- Immutable modifier lists.
- Duplicate-modifier validation.
- Exact modifier assignment across all seven campaign stages.
- Modifier composition independent of list order.
- Shield recharge delay, boundary-crossing ticks, damage resets, rate, cap,
  corrosion interaction, trait filtering, resolved-enemy behavior, and
  `overlayDirty` propagation.
- Shield Matriarch's current profile resolving to 20 shield per second.
- Swarm bounty rounding, trait filtering, boss reward, and the current
  Salvage Rift total-economy delta.
- Reinforced armor, armor shred, cap, trait filtering, and agreement between
  the exposed runtime value and damage input.
- Regen pulse cadence, final partial bursts, group transitions, normal groups,
  single-enemy groups, and the accepted six- and eight-enemy timestamps.
- Reduced starting health after campaign/tech bonuses, clamp, restart, snapshot,
  direct `GameSession.initial(stage: ...)` construction, explicit
  `baseHealth` overrides, Gold/Silver/Clear outcomes, and absolute Silver
  threshold.
- Enhanced clear bonus after the tech adjustment, rounding, positive-only
  behavior, final-wave behavior, preview/payout agreement, and the corrected
  Salvage Crew preview on an unmodified stage.
- Enemy speed multiplier, composition with player time scale, and no-modifier
  fallback.
- Gravity Well radius/duration at each level and specialization, plus unchanged
  non-Gravity-Well towers.
- `TowerStatsResolver` and `TowerComponent.updateTower` retaining amplified
  Gravity Well stats after upgrade and specialization.
- `GameSession.snapshot()` and `OrionDefenseGame.overrideFeedback()` preserving
  active stage modifiers.

### Game-Layer Integration

`OrionDefenseGame` tests prove:

- The selected stage passes modifiers to spawned enemy logic.
- Boss minions created through the generic summon path inherit active stage
  modifiers. This test uses a synthetic modified stage because Relay Breaker,
  the only current summoner, belongs to unmodified Outpost Alpha.
- Nebula enemies recharge through real game ticks.
- Salvage Rift applies the bounty through the real kill callback.
- Aurora Gate uses pulse timing through the real spawn loop, including one
  large-`dt` case that crosses both an intra-burst interval and a pulse gap and
  asserts the exact spawn count and proves the next spawn occurs at the
  expected boundary.
- Void Bastion initializes and restarts with its resolved health and awards its
  adjusted wave bonuses.
- Singularity Core applies enemy speed and stage-adjusted Gravity Well stats.
- Outpost Alpha preserves current mission mechanics; its wave preview now
  correctly includes the existing Salvage Crew tech adjustment.

### Widget Coverage

Widget tests cover:

- Opening and dismissing a stage briefing.
- Starting and replaying a stage from the briefing.
- All six stages' modifier titles and descriptions.
- Outpost Alpha's `Standard Conditions` fallback.
- Existing side-stage rewards and best results in the briefing.
- Locked stages never opening the briefing.
- Save/reset guards preventing stage launch.
- Compact-height briefing content remains scrollable.
- Build-phase environment reminder contents and existing hide behavior during
  combat and end states.
- Existing stage-selection tests are migrated to assert the briefing and tap
  its `Start Mission` or `Replay Mission` action before expecting the game
  screen. The current migration surface is 24 direct Outpost Alpha taps in
  `test/widget_test.dart`, one in `test/widget/sell_button_test.dart`, and one
  in `integration_test/app_smoke_test.dart`. Shared helpers should be updated
  where possible rather than duplicating the new interaction.

### Manual Balance and Clearability

After automated verification, play every modified stage at normal 1x speed
from the minimum campaign state required to unlock it, without debug gold,
health, or damage injection. Clear each stage at least once and record the
result in the implementation handoff. Also replay Outpost Alpha to confirm the
baseline remains clearable.

The pass specifically checks that Salvage Rift's additional 253 available gold
does not trivialize its later waves, Aurora Gate's boss overlap remains
readable and survivable, the pure-pressure stages remain fair with existing
tower counters, and Void Bastion's risk/reward trade-off is viable. A stage
that cannot be cleared, or whose modifier does not materially affect play,
returns to tuning before the ticket is complete.

## Verification

Run:

```bash
dart format .
flutter analyze
flutter test
flutter test integration_test
```

The feature is complete when all six non-baseline stages visibly advertise and
apply their accepted mechanics, Outpost Alpha's mission mechanics remain
unchanged, existing campaign validation and persistence still pass, the full
analyzer/unit/integration suite is green, and the manual balance and
clearability gate passes.
