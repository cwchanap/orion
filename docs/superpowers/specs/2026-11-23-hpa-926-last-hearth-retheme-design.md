# HPA-926 — Last Hearth final re-theme: design

**Linear:** [HPA-926](https://linear.app/cwchanap/issue/HPA-926/orion-re-theme-the-game-to-last-hearth) · **Parent / approved visual reference:** [HPA-921](https://linear.app/cwchanap/issue/HPA-921/orion-pivot-to-last-hearth-an-anime-character-tower-defense), attachment “UI mockup overview (six screens, approved art, chibi on the board)” (2026-11-17).
**Baseline:** main after merged PRs [#50](https://github.com/cwchanap/orion/pull/50), [#51](https://github.com/cwchanap/orion/pull/51), [#52](https://github.com/cwchanap/orion/pull/52), [#54](https://github.com/cwchanap/orion/pull/54), [#56](https://github.com/cwchanap/orion/pull/56); inspected main tree `f4681dd0430e447b14c68a071e2edae16e00c9e3` on 2026-11-23. All five dependencies are Done. #53 was superseded by merged #54; #55 is unrelated screenshot cleanup.
**Status:** design only; implement and validate in this same draft PR.

## 1. Product goal and boundaries

The last pivot step makes the existing playable campaign read as **Last Hearth**, a hopeful anime defense of Camp Orion in permanent Hokkaido winter. Frostbitten corpses follow warmth toward the Orion Hearth. The Watch's Kindled defend it; signal flares call survivors, Scrip is camp ration credit, spare dog tags are traded for Scrip, Gold is the in-battle currency. Preserve approved roster, fixed signatures, squad rules, stage progression, medals, endless, Codex, tips, first-mission guide, settings and the HPA-699 UI kit. No new gameplay, tuning, save system, stages, enemies, layouts, art generation, audio generation, story scenes, voices, music, or optional signature glyph system. One PR for HPA-926; parent HPA-921 is not a second implementation PR.

Prefer display-only renames: keep existing stage IDs (including `outpost-alpha`, etc.), enum values, persisted keys, internal filenames, sprite grid indices and package/bundle/application identifiers. Existing art paths use stage IDs; keeping them avoids needless asset/save changes. Ticket permits breaking saves but no migration or reset is needed for this work. Do not rename the repo or Dart package. No global search-and-replace of identifiers or of words such as drone/armor: Tetsuo's scrap drones and combat stat terms remain legitimate; the *enemies* are Frostbitten, not drones.

## 2. Canonical presentation vocabulary

Use the existing data owners, not a second presentation registry. Stage names/descriptions in `OrionCampaign`; archetype/trait labels, boss names, module titles/effects and combat-style labels in `game_models.dart`; stage modifiers in `StageModifierMetadata`. All dependent UI, search, semantics, accessibility, tooltips and dynamic messages consume these or equivalent shared labels. Keep numeric interpolation and counter meaning unchanged.

| Stage (current name) | New name | Description direction |
| --- | --- | --- |
| Outpost Alpha | Ember Road | First patrol on the road to the Hearth. |
| Nebula Relay | Frozen Rail Yard | Ice-shelled walkers advance through a curved rail approach. |
| Salvage Rift | Sunken Depot | Optional supply patrol through fast crawlers. |
| Asteroid Foundry | Dead Foundry | Scrap-plated enemies cross a long industrial road. |
| Aurora Gate | Aurora Gate | Ice-shelled and regrowing Frostbitten test different defenses. |
| Void Bastion | White Bastion | Optional fortress route crowded with brutes. |
| Singularity Core | The Cold Heart | Final patrol confronts every Frostbitten threat. |

| EnemyArchetype (internal enum unchanged) | Label |
| --- | --- |
| basicDrone | Walkers |
| basicEliteDrone | Elite Walkers |
| armoredDrone | Scrap-plated Walkers |
| shieldedDrone | Ice-shelled Walkers |
| swarmDrone | Crawlers |
| regenDrone | Regrowing Walkers |
| heavyDrone | Brutes |
| armoredHeavyDrone | Scrap-plated Brutes |
| regenHeavyDrone | Regrowing Brutes |

Trait labels: Armored → Scrap-plated; Shielded → Ice-shelled; Swarm → Crawlers; Regen → Regrowing; Heavy → Brute. Targeting filters use corresponding Scrap-plated / Ice-shelled labels. Armor, shield strength, regen rate, HP and damage remain readable mechanical stats. Keep the explicit labels for the nine catalog archetypes and bosses. Replace the composite adjective builder and `_traitAdjective` with one generic `Frostbitten` fallback. All shipped campaign and endless waves use catalog stats, but `GameSession` also accepts custom `StageDefinition` waves and existing tests construct custom `EnemyStats` (e.g. `game_session_test.dart` preview-stage, `orion_defense_game_test.dart` pause fixtures). Throwing would break valid snapshot construction and unrelated tests; do not introduce a new grammar algorithm or require custom callers to register an archetype. Sweep every shipped wave in a test to assert its exact catalog label, so a newly added unlabeled authored enemy cannot silently pass. Boss label mapping: Relay Breaker → Gatebreaker; Shield Matriarch → Rime Matriarch; Swarm Queen → Brood Mother; Armored Excavator → Scrap Colossus; Regen Warden → Thawless Warden; Siege Carrier → Corpse Hauler; Singularity Core → The Frost Heart (distinct from stage The Cold Heart). Carry boss identity as optional `BossDefinition? boss` on `WavePreviewGroup`, populated from `group.enemyStats` when it is a `BossDefinition` in `GameBalance.wavePreview`. `WavePreview.bossGroups` checks `g.boss != null`, and `OrionArt.previewGroup` resolves `group.boss!.sprite` when present, never matching localized/display names. Update synthetic boss preview fixtures to supply the boss object explicitly; ordinary briefing threat groups remain non-boss. Cover all seven bosses, a misleading ordinary group label, and a boss with arbitrary display copy.

### Proposed module names (all 13, reviewable in this PR)

| RunModuleId | Old | Proposed |
| --- | --- | --- |
| heavyCaliber | Heavy Caliber | Heavy Caliber |
| overclockRelay | Overclock Relay | Quickened Hands |
| longSight | Long Sight | Long Sight |
| emergencySalvage | Emergency Salvage | Emergency Supplies |
| cryoReservoir | Cryo Reservoir | Deep Rime |
| rocketFusing | Rocket Fusing | Wide Flame |
| relayCalibration | Relay Calibration | Watch Training |
| relayArc | Relay Arc | Forked Lightning |
| salvagedDrones | Salvaged Drones | Scrap Workshop |
| foundryNanites | Foundry Nanites | Corrosive Serum |
| auroraFocus | Aurora Focus | Steady Aim |
| siegeRounds | Siege Rounds | Piercing Rounds |
| gravityEcho | Gravity Echo | Gravity Echo |

Use “Field Modules” for the existing Salvage Modules system across draft, acquired list, Codex, rewards, tips and report; blueprint remains a plausible recovered camp design. Each current affinity, unlock, offer and effect stays identical, including numeric values, tradeoffs and immediate Gold. Proposed combat-style display labels for legacy enum values: Laser → Direct Fire; Rocket → Fire Blast; Cryo → Frost; Railgun → Piercing Shot; Ion Chain → Chain Lightning; Nanite → Corrosion; Gravity Well → Gravity Field; Drone Bay → Scrap Drones. Preserve approved character-specific signature names (Dawnbreak etc.); where reachable, use the character signature rather than the old specialization label, and rewrite old role descriptions/counter copy where needed. Don't expose unused variant names in player surfaces. Do not alter the actual combat style or module affinity.

### Proposed modifier names (all 8 plus default)

| StageModifier | Old | Proposed |
| --- | --- | --- |
| shieldRecharge | Shield Recharge | Refreezing Shells |
| swarmBounty | Swarm Bounty | Crawler Bounty |
| reinforcedArmor | Reinforced Armor | Reinforced Plating |
| regenPressurePulses | Pressure Pulses | Regrowing Hordes |
| reducedStartingHealth | Fragile Base | Fading Hearth |
| enhancedClearBonus | Salvage Reserves | Supply Cache |
| enemySpeedSurge | Temporal Surge | Blizzard Rush |
| amplifiedGravityWells | Amplified Wells | Gravity Surge |
| none | Standard Conditions | Standard Conditions |

Keep the existing metadata formulas; e.g. Fading Hearth means starting Hearth health reduced, Supply Cache means increased wave-clear Gold, Blizzard Rush means faster enemies, not a new weather mechanic. Update descriptions to match names and combat style labels.

### Surface copy

Title wordmark both layers: “Last Hearth”; eyebrow “CAMP ORION // THE WATCH”; tagline “KEEP THE HEARTH LIT”. Sectors → Routes; Sector Map → Patrol Map; Orion Campaign → Camp Orion; all sectors cleared → All routes cleared. Use Route 01 etc. in map/briefing headers and update `StageDefinition.mapLabel` to Ember, Rail Yard, Depot, Foundry, Gate, Bastion, Cold Heart (use compact labels within current layout); preserve numbering, main/side distinction, mission/replay/endless semantics. HUD, report, onboarding and semantic strings use “Hearth” or “Hearth health” (full name Orion Hearth on narrative/introduction) for base/core. Replace in-battle “credits” with Gold, but keep persistent Scrip and its explanatory ration-credit meaning. Combat actions still Deploy, Upgrade, Signature, Recall, targeting, waves; no tower placement or R&D language. Mission victory/debrief celebrates a defended Hearth, defeat an extinguished flame, rewards show saved/failed states and actual amounts. Enemy art descriptors, fallback labels, badge labels, Codex roles/search terms and scanner counts must use new names. Don't add a localization subsystem. Extend the existing `test/widget/design_system_tripwire_test.dart` `_libDartFiles` traversal with a case-insensitive vocabulary tripwire over Dart string literals, including semantic and interpolated copy. Ban the changed old stage/boss names (not unchanged Aurora Gate), `sector`/`sectors` as words, `salvage module(s)`, `credits`, `base health`, `drone(s)` as words, `star chart`, `R&D`/`R & D`, and old title/tagline wording. Keep small explicit path + literal allowlist entries with reasons for legitimate scrap-drone combat stats/copy, retained internal asset paths, keys or diagnostics; do not exempt entire files or rename persisted identifiers. Match text words rather than identifier fragments, skip comments/imports and distinguish internal paths/IDs from visible copy. Use a lightweight scan with representative tests for mixed case, interpolation, plurals, allowlisted and prohibited examples; no new parser package. Keep normal widget assertions for changed visible labels. Retain approved Camp/Flare terminology and existing no-fake-success/retry behavior.

## 3. Final art wiring and small rendering fixes

### Character images

HPA-924 delivered all 36 assets (12 characters × portrait 1024×1536, opaque square face 512×512, transparent full-body chibi 512×512). Portrait and chibi in `OrionArt` are already data-driven and used in roster, flare and battle; don't regenerate, duplicate or introduce a new cache. Add the equivalent `characterFace(Character)` descriptor derived from `characters/${character.name}/face.png` with semantic label and whole-image source rect. Use existing bounded Flutter image cache for small face/portrait sizes; Flame's existing preloaded chibi sprite path stays for board.

| Surface | Asset role |
| --- | --- |
| Camp owned roster cards and sheet hero | full portrait; unowned mystery cards keep existing obscuring behavior |
| Flare marquee/new-recruit hero | full portrait |
| Flare result compact draw tiles | face (preserve duplicate tint/label and rank) |
| Battle dock and stage briefing ordered squad tokens/picker; small inspector avatar | face for compact identity; drag preview retains chibi |
| Live deployed characters | full-body chibi, rank ring, existing selection/placement animation |
| Codex character art | existing final portrait/chibi by role; use face for compact thumbnail if present |

Keep existing image error fallback as a failure safeguard, not the normal shipped presentation. Remove stale placeholder references/comments in current production docs and code; no happy-path fallback glyph or generic tower cell for a deployed member. Preserve old atlas fallback cells and legitimate effect sprites. Existing per-directory Flutter manifest registration is required for any added character, but no new widget switch/cases. Test every catalog member has all three descriptors and all bundled files fully decode, using existing contract tests.

### Winter road / board

HPA-925 replaced the old path atlas with 444×444 edge-midpoint tiles. `BoardComponent.render` currently deflates the path tile rectangle by 1px and then paints an opaque/wide cyan lane (`_renderLane`, glow/halo, rim/channel/core and flow chevrons) over it. Draw each snow-road tile to the full `cellRect(pathCell)` so the connector edges meet. Delete `_renderLane` and its halo/flow-chevrons/paints/cache entirely, not behind a feature flag. Retain the existing neutral path-cell fallback when art is unavailable (adjust only if needed for legibility) and existing endpoint markers. No cyan channel covering snow, no art hack. Preserve grid, placement danger overlay (visible on invalid drag), selected/valid/invalid highlights, range ring, spawn/breach/Hearth markers, layout, path hitboxes, enemy motion, resize and layering. Remove lane-specific cache/paint logic, including disposal/invalidation; don't change board coordinates or path rules. Validate straight, corner, cap and all seven stage routes, path readability and placement at both widths. Do not redesign board UI to match obsolete cyan in mockup; this explicit ticket correction takes precedence.

### Camp/Flare scene

Both backdrops currently wrap a `Size.square(640)` SpriteWidget in a covering FittedBox for 512×1110 `tech-tree-rnd-bay.png`. [Flame 1.38.2 SpritePainter](https://github.com/flame-engine/flame/blob/v1.38.2/packages/flame/lib/src/widgets/sprite_painter.dart) uses the minimum axis scale, so the art is **letterboxed**, not stretched: the square child is covered, but the painted strip is only ~262 px wide in a 320×568 viewport, leaving ~29 px bands each side. At 390×844 the matching aspect hides the problem. Add `static const Size campBackdropSize = Size(512, 1110)` beside `OrionArt.briefingHeroAspect`; use it in both SpriteWidgets, keeping the existing FittedBox cover/clip/scrim. No new layout abstraction. The regression must assert the **painted art rect covers the full viewport**, especially width at 320×568, using loaded sprite source dimensions and actual child/cover transform (or real pixels), not merely aspect/no stretching or the outer FittedBox bounds. Check both widths and centered crop/text contrast in MCP screenshots. Existing world-map/title/debrief/briefing/crest/board art files have already been replaced in place by #54; verify current descriptors/crops and update accessible labels (“Star chart backdrop” → “Patrol map backdrop”, etc.). Preserve source dimensions, sprite indices and all existing assets.

### Visual language and app name

Keep the existing HPA-699 component hierarchy, typography, padding, action/disabled/selection semantics and rank colors. Adjust title/wordmark glow and limited backdrop/neutral trim/accent tokens in `orion_ui_theme.dart`, `orion_theme_data.dart`, `orion_title_view.dart` for warm ember highlights against cold blue/white snow. Do not globally replace cyan if used for frost, range or meaningful state. Ensure title fits without overlap at compact width and existing scrims remain readable. Compare all six parent mockup panels and their applicable additional states; approved winter artwork and explicit renderer corrections supersede sci-fi art/lanes, not layout. Update `MaterialApp.title` and user-facing launcher/web/desktop names (Android manifest label, iOS Info.plist display name, macOS app product/window display name only where safe without changing bundle IDs, web manifest/index title, Linux/Windows window/display metadata as applicable). Preserve package/application/bundle IDs, executable/target names, app icon, existing build settings unless a display-only label change requires otherwise. Static inspection of platform metadata plus existing CI build checks; no additional native acceptance run.

## 4. New audio cue integration

All five files are already committed and registered by #56; old combat/victory/defeat files were replaced in place. Reuse page-owned `GameFeedback` / `PlatformGameFeedback` and existing preference callbacks (preferences loaded and Sound Effects enabled), not a second audio engine, no new music. Extend interface, NoOp implementation, platform implementation and all fake/recording implementations. Five filenames are rare UI one-shots, outside high-frequency combat limiter/pools. Reuse best-effort one-shot path and shared AudioContext; errors never fail a save or change wallet. Keep existing haptic/music settings behavior. Keep `PlatformGameFeedback.sounds` exactly the four existing warm-up files. Add four semantic methods (`flareLaunched`, `recruitRevealed({required bool rare})`, `characterLeveledUp`, `scripGained`) using `_emit` and five filename constants/one-shot mappings, no new haptic. Reuse the existing recording AudioCache, mocked audioplayers channel and one-shot helpers in `platform_game_feedback_test.dart`; no injectable starter or audio test framework.

| Event | Filename / trigger |
| --- | --- |
| accepted flare launch | `flare_launch.wav` once per accepted 1/10 pack: inside `_fireFlare`'s `buildSave`, construct the payload via `committed.withFlareBatch(batch!)` first, then emit and return the payload. Existing busy/generation and aggregate checks are sufficient; no duplicate press-time validation. Rejected action never launches. A store failure after launch can play the attempt cue but never reveal or show a successful result. |
| committed batch shown | `recruit_reveal.wav` once per results screen, `recruit_reveal_rare.wav` instead if any A/S draw (including duplicate reveal); no per-tile spam. Results still appear for duplicate-only batches. Emit on successful publication/first reveal, not on build, rerender or navigating back. |
| committed level increase | `level_up.wav` once in `_levelUpCharacter` onCommitted; not on busy, cap, stale price, rejected or failed write. |
| committed positive stage-clear Scrip award | `scrip_gain.wav` once per positive stage-clear payout in `_saveMissionResult` onCommitted, including retained-best/replay and successful retry. No separate gain sound for flare duplicate refunds (shown on the reveal), no cue for zero or a debit, no gain on endless/defeat/reset. |

The launch is an attempt cue; other events reflect persisted state. Keep `_persistSave`, `CampaignSave`, `FlareRules`, widget builds and snapshot listeners unchanged; side effects belong to these specific page callbacks. Use the existing mounted/generation and preferences gates, and ensure the synchronous feedback invocation is best effort and cannot convert a completed save into a failure. The committed batch alone selects the reveal variant; no re-roll. **Accept layered playback intentionally:** local saves can complete while the 750 ms flare launch plays, and the stage-clear award may overlap the 500 ms victory stinger. No third refund cue during reveal, timers, sequencer, delayed starts, mixing or changes to queue timing. Defer perceptual mix tuning unless a real problem is reported. Network evidence on first play-path requests plus existing platform mapping/enablement tests verifies integration; it does not establish audible/perceptual quality. No human listening gate.

## 5. Acceptance

- All seven stage names/descriptions/map labels, nine archetypes, five traits, seven bosses, 13 modules, eight modifiers and default have matching final labels in canonical sources and reachable screens. Tests check shipped wave labels, generic custom-wave fallback, boss identity/art independent of copy, search/counter semantics and vocabulary tripwire including accessibility. Legitimate scrap drones/stat terms and internal IDs are not false positives.
- All 12 members resolve portrait/face/chibi via ID; all relevant surfaces use final art, no normal generic placeholders; character/squad, level, gold, flare odds/refund, rewards, path geometry, waves, modifiers, module unlocks, campaign/endless and save tests retain existing numeric/behavior assertions.
- Extend existing platform one-shot mapping and mute event tests for the five files (no new haptics or warm-up changes), NoOp and runtime asset contract. Page-level recording fake tests focus on transaction boundaries: accepted launch, normal/rare batch reveal including duplicate-only and mixed packs, level-up and stage award once on commit, no success cue on reject/failure, exactly once after retry, none on rebuild, no gain on refund/debit/defeat/endless. Existing preference-loading/disposal, combat limiter and music coverage is reused; no per-cue page preference matrix.
- Full `flutter analyze`, `flutter test`, `flutter build web --release`; existing CI including integration tests and Python asset contracts. No new native acceptance requirement. MCP Chrome real app E2E and visual parity in the companion plan, including actual playable stage from a clean profile, paid flare, level-up, stage replay and sound toggle. Deterministic tests cover rare paths rather than requiring lucky rolls in browser. Capture first-trigger requests for uncached new cues (no manual prefetch) through the existing one-shot playback path and an SFX-off check with a cold in-process audio cache; existing platform tests assert actual playback dispatch. A cached request cannot establish silence and network evidence cannot establish audible output. No Web Audio instrumentation/retry loop; report perceptual quality as unverified.
- README explains Last Hearth, new roster/squad/levels/flare/Scrip, fixed odds, campaign/endless and current roadmap. Update stale active agent guidance for asset/economy handoff; historical specs stay history. Parent HPA-921 closes only after this child is implemented, merged and its acceptance evidence passes; this draft alone is not completion.

See [implementation plan](../plans/2026-11-23-hpa-926-last-hearth-retheme.md).
