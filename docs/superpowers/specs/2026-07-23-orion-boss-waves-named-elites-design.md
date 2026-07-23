# Orion Boss Waves and Named Elite Enemies Design

## Context

HPA-99 asks for named boss/elite enemies at each stage finale so clearing a mission feels more dramatic than clearing another normal wave. Orion is a Flutter + Flame tower-defense game with a deliberate split between **pure game logic** (`lib/game/rules/`, `lib/game/models/`) and the **Flame rendering layer** (`lib/game/components/`, `lib/game/orion_defense_game.dart`). State flows from `GameSession` through immutable `GameSnapshot`s into the UI; combat math is delegated to pure `rules/` functions.

Today every enemy is an `EnemyStats` value (`health`, `speed`, `baseDamage`, `goldReward`, `traits`, `shieldHealth`, `armorReduction`, `regenPerSecond`). The `EnemyArchetype` enum maps to `EnemyStats` via `GameBalance.enemyArchetype(...)`, and all enemy stat constants are private `static const` in `GameBalance`. Each stage defines exactly 8 `WaveDefinition`s; each `WaveDefinition` holds a list of `WaveGroup`s (`enemyCount` + `enemyStats` + `spawnInterval` + `initialDelay`). `OrionDefenseGame._spawnWaveEnemies` walks the groups in order and calls `_spawnEnemy(group.enemyStats)`, which constructs an `EnemyComponent`. A wave completes when `_spawnedCount >= wave.enemyCount && _activeEnemyComponents.isEmpty` (`_finishWaveIfComplete`).

`EnemyComponent` already carries two callback hooks — `onKilled` and `onReachedBase` — and ticks timer-driven effects inline (`_tickSlow`, `_tickCorrosionAndRegen`). Enemy rendering picks one of two sprites via `GameSpriteSheet.spriteForEnemy(stats)` (threshold: `health >= 70`); there is no per-enemy label, tint, or scale. Enemy stat values are identified by `identical(...)` in `GameBalance._enemyLabelForStats` for the pre-wave intel panel.

The codebase keeps one sprite sheet per concern in dedicated loader classes: `GameSpriteSheet` (4×3), `GameTowerVarietySheet` (4×4), `GamePathTiles`, `GameTerrain`. Each loader hard-codes its grid dimensions and has a matching `*_test.dart`.

## Goal

Introduce a named boss enemy as the finale of every stage's wave 8 — **all seven ship as playable encounters** (spawn, distinct art, name, preview label). **Relay Breaker** (Outpost Alpha) alone gets a bespoke periodic minion-summon mechanic end-to-end (model, mechanic, rendering, tests); the other six are stat-block bosses with no bespoke mechanic — their bespoke mechanics are the only thing deferred. Bosses reuse the existing spawn, combat, completion, and win/loss flow with no changes to non-boss waves.

## Decisions

Locked during brainstorming:

1. **Scope** — all seven bosses ship as playable wave-8 encounters (stat-block + name + sprite + spawn + render + preview). Relay Breaker alone is implemented end-to-end with its minion-summon mechanic; the other six are stat-block bosses whose bespoke mechanics are deferred.
2. **Mechanics** — stat-block plus one deterministic periodic mechanic for Relay Breaker: **periodic minion summon**.
3. **Visuals** — new dedicated boss sprite art (a new `GameBossSheet`), not procedural tinting.
4. **Final wave shape** — **augment**: wave 8 keeps its existing groups; the boss is appended as an additional `WaveGroup(enemyCount: 1)`.

## Architecture: inheritance hybrid

`BossDefinition extends EnemyStats`. Because every existing API already accepts `EnemyStats`, the boss flows through the unchanged spawn path as a `WaveGroup(enemyCount: 1, enemyStats: bossDef)` — **zero changes to `_spawnWaveEnemies`, `_spawnedCount`, or `_finishWaveIfComplete`** — while boss-only fields (`name`, `summonMechanic`, `sprite`) live in the subclass, keeping `EnemyStats` pure. The cost is a few localized `stats is BossDefinition` checks in render/preview, which is acceptable and keeps each concern in one place.

This was chosen over (a) adding `name`/`isBoss`/`summonMechanic` directly to `EnemyStats` (pollutes the common type and complicates `spriteForEnemy`) and (c) a stage-level `bossEncounter` overlay (decouples the boss from the wave it belongs to, adding indirection for no gain).

## Scope

In scope:

- `BossDefinition extends EnemyStats` and `SummonMechanic` value types, plus a `BossSprite` enum, in `lib/game/models/game_models.dart`.
- Seven `static const BossDefinition` boss constants in `GameBalance` (only `relayBreaker` carries a `SummonMechanic`).
- Boss appended as the final `WaveGroup` of each stage's wave 8 (Outpost Alpha in `GameBalance.waves`; the other six via the `_waves()` helper).
- `EnemyComponent` optional boss fields (`bossSheet`, `onSummonMinions`, `minionOf`) and an inline summon timer tick.
- `OrionDefenseGame` wiring: pass the boss sheet + a summon callback that spawns capped minions; tag minions via `minionOf`.
- A new `GameBossSheet` loader + `orion_boss_sheet.png` (4×2 grid, 7 of 8 cells used).
- Boss render treatment: larger radius/scale, boss sprite, always-on health bar, name label.
- Wave-preview label uses the boss name.
- Tests across balance, enemy-component summon timing, boss-sheet math, and campaign validation.

Out of scope (non-goals from the issue):

- Summon mechanics (or any bespoke periodic mechanic) for the other six bosses.
- Cutscenes, dialogue, or boss intro/defeat banners.
- Balance tuning of the six data-slot bosses beyond a sane first-pass stat block.
- Boss-specific achievements/medals changes (existing medal flow is untouched).

## Design

### `lib/game/models/game_models.dart`

New types beside `EnemyStats`:

```dart
enum BossSprite {
  relayBreaker,
  shieldMatriarch,
  swarmQueen,
  armoredExcavator,
  regenWarden,
  siegeCarrier,
  singularityCore,
}

class BossDefinition extends EnemyStats {
  const BossDefinition({
    required super.health,
    required super.speed,
    required super.baseDamage,
    required super.goldReward,
    super.traits,
    super.shieldHealth,
    super.armorReduction,
    super.regenPerSecond,
    required this.sprite,
    required this.name,
    this.summonMechanic,
  });

  final BossSprite sprite;
  final String name;
  final SummonMechanic? summonMechanic;
}

class SummonMechanic {
  const SummonMechanic({
    required this.interval,
    required this.minionStats,
    this.firstDelay = 3.0,
    this.count = 3,
    this.maxActive = 9,
  }) : assert(interval > 0, 'interval must be positive'),
       assert(firstDelay >= 0, 'firstDelay must be non-negative'),
       assert(count > 0, 'count must be positive'),
       assert(maxActive >= 0, 'maxActive must be non-negative');

  final double interval;        // seconds between summons
  final EnemyStats minionStats; // reuse GameBalance._basicDrone
  final double firstDelay;      // delay before the first summon
  final int count;              // minions requested per summon
  final int maxActive;          // cap on concurrently-living minions
}
```

Notes:

- `BossDefinition` has a `const` constructor (all final fields, const super call), so the seven instances can be `static const` in `GameBalance`.
- `minionStats` is typed `EnemyStats`, so a boss may summon any existing archetype (Relay Breaker reuses the private `GameBalance._basicDrone`).

### `lib/game/models/game_models.dart` — `GameBalance`

Seven boss constants placed beside the existing private enemy stats (so they can reference `_basicDrone`):

```dart
static const BossDefinition relayBreaker = BossDefinition(
  name: 'Relay Breaker',
  sprite: BossSprite.relayBreaker,
  health: 640,
  speed: 46,
  baseDamage: 4,
  goldReward: 120,
  traits: {EnemyTrait.armored, EnemyTrait.shielded, EnemyTrait.heavy},
  armorReduction: 0.40,
  shieldHealth: 100,
  summonMechanic: SummonMechanic(
    interval: 8.0,
    firstDelay: 4.0,
    count: 3,
    maxActive: 9,
    minionStats: _basicDrone,
  ),
);
```

The other six carry `summonMechanic: null` and a first-pass stat block themed to their stage. These are intentionally conservative and tunable later:

| Stage              | Boss                | Sprite              | HP   | Traits                  | Notable defenses            | Summon |
|--------------------|---------------------|---------------------|------|-------------------------|-----------------------------|--------|
| Outpost Alpha      | Relay Breaker       | relayBreaker        | 640  | armored, shielded, heavy | armor 0.40, shield 100      | yes    |
| Nebula Relay       | Shield Matriarch    | shieldMatriarch     | 520  | shielded, heavy         | shield 200                  | no     |
| Salvage Rift       | Swarm Queen         | swarmQueen          | 480  | swarm, regen            | regen 4.0/s                 | no     |
| Asteroid Foundry   | Armored Excavator   | armoredExcavator    | 700  | armored, heavy          | armor 0.45                  | no     |
| Aurora Gate        | Regen Warden        | regenWarden         | 560  | regen, heavy            | regen 6.0/s                 | no     |
| Void Bastion       | Siege Carrier       | siegeCarrier        | 800  | armored, heavy          | armor 0.35, dmg 5           | no     |
| Singularity Core   | Singularity Core    | singularityCore     | 900  | armored, shielded, regen, heavy | armor 0.40, shield 150, regen 5.0/s | no     |

**Trait/defense consistency rule:** every defense must be paired with its trait — `shieldHealth > 0` ⇒ `EnemyTrait.shielded`, `armorReduction > 0` ⇒ `EnemyTrait.armored`, `regenPerSecond > 0` ⇒ `EnemyTrait.regen`. Targeting (`targetCandidate.isShielded`/`isArmored`) and the recommended-tower logic (`_counterTowersForTrait`) key off the traits, not the raw values, so an unpaired defense would render a bar but be ignored by tower selection. Relay Breaker therefore carries `{armored, shielded, heavy}` to match its `armorReduction: 0.40` + `shieldHealth: 100`. This rule holds for every boss in the table above.

**Summoned-minion economy:** Relay Breaker reuses `_basicDrone` for its minions — no dedicated stat. Wave-8 gold is currently *unspendable*: towers can only be placed/upgraded during `GamePhase.build`, killing the wave-8 boss ends the stage, and medals derive only from base health (`StageResult.fromVictoryBaseHealth`). So the boss's `goldReward: 120` and a minion's `goldReward` are both inert; there is no "wave-8 inflation" to guard against. If a future change makes mid-wave gold spendable, introduce a tuned minion stat at that point (YAGNI for now).

(Boss `baseDamage: 4` against `initialBaseHealth: 20` is intentional — a boss leak is a major medal swing, which is the stakes of the finale.)

A new `GameBalance.bosses` accessor returns an unmodifiable list of the seven `BossDefinition`s in stage order, for tests and future tooling.

### Wave integration — augment, no spawn-loop changes

**Outpost Alpha** (`GameBalance.waves[7]`): append a sixth group to the existing five-group finale:

```dart
WaveGroup(
  enemyCount: 1,
  enemyStats: relayBreaker,
  initialDelay: 2.5,
),
```

**Other six stages** (`lib/game/campaign/orion_campaign.dart`): extend the `_waves()` helper with an optional named boss parameter:

```dart
List<WaveDefinition> _waves(
  List<WaveGroup> singleGroups, {
  BossDefinition? finaleBoss,
  double bossInitialDelay = 2.5,
}) {
  const clearBonuses = [30, 40, 50, 65, 80, 95, 115, 0];
  return List.unmodifiable([
    for (var index = 0; index < singleGroups.length; index += 1)
      WaveDefinition(
        groups: List.unmodifiable(
          index == singleGroups.length - 1 && finaleBoss != null
              ? [
                  singleGroups[index],
                  WaveGroup(
                    enemyCount: 1,
                    enemyStats: finaleBoss,
                    initialDelay: bossInitialDelay,
                  ),
                ]
              : [singleGroups[index]],
        ),
        clearBonus: clearBonuses[index],
      ),
  ]);
}
```

Constraints: still requires exactly 8 base groups (`singleGroups.length == 8`); the boss group is appended only to index 7, never replacing; `_group(...)` is unchanged. Each of the six stages passes its `BossDefinition` as `finaleBoss`.

**Campaign invariant:** the existing per-stage loop in `OrionCampaign.validateStages` gains checks that, for every stage: (a) `waves.length == 8`; (b) the **last** group of wave 8 is a boss — `enemyStats is BossDefinition` and `enemyCount == 1`; and (c) no earlier group in wave 8, and no group in waves 1–7, is a boss. This pins the encounter *shape* (boss is the sole, final enemy of the finale) rather than merely "wave 8 contains a boss somewhere" — the latter would still permit a boss mid-wave or duplicate bosses. Adding it to the existing loop covers both Outpost Alpha (`GameBalance.waves`) and the six `_waves()` stages uniformly. The campaign test covers malformed-data cases for each condition (boss not last, boss in wave 7, `enemyCount != 1`, two bosses in wave 8).

Because the boss is a normal `WaveGroup` with `enemyCount: 1`, `_spawnWaveEnemies` spawns it in order, `_spawnedCount` counts it, and the existing `enemyCount` getter includes it. **`_finishWaveIfComplete`, win/loss, and clearBonus (0 on wave 8) are untouched.** Existing waves 1–7 are byte-identical.

### Minion summon mechanic

`EnemyComponent` gains three optional, additive fields. `onSummonMinions` takes the summoning component as its first argument — `(EnemyComponent source, int count)` — exactly like `onKilled`/`onReachedBase` pass `this`, so the game can identify *which* boss summoned (all nullable so non-boss enemies are unaffected):

```dart
final GameBossSheet? bossSheet;
final void Function(EnemyComponent source, int count)? onSummonMinions;
final int? minionOf; // enemyId of the summoning boss, or null for a normal enemy
```

Summon-timer state is initialized eagerly at construction (the `stats` parameter is available in the initializer list — no sentinel needed):

```dart
double _summonRemaining; // = mechanic?.firstDelay ?? 0, set in the initializer list
```

In `update(dt)`, after the existing ticks, when `stats` is a `BossDefinition` with a non-null `mechanic`, **accumulate** (mirroring `_spawnTimer += ...` in `_spawnWaveEnemies`) so overshoot is never discarded and the interval stays exact for arbitrary `dt`:

```dart
final mechanic = boss.summonMechanic;
if (mechanic != null && onSummonMinions != null) {
  _summonRemaining -= dt;
  while (_summonRemaining <= 0) {
    _summonRemaining += mechanic.interval;
    onSummonMinions!(this, mechanic.count);
  }
}
```

This lives beside `_tickSlow` / `_tickCorrosionAndRegen` — same inline-timer pattern, fully deterministic given `dt`. (A single `if` with `_summonRemaining = mechanic.interval` would drop the overshoot every fire and drift up to one frame per summon; the `while` makes "fires every 8.0s" exactly true.)

**Ownership split:** `EnemyComponent` only owns the timer and fires the requested count; `OrionDefenseGame` owns cap enforcement, minion bookkeeping, and spawning. The active-minion count reads the same registry targeting uses — `_activeEnemyComponents.values`, not the component tree:

```dart
onSummonMinions: (source, count) {
  // `source` is the summoning EnemyComponent, passed as `this` by the
  // component (same pattern as onKilled/onReachedBase).
  final mechanic = (source.stats as BossDefinition).summonMechanic!;
  final active = _activeEnemyComponents.values
      .where((e) => e.minionOf == source.enemyId && e.isAlive)
      .length;
  final toSpawn = math.max(0, math.min(count, mechanic.maxActive - active));
  for (var i = 0; i < toSpawn; i++) {
    _spawnMinion(from: source, stats: mechanic.minionStats);
  }
}
```

`_spawnMinion` mirrors `_spawnEnemy` exactly: allocates `_nextEnemyId`, inserts into `_activeEnemyComponents`, wires `onKilled`/`onReachedBase`, and sets `minionOf: source.enemyId`. A minion that is only `add()`ed to the component tree would be invisible to targeting, splash, chain, drone selection, tap-to-inspect, and — critically — the `_finishWaveIfComplete` empty check, all of which read `_activeEnemyComponents.values`.

**Minion pathing (residual waypoints + progress seed):** minions inherit the *same stage path* as the boss — never a special path — but must start at the boss's current position. Because `EnemyComponent` forces `position: waypoints.first` and walks from index 1, the game cannot just set position after construction. `EnemyComponent` exposes:

```dart
List<Vector2> residualWaypointsFromHere() =>
    [position.clone(), ...waypoints.sublist(_targetWaypointIndex)];
```

`_spawnMinion` builds the minion's waypoints from the summoning boss's `residualWaypointsFromHere()`, so the minion spawns at the boss's location and walks the remaining path with no teleport. A minion that reaches the base damages it normally (`stats.baseDamage`).

Two correctness requirements on that construction:

- **Seed `_completedDistance` from `boss.pathProgress`.** `pathProgress = _completedDistance + _currentSegmentLength * _segmentProgress`, and `_completedDistance` starts at 0. `pathProgress` is the universal tie-break in `TowerTargeting._prefers` and the primary key for `first`/`shielded`/`armored` modes — so a minion summoned 80% down the path would otherwise report ~0, be ranked behind everything, and towers would keep firing the boss while minions walk into the base. `EnemyComponent` therefore takes an `initialCompletedDistance` ctor param (set to the summoning boss's `pathProgress`) so minions rank where they actually are.
- **Guard the residual length.** `residualWaypointsFromHere()` returns a one-element list when `_targetWaypointIndex == waypoints.length`, which trips `EnemyComponent`'s `waypoints.length >= 2` assert. Unreachable today (that state is post-`_resolve`, and summons require `isAlive`), but `_spawnMinion` skips the summon when `residualWaypointsFromHere().length < 2` as a cheap guard.

**Lifecycle:** minions are *not* despawned when the boss dies — completion already requires clearing them. Summoned minions are inserted into `_activeEnemyComponents` (same as regular enemies) and removed on kill/reach-base, so the existing `… && _activeEnemyComponents.isEmpty` gate already prevents wave completion while any minion lives. They are *not* counted in `_spawnedCount`/`wave.enemyCount` (they are bonus enemies), which is correct.

**Time scaling:** Flame scales the `dt` passed to children by `timeScale` (`HasTimeScale` + `updateTree`), so the summon timer tracks game speed consistently with movement; `_isPaused` early-returns before `super.update`, so summons freeze on pause. Slow effects reduce movement only, not the summon timer — intentional (a slowed boss still summons, just walks slower).

### `EnemyComponent.render` — boss branch

`_spawnEnemy` passes `radius: 20` (vs the default `11`) and `bossSheet` when `stats is BossDefinition`. `20` is deliberate: the sprite renders at `radius * 2.4 = 48px`, roughly one board cell (`min(w/8, h/12) ≈ 48pt`) and ~1.8× a normal drone — clearly bigger without overflowing onto neighbouring cells. In `render`, before the existing sprite logic (`stats` is a public final field, so it does not promote — the cast is required here):

```dart
final boss = stats is BossDefinition ? stats as BossDefinition : null;
if (boss != null && bossSheet != null) {
  bossSheet!.sprite(boss.sprite).render(
    canvas,
    position: Vector2(radius, radius),
    size: Vector2.all(radius * 2.4),
    anchor: Anchor.center,
  );
} else {
  // existing GameSpriteSheet.spriteForEnemy(stats) path — also the free
  // fallback: every boss has health >= 480, so spriteForEnemy returns
  // heavyDroneEnemy, and a missing bossSheet renders a scaled heavy drone
  // with no extra code.
}
```

Boss-specific rendering layered on top of the existing `_overlayRenderer.render(...)`:

- **Always-on health bar** — add an `isBoss` field to `EnemyOverlayData`. That type has a factory, a private const constructor, instance fields, and a `copyWith`, so this is four sites: the factory param (default `false`), the private `._({...})` forwarding, the field declaration, and `copyWith`'s arg/forward. Set it from `stats is BossDefinition` in the `EnemyComponent.overlayState` getter. In `EnemyOverlayState.fromData`, force both flags on for bosses: `shouldRender = data.isBoss || data.isInspected || isNotable;` and `showHealthBar = shouldRender && (data.isBoss || data.isInspected || isDamaged || hasShieldState);`. This keeps the overlay's badge-limit logic intact while guaranteeing the boss always shows its health bar (and shield bar, since a shielded boss has `hasShieldState`).
- **Name label — drawn inside `EnemyOverlayRenderer`, not `EnemyComponent`.** `EnemyOverlayLayout` is computed *inside* `render()` via `EnemyOverlayLayout.compute(state, radius)` and never exposed, so the component cannot read it without recomputing. Add an optional `String? name` parameter to `EnemyOverlayRenderer.render(...)`; `EnemyComponent.render` passes `name: boss?.name`. The renderer caches a `TextPainter` and draws it above the layout's top edge. Note the coordinate convention: the renderer uses `centerX = radius` and `y = layout.badgesY` directly as **component-local** coordinates (no center offset), so draw the label at `layout.originY - labelGap` in the same component-local space — do **not** add `radius`. No other enemy draws text.

**Sheet wiring (`OrionDefenseGame`):** add a `_bossSheet` field; `onLoad` awaits `GameBossSheet.load(images)` alongside the other sheets and passes it into `_spawnEnemy` whenever `stats is BossDefinition` (plus the larger `radius: 20`). `orion_boss_sheet.png` is a **mandatory** asset — `images.load` throws on a missing/undeclared file, so the PNG must exist and be listed in `pubspec.yaml` for `onLoad` to succeed (the other sheets have the same hard dependency; this is not a fallback the nullable render branch can rescue). The render `else` branch is a defensive/test-only null-check: when `_bossSheet` is null (e.g. a unit test that builds an `EnemyComponent` without loading images) the boss falls back to `spriteForEnemy` → `heavyDroneEnemy` (every boss is ≥480 HP). It is not a substitute for shipping the asset.

### `lib/game/assets/game_boss_sheet.dart` — new loader

Mirrors `GameTowerVarietySheet`:

```dart
class GameBossSheet {
  static const String fileName = 'orion_boss_sheet.png';
  static const String assetPath = 'assets/images/$fileName';
  static const int columns = 4;
  static const int rows = 2; // 8 cells; BossSprite has 7 values

  Sprite sprite(BossSprite sprite) => _sprites[sprite]!;
  // load(images), fromImage(image), sourceRectFor(sprite, ...) — identical shape
  // to GameTowerVarietySheet.
}
```

`BossSprite` enum order is the sprite-sheet cell order, read left-to-right, top-to-bottom (index 0 = cell (0,0), … index 4 = cell (0,1)). `orion_boss_sheet.png` is declared in `pubspec.yaml` under `assets/images/` alongside the other sheets. Its grid math is covered by a new `game_boss_sheet_test.dart` matching the existing sheet tests, asserting each `BossSprite → sourceRect` mapping.

### Wave preview / HUD

`GameBalance._enemyLabelForStats` gains an early guard so the pre-wave intel panel shows the boss name instead of "Drones":

```dart
if (stats is BossDefinition) return stats.name; // param promotes — no cast needed
```

Trait/recommended-tower logic reads `stats.traits` and is unchanged; boss traits surface naturally in the intel panel.

## Determinism & testing

All summon behavior is timer-driven with fixed intervals, so it is fully deterministic for any given `dt` sequence. Tests:

- **`test/game/game_balance_test.dart`** — the seven `BossDefinition`s exist with the expected stats from the table above; only `relayBreaker` has a non-null `summonMechanic` with `interval: 8.0`, `firstDelay: 4.0`, `count: 3`, `maxActive: 9`, and `minionStats` identical to `_basicDrone`; the trait/defense pairing rule holds for every boss; each stage's wave 8 contains exactly one boss group with the expected `BossSprite`; the wave-8 preview's last group label is exactly `'Relay Breaker'`. **`SummonMechanic` invariants:** the const constructor's assertions reject `interval <= 0`, `firstDelay < 0`, `count <= 0`, and `maxActive < 0` (an `interval <= 0` would make the catch-up `while` loop non-terminating). **Existing assertions that must be reworked, not just extended:** the wave-8 `enemyCount` expectation `46 → 47` (the "approved enemy counts" test), and the "approved wave groups" test — its `_ExpectedWaveGroup(EnemyArchetype, count, interval)` table and its `expect(group.initialDelay, 0)` per-group assertion cannot represent a boss group (no `EnemyArchetype`, `initialDelay: 2.5`). That table needs a boss-aware shape (e.g. a nullable archetype / explicit boss marker) so the boss group is matched on `enemyStats is BossDefinition` + `initialDelay: 2.5` rather than archetype identity.
- **`test/game/enemy_component_test.dart` (summon timing)** — construct an `EnemyComponent` with `relayBreaker`, a recording `onSummonMinions` (which receives the summoning `EnemyComponent` as its first arg, like `onKilled`), and drive `update(dt)` with a fake clock: assert the first fire at `firstDelay` (4.0s), then every `interval` (8.0s), each carrying `count` (3); assert no fires when `summonMechanic == null` (a data-slot boss); assert the summon timer does not advance for a normal (non-boss) enemy.
- **`test/game/enemy_component_test.dart` (boss overlay)** — `EnemyOverlayState.fromData` with `isBoss: true` forces `shouldRender` and `showHealthBar` true at full health with no damage and no traits (the boss always shows its bar); a non-boss with the same data renders nothing. Covers the `isBoss` plumbing end-to-end through the data → state path.
- **`test/game/game_boss_sheet_test.dart`** (new) — `sourceRectFor` cell math and `BossSprite → cell` mapping, mirroring `game_tower_variety_sheet` tests.
- **`test/game/orion_campaign_test.dart`** — `OrionCampaign.validate()` still returns no errors; each stage's wave 8 boss matches the expected `BossSprite`.
- **`test/game/orion_defense_game_test.dart` (minion lifecycle)** — at the game layer (querying `game.children.whereType<EnemyComponent>()`, the existing pattern): a boss's `onSummonMinions` spawns minions that (a) path from the boss's position with `pathProgress ≈ boss.pathProgress` at spawn (so towers rank them correctly), and (b) are visible to targeting via `_activeEnemyComponents`; the `maxActive` cap is honored; minions survive a boss death and must be cleared; the wave does not complete until boss + minions are all resolved.
- **`test/game/orion_defense_game_test.dart` (render wiring)** — a spawned boss `EnemyComponent` is constructed with `radius: 20` and the `GameBossSheet`, and its `overlayState` reports `shouldRender`/`showHealthBar` true at full health (exercises the always-on bar + boss sprite selection without rasterizing). Covers the "render distinctly" acceptance criterion behaviorally.

## Risks & mitigations

- **Sprite art style match.** Generating seven consistent boss sprites that match the existing sheet style is the riskiest step. Mitigation: produce the full `orion_boss_sheet.png` in a single generation pass (using the `generating-images-with-cli` skill, scratch work under `tmp/`) for visual consistency. The PNG is a hard load dependency (`images.load` throws if missing), so art must land before the game boots — generate it early in the implementation.
- **Minion runaway.** A fixed `maxActive` cap enforced by the game prevents unbounded minion growth if the player ignores adds.
- **`EnemyStats` identity checks.** `_enemyLabelForStats` uses `identical(...)` against the private stat constants; a `BossDefinition` is never identical to those, so the new `is BossDefinition` guard must come first to avoid mislabeling a boss as "Drones."

## Acceptance criteria mapping

- **Model for boss/elite definitions** — `BossDefinition extends EnemyStats` + `SummonMechanic`.
- **At least one stage has a named boss end-to-end** — Relay Breaker on Outpost Alpha (model, spawn, summon, render, preview, tests).
- **Bosses render distinctly** — dedicated `GameBossSheet`, larger radius/scale, always-on health bar, name label.
- **Boss defeat completes the wave normally, win/loss preserved** — boss is a `WaveGroup`; completion/win/loss paths unchanged.
- **Boss mechanics deterministic and testable** — fixed-interval summon timer, unit-tested with a fake clock.
- **Existing non-boss waves unchanged** — augment-only; waves 1–7 and non-boss groups in wave 8 are byte-identical.
