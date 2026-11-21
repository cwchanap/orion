# HPA-924 — Last Hearth character art pack (Design Spec)

Date: 2026-11-21  
Linear: https://linear.app/cwchanap/issue/HPA-924/orion-produce-the-last-hearth-character-art-pack  
Parent direction: https://linear.app/cwchanap/issue/HPA-921/orion-pivot-to-last-hearth-an-anime-character-tower-defense  
Follow-on integration: HPA-926  
Baseline: `main` at `3616b232425bf340ea63d1e0a609b25ba3ac66b2`

## Outcome and scope

Ship **36 final in-game character images** for the 12 approved Last Hearth characters: a portrait/card, square face, and transparent chibi for each. Reuse the approved character concepts and chibi samples wherever they already meet the quality bar; regenerate or retouch only failing images. This is an **asset-only ticket**, one PR. No Dart, rendering, navigation, gameplay, balance, UI layout, or new SFX. HPA-925 owns enemies/boards, HPA-927 owns audio, and HPA-926 owns the winter retheme and any future face-image UI wiring.

## Verified repository baseline (not the stale ticket assumptions)

- `assets/images/characters/{id}/` already exists for all 12 IDs and contains `portrait.png` (1024 × 1536) and `chibi.png` (512 × 512), **24 images already in main**. Total current size: approximately **21.14 MiB**. There are no `face.png` files.
- `pubspec.yaml` already lists **all 12 character directories**. Do **not** add a duplicate entry or modify the manifest unless this baseline actually changes.
- `lib/game/ui/orion_atlas_sprite.dart` loads **`characters/{character.name}/portrait.png` and `chibi.png`** through `OrionArt`; both descriptors use the entire image. These paths are used by the existing Camp, character sheet, dock and battle surfaces.
- `test/game/character_art_contract_test.dart` already pins all 12 IDs, both canonical paths, dimensions, RGBA PNG format for chibis, full-frame cropping and manifest registration. **Keep these contracts intact.** It does not currently check face assets.
- The existing images are approved HPA-922 concept placeholders, not proof that all three production variants or size targets have been met. HPA-922 and HPA-923 are merged; HPA-926 remains blocked by this and the other asset tickets.

## Canonical outputs (no parallel names)

| User-facing role | Exact path in each `assets/images/characters/{id}/` | Requirements |
| --- | --- | --- |
| Card / full-body portrait | `portrait.png` **(reuse existing filename, not `card.png`)** | 1024 × 1536 PNG, full body, 2:3 portrait, clean silhouette and usable contrast in a dark Camp/character-sheet UI; preserve approved identity |
| Face / squad thumbnail | `face.png` **(new)** | 512 × 512 square PNG, face plus distinctive hair and upper shoulders, recognizable and legible at 40 logical px, no name/rank text baked into the pixels |
| On-board character | `chibi.png` **(reuse existing filename)** | 512 × 512 RGBA PNG with real transparent exterior, full body, three-quarter-front idle pose, about 2.5 heads tall, readable at 48 logical px against both dark and snow/light backgrounds |

Exactly 12 IDs, derived from the `Character` enum (no new ID mapping): `haruto`, `mio`, `sayo`, `tetsuo`, `rin`, `kaito`, `elena`, `shiori`, `akane`, `ren`, `hikari`, `jin`. Exactly **36 final images**. Provenance and contact sheets are supporting documents, not extra game-image variants. Keep the current on-disk image dimensions to avoid any rendering or Dart changes.

**Why `portrait.png` instead of `card.png`:** HPA-924 calls the first deliverable a “card,” while the shipped HPA-922 loader and asset contract already require `portrait.png`. Treat “card” as its presentation role; do not add a duplicate and do not require HPA-926 to reconcile two paths.

## Art direction and approved inputs

- Source of truth: the approved HPA-924 full-size ZIP (including `character-prompts.json`), HPA-921 approved lineup and chibi sheet, and HPA-922 existing 24 PNGs. Match individual characters' hair, face, outfit and colours; match the approved crisp, cel-shaded anime linework across the cast.
- **Summer outfits:** `hikari`, `akane`, `mio` and `kaito` retain the approved summer designs. The other eight retain the approved stylish v2 outfits; do not replace them with bulky winter gear. All characters are adults and modestly dressed.
- Rank cues in the artwork: E/D restrained/plain, C/B subtle glow, A/S stronger ability effects, without obscuring small sprites. Leave readable rank labels to the existing UI; never bake labels into the images.
- Start with a **12 × 2 existing-asset audit**, comparing each current portrait/chibi to the approved ZIP. Keep matches and optimize losslessly first. Generate a new take with an approved per-character reference **only** where composition, transparency, fidelity or small-size readability fails. Avoid unrelated redesign or spending 24+ image-generation calls without evidence.
- Produce `face.png` by a carefully placed crop/reframe of the approved high-resolution portrait when that preserves the character's face/hair; use reference-conditioned generation only for faces that cannot make a legible crop. Never crop an existing 512px chibi for a face portrait.
- Chibi sheets from the ZIP are references, **not** runtime atlas files. Final exports must be independent per-ID PNGs, centered and scaled so limbs/effects stay within the frame with limited unused transparent padding.

## File size and provenance

- HPA-924 suggests **about 200 KB per card**; the existing 1024 × 1536 PNG portraits are currently approximately 1–2.2 MiB each. Treat 200 KB as a **best-effort optimization target**, not permission to lose approved detail or change runtime file extensions. Try metadata stripping, lossless PNG optimization and tasteful indexed palette reduction only if visual quality remains intact. Record before/after bytes and any justified outliers in the PR.
- Add `assets/images/characters/provenance.json`, one entry for **each of the 36 final images**: character ID, role/path, whether approved/reused/cropped/retouched/generated, approval reference, source image identifiers or hashes, transformation, and generator/model + prompt text when generation actually occurred. For non-generated crops, record the crop/source rather than inventing a model call. Reference the Linear ZIP without committing original work files, a private source archive, API keys or machine-specific paths.
- If a current approved file is carried over unchanged, its provenance should say so; do not relabel it as newly generated.

## Visual validation contract

The full-size approved lineup and chibi reference in HPA-921/HPA-924, and the HPA-922 UI mockups **10 Camp**, **11 character sheet**, **14 briefing**, **15 battle**, are the visual references. A single contact sheet must show all 36 outputs at normal and tiny UI sizes, including a 40px face and 48px chibi on both dark and light backgrounds; also show the 12 identities with clear IDs. Save a before/after size summary and explain substantive changes.

After asset replacement, perform an **MCP-driven web E2E** (Chrome; one platform suffices because there is no platform-specific code): open title → Camp roster → starter character sheet → stage briefing → deploy Haruto and Mio in Stage 1 → observe chibis on the real board → return/reload and verify art remains loaded. Capture **390 × 844** and **320 × 568** screenshots. Compare the captures with the attached approved mockups, checking identity, silhouette, contrast, small-sprite legibility, no crop/overflow, rank distinction and absence of broken/fallback art. The new `face.png` is intentionally **not wired to UI yet**; inspect it via the contact-sheet browser page instead. Record MCP evidence and deviations in a committed validation note.

## Acceptance criteria (automation/evidence, not human approval)

1. The 12 canonical folders contain exactly `portrait.png`, `face.png` and `chibi.png` as playable art; all **36 PNGs** decode, meet the dimensions above, and chibis have non-opaque background pixels while retaining full-body coverage. Validate by an executable local asset-audit command; attach its output summary.
2. Existing `OrionArt` paths and the 24-file Flutter asset contract pass unchanged; `pubspec.yaml` remains correct without a redundant edit. `flutter analyze`, `flutter test` and `flutter build web --release` pass on the final branch.
3. The approved appearance/seasonal outfits are represented in a committed 36-image contact sheet, with small-size previews (40px faces, 48px chibis) on dark and light backgrounds, and a provenance record for every asset. No secrets or source ZIP are committed.
4. **MCP Chrome E2E** opens real Camp, character sheet and battle paths and confirms portrait/chibi rendering after reload. Screenshots at both specified viewport sizes are compared to the approved Linear art/mockups with a factual discrepancy log. No native test is required for this asset-only, cross-platform change.
5. One draft PR for HPA-924 holds planning documents, eventual art, evidence and fixes. No art generation or game-code implementation for HPA-925/926/927 is included; no separate implementation PR.

The final creative sign-off can be a follow-up conversation, but **it is not an acceptance gate**; the checklist above is the completion contract.
