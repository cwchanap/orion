# HPA-753 — Codex Search Implementation Plan

**Linear:** [HPA-753](https://linear.app/cwchanap/issue/HPA-753/orion-find-codex-entries-without-scrolling)  
**Design authority:** [HPA-753 design](../specs/2026-11-04-hpa-753-codex-search-design.md)  
**PR policy:** One ticket = one PR. Start as documentation-only draft; add production code/tests to **this same PR** after owner reviews the plan.

## Verified baseline and review corrections

- `lib/game/ui/codex_view.dart` owns one `_section` index and four `ScrollController` instances, **but its section `ListView`s have no keys**. Switching tabs reuses a `Scrollable` element and carries the previous tab's pixel offset to the next tab, so existing per-tab scroll retention is **broken** despite the comment in the source. Verified in the review via a throwaway widget probe. A `PageStorageKey<int>(_section)` on each section list fixes it.
- Its `_body()` switch maps directly over `CodexData.towers`, `traits` + `enemies`, `effects`, and `stagesFor(progress)`; no filter or text field exists.
- `lib/game/codex/codex_data.dart` is pure Dart (no Flutter imports). The existing entry types have the labels and authored descriptions needed for search; `CodexStageEntry.modifiers` exposes both `title` and `description`, and the Codex card actually renders both.
- `test/game/codex/codex_data_test.dart` already exists for pure tests; `test/widget/codex_view_test.dart` covers tab navigation, numerical formatting, stage status/rewards, and a narrow viewport.
- Flutter's lazy `ListView` on the default 800×600 test viewport initially builds only the first few cards. A test that asserts an **offscreen** unrelated entry is absent can pass even if filtering is entirely broken.
- On 320×568 with the keyboard visible (260px bottom inset), a raw new `TextField` + full-size header/chips overflows at 2×/3× text scale. Follow the app's `MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15)` compact chrome convention, but clamp only the header/chips/search field, **not** the list cards.
- Codex entry is from the world map; HPA-715 Endless Mode does not touch the Codex. No save format or downstream API change.

## File map

**Modify four existing files (no new files):**

- `lib/game/ui/codex_view.dart` — section `PageStorageKey`, search field/controller, per-tab filtering/empty state/divider, keyboard-safe chrome, focus and scroll behavior.
- `lib/game/codex/codex_data.dart` — derived `searchTerms` getters on the five searchable top-level entry types and one pure `codexMatches` helper. No authored game data changes.
- `test/widget/codex_view_test.dart` — scroll-key regression, search wiring and lazy-list-safe assertions, keyboard inset and accessibility checks.
- `test/game/codex/codex_data_test.dart` — exhaustive small pure matching tests.

**Read-only:** `lib/game/ui/orion_typography.dart`, `lib/game/ui/orion_ui_theme.dart`, existing Codex card content and stage metadata.

**No new Dart files, assets, packages, persistence fields, services, or generic abstractions.**

## Task 0 — Fix the existing per-tab scroll regression (green on its own)

1. Add a focused widget regression to `test/widget/codex_view_test.dart`: on a short viewport, scroll Towers to a nonzero offset; tap Enemies and assert its scroll begins at zero; return to Towers and assert its prior offset is retained. **Read the section's controller offset via** `tester.widget<ListView>(find.byKey(const PageStorageKey<int>(0))).controller!.offset` (and key 1 for Enemies). Do not use `find.byType(Scrollable)`; once Task 2 adds `TextField`, its `EditableText` has another `Scrollable`.
2. Confirm the test fails on the current unkeyed lists.
3. Add `key: PageStorageKey<int>(_section)` to **each** section's `ListView` in `_body()`. Do not replace the existing four `ScrollController` instances.
4. Run `flutter test test/widget/codex_view_test.dart`; commit a separate small **commit**, not a separate PR.

## Task 1 — Pure matching terms and unit tests

1. Add pure tests in the **existing** `test/game/codex/codex_data_test.dart` for `codexMatches`: case-insensitive, trimmed whole-string substring; empty/whitespace matches all; unrelated text does not match. Use real `CodexData` entries for the five search categories.
2. Specifically assert:
   - **Towers:** each specialization name/role description can find its parent tower; matching `Pulse Laser` returns Laser.
   - **Enemies:** an enemy's label, authored role, or trait label can find it; glossary trait entries match their label **and effect description**.
   - **Effects:** effect titles, descriptions and related specialization labels match.
   - **Stages:** stage name/map label/description and **modifier title/description** match; `locked` does not match a dynamic stage status, and numeric stats/rewards are not search terms.
3. In `lib/game/codex/codex_data.dart`, add `Iterable<String> get searchTerms` to `CodexTowerEntry`, `CodexEnemyEntry`, `CodexTraitEntry`, `CodexEffectEntry` and `CodexStageEntry`. Derive terms directly from existing properties; do **not** copy or normalize them into a stored index.
4. Add one pure `codexMatches(String query, Iterable<String> terms)` helper that normalizes the raw query and each term with `trim().toLowerCase()`; empty query always returns true. No new class hierarchy or search service.
5. Run `flutter test test/game/codex/codex_data_test.dart`; commit.

## Task 2 — UI search, filtering, and valid widget assertions

1. Before implementing, extend `test/widget/codex_view_test.dart` with failing new-behavior tests. **Negative filtering assertions must inspect an entry that is visible without filtering.** Example: search for `gravity` and assert the first Laser card is **gone**; then assert Gravity Well appears. Use the existing tall test surface, `ensureVisible`, or scrolling for positive results further down lazy lists.
2. Test each tab's search wiring (not every term mapping already covered by unit tests): active section only, case-insensitive/trimmed match, parent tower card on a specialization match, independently filtered trait/enemy groups with divider iff both exist, effect/stage results, clear action, zero-results message, and tab switching. **Re-tapping the selected chip must retain its query and focus**; tapping a different chip clears the query.
3. Add a short-surface test at **320×568** with text scales **2× and 3×** and `tester.view.viewInsets = const FakeViewPadding(bottom: 260)` to simulate the software keyboard. Enter a query, clear it and switch tabs; assert no RenderFlex/overflow exception. Verify a single accessible search label, usable Clear tooltip, and no-results semantics. **Drag a populated list and a one-item empty-results list and confirm keyboard focus is dismissed.** Reset test view settings in teardown.
4. In `_CodexViewState`, add one `TextEditingController` and dispose it. Insert a `TextField` under chips with a search icon and optional Clear action. Make the placeholder reflect the selected section (e.g. `Search towers`).
5. Wrap **only the existing header, chip row and new field** with `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.15, child: ...)`; keep `Expanded(child: _body())` outside so card text scales fully. Use the same theme and typography roles, no new sizes or fixed-height list. **Require** `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag` on **all four** section `ListView`s; in zero-results mode use `const AlwaysScrollableScrollPhysics()` so dragging still works with content shorter than the viewport.
6. Filter each tab by calling `codexMatches(_searchController.text, entry.searchTerms)` on the entry objects; retain unchanged whole-card builders. Enemies filters trait glossary and enemy cards independently and shows the divider only when both sets are nonempty. With zero results, **do not swap out the active `ListView` for a `Center`**: render a padded `No matches in [section]` as its sole child, retaining the **same** `PageStorageKey<int>(_section)`, controller and drag-to-dismiss behavior. For this case set `const AlwaysScrollableScrollPhysics()` to ensure the drag is recognized.
7. Route both `onChanged` and programmatic Clear through one setState/scroll-reset helper (the latter does not call `onChanged`). Scroll the active controller to zero **only when `controller.hasClients`** to prevent `jumpTo` failures during transient detachment. On chip tap, **guard `if (_section == index) return;`** before clearing search or unfocusing; only a different section clears the search. Never reset another tab's unfiltered scroll offset.
8. Run `flutter test test/widget/codex_view_test.dart` and both Codex test files; commit.

## Task 3 — Full verification and same-PR delivery

1. `dart format --output=none --set-exit-if-changed .`
2. `flutter analyze`
3. `flutter test --coverage` (project's 90% Codecov threshold must hold)
4. `flutter build web --release`
5. From the world map, verify the portrait Codex field and match → Clear → switch behavior, including a specialization name, stage modifier description, compact keyboard-open viewport, independent tab scrolling, drag-to-dismiss even for empty results, and active-chip re-tap retaining the search.
6. Push the implementation and tests onto **this same draft PR**, update its checklist, and request owner review when green. Do not create a second implementation PR or mark ready before review.

## Owner decision — query on tab switch

Keep **clear on section switch**. The ticket intentionally makes search local to one current section, so a new section always opens in the full-list state. Preserving the same keyword across tabs (e.g. `shield`) is a reasonable alternative but would change the already documented behavior and can make tabs initially show zero results. Revisit only if player feedback warrants it.



## Not in this ticket

Global search, query persistence, new game information, codex unlock changes, cross-screen navigation, analytics, cloud services, fuzzy search/ranking, art, SFX, new settings, and any HPA-715 work.
