# HPA-716 — Campaign completion and side-route clarity (design)

**Linear:** https://linear.app/cwchanap/issue/HPA-716  
**Status:** Proposed for review; design + plan first, then code in this **same PR**.  
**Scope:** World-map presentation and next-stage recommendation only.

## Problem and decision

Orion has **five main-path stages** and **two optional stages**. CampaignProgress.isCampaignComplete correctly treats the five main stages as campaign completion. WorldMapView._SectorHeader, however, shows a combined cleared/total count across all seven stages. After the final main mission, the completion icon can appear beside **5/7**, without explaining that the other two are optional. _MissionDestination also falls back to a previously cleared stage rather than offering an available unfinished optional mission.

**Decision:** Separate main-route progress from optional progress in the existing map header and suggest an available unfinished side stage after the main route. Avoid new screens, state, persistence, or progression rules.

This task is independent of [HPA-715 Endless Mode](https://linear.app/cwchanap/issue/HPA-715), which explicitly excludes world-map UI changes.

## Player-facing states

| Saved campaign | Header | Suggested destination |
| --- | --- | --- |
| Fresh | MAIN 0/5; no completion claim | Outpost Alpha (next main) |
| Alpha and Nebula cleared; side unlocked | MAIN 2/5 | Asteroid Foundry (main first) |
| Five main cleared; no sides | CAMPAIGN COMPLETE; MAIN 5/5; SIDE 0/2 | Salvage Rift (optional) |
| Five main and Salvage Rift cleared | CAMPAIGN COMPLETE; MAIN 5/5; SIDE 1/2 | Void Bastion (optional) |
| All seven cleared | ALL SECTORS SECURED; MAIN 5/5; SIDE 2/2 | Replay the last playable stage |

The destination is a suggestion, never a restriction. All unlocked map nodes remain tappable.

## Header UX

- Retain Orion Sector, the existing badge, backdrop, theme, utility rail, and Challenge Badge.
- Before main completion, display **MAIN x/5** rather than a combined x/7. Do not needlessly increase early-game chrome.
- After main completion, show **CAMPAIGN COMPLETE** (or **ALL SECTORS SECURED** when all known stages are cleared), plus the distinct **MAIN 5/5** and **SIDE y/2** totals.
- Derive totals from the stages supplied to WorldMapView, not from fixed OrionCampaign globals. Derive clears from CampaignProgress.isCleared(stage.id), and continue using CampaignProgress.isCampaignComplete(stages) as the authority for main completion.
- The empty-stage fixture stays empty and must not claim completion.
- Give the header one readable semantic summary distinguishing main and side stages. Fit copy in small portrait viewports and under high system text scale without obstructing map controls.

## Suggested destination

Retain _MissionDestination in lib/game/ui/world_map_view.dart and use its existing surface, asset, selection callback, and disabled behavior. Choose:

1. The first **unlocked, uncleared main** stage in supplied stage order.
2. Otherwise, the first **unlocked, uncleared optional** stage in supplied stage order.
3. Otherwise, the last non-locked stage as the existing replay fallback.

The destination kicker and semantics should communicate **NEXT MAIN**, **OPTIONAL ROUTE**, or **REPLAY**, as appropriate. Keep stage briefing, unlock conditions, and all stage node interactions unchanged.

**Campaign complete** means five main-path clears; **all sectors secured** means the entire provided stage set is cleared. Never imply that optional stages block the main campaign.

## Code boundaries

Change only:
- lib/game/ui/world_map_view.dart (derived counts, header copy/semantics/layout, destination priority and kicker)
- test/widget/world_map_command_deck_test.dart (focused regression scenarios)
- Any directly affected existing scene 1f visual reference/expectation, only if the intentional copy change requires it

Do not modify GameSession, OrionDefenseGame, CampaignProgress, save codecs, stage definitions, unlocks, balance, medals, blueprints, music, or settings. No new packages, models, services, one-time popup, or save version. Reuse existing icons/assets; this task requires **no new art or SFX**.

## Verification

- Fresh and partial campaigns still suggest the next main mission.
- Five main clears without side clears show CAMPAIGN COMPLETE with SIDE 0/2, and tapping the suggested destination opens Salvage Rift.
- When only Void Bastion remains, it becomes the suggestion.
- All seven cleared show ALL SECTORS SECURED and offer ordinary replay, not a misleading next stage.
- Busy saving/resetting disables the suggested stage; all map nodes remain unchanged.
- Header/destination semantics match visible text. Check 320x568 and text-scale 3x for overflow.
- Flutter format, analyze, full tests, >=90% Codecov gate, and web build pass.

## Out of scope

Endless scores, gameplay or economy changes, one-time campaign cutscenes, new art/SFX/music, achievements, analytics, online saves, generic navigation abstractions, and backward-compatibility systems. Future custom assets must be a separate ticket.
