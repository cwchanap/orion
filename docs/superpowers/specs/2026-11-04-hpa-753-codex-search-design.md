# HPA-753 — Search the Codex without scrolling

**Linear:** [HPA-753](https://linear.app/cwchanap/issue/HPA-753/orion-find-codex-entries-without-scrolling)  
**Status:** Proposed for owner review, design-only draft PR  
**Scope:** Flutter Codex UI; independent from HPA-715 Endless Mode

## Problem and player value

The Codex has four section chips (Towers, Enemies, Effects, Stages). Each tab currently builds an unfiltered `ListView` of detailed cards in `lib/game/ui/codex_view.dart`. A player checking a specialization, trait, mechanic, or stage while learning the game must scroll long lists on a portrait screen.

The data is already available in `lib/game/codex/codex_data.dart`: eight towers with 16 specializations, nine enemy archetypes and five trait entries, an effect glossary, and seven stages. We only need to make it discoverable. No game rules or content need changing.

## Decision

Add **one local search field immediately below the section chips**. Search filters **the active section only**. It is a straightforward trimmed, case-insensitive substring match over already-authored labels and prose, with no indexing, fuzzy ranking, shared search service, navigation changes, or persistence.

This design keeps the existing four-section interaction, Codex cards, status visibility, and per-section `ScrollController` instances. A single `TextEditingController` + small matching helper inside `_CodexViewState` is sufficient.

## Interaction contract

1. Opening Codex still defaults to Towers with every tower card visible, with an empty field labelled **Search towers**.
2. Typing a query filters the active tab immediately. Normalize with `trim().toLowerCase()`. Match the **whole resulting string** as one substring, including spaces (no token ranking).
3. Whitespace-only input is equivalent to no query: all items remain. A clear icon is available when the input is nonempty and restores the full current section with one tap.
4. Switching a chip clears the query and dismisses the keyboard, so the newly selected tab always opens with its full list. Switching tabs with no query must continue preserving the independently owned scroll positions; searching or clearing scrolls the active tab to its start.
5. When there are no matches, replace the list body with a short, readable **No matches in [section]** state. The persistent search field and clear icon remain accessible.
6. Keep the current `Card` rendering and authored stats unchanged. This is a discoverability improvement, not a redesign.

### Search fields by section

| Section | Searchable text | Display behavior |
| --- | --- | --- |
| Towers | `CodexTowerEntry.label`, each specialization's `label` and `description` | Matching a specialization shows its **whole parent tower card**; do not hide other specializations within it. |
| Enemies | `CodexEnemyEntry.label`, `roleDescription`, trait `label`s; each glossary `CodexTraitEntry.label` and `effect` | Filter glossary rows and enemy cards independently. Show the separator **only if both groups have results**; zero results across both groups shows the empty state. |
| Effects | `CodexEffectEntry.title`, `description`, each related specialization's `label` | Matching an effect or its related specialization shows the whole effect card. |
| Stages | `CodexStageEntry.stage.name`, `mapLabel`, `description`, and existing modifier `title`s | Matching shows whole stage card, including its real locked/unlocked/cleared state and reward information. |

Do not match generated numeric stats or dynamic progress labels (e.g. searching "Locked" should not match all locked stages). Keep the content/data source `CodexData` as authority.

### Visual and accessibility behavior

- Reuse the existing Codex column: header → four wrapping section chips → compact search field → `Expanded` scrolling content. No fixed-height card area or new overlay.
- Use standard Material `TextField`/`InputDecoration` with search icon, context-specific accessible label, clear icon with a tooltip/semantic label, and a touch-sized target. Match existing `OrionUiTheme` colors and `OrionTypography` roles; do not add a typography size.
- Do not hide section chips while the keyboard is up. Let the existing `Expanded` list shrink naturally. Keep the field readable on a 320×568 logical viewport and with increased system text scaling.
- Do not announce duplicate search labels through nested `Semantics`; a single readable field label is enough. Empty state should be discoverable by screen reader.
- The current four scroll controllers remain owned/disposed by `_CodexViewState`; dispose the new text controller too.

## Implementation sketch

In `CodexView` only:

- Keep `int _section` and `_scrollControllers`; add one `TextEditingController _searchController`, and derive `query = _searchController.text.trim().toLowerCase()` when building.
- A tiny `_containsAny(query, Iterable<String> values)` helper handles shared case-insensitive substring matching. The per-section predicates select only the fields above; no new generic search model.
- Compute filtered view-local lists from `CodexData` in `_body()` (this content is tiny). Reuse `_towerCard`, `_enemyCard`, `_stageCard`, and current effect-card widget tree unchanged.
- `onChanged` rebuilds only the Codex view and resets the **active** controller to offset zero when attached. Clear uses `_searchController.clear()` plus the same rebuild/reset path (programmatic clear does not trigger `onChanged`).
- Chip selection clears the query and unfocuses input without altering another section's controller.

No external service, dependencies, save fields, database, new game mode, art, or sound.

## Edge cases deliberately kept simple

- Trim surrounding whitespace, case-insensitively match ASCII and existing text via `toLowerCase()`; no locale-aware folding or typo correction.
- Empty query displays the exact existing Codex content and ordering.
- Match a specialization via its parent tower or a trait through its existing enemy or glossary entry; do not flatten the sections.
- No persistence of search query across Codex visits. Leaving/backing out of the Codex retains existing navigation behavior.
- No cross-tab result counts, sorting, autocomplete, highlighted substrings, favorites, or search history.

## Acceptance and testing

1. Default Codex tabs, card content, and scene navigation continue to match existing tests.
2. Towers: typing a specialization name (e.g. "pulse laser") finds its parent tower; case and surrounding whitespace do not matter; another unrelated tower is filtered out.
3. Enemies: typing a trait (e.g. "shielded") finds the glossary description and corresponding enemy; the separator appears only when both groups match.
4. Effects and Stages: matches include related specialization names and stage/modifier names respectively.
5. Unmatched text renders the empty state; Clear restores all entries. Switching tabs clears active search without destroying unrelated scroll positions.
6. Search field, clear action, and no-results state have usable semantics and no overflow at 320×568 with increased text scaling.
7. `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test --coverage` (90% Codecov gate), and `flutter build web --release` pass after implementation.

## Explicit non-goals

Changes to `CodexData` itself, stats, game balance, unlock rules, world map, mission HUD, Endless Mode (HPA-715), persistence, analytics, cloud search, fuzzy matching, search navigation from gameplay, art/SFX/music, and any new package.

## Delivery

**One ticket, one PR.** This branch initially contains **only** design spec and implementation plan. Following review, put the implementation and tests on **this same PR**. Do not open a separate implementation PR.
