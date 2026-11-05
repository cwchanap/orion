# HPA-753 — Search the Codex without scrolling

**Linear:** [HPA-753](https://linear.app/cwchanap/issue/HPA-753/orion-find-codex-entries-without-scrolling)  
**Status:** Revised after owner review (November 4); design-only draft PR  
**Scope:** Flutter Codex UI; independent from HPA-715 Endless Mode

## Problem and player value

The Codex has four section chips (Towers, Enemies, Effects, Stages). Each tab currently builds an unfiltered `ListView` of detailed cards in `lib/game/ui/codex_view.dart`. A player checking a specialization, trait, mechanic, or stage while learning the game must scroll long lists on a portrait screen.

The data is already available in `lib/game/codex/codex_data.dart`: eight towers with 16 specializations, nine enemy archetypes and five trait entries, an effect glossary, and seven stages. We only need to make it discoverable. No game rules or content need changing.

## Decision

Add **one local search field immediately below the section chips**. Search filters **the active section only**. It is a straightforward trimmed, case-insensitive substring match over already-authored labels and prose, with no indexing, fuzzy ranking, shared search service, navigation changes, or persistence.

This design keeps the existing four-section interaction, Codex cards, and status visibility. **Current bug:** the four section `ListView`s are unkeyed, so switching sections can carry the previous section's scroll pixels into the next section and discard its prior offset. Add `PageStorageKey<int>(_section)` to each list and test retention before search work. Use one `TextEditingController` in `_CodexViewState`; put pure search terms and the single match helper beside the existing Codex entry types in `codex_data.dart`.

## Interaction contract

1. Opening Codex still defaults to Towers with every tower card visible, with an empty field labelled **Search towers**.
2. Typing a query filters the active tab immediately. Normalize with `trim().toLowerCase()`. Match the **whole resulting string** as one substring, including spaces (no token ranking).
3. Whitespace-only input is equivalent to no query: all items remain. A clear icon is available when the input is nonempty and restores the full current section with one tap.
4. Switching a chip clears the query and dismisses the keyboard, so the newly selected tab shows its full list. With a section-specific `PageStorageKey<int>(_section)`, switching **without** a query preserves each section's scroll offset (fixing current behavior); applying or clearing search scrolls only the active section to the top. This deliberately keeps search local to the active section instead of silently carrying an old filter to a new tab.
5. When there are no matches, replace the list body with a short, readable **No matches in [section]** state. The persistent search field and clear icon remain accessible.
6. Keep the current `Card` rendering and authored stats unchanged. This is a discoverability improvement, not a redesign.

### Search fields by section

| Section | Searchable text | Display behavior |
| --- | --- | --- |
| Towers | `CodexTowerEntry.label`, each specialization's `label` and `description` | Matching a specialization shows its **whole parent tower card**; do not hide other specializations within it. |
| Enemies | `CodexEnemyEntry.label`, `roleDescription`, trait `label`s; each glossary `CodexTraitEntry.label` and `effect` | Filter glossary rows and enemy cards independently. Show the separator **only if both groups have results**; zero results across both groups shows the empty state. |
| Effects | `CodexEffectEntry.title`, `description`, each related specialization's `label` | Matching an effect or its related specialization shows the whole effect card. |
| Stages | `CodexStageEntry.stage.name`, `mapLabel`, `description`, and existing modifier **`title` and `description`** | Matching shows the whole stage card, including its real locked/unlocked/cleared state and reward information. |

Search authored entry labels, roles, and descriptions shown on the cards, including the stage modifier description (not just its title). Do not match generated numeric stats, computed reward values, UI field keys, or dynamic progress labels (e.g. searching "Locked" should not match all locked stages). Keep `CodexData` as authority; the `searchTerms` accessors are derived from the existing fields, not a copied search index.

### Visual and accessibility behavior

- Reuse the existing Codex column: header → four wrapping section chips → compact search field → `Expanded` scrolling content. No fixed-height card area or new overlay.
- Use standard Material `TextField`/`InputDecoration` with search icon, context-specific accessible label, clear icon with a tooltip/semantic label, and a touch-sized target. Match existing `OrionUiTheme` colors and `OrionTypography` roles; do not add a typography size.
- Do not hide section chips while the keyboard is up. At 320×568 with a 260px keyboard inset, 2×/3× text scaling currently overflows the top chrome even before search. Wrap **only** the header, chips and new field with `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.15, child: ...)`, using the repo's existing compact-chrome pattern; keep `Expanded(child: _body())` **outside** that wrapper so Codex cards retain the user's full text scale. Optional: dismiss the keyboard on list drag (`keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag`). Test the actual keyboard inset, not just a small surface.
- Do not announce duplicate search labels through nested `Semantics`; a single readable field label is enough. Empty state should be discoverable by screen reader.
- The current four scroll controllers remain owned/disposed by `_CodexViewState`; dispose the new text controller too.

## Implementation sketch

The small implementation spans two existing production files:

- **`codex_data.dart` (pure Dart):** add `Iterable<String> get searchTerms` on the five searchable top-level entry types (`CodexTowerEntry`, `CodexEnemyEntry`, `CodexTraitEntry`, `CodexEffectEntry`, `CodexStageEntry`), deriving terms from their existing labels/descriptions, and one `codexMatches(String query, Iterable<String> terms)` helper that trims and lowercases query and terms. An empty/whitespace-only query matches all entries. No new interface hierarchy or copy of the data.
- **`codex_view.dart` (Flutter):** first key each section's existing `ListView` with `PageStorageKey<int>(_section)` to repair per-tab scrolling; keep `int _section` and the current four controllers.
- Add one `TextEditingController _searchController` and dispose it. Derive the active query from the controller; use the five `searchTerms` getters and `codexMatches` to filter small view-local lists in `_body()`, without caching or altering the card builders.
- Clamp text scaling to 1.15 **only for the header/chips/search field** using `MediaQuery.withClampedTextScaling`; the scrolling cards stay outside this wrapper at full text scale. Keep compact layouts keyboard-safe.
- `onChanged` and the clear icon use one helper that rebuilds the Codex view and resets the **active** controller to zero when attached. Programmatic `clear()` does not trigger `onChanged`.
- Chip selection clears the query and unfocuses the input without resetting other sections' controllers. Switching without a search preserves independent offsets with the new list keys.

Keep `_towerCard`, `_enemyCard`, `_stageCard`, the effect card, and the data contents unchanged.

No external service, dependencies, save fields, database, new game mode, art, or sound.

## Edge cases deliberately kept simple

- Trim surrounding whitespace, case-insensitively match ASCII and existing text via `toLowerCase()`; no locale-aware folding or typo correction.
- Empty query displays the exact existing Codex content and ordering.
- Match a specialization via its parent tower or a trait through its existing enemy or glossary entry; do not flatten the sections.
- No persistence of search query across Codex visits. Leaving/backing out of the Codex retains existing navigation behavior.
- No cross-tab result counts, sorting, autocomplete, highlighted substrings, favorites, or search history.

## Acceptance and testing

1. Default Codex tabs, card content, and scene navigation continue to match existing tests.
2. Towers: typing a specialization name (e.g. "pulse laser") finds its parent tower; case and surrounding whitespace do not matter. Negative assertions must name an **unfiltered, initially built** item (e.g. a search for "gravity" removes the first Laser card), not an offscreen lazy-list item whose absence proves nothing. Use a tall surface or scroll for distant positive matches.
3. Enemies: typing a trait (e.g. "shielded") finds the glossary description and corresponding enemy; the separator appears only when both groups match.
4. Effects and Stages: matches include related specialization names and stage/modifier **titles and descriptions** respectively. Pure unit tests exercise each top-level entry type's terms and the matcher, including that "locked" does not accidentally match dynamic stage status.
5. Unmatched text renders the empty state; Clear restores all entries. Verify that scroll positions are **broken on current unkeyed lists** and fixed by keying them: scroll Towers down, switch to Enemies (begins at zero), then return to Towers (previous offset retained). Switching tabs clears active search without destroying unrelated offsets.
6. Search field, clear action, and no-results state have usable semantics and no overflow at **320×568**, both **2× and 3× text scaling**, and `tester.view.viewInsets = const FakeViewPadding(bottom: 260)` simulating the open keyboard. Keep card text at full scale.
7. `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test --coverage` (90% Codecov gate), and `flutter build web --release` pass after implementation.

## Explicit non-goals

Changes to existing Codex authored content or stats, game balance, unlock rules, world map, mission HUD, Endless Mode (HPA-715), persistence, analytics, cloud search, fuzzy matching, search navigation from gameplay, art/SFX/music, and any new package. Pure `searchTerms` getters and `codexMatches` in `codex_data.dart` are in scope.

## Delivery

**One ticket, one PR.** This branch initially contains **only** design spec and implementation plan. Following review, put the implementation and tests on **this same PR**. Do not open a separate implementation PR.
