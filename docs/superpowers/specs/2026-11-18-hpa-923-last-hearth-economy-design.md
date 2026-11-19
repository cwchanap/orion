# HPA-923 — Last Hearth Scrip, character leveling and signal flares (Design Spec)

Date: 2026-11-18  
Linear: https://linear.app/cwchanap/issue/HPA-923/orion-scrip-economy-character-levels-and-the-signal-flare  
Parent direction: https://linear.app/cwchanap/issue/HPA-921/orion-pivot-to-last-hearth-an-anime-character-tower-defense  
Dependency: HPA-922 is complete in `main` (reviewed at `f8f89afc4b6760d2ceaf9c8b4b66b4dd6875c15e`).  
Delivery: **one implementation PR for HPA-923**; this draft PR carries the spec and plan first, then implementation and evidence. No separate planning/implementation PRs.

## Goal and player experience

A fresh player starts with Haruto and Mio at level 1 and **0 Scrip**. Clearing Stage 1 earns at least 1,000 Scrip, enough to fire ten signal flares at once. Each flare recruits one of the 12 existing characters, or trades a duplicate dog tag for Scrip. Players can spend Scrip on permanent character levels (1–40) in Camp, then put newly recruited/leveled characters into a squad using the existing stage-briefing picker. Stage clears and replays fund further progression.

Scrip is **persistent** and independent from **battle gold** (which still resets each mission). A success/failure of a single save must never leave the Scrip balance inconsistent with the granted character, level or stage result.

## Verified baseline on main

- `lib/game/campaign/campaign_progress_store.dart` already has one `CampaignSave` (stage progress, Endless bests, owned levels, ordered squad) under SharedPreferences key `orion.campaign.progress`, codec version 4, plus a matching in-memory test store. **Extend this aggregate in place.**
- `lib/game/ui/orion_game_page.dart` owns `_persistSave`: a serialized committed-base write queue, generation guards, rollback/failure reporting, first-load recovery and reset. `_committedProgress`, `_committedOwnedLevels` and `_committedSquad` are the sources for queued transactions. Extend these to Scrip; do not create another wallet store.
- Stage victories currently **skip persistence when the result does not improve the best**: `_handleStageWon` sets `saved` and returns. This is incorrect for a replayable currency. Every successful *mission* completion must run one reward transaction regardless of best-medal improvement; `CampaignProgress.recordResult` already keeps the best unchanged when appropriate.
- `lib/game/ui/camp_view.dart` shows owned levels in a read-only `_CharacterSheet`. It already derives preview stats with `GameBalance.characterScalingFactor` and uses `TowerStatScale`; add purchase/next-level previews here.
- `OrionMenuShell` has Map/Camp/Codex and a medal chip; `StageBriefingSheet` already knows whether the stage has been cleared; `MissionReportContent` keeps the best-result comparison separate from blueprint rewards.
- `TowerStatsResolver` already scales damage, corrosion DPS and drone damage from persistent level. No combat stat mechanics need to change.
- The approved Linear artboards are **11 (character sheet with Level up), 12 (signal flare), 13 (flare results), 14 (stage briefing with Scrip)**. Existing character art and menu/backdrop assets are sufficient for this code task; final winter art, effects and audio belong to HPA-924/925/927 and HPA-926.

## Boundaries and intentional exclusions

Keep stages, boards, waves, bosses, medals, run modules, Endless, the Codex, guidance, deployed character tiers, squad selection and character art contracts unchanged unless required for the economy. Do not introduce an economy service, new persistence key, network sync, external purchase flow, equipment, pity/banners, character shards, a second leveling system, or a separate PR for any implementation slice.

No Scrip from losses or Endless mode. No Scrip from in-battle gold, and no exchange between the two currencies.

## Balance: one source of truth

Put all tunables in `GameBalance` in `lib/game/models/game_models.dart`. Put calculation/roll logic in small pure classes under `lib/game/rules/`. The following numbers are initial tuning values, not a live-ops system:

- Initial Scrip: **0**. One flare costs **100**; ten cost **1,000** with no discount.
- Duplicate Scrip refund by rank: E **10**, D **25**, C **60**, B **200**, A **600**, S **2,000**.
- Persistent level cap: **40**. Upgrading current level L to L+1 costs `60 + 40 × (L - 1)`; L=1 costs 60, L=4 costs 180. Prices do not vary by rank. No payment/action at level 40.
- Medal payout multiplier: Clear `100%`, Silver `125%`, Gold `150%`. Use integer-percent arithmetic (truncate any fractions) for stable display and tests.
- A successful mission clear pays `firstClearBonus + floor(replayBase × medalPercent / 100)`, where `firstClearBonus` is included **only when the committed profile has no prior result for this stage**. A replay always pays the replay component even if the medal/best HP is unchanged.

Proposed per-stage starting values (the known seven stage IDs are intentional: no new stage-schema/config framework):

| Existing stage id | First-clear bonus | Replay base (Clear medal) | Total first clear (Clear medal) |
| --- | ---: | ---: | ---: |
| `outpost-alpha` | 900 | 100 | **1,000** |
| `nebula-relay` | 180 | 120 | **300** |
| `salvage-rift` (side) | 220 | 140 | 360 |
| `asteroid-foundry` | 240 | 160 | 400 |
| `aurora-gate` | 300 | 200 | 500 |
| `void-bastion` (side) | 380 | 220 | 600 |
| `singularity-core` | 440 | 260 | 700 |

**Stage 1 guarantee and medal tradeoff:** A Clear-medal first win pays exactly 1,000 (the price of ten flares). A Silver/Gold first win pays 1,025/1,050, respectively. This preserves the hard *at least ten flares* onboarding guarantee and applies the ticket's better-medal bonus without silently capping rewards. Stage 1 replays pay 100/125/150 by medal. Stage 2 first clear pays 300/330/360 and replays 120/150/180. Adjust only centralized `GameBalance` values if the playable tuning pass finds a problem.

`StageScripRules` takes stage ID, current-run `StageMedal` and `wasAlreadyCleared`, returns a nonnegative integer award. It must not depend on the saved best medal or create awards on stage launch. A test covers every known stage ID, all medals, and first/replay distinction.

## Recruitment rules (pure, seeded, atomic)

Use **exactly** the owner's fixed rate table, expressed as 10,000-basis-point integer weights. Roll rank first, then choose uniformly among `Character.values` of that rank:

| Rank | S | A | B | C | D | E |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Probability | 0.1% | 0.5% | 2% | 10% | 20% | 67.4% |
| Basis points | 10 | 50 | 200 | 1,000 | 2,000 | 6,740 |

The weight sum must be exactly 10,000. One and ten pulls use the same rule, with an injected `Random` (or small `nextInt(maxExclusive)` seam) so tests are seeded/deterministic. No pity, banner modifiers, or real-money integration.

Process a ten-pull **in order**, against an evolving owned set: the first copy of an unowned character becomes owned at **level 1**; a second copy of that same character in the same batch is a duplicate. On duplicates, award the rank's Scrip refund instead of adding another roster entry. The player must have the full **100 or 1,000 Scrip before starting**; later duplicate refunds do not bypass initial affordability. Results preserve all ten outcomes in draw order: identity, rank, `NEW` or `DUPLICATE`, per-duplicate Scrip, total refunds and resulting balance. Newly recruited characters are **not automatically added to the active squad**; the stage-briefing squad picker continues to own that decision.

`FlareRules` should be stateless and return a batch outcome plus the updated owned levels/balance from inputs. The UI may inject an RNG for tests, but it must not roll or mutate the profile outside the queued `_persistSave` committed-base transaction. Reveal the results **only after a successful save**; on failure, preserve the previous balance/roster and allow retry. A save retry is a new uncommitted attempt (no prior failed draw is revealed or spent).

## Levels and stats

The character sheet shows current level, Scrip balance, next-level cost, and **before → after** combat stat preview (including relevant secondary damage channels) computed from the existing `GameBalance` / `TowerStatScale` path. Do not introduce a separate stat formula. The Level Up action is disabled with an explicit reason when underfunded, at level 40, or saving. Pressing it triggers one committed-base `CampaignSave` update that deducts cost and increments exactly that owned character's level; no effect on the current battle or on in-battle tier. After commit, the Camp sheet and top-bar currency immediately reflect the saved state. A failed write leaves both unchanged and permits retry.

## Save and stage completion transaction

Extend `CampaignSave` with a nonnegative `scrip` value. Extend the **existing version-4 codec** with a `scrip` field; an absent/invalid `scrip` in an otherwise valid v4 payload reads as 0, independently of valid progress and roster fields. This is an additive field with no separate migration system or alternate key. Existing pre-v4 reset semantics remain. Reset restores 0 Scrip, Haruto/Mio at level 1, the initial squad and empty progress.

Mirror the existing committed-base queue with `_scrip` and `_committedScrip`. Every write builds from the latest committed aggregate inside `_persistSave`:

1. **Mission victory**: capture completion once, calculate payment based on the committed `progress.resultFor(stageId)`, record a better result if any, credit Scrip and save **as one aggregate**. This happens even when `recordResult` retains the old best. The existing `_missionSaveState` remains `saving → saved/failed`; duplicate win callbacks, retry taps or navigation cannot credit twice. On a failed write, keep the unchanged committed balance and report that the award was **not credited**. A Retry Save recomputes against the unchanged committed state and credits once on success.
2. **Level Up**: validate ownership, max level, price and funds against the committed aggregate, deduct and update the level together, then publish the committed profile.
3. **Fire 1/10**: validate committed funds, roll the entire ordered batch against the committed owned set, deduct the full entry fee and apply all duplicate credits/new ownership **within the same save**, then publish the batch result only on commit.
4. **Squad Launch, Endless best and reset**: retain the established queue and failure guards. Every constructor/`withSquad` operation must carry forward Scrip; never reconstruct a `CampaignSave` and silently reset the wallet.

The mission report keeps existing medal/best-result comparisons and blueprint recovery. Add an **independent Scrip award fact** with estimated/pending, saved and failed/uncredited states. A replay whose saved best is retained still shows a positive saved Scrip award. No award on loss/Endless. The stage briefing displays Scrip reward expectations for first-clear versus replay and explains the medal bonus; the exact medal is determined by the completed run.

## UI changes (reuse current Orion UI kit)

- Menu top bar: Scrip resource chip with accessible label and stable formatted integer. Retain the medal tally and Settings; handle narrow widths rather than overflow. Tabs in order **Map, Camp, Flare, Codex**; add `OrionMenuDestination.flare` / `_ShellView.flare`, not a new app navigator.
- Camp artboard **11**: extend the existing private character sheet with Level Up button, Scrip cost, level-cap and insufficiency state, preview values, single-flight saving indicator and save-error feedback. The roster remains a grid of all 12 with locked/owned states.
- Flare artboard **12**: new small `FlareView` with one of the existing backgrounds/character art assets, a permanently visible fixed-rate table, Scrip balance, and Fire 1 / Fire 10 controls disabled for insufficient funds or pending save. Do not generate art or SFX in this ticket.
- Result artboard **13**: show all pulls in sequence, highlight new recruits, visibly mark duplicate Scrip refund and show total refund/net balance. A Return action goes back to the Flare screen.
- Briefing artboard **14**: display the relevant first-clear/replay Scrip projection without implying medal is known beforehand. Keep existing squad draft, modifiers, Replay/Endless and save-before-launch behavior.
- Mission report: show pending/saved/uncredited Scrip separately from blueprint/module rewards; keep Retry Save and the existing navigation guard.

All affected UI must work on portrait 320×568, 2× text scale, screen-reader labels and touch/keyboard navigation without clipping or overlapping. Compare implementation screenshots against Linear's attached artboards **11/12/13/14**; any deliberate backdrop differences are acceptable placeholders until HPA-926 and must be recorded.

## Testing and end-to-end contract

Pure tests:
- Rates add to 10,000; exhaustive threshold/bucket test and seeded sample; uniform selection within rank; ordered ten-pull including duplicate of a newly pulled character; affordability; total refunds/net result.
- All seven stage payout tables, three medals, first-clear only once, replay with unchanged medal/best, no loss/Endless award.
- Level prices 1→2 and 4→5, level 40 stop, insufficient funds, owned-only upgrade, and actual increased damage/corrosion/drone channels through `TowerStatsResolver`.
- v4 codec missing/corrupt Scrip fallback, atomic reload and reset, failure/Retry Save, two queued writes and no lost wallet updates.

UI/widget tests:
- Four menu tabs, visible/accessible top-bar Scrip, disabled/reenabled purchase and pull controls, batch display, real after-commit updates, failed-save feedback, and replay report showing both best retained and Scrip earned.
- Compact portrait 320×568 and 2× font layouts; no off-screen Level Up, Fire 10, rates, result counts or mission reward.

**MCP-driven E2E acceptance (one web/Chrome platform is enough):** fresh save → Stage 1 win/commit → Scrip visible ≥1,000 → 10-flare fire/result → roster and balance persist on reload → level up an owned character → verify higher stats and level after reload → play/replay a stage with unchanged best → obtain additional Scrip once → verify Codex, squad Launch, Endless and existing settings still work. Failure injection in a test store must prove no partial purchase/recruitment/reward on failed write. If browser wave completion is impractical, use the existing deterministic full-wave headless game-loop fixture for the victory portion and the browser MCP for all reachable UI/save/reload paths.

Capture screenshot evidence for **Linear mockups 11, 12, 13, 14** plus the mission report; record tested commit, viewport and deviations in the **same PR**. Run `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test --coverage`, `flutter build web --release` and repository CI. No human signoff criterion.

## Risks deliberately kept small

- High E odds (67.4%) mean early duplicate-heavy ten-pulls by design; no pity mechanism. Keep the starter Stage-1 payout guaranteed and make duplicate credits unmistakable.
- A S-rank duplicate refund exceeds a single flare's cost; this is an explicitly configured rare reward, not an invariant requiring net spending every batch.
- Best result and Scrip payout are different facts: an unchanged best **must not** suppress currency.
- Do not move reward/roster mutations into widgets or build a generalized transaction engine; reuse the one queue already in place.
