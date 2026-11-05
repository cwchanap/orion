# HPA-753 — Codex Search Implementation Plan

**Linear:** [HPA-753](https://linear.app/cwchanap/issue/HPA-753/orion-find-codex-entries-without-scrolling)  
**Design authority:** [HPA-753 design](../specs/2026-11-04-hpa-753-codex-search-design.md)  
**PR policy:** One ticket = one PR. Start as documentation-only draft; add production code/tests to **this same PR** after owner reviews the plan.

## Verified baseline

- `lib/game/ui/codex_view.dart` already owns one `_section` index and four `ScrollController` instances, which preserve independent tab scroll positions.
- Its `_body()` switch maps directly over `CodexData.towers`, `traits` + `enemies`, `effects`, and `stagesFor(progress)`; no filter or text field exists.
- `lib/game/codex/codex_data.dart` supplies the names, specialization role descriptions, enemy traits/roles, effect descriptions/related specialization identities, and stage descriptions/modifiers needed to match.
- `test/widget/codex_view_test.dart` covers tab navigation, key fact formatting, stage status/rewards, and a narrow viewport. Keep those regression tests unchanged unless an intentional search-specific expectation requires it.
- Codex entry is from the world map; HPA-715 Endless Mode does not touch the Codex or these tests. No downstream interface or save-data change is needed.

## File map

**Modify only:**
- `lib/game/ui/codex_view.dart` — field, local query state, four tab-local matching predicates, empty state, and scroll/focus behavior.
- `test/widget/codex_view_test.dart` — targeted widget tests for search and compact accessibility behavior.

**Already existing, read-only:** `lib/game/codex/codex_data.dart`, `lib/game/ui/orion_typography.dart`, `lib/game/ui/orion_ui_theme.dart`.

**No new Dart files, assets, packages, persistence fields, or abstractions.**

## Task 1 — Pin existing behavior with tests (same PR)

Before changing the widget, extend `test/widget/codex_view_test.dart` with scoped test groups:

1. Empty search is no-op: Towers still shows Laser; switching to Enemies/Effects/Stages renders their existing content.
2. Tower match by name and **specialization** (`Pulse Laser`) even with `'  pUlSe lAsEr  '`; parent Laser card remains while an unrelated tower card is absent.
3. Enemy trait search (e.g. `shielded`) filters both trait glossary and enemy cards, while the separator is displayed only when both matching groups exist; query matching only a role should omit the glossary separator.
4. Effect search by title and a **related specialization label**; stage search by name and a known stage-modifier title.
5. A nonexistent query shows the explicit empty state, not a blank list. Clear icon restores the current full list.
6. Switching from a filtered section to another clears the query; unfiltered tab-to-tab navigation retains each tab's scroll offset. Typing or clearing a search resets only that section's scroll offset.
7. In a 320×568 logical viewport with increased text scaling, enter text/clear/switch tabs and assert no exception/overflow; confirm accessible search label and Clear tooltip.

Keep assertions on existing `find.text` labels and actual returned entries, not implementation-only private helpers. Avoid unnecessarily large fake datasets.

## Task 2 — Add the smallest search state and UI

In `_CodexViewState`:

1. Add one `TextEditingController`; dispose it along with existing scroll controllers.
2. Insert a compact `TextField` beneath the wrapping chips and above `Expanded(child: _body())`. Label/hint uses the active section name (e.g. `Search towers`); prefix search icon and a suffix Clear control (only for nonempty text) use existing Material icons. Keep a minimum comfortable touch target.
3. Normalize query with `trim().toLowerCase()`, and define a tiny local match helper accepting a list/iterable of authored strings. No `ChangeNotifier`, new widget architecture, search package, service, or state management library.
4. A single `_applySearchChange()` helper performs `setState` and, if the **current** controller is attached, `jumpTo(0)`. Wire both `onChanged` and Clear explicitly (controller edits do not call `onChanged`).
5. On a new section choice, call `FocusScope.of(context).unfocus()`, `_searchController.clear()`, then change `_section`. When no search was active, do not reset any controller; the pre-existing per-tab scroll behavior remains.

Run the narrow widget test group.

## Task 3 — Filter the existing tab lists (no data duplication)

Change only `_body()`; reuse card builders without altering their content:

1. Towers: filter `CodexData.towers` against tower label and specialization label/description; when a specialization matches, render the whole tower card.
2. Enemies: separately filter `CodexData.traits` (label/effect) and `CodexData.enemies` (label/role/trait labels). Add a divider **only if both groups are nonempty**; render the empty state if both are empty.
3. Effects: filter `CodexData.effects` by title, description, and related specialization labels; keep the existing `Card` widget tree.
4. Stages: filter `CodexData.stagesFor(widget.progress)` by stage name/map label/description and modifier titles. Keep status and reward rendering unchanged.
5. For each tab, if there are zero matches with nonempty query, render one accessible `No matches in [section]` message in the expanded content area. No additional state source.

Run `flutter test test/widget/codex_view_test.dart`.

## Task 4 — Final regression and delivery

1. `dart format --output=none --set-exit-if-changed .`
2. `flutter analyze`
3. `flutter test --coverage` (project's 90% Codecov threshold must hold)
4. `flutter build web --release`
5. Verify Codex from the world map on a portrait viewport, including a search for a specialization followed by clearing and switching tabs.
6. Add implementation/tests on **this draft PR**, update its checklist, and request owner review. Do not create a second PR or mark ready before review.

## Not in this ticket

Global search, query persistence, new game information, codex unlock changes, cross-screen navigation, analytics, cloud services, fuzzy search/ranking, art, SFX, new settings, and any HPA-715 work.
