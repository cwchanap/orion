# HPA-716 — Campaign completion and side-route clarity (implementation plan)

> **One Linear task, one PR.** This is a docs-first draft. Implement and test on the **same branch and PR** after review.

**Linear:** https://linear.app/cwchanap/issue/HPA-716  
**Design:** ../specs/2026-11-03-hpa-716-campaign-completion-design.md  
**Base:** main

## Implementation strategy

Stay inside WorldMapView. Derive progress presentation from the supplied stages + committed CampaignProgress, preserve unlock authority, and add one extra destination-selection priority for unfinished optional stages. Do not create a routing service, new save field, or state machine.

## 1. Write focused failing widget tests first

Extend test/widget/world_map_command_deck_test.dart using the existing buildMap fixture and the actual OrionCampaign.stages:

- Fresh: MAIN 0/5, no completion banner; the destination opens Outpost Alpha.
- Main partial: only Alpha and Nebula cleared, Salvage Rift unlocked; the destination opens Asteroid Foundry (main first).
- Main complete/optional 0: results for all five main stages and no optional ones; CAMPAIGN COMPLETE, MAIN 5/5, SIDE 0/2; destination opens Salvage Rift.
- Main complete/optional 1: add Salvage Rift; SIDE 1/2; destination opens Void Bastion.
- Full clear: ALL SECTORS SECURED, MAIN 5/5, SIDE 2/2; destination offers replay and calls onStageSelected.
- Empty stages: existing "No stages available" state remains, with no completion announcement.

Test header and destination semantic labels using tester.ensureSemantics.

## 2. Update header with separate main/side progress

In lib/game/ui/world_map_view.dart:

- Count main and optional stage totals and clears separately inside WorldMapView.build.
- Pass simple integers and booleans into _SectorHeader. Continue using CampaignProgress.isCampaignComplete(stages) for campaign completion, and use all stage clears for the fully-secured copy.
- Preserve the current title, badge location, utilities, Challenge Badge, and background. Add only short completion/optional text and matching accessibility semantics.
- Update the _EmptySectorMap call to keep the empty-state header safe; do not present it as completed.
- Check wrapping at 320px and larger system font scale; do not move the utility rail or hide gameplay targets.

## 3. Recommend unfinished optional routes

Inside _MissionDestination.build:

- Keep the existing unlocked+uncleared main-stage query.
- Next use the first unlocked+uncleared side-stage query.
- Retain the current last-playable-stage fallback for replay once no unfinished unlocked stages remain.
- Add a small NEXT MAIN / OPTIONAL ROUTE / REPLAY kicker and a semantic button label that reflects it.
- Keep the existing stage briefing callback, image, tap target, and save/reset busy gating.
- Add a focused busy-state test when an optional stage is the destination.

Do not extract an abstraction unless the existing method genuinely becomes harder to read.

## 4. Regression and ship in the same PR

Run:
- flutter test test/widget/world_map_command_deck_test.dart
- dart format --output=none --set-exit-if-changed .
- flutter analyze
- flutter test --coverage
- flutter build web --release

Check the existing map-node, narrow-screen, semantic and scene 1f tests. If an approved screenshot/reference changes due to deliberate header copy, update only the affected reference and document the reason. The Codecov project and patch gates remain >=90%.

Once tests and CI pass, update this PR body with results; do not open a second implementation PR. HPA-715 remains separate and no new media-generation task is needed.

## Done when

The five-main-stage victory is unmistakable, unfinished optional content is visible and suggested, full seven-stage completion is accurately labeled, and replay remains possible. No game rules, persistence, rewards, or art/audio assets change.
