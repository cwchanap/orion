# HPA-924 — Last Hearth character art pack (Implementation Plan)

Date: 2026-11-21  
Ticket: https://linear.app/cwchanap/issue/HPA-924/orion-produce-the-last-hearth-character-art-pack  
Design: [HPA-924 character art pack](../specs/2026-11-21-hpa-924-character-art-pack-design.md)  
Baseline: `main` @ `3616b232425bf340ea63d1e0a609b25ba3ac66b2` (HPA-922 and HPA-923 merged)

**PR policy: one PR for this one art ticket.** This draft starts with design and plan only. Produce the art, contact sheet, validation evidence and any design-review fixes on this same branch/PR; never create a separate implementation PR. Steps below are working checkpoints, not PR boundaries.

## Scope guard

HPA-924 is an **asset-production** task, not an art + coding task. There is no Dart or game-UI implementation in this PR. HPA-925 owns enemy/board art, HPA-927 sound, HPA-926 final character-asset wiring/retheme. Do not regenerate existing approved art gratuitously. The existing 12 per-ID folder manifest entries, 24 `portrait.png`/`chibi.png` files and `OrionArt` paths are already in main: implement the ticket as **reuse/retouch/optimize 24 existing images + add 12 missing face images**, with replacements only when needed.

The HPA-924 ticket uses the names “card / face / chibi”; this repository uses **`portrait.png` for the card**. Final convention: `portrait.png` 1024 × 1536, `face.png` 512 × 512, `chibi.png` 512 × 512 RGBA, under `assets/images/characters/{Character.name}/`. Do not add `card.png` or change Flutter paths. Every image remains PNG because the existing contract and loader require those extensions. Do not change `pubspec.yaml` unless the current directory entries disappear.

## Checkpoint 1 — Input audit and keep/redo decisions

Inputs: HPA-924's attached **approved concepts + chibi + prompts ZIP**, HPA-921's approved lineup/chibi sheet and the files on `main`. The approved ZIP is a production source, **not** something to add verbatim to the repository.

1. Inspect the two existing files for every ID: `haruto`, `mio`, `sayo`, `tetsuo`, `rin`, `kaito`, `elena`, `shiori`, `akane`, `ren`, `hikari`, `jin`.
2. Verify real dimensions, alpha transparency and visual identity against the matching source concept (not just that the PNG opens). Pay special attention to transparent chibi exterior, uncropped limbs, hair/outfit consistency and detail at 48px. Check C/B/A/S effect hierarchy without changing the approved designs.
3. Record **keep / optimize / retouch / regenerate** for each current portrait and chibi, with specific failure reasons. The existing **24 images total ~21.14 MiB**, so record each asset's bytes for before/after comparison.
4. Confirm the HPA-924 ZIP is accessible locally and identify per-character prompt keys (`e1-haruto-sakaki`, etc.) by name; map them to the canonical `Character.name` IDs. Keep the image references local/private, and do not print, export or commit credentials.

**Gate:** a 12-character audit table has no unresolved identity or source mapping. **Do not** start a new batch of API generation when approved files already pass.

## Checkpoint 2 — Deliver 12 square face portraits

Paths: `assets/images/characters/{id}/face.png` (new).

1. Use the approved `portrait.png`/source concept to crop or reframe a **512 × 512** view with readable eyes, hair silhouette and shoulders. Keep a little space around hair and avoid a crop of the existing chibi. Use local image tooling; no production dependency required.
2. At **40 logical px** on dark and light UI mock backgrounds, compare to the lineup for recognizable identity and clean contrast. If the existing source cannot produce a legible crop, generate a **reference-conditioned** face variant using the approved image and the character's prompt; use the image model named in HPA-924 when it is available. Do not invent a new outfit.
3. Keep PNG extensions, final size and filenames deterministic. No additional `face_alt` or unused export variants in the app's asset directories.

**Gate:** all 12 `face.png` files decode at 512 × 512 and are visually distinct at 40px on the contact-sheet preview. These files will be **unreferenced by today's game UI** until HPA-926; that is intentional.

## Checkpoint 3 — Finalize and optimize the 24 currently bundled assets

Paths: `assets/images/characters/{id}/portrait.png` and `chibi.png` (in place).

1. **Keep** image data unchanged when the approved portrait/chibi already meets the spec. For failing images, retouch or generate an approved-reference-conditioned replacement; preserve the approved stylish outfits. Hikari, Akane, Mio and Kaito retain summer designs.
2. Keep portraits exactly **1024 × 1536 PNG**, full-frame, and chibis exactly **512 × 512 RGBA PNG**, with non-opaque exterior. Character/effects must be fully in frame and visibly legible at 48px. The current `OrionArtDescriptor` takes the whole sprite image; **do not rely on a source-rect crop or new code**.
3. Optimize PNG bytes (lossless first, optional palette reduction only after same-size visual inspection). HPA-924's **~200 KB card** is a soft target; current portraits are ~1–2.2 MiB. Do not lower resolution, change to WebP or produce perceptibly degraded images just to satisfy a nominal limit. Report sizes and trade-offs.
4. Re-run the exact HPA-922 character-art contract after replacements, especially 12 directory registration, path names, 1024 × 1536/512 × 512 dimensions and RGBA chibis. Existing Camp and battle rendering must continue using the same paths.

**Gate:** all 24 current-path images are final or intentionally retained approved originals, contracts pass, no Dart diffs.

## Checkpoint 4 — Provenance, asset inventory and contact sheet

Create:
- `assets/images/characters/provenance.json` (36 records, keyed by ID/role/path; source reference, approved/reused/cropped/generated method, source hash/identifier, exact generation prompt and model when applicable, output hash).
- `docs/superpowers/validation/2026-11-21-hpa-924-character-art.md` (audit table, before/after sizes, validation commands/results, browser screenshot links, and deviations).
- A **single contact-sheet image** linked by the validation note, with all 36 finals plus representative 40px face and 48px chibi checks on dark/light backgrounds. Store a suitably sized artifact under `docs/superpowers/validation/hpa-924-evidence/`, without embedding full source concepts.

For unchanged or locally cropped images, record **no model generation** rather than guessing a model name. Reference the approval source through the stable Linear ticket and attachment title, not expiring signed URLs. Do not commit the ZIP, staging files, private keys, disposable candidates or local source-path secrets. If generation was used, preserve prompt text/model with provenance for reproducibility.

**Gate:** there are exactly 36 final playable image files; one provenance entry per file; contact sheet demonstrates all 12 identities and visual size checks.

## Checkpoint 5 — Automated acceptance, then MCP browser E2E

**Local checks on the final asset tree:**

1. Run a one-off image audit (local Python/Pillow or equivalent; no new production library) enumerating `Character`'s 12 IDs and exactly the three required image filenames per directory. Assert PNG decode, precise dimensions, chibi RGBA **and actual transparent pixels**, and the existence/uniqueness of all 36 provenance entries. Print sizes and total bytes. Keep the audit result in the validation note. The existing repository test covers only 24 images, so this independent face/provenance audit is necessary.
2. Run `flutter test test/game/character_art_contract_test.dart`, `flutter analyze`, `flutter test`, and `flutter build web --release`. Existing `pubspec.yaml` registration must bundle the new face PNGs without a manifest edit; confirm their paths appear in the built asset manifest. No Dart change or native platform-specific code.
3. Check the branch diff: only final image replacements/additions, provenance, documentation/contact-sheet evidence. No game code, no source ZIP.

**MCP-driven end-to-end visual acceptance (required):**

1. In an isolated Chrome/Flutter-web session via MCP, run the real game: **title → Camp → Haruto sheet → Map/Stage 1 briefing → deploy Haruto and Mio**. Inspect the in-game portrait and chibi source, confirm no broken/fallback images, and reload to verify asset loading again. The MVP flow need not force a campaign victory since mechanics and saves are unchanged.
2. Capture **390 × 844** (standard portrait) and **320 × 568** (compact) screenshots of Camp, sheet and battle; capture the contact-sheet page with 40px faces and 48px chibis on dark/light backgrounds through MCP as well.
3. Compare screenshots with **HPA-921/HPA-924 approved concepts** and **HPA-922 mockups 10/11/14/15**, checking identity, 2.5-head chibi silhouette, hairstyle/outfits (including summer four), rank effects, facial recognizability, clipping, layout and readable contrast. Write observed discrepancies and fixes in the validation note; do not claim visual parity on the basis of passing image-header tests alone.
4. Use **one browser platform**, as this is an asset-only cross-platform change. Do not add a native acceptance gate. No manual/human approval criterion.

**Final gate:** automated checks and the MCP browser flow pass on the final PR head, and screenshots/contact sheet are discoverable in the PR.

## Acceptance checklist (end to end)

- [ ] 12 IDs × (`portrait.png`, `face.png`, `chibi.png`) = **36** final valid PNGs; 24 existing runtime paths/dimensions remain stable; all chibis transparent and full-body.
- [ ] Visual sheet at full/tiny size demonstrates all 36 and preserves approved identities, rank cues and summer/v2 outfits.
- [ ] Per-file provenance, final hashes, source/prompt references and before/after sizes are recorded without exposing credentials or committing original source ZIP.
- [ ] All existing Flutter art/asset tests, analyzer, full tests and web build pass; no Dart/gameplay diff.
- [ ] **MCP E2E** checks real Camp, sheet and battle after reload; screenshot visual check at both viewports is compared to Linear references and documented. Face art (not yet in UI) is checked on the contact-sheet page.
- [ ] All subsequent implementation assets/evidence land in **this same HPA-924 draft PR**. HPA-925/926/927 stay separate.

## Review focus

1. Accept mapping `card` → existing runtime `portrait.png`, avoiding a fourth image or new Dart loader.
2. Accept reuse/optimization of already-approved HPA-922 files, regenerating **only** demonstrated failures.
3. Accept preserving required PNG dimensions/paths over forcing a 200 KB card cap, with transparent recorded size exceptions.
4. Confirm HPA-926 alone will wire `face.png` into the UI; HPA-924 adds it as an independent art asset and validates it visually via contact sheet.
