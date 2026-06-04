# Orion Tower Variety Expansion Design

## Context

Orion is a Flutter and Flame tower-defense MVP with a pure Dart rule layer. The current game has an 8 by 12 board, a fixed path, five manually started waves, three tower types, one normal upgrade level, simple enemy stats, and a single 4 by 3 sprite sheet for the existing towers, enemies, projectiles, spawn marker, base marker, and impact effects.

The expansion keeps the existing architecture: `GameBalance` owns balance data, `GameSession` owns deterministic state and economy, `BoardLayout` owns board/path rules, Flame components render and animate combat, and Flutter overlays expose controls.

## Goal

Increase tower variety enough that the player makes distinct strategic choices across a longer run. The feature should add new sci-fi tower roles, deeper upgrades, light enemy counters, and enough wave space for the expanded roster to matter.

## Scope

The game expands from five waves to eight waves and from three tower types to eight tower types.

Starting towers:

- Laser: fast single-target baseline.
- Rocket: splash baseline.
- Cryo: slow/control baseline.

New towers:

- Railgun: slow, high-damage line-piercing shots.
- Ion Chain: jumps between nearby enemies and performs well against clustered light units.
- Nanite Corrosion: damage over time plus armor weakening.
- Gravity Well: low damage, strong area control represented as area slow and bunching pressure.
- Drone Bay: launches capped autonomous drones that chase targets briefly.

Unlock cadence:

- Laser, Rocket, and Cryo are available before wave 1.
- Railgun unlocks after clearing wave 1.
- Ion Chain unlocks after clearing wave 2.
- Nanite Corrosion unlocks after clearing wave 3.
- Gravity Well unlocks after clearing wave 4.
- Drone Bay unlocks after clearing wave 5.
- Waves 6 through 8 are the proving ground for the full roster and final specializations.

## Upgrade Model

Each placed tower has three effective tiers:

- Level 1: base tower.
- Level 2: normal paid upgrade that improves the tower's core role.
- Level 3: one of two paid final specializations.

`PlacedTower` should track `level` and an optional specialization. Level 1 towers can only take the normal upgrade. Level 2 towers can only choose one specialization. Specialized towers are maxed and cannot upgrade again.

Suggested specialization labels and roles:

| Tower | Specialization A | Specialization B |
| --- | --- | --- |
| Laser | Pulse Laser: faster sustained fire | Prism Laser: small secondary split damage |
| Rocket | Siege Rocket: larger explosions | Cluster Rocket: smaller follow-up bursts |
| Cryo | Deep Freeze: stronger and longer slow | Frostbite: better damage against slowed enemies |
| Railgun | Lance Railgun: longer pierce line | Magnetic Railgun: bonus armor damage |
| Ion Chain | Storm Relay: more jumps | Overload Relay: bonus shield damage |
| Nanite | Dissolver Nanites: stronger armor weakening | Replicator Nanites: corrosion spreads on kill |
| Gravity Well | Singularity Well: stronger area slow | Crush Well: periodic area damage |
| Drone Bay | Interceptor Bay: more short-lived drones | Hunter Bay: fewer stronger drones |

The first implementation uses these concrete starter costs:

| Tower | Unlock | Cost | Level 2 Cost | Specialization Cost |
| --- | ---: | ---: | ---: | ---: |
| Laser | Wave 1 | 50 | 70 | 120 |
| Rocket | Wave 1 | 80 | 100 | 150 |
| Cryo | Wave 1 | 70 | 90 | 140 |
| Railgun | Wave 2 | 110 | 150 | 210 |
| Ion Chain | Wave 3 | 95 | 130 | 190 |
| Nanite Corrosion | Wave 4 | 90 | 125 | 180 |
| Gravity Well | Wave 5 | 120 | 160 | 220 |
| Drone Bay | Wave 6 | 130 | 170 | 240 |

## Tower Behavior

The existing `TowerStats` table should grow into a behavior-capable stat model. Keep common fields such as cost, range, damage, fire interval, projectile speed, splash radius, slow multiplier, and slow duration. Add nullable or defaulted behavior fields for the new mechanics:

- `pierceCount` and `pierceWidth` for Railgun.
- `chainCount`, `chainRange`, and `chainFalloff` for Ion Chain.
- `corrosionDamagePerSecond`, `corrosionDuration`, and `armorShred` for Nanite Corrosion.
- `fieldRadius`, `fieldDuration`, and `fieldTickInterval` for Gravity Well.
- `droneCount`, `droneLifetime`, `droneDamage`, `droneAttackInterval`, and `maxActiveDrones` for Drone Bay.
- `shieldDamageMultiplier` and `armorDamageMultiplier` for counter specializations.

Behavior rules:

- Laser remains a direct projectile tower. Prism Laser applies one 35% damage secondary hit to the nearest alive enemy within 55 pixels of the primary target.
- Rocket remains a splash tower. Cluster Rocket creates two delayed 45% damage secondary bursts within 42 pixels of the primary impact.
- Cryo remains a direct slow tower. Frostbite reads whether the target is already slowed.
- Railgun fires along a line through its selected target and damages enemies close to that line, capped by pierce count.
- Ion Chain hits the selected target, then jumps to the nearest alive enemy within chain range without repeating targets.
- Nanite Corrosion applies damage over time after shields are gone and temporarily lowers armor reduction.
- Gravity Well creates a temporary field at the target location. For the first pass, "pull" is represented by area slow and repeated damage/control ticks so enemies stay on the path.
- Drone Bay launches short-lived drone components. Drones chase targets and attack at intervals until their lifetime expires. Each tower and the session must cap active drones.

Create a pure `combat_effects.dart` helper for shield, armor, corrosion, chain, pierce, slow, gravity-field, drone-damage, and specialization calculations. `ProjectileComponent` should animate travel and delegate effect math instead of becoming the owner of all combat rules.

## Light Enemy Counters

Enemy counters should stay readable and data-driven. Add lightweight enemy traits and defense fields to `EnemyStats` instead of a full resist matrix.

Traits:

- `armored`: health damage is reduced by armor. Railgun and Nanite tools counter it.
- `shielded`: starts with shield health. Ion Chain and Overload Relay counter it.
- `swarm`: low health, higher count, usually faster spawn cadence.
- `regen`: slowly recovers health unless corroded.
- `heavy`: high health and base damage, used for balance and sprite choice.

Damage and status rules:

- Shield health absorbs incoming damage before health damage.
- Shield bonus damage applies only while shield health remains.
- Armor reduces health damage after shields are gone. Armor reduction is clamped from 0 to 0.75.
- Armor-piercing or armor-shred effects reduce the armor penalty, not base damage.
- Corrosion damage bypasses armor after shields are gone and pauses regeneration while active.
- Regeneration cannot raise health above max health.
- Slow effects clamp final speed multiplier between 0.25 and 1.0.
- Multiple slows use the strongest active multiplier and longest remaining duration.

## Waves And Economy

`WaveDefinition` should support multiple groups instead of one repeated enemy stat block. A `WaveGroup` should define count, enemy stats, spawn interval, and optional initial delay. This lets later waves mix basic, shielded, armored, swarm, regen, and heavy enemies without custom spawn code.

Starting gold should increase from 120 to 150 for the longer run. Add a wave-clear bonus to smooth purchases and specializations without adding selling, interest, or persistence.

Starter enemy archetypes:

| Archetype | Traits | Health | Shield | Armor Reduction | Regen/sec | Speed | Base Damage | Reward | Spawn Interval |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Basic Drone | none | 36 | 0 | 0 | 0 | 74 | 1 | 8 | 0.85 |
| Basic Elite Drone | none | 90 | 0 | 0 | 0 | 86 | 1 | 13 | 0.75 |
| Armored Drone | armored | 70 | 0 | 0.30 | 0 | 66 | 1 | 12 | 1.00 |
| Shielded Drone | shielded | 48 | 35 | 0 | 0 | 78 | 1 | 12 | 0.90 |
| Swarm Drone | swarm | 22 | 0 | 0 | 0 | 100 | 1 | 5 | 0.35 |
| Regen Drone | regen | 78 | 0 | 0 | 2.5 | 72 | 1 | 14 | 1.00 |
| Heavy Drone | heavy | 150 | 0 | 0 | 0 | 58 | 2 | 18 | 1.20 |
| Armored Heavy Drone | armored, heavy | 175 | 0 | 0.35 | 0 | 54 | 2 | 22 | 1.25 |
| Regen Heavy Drone | regen, heavy | 190 | 0 | 0 | 3.0 | 54 | 3 | 25 | 1.30 |

Starter wave structure:

| Wave | Groups | Clear Bonus | Purpose |
| ---: | --- | ---: | --- |
| 1 | 8 basic drones | 30 | Baseline with starting towers |
| 2 | 8 basic drones, 2 armored drones | 40 | Railgun introduction |
| 3 | 10 basic drones, 4 shielded drones | 50 | Ion Chain introduction |
| 4 | 8 basic drones, 4 armored drones, 4 shielded drones | 65 | Nanite introduction |
| 5 | 20 swarm drones, 4 heavy drones | 80 | Gravity Well introduction |
| 6 | 10 shielded drones, 6 regen drones, 6 swarm drones | 95 | Drone Bay unlock after clear |
| 7 | 8 armored heavy drones, 8 shielded drones, 12 swarm drones | 115 | Specialization pressure |
| 8 | 8 basic elite drones, 8 shielded drones, 8 armored drones, 18 swarm drones, 4 regen heavy drones | 0 | Final mixed assault |

The implementation starts with these values. Tuning changes should update the balance tests in the same change.

## Unlocks And UI

`GameSession` should expose unlocked tower types based on cleared wave count and block placement of locked towers. The UI uses progressive reveal: locked towers are hidden from the picker until they unlock. The rule layer still enforces locks for direct calls and invalid UI states.

The bottom tower picker should remain compact despite eight towers:

- Starting state shows only Laser, Rocket, and Cryo as active choices.
- As towers unlock, the picker wraps into compact rows.
- Direct attempts to place locked towers should not spend gold and should produce clear feedback if invoked.

The upgrade panel should show the selected tower's current level and status:

- Level 1: one normal upgrade button.
- Level 2: two specialization buttons.
- Level 3: maxed state.

No separate tech-tree screen is required for this pass.

## Visual Assets

The existing `orion_sprite_sheet.png` should remain stable for the current towers, enemies, projectiles, markers, and impact effects. Add a second project-owned raster atlas for the expanded tower roster instead of changing old sprite indices.

New asset:

- Filename: `orion_tower_variety_sheet.png`
- Location: `assets/images/`
- Layout: 4 by 4 fixed grid.
- Contents by index: Railgun tower, Ion Chain tower, Nanite tower, Gravity Well tower, Drone Bay tower, rail slug, ion arc, nanite cloud, gravity field, drone, shield indicator, armor indicator, regen indicator, corrosion indicator, cluster burst, and prism split.

The new asset should use the same top-down sci-fi style as the existing sprite sheet. If the asset is unavailable during tests, components should keep a simple color-coded fallback.

## Architecture

Keep pure game rules separate from Flame rendering:

- `game_models.dart`: tower types, specialization values, tower stats, enemy traits, enemy stats, wave groups, placement results, and snapshots.
- `game_session.dart`: gold, base health, wave progress, tower placement, tower unlocks, normal upgrades, specialization purchases, wave start/completion, rewards, and restart.
- `tower_targeting.dart`: target selection helpers for closest-to-base targeting plus any explicit chain/pierce candidate helpers.
- `combat_effects.dart`: pure helper for shield, armor, corrosion, chain, pierce, slow, gravity-field, drone-damage, and specialization calculations.
- `EnemyComponent`: movement, health, shield, statuses, regen, and callbacks.
- `TowerComponent`: cooldowns and launch requests.
- `ProjectileComponent`: travel animation and delegation to effect resolution.
- `OrionDefenseGame`: spawning wave groups, adding towers/projectiles/drones/fields, keeping component maps synchronized, and publishing snapshots.
- `orion_game_page.dart`: HUD, tower picker, locked states, upgrade panel, specialization buttons, and end-state panel.

The implementation should avoid moving board geometry, path cells, terrain rendering, path tile rendering, or general Flame lifecycle code unless a tower behavior requires a narrowly scoped change.

## Error Handling And Edge Cases

- Locked towers cannot be placed through UI or direct `GameSession` calls.
- Invalid placement, insufficient gold, active-wave placement, and locked placement must not spend gold.
- Normal upgrades and specialization purchases are allowed only during build phase.
- Specialization fails cleanly when the tower is missing, not level 2, already specialized, maxed, unaffordable, or the session is not in build phase.
- Restart resets unlock progress, tower IDs, gold, base health, selected state, active drones, projectiles, fields, enemies, statuses, and wave counters.
- Shield, armor, regen, corrosion, slow, and gravity effects must clamp to sane bounds.
- Drone Bay must cap active drones per tower and across the session.
- Enemies must remain on the fixed path; Gravity Well does not physically drag enemies off route in this pass.
- Existing persistence, save/load, multiple maps, tower selling, and audio stay out of scope.

## Testing Strategy

Pure Dart tests should cover:

- Tower unlocks by cleared wave count.
- Placement denial for locked towers.
- Normal upgrade from level 1 to 2.
- Specialization from level 2 to 3.
- Denial of repeated upgrades, repeated specialization, unaffordable specialization, and active-wave specialization.
- Gold spending and clear bonuses.
- Wave group definitions and total spawn counts.
- Enemy trait stat construction.
- Shield damage absorption and shield bonus damage.
- Armor reduction, armor shred, and armor clamp behavior.
- Corrosion ticks, corrosion duration, regen pause, and health clamps.
- Slow stacking and speed multiplier clamps.
- Railgun pierce target selection or effect math.
- Ion chain jump selection without repeated targets.
- Drone cap behavior.

Widget and game smoke tests should cover:

- The app still boots into the game shell.
- The initial tower picker exposes the starting towers.
- Later towers appear in the picker only after their unlock wave is cleared.
- The upgrade panel changes from normal upgrade to specialization choices.
- Existing HUD values still render.

Manual verification should cover:

- Run formatter.
- Run Flutter analyzer.
- Run Flutter tests.
- Launch a web run.
- Start wave 1, clear it, confirm Railgun unlocks.
- Place at least one new tower.
- Reach a level 2 tower and choose one specialization.
- Survive into waves 6 through 8 with the full roster available.
- Confirm no runtime asset-load errors appear.

## Acceptance Criteria

- Orion has eight tower types with distinct roles and data-driven stats.
- The run has eight waves with mixed enemy groups and light enemy traits.
- Towers unlock across waves according to the approved cadence.
- Each tower supports one normal upgrade and one of two final specializations.
- `GameSession` enforces locked placement, upgrade rules, specialization rules, economy, clear bonuses, and restart behavior.
- Combat supports shields, armor, regen, corrosion, slow, pierce, chain, gravity fields, and capped drones.
- The Flutter UI can place unlocked towers and specialize selected towers without a separate tech-tree screen.
- The visual layer gives the five new towers readable board sprites or a fallback while the new atlas is unavailable.
- Focused tests cover rule changes and combat-effect math.
- Existing board layout, path, terrain, path tiles, win/loss flow, and restart loop continue to work.
