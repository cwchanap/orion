# HPA-20 — Progression Payoff Preview Implementation Plan

> **For agentic workers:** implement this plan on the same HPA-20 branch/PR. Do not split the ticket into multiple PRs. Work task by task, test-first, and keep each commit green.

**Goal:** Show a compact current → candidate comparison for tower upgrades and specializations, a role sentence per specialization, and honest current-run beneficiary context on Salvage Module cards, without changing any mutation, cost, picker, or balance behavior.

**Architecture:** `GameSession.snapshot()` resolves preview stats through the existing `resolveTowerStats` on `PlacedTower.upgraded()` / `.specialized()` values and counts module beneficiaries with the same affinity predicate `RunModuleRules` already uses. The snapshot carries the results; widgets only format them.

**Tech stack:** Flutter + Flame + Dart. No new packages or assets.

**Spec:** docs/superpowers/specs/2026-10-15-hpa-20-progression-payoff-preview-design.md

## Global constraints

- One PR for HPA-20, including planning and implementation.
- No changes to `upgradeTower`, `specializeTower`, `selectRunModule`, `_moduleCandidates`, `ModuleOfferPicker`, costs, affordability, or phase gating.
- No balance, module, or art changes. `game_balance_test.dart` must pass untouched.
- No recommendation, ranking, power score, DPS, board highlight, analytics, or generic comparison/view-model framework.
- Widgets never compute stats; they only format two resolved `TowerStats` values and a count.
- New `GameSnapshot` fields are optional with defaults so existing constructions compile unchanged.

---

## Expected file shape

### Modify

- lib/game/models/game_models.dart — `TowerSpecialization.role`, `RunModuleDefinition.affectsTowerStats`, three new `GameSnapshot` fields
- lib/game/codex/codex_data.dart — read `spec.role`; delete `_specializationDescription`
- lib/game/rules/run_module_rules.dart — public `appliesToTower`, new `beneficiaryCount`
- lib/game/rules/game_session.dart — populate preview fields in `snapshot()`
- lib/game/ui/tower_inspector.dart — upgrade preview, specialization role + preview
- lib/game/ui/run_module_draft_panel.dart — `beneficiaries` input and context line
- lib/game/ui/orion_game_page.dart — pass `snapshot.pendingRunModuleBeneficiaries`
- test/game/game_session_test.dart
- test/game/run_module_rules_test.dart
- test/game/codex/codex_data_test.dart
- test/widget/tower_inspector_test.dart
- test/widget/run_module_draft_panel_test.dart

### Create

Nothing. Do not add a new model/view-model file.

---

## Task 1: Canonical specialization role sentence

**Files:** lib/game/models/game_models.dart, lib/game/codex/codex_data.dart, test/game/codex/codex_data_test.dart

1. Test first in `codex_data_test.dart`: for every `TowerSpecialization`, `CodexData.towerFor(spec.type).specializations.firstWhere(...).description == spec.role`, and `spec.role` is non-empty. Also add a test that every role is ≤ 90 characters so the card text stays compact.
2. Add to `enum TowerSpecialization` a `String get role => switch (this) { ... }` containing the 16 sentences copied verbatim from `CodexData._specializationDescription`.
3. In `CodexData.towerFor`, set `description: spec.role`; delete `_specializationDescription`.
4. Run `flutter test test/game/codex/ test/widget/codex_view_test.dart`. Codex output must be identical.

Commit: `HPA-20: move specialization role text onto TowerSpecialization`

## Task 2: Upgrade and specialization preview stats on the snapshot

**Files:** lib/game/models/game_models.dart, lib/game/rules/game_session.dart, test/game/game_session_test.dart

1. Tests first in `game_session_test.dart`, new `group('GameSession progression previews', ...)`:
   - Build a session with non-empty `CampaignModifiers` (e.g. a laser damage fraction and cryo slow bonus), a stage whose `modifiers` affect tower stats (pick one `StageModifierRules.effectiveTowerStats` touches; see `stage_modifier_rules_test.dart`), and an acquired module. To acquire one, advance to a draft with a deterministic `offerPicker` (see `module_offer_picker_test.dart` / existing session tests for a fixed picker) and call `selectRunModule`.
   - Place a Laser and a Cryo tower. For each: `final preview = session.snapshot(selectedTower: tower).selectedTowerUpgradeStats;` then `session.upgradeTower(tower.id)` and compare `preview` field-by-field (damage, fireInterval, range, slowDuration, splashRadius, level) with `session.resolveTowerStats(session.towerAt(tower.position)!)`.
   - Specialization: for each `spec` of the tower type, use a fresh identically-built session (or rebuild from the same factory helper), upgrade to L2, read `snapshot(selectedTower: l2).selectedTowerSpecializationStats[spec]`, then `specializeTower(id, spec)` and compare with the real resolved stats.
   - Non-mutation: capture `gold`, `towers` (ids/levels/specializations), `acquiredRunModules`, `pendingRunModuleOffer`, `phase` before and after calling `snapshot(selectedTower: ...)` three times; all equal.
   - Absence: no selection → upgrade null, spec map empty. L1 → spec map empty. L2 → upgrade null, spec map has exactly `GameBalance.specializationsFor(type)` keys. L3 → both empty.
2. Add to `GameSnapshot` constructor/fields: `this.selectedTowerUpgradeStats` and `Map<TowerSpecialization, TowerStats> selectedTowerSpecializationStats = const {}` (store via `Map.unmodifiable`).
3. In `GameSession.snapshot()` compute both via `resolveTowerStats(selectedTower.upgraded())` and `resolveTowerStats(selectedTower.specialized(spec))`, guarded by `canUpgrade` / `canSpecialize` so the `StateError`/`ArgumentError` branches in `PlacedTower` are never hit.
4. Run `flutter test test/game/game_session_test.dart test/game/tower_stats_resolver_test.dart`.

Commit: `HPA-20: publish resolved upgrade/specialization previews in the snapshot`

## Task 3: Module beneficiary counts

**Files:** lib/game/models/game_models.dart, lib/game/rules/run_module_rules.dart, lib/game/rules/game_session.dart, test/game/run_module_rules_test.dart, test/game/game_session_test.dart

1. Tests first in `run_module_rules_test.dart`:
   - `affectsTowerStats` is false only for `emergencySalvage`, true for every other catalog entry.
   - `beneficiaryCount`: Heavy Caliber with 3 mixed towers → 3; Cryo Reservoir with 2 cryo + 1 laser → 2; Rocket Fusing with no rockets → 0; Emergency Salvage with 3 towers → 0; any module with no towers → 0.
   - Existing `applyTowerStats` tests unchanged and green.
2. In game_models.dart add `bool get affectsTowerStats => damageMultiplier != 1 || fireIntervalMultiplier != 1 || rangeMultiplier != 1 || splashRadiusMultiplier != 1 || slowDurationBonus != 0;`.
3. In run_module_rules.dart rename `_appliesToTower` → public `appliesToTower` (keep `applyTowerStats` calling it), add:
   ```dart
   static int beneficiaryCount(RunModuleDefinition definition, Iterable<PlacedTower> towers) =>
       !definition.affectsTowerStats
           ? 0
           : towers.where((t) => appliesToTower(definition.affinity, t.type)).length;
   ```
4. Add `Map<RunModuleId, int> pendingRunModuleBeneficiaries = const {}` to `GameSnapshot`. In `GameSession.snapshot()`, when `_pendingRunModuleOffer` is non-null, fill it for each offered id from `RunModuleRules.beneficiaryCount(runModuleDefinition(id), _towersByPosition.values)`.
5. Session test: after reaching a draft with a fixed picker and some placed towers, the map's keys equal `offer.moduleIds` and counts match; after `selectRunModule`, the map is empty. Assert the offer ids are identical to the pre-change behavior for the same picker (offer eligibility unchanged).
6. Run `flutter test test/game/run_module_rules_test.dart test/game/game_session_test.dart test/game/module_offer_picker_test.dart`.

Commit: `HPA-20: count current Salvage Module beneficiaries`

## Task 4: Inspector upgrade preview

**Files:** lib/game/ui/tower_inspector.dart, test/widget/tower_inspector_test.dart

1. Widget tests first (follow the existing snapshot fixtures in this file):
   - L1 laser with `selectedTowerStats` = L1 base and `selectedTowerUpgradeStats` = L2 base: finds `tower-upgrade-preview`, texts for Damage `12 → 18`, Fire `0.42s → 0.34s`, Range `145 → 160`; `tower-upgrade` still shows `Upgrade <cost>` and invokes `onUpgrade` when affordable.
   - Unchanged-row hiding: craft a candidate equal to current except damage; only the Damage row renders.
   - Semantics: `find.bySemanticsLabel(RegExp(r'^Upgrade preview\. Damage 12 to 18'))`.
   - `selectedTowerUpgradeStats == null` → no preview widget, button unchanged (covers existing null-stats test).
2. Implement a private `_PreviewRow` record/class `(String label, String from, String to)` and a private top-level `List<_PreviewRow> _previewRows(TowerStats current, TowerStats candidate, TowerSecondaryMetric? secondary)` that reuses `number`, `cadence`, `_InspectorBody._secondaryLabel`, and `_InspectorBody._secondaryValue` and drops rows whose formatted strings match. Promote those two static helpers to file-private top-level functions if that is cleaner; do not duplicate them.
3. Add a private `_StatPreview` widget rendering the rows (single `Semantics(container: true, excludeSemantics: true, label: ...)`, "to" in the label, "→" in the visible text, seconds spelled out for Fire/Slow in the label).
4. In `_ProgressionActions`, for `canUpgrade`, render the `'UPGRADE - LV ${tower.level + 1}'` header (same interpolation as the adjacent `SPECIALIZE` header), `_StatPreview` (key `tower-upgrade-preview`) when both stats are present, then the unchanged button.
5. Run `flutter test test/widget/tower_inspector_test.dart`.

Commit: `HPA-20: show upgrade preview in the tower inspector`

## Task 5: Specialization role + preview cards

**Files:** lib/game/ui/tower_inspector.dart, test/widget/tower_inspector_test.dart

1. Widget tests first:
   - L2 cryo with both specialization previews: each card shows `spec.role` and its preview (key `tower-specialization-preview-${spec.name}`); Deep Freeze shows a Slow row; the button-semantics label starts with `'Deep Freeze <cost>. <role>.'`; tapping still calls `onSpecialize(spec)` when affordable and does nothing when disabled.
   - Missing map entry → card shows role but no preview rows.
   - Layout: at `physicalSize` 360×640 and 390×844 (DPR 1), pump an L2 tower of every `TowerType` and assert `tester.takeException()` is null; the existing "caps height and scrolls internally on a phone" test stays green.
2. Pass `currentStats: stats` and `candidateStats: snapshot.selectedTowerSpecializationStats[spec]` into `_SpecializationCard`; render role text then `_StatPreview` under the existing cost. Extend the card's semantics label with the role and preview text.
3. Run `flutter test test/widget/tower_inspector_test.dart test/widget/scene_parity_regression_test.dart`. If the scene-parity capture changes because the inspector grew, update only the affected expected capture, and say so in the PR.

Commit: `HPA-20: explain specialization role and payoff on each card`

## Task 6: Salvage Module context line

**Files:** lib/game/ui/run_module_draft_panel.dart, lib/game/ui/orion_game_page.dart, test/widget/run_module_draft_panel_test.dart

1. Widget tests first, with an explicit `beneficiaries` map:
   - Heavy Caliber count 3 → `Affects your 3 placed towers`; count 1 → `Affects your 1 placed tower`; count 0 → `Affects every tower you build`.
   - Cryo Reservoir count 2 → `Affects your 2 placed Cryo towers`; count 0 → `Benefits Cryo towers you build later`.
   - Emergency Salvage → no context line (assert none of the phrases above appear for that card).
   - Semantics label = existing label + `'. <context line>'` when present; unchanged for Emergency Salvage.
   - Existing 360×640 test still renders with no exception and selection still calls back with the right id. Card order equals `offer.moduleIds` order.
2. Add `final Map<RunModuleId, int> beneficiaries` (default `const {}`) to `RunModuleDraftPanel`; pass `beneficiaries[id]` (default 0) into `_RunModuleCard`. Add a private `String? _contextLine(RunModuleDefinition d, int count)` implementing the spec table. Render it under the affinity label with `OrionTypography.microLabel(size: 9, color: uiTheme.textMuted)`.
3. In `orion_game_page.dart`, pass `beneficiaries: snapshot.pendingRunModuleBeneficiaries`.
4. Run `flutter test test/widget/run_module_draft_panel_test.dart test/widget_test.dart`.

Commit: `HPA-20: add current-run context to Salvage Module cards`

## Task 7: Full verification and PR

1. `dart format --set-exit-if-changed .`
2. `flutter analyze` — zero issues.
3. `flutter test` — full suite green, including `game_balance_test.dart` untouched.
4. Manual check on a portrait device/emulator: select an L1 tower (preview visible beside Upgrade), upgrade, open specialization cards (roles + previews readable, sheet scrolls), reach a module draft with and without matching towers.
5. Update the HPA-20 PR description with screenshots of the three surfaces and tick the acceptance checklist.

## Risks and notes

- **Snapshot cost:** previews add at most two extra `resolveTowerStats` calls per snapshot, only while a tower is selected. The resolver is a few `copyWith`s; no caching needed.
- **Stale selection:** `OrionDefenseGame` already replaces `_selectedTower` after upgrade/specialize, so the next snapshot recomputes previews for the new level. Task 2 tests cover the L2/L3 transitions at the session level.
- **Text length:** the longest role sentence is ~75 characters; Task 1's length guard keeps future edits compact. Cards wrap rather than truncate.
- **Module counts during a draft:** towers can't be placed or sold while a draft is pending (`_canMutateBuild`), so counts are stable for the life of the offer.
