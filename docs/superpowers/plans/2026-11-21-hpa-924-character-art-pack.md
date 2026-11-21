# HPA-924 — Last Hearth character art pack (Implementation Plan)

Date: 2026-11-21  
Linear: https://linear.app/cwchanap/issue/HPA-924/orion-produce-the-last-hearth-character-art-pack  
Design: [HPA-924 character art pack](../specs/2026-11-21-hpa-924-character-art-pack-design.md)  
Baseline: `main` @ `3616b232425bf340ea63d1e0a609b25ba3ac66b2` (HPA-922 and HPA-923 merged)  
Review: https://github.com/cwchanap/orion/pull/52#pullrequestreview-6003901530

**One ticket → one PR.** This draft begins with design and plan. Add the final art, minimal CI contract extension, provenance and validation notes **to this same PR**. Checkpoints are work slices, not new PRs. Keep the plan YAGNI: use existing paths and tests; no production Dart, new art registry, separate Python audit, CI job, asset format change, or new Flutter dependency.

## Existing baseline and contract

All 12 `assets/images/characters/{Character.name}/` directories already have `portrait.png` at **1024×1536** and `chibi.png` at **512×512**; the 24 files total **~21.14 MiB**. All directories are already registered in `pubspec.yaml`. The existing `OrionArt` descriptors and `test/game/character_art_contract_test.dart` use those exact paths and enforce RGBA (PNG type 6) for chibis.

Deliver **exactly 36 images** after this ticket: **`portrait.png` = ticket “card”, `face.png` = new opaque square image, `chibi.png` = existing full-body RGBA battle sprite** in each directory. No `card.png`, path/manifest changes or face widget yet; HPA-926 owns face UI integration and the winter retheme. HPA-925 owns enemies/boards; HPA-927 SFX.

## Checkpoint 0 — Extend the existing test, first

Modify **only** `test/game/character_art_contract_test.dart` (not `lib/`):

1. Keep looping over the existing `Character.values` and existing descriptor/manifest assertions. For each directory, assert the **exact set** `{portrait.png,face.png,chibi.png}` to prevent extra bundled variants, and assert image dimensions: portrait 1024×1536; face 512×512; chibi 512×512 + IHDR PNG type 6. Do not hand-maintain another 12-ID list.
2. Add a bounded async pixel check through `dart:ui` (`instantiateImageCodec` → `getNextFrame` → `toByteData(format: ui.ImageByteFormat.rawRgba)` → dispose frame/codec): every chibi has **fully transparent alpha on its 1px four-edge border**. A transparent border is a useful anti-clipping guard but does **not** replace small-size visual inspection.
3. Decode/read `assets/images/characters/provenance.json` and assert its JSON object key set equals `Character.values` cross `{portrait.png,face.png,chibi.png}` (**36 unique entries**); optionally assert that each record has a method and source reference. The parent provenance file is not bundled by the already registered subdirectories.
4. A test change is **allowed** in an otherwise asset-only PR. No additional Python/Pillow runtime checks are necessary; this is durable in existing Flutter CI. Test-first means it will initially fail on missing faces/provenance; complete those assets **on the same PR** before requesting green final CI/merge.

**Gate:** the new checks have failed as expected for missing faces/provenance and are committed in this draft; subsequent checkpoints bring them green. Do not merge a red PR.

## Checkpoint 1 — Audit approved source ZIP versus existing 24 files

Inputs: approved HPA-924 character concepts/chibis/prompts ZIP, HPA-921 approved lineup/chibi sheet, and current repo PNGs. The ZIP stays local/private.

1. Match each existing `{id}/portrait.png` and `{id}/chibi.png` to its source ZIP entry using **SHA-256 byte comparison** first (these assets were originally copied from that source during HPA-922). A byte-identical approved original needs **no second identity review**; inspect only 48px readability if chibi, or visual fit for its role.
2. For nonidentical files, compare decoded pixels and approved design details; make a concrete **keep / lossless-optimize / retouch / regenerate** decision with reason. Check rank effect hierarchy and hair/outfit continuity; four summer outfits remain Hikari, Akane, Mio and Kaito.
3. Capture the current per-file sizes and source ZIP entry references in a small validation table. Do not print credentials, add source ZIP contents to Git, invent new source IDs, or regenerate approved matches by default. Use the existing per-character `Character.name` mapping.

**Gate:** each of 24 existing assets has a documented provenance source and an explicit keep/redo outcome.

## Checkpoint 2 — Finalize portraits and chibis **before** cropping faces

Paths: the existing `assets/images/characters/{id}/portrait.png` and `chibi.png`.

1. Reuse already approved matches unchanged. Retouch/regenerate **only** files that fail approved identity, shape, transparency, scale or visual legibility, using reference-conditioned generation when needed. Preserve approved 12-character roster, adult styling and summer/v2 outfits.
2. Keep dimensions/paths fixed: **1024×1536 portraits**, **512×512 RGBA type-6 chibis**. No new loader, Dart production changes, SVG, WebP or atlas; no cropped sprite reference rectangles. Use current tests to reject accidental format changes.
3. **Portraits:** lossless optimize first; optionally use palette/indexed PNG reduction **only for portraits**, after comparing the visible result to the approved artwork. **Chibis:** lossless optimization only, with RGBA type-6 preserved and color-type conversion off (e.g. `oxipng --nc`); or leave the file unchanged. Do not use indexed `pngquant` output for chibis.
4. For every file claimed “losslessly optimized”, compare **decoded RGBA pixels** before/after, not just byte hashes. Record a pixel-equal yes/no outcome and before/after bytes. If the pixels are equal, do not spend an extra browser visual test on that file. If they differ, treat as changed art with a visual check.
5. The card-size suggestion (~200 KB) is a **soft** optimization goal, not a reason to shrink dimensions, change format or damage fidelity. Document exceptions.

**Gate:** the 24 final-path runtime assets are fixed; the old 24-file test assertions pass; the new 36-file check still waits for faces and provenance. No production Dart diff.

## Checkpoint 3 — Create 12 opaque, circle-safe face thumbnails **from finalized portraits**

Paths: `assets/images/characters/{id}/face.png`.

1. Use the **final** 1024×1536 approved portrait as the crop/reframe source, not a draft portrait and **never** the 512px chibi. Save **512×512 opaque PNG** with portrait-derived background; preserve hairstyle, face and upper shoulders.
2. Compose essential hair and face **inside the centered inscribed circle**, even though output stays a square image. This allows HPA-926 to choose a circular squad chip without clipping the character's defining features. Do not pre-mask into a circle; retain a complete square.
3. Record the source crop rectangle (coordinates relative to the final portrait), its source portrait **SHA-256** and transform in provenance. If a finalized portrait later changes, check the source SHA and re-crop its face before concluding the art is complete.
4. At 40 logical px, compare each face against the approved lineup on dark and light mock backgrounds. If the final portrait cannot yield a recognizable crop, make a **reference-conditioned face generation** using the same approved character concept; record prompt/model, preserve outfit/hair/identity. Keep only the final `face.png` in each registered directory.

**Gate:** all 12 faces are distinct, readable, 512×512 and opaque, with circle-safe framing and accurate crop provenance.

## Checkpoint 4 — Final provenance and a **single static** contact sheet

Files to commit:
- `assets/images/characters/provenance.json`: JSON object with **36 keys**, one for each `{id}/{filename}`. Include role/source approval, method (`reused`/`optimized`/`cropped`/`retouched`/`generated`), stable source ZIP entry or art reference, source portrait SHA/crop rect **for cropped faces**, generation model and actual prompt **only if generated**. Follow the clear record-by-asset style of `assets/audio/music_provenance.json`. **No output hash** field: Git already pins final outputs.
- `docs/superpowers/validation/2026-11-21-hpa-924-character-art.md`: keep/redo audit, source ZIP compare results, decoded-pixel equality for lossless optimization, before/after bytes, test/CI evidence, MCP screenshot references and justified deviations.
- `docs/superpowers/validation/hpa-924-evidence/contact-sheet.png`: exactly one composed PNG showing all 12 IDs × three variants, 40px faces and 48px chibis on both dark and light backgrounds. Render locally with Pillow/comparable tool via ignored `tmp/`, using smooth downscale that approximates current `FilterQuality.medium`. **No temporary web page** or MCP capture of the contact sheet.

Do not commit the source ZIP, prompt archive, source images, generator scripts or experimental output folders. Do not place temporary working files in any registered per-ID directory.

**Gate:** all 36 provenance keys match the final files, all image/crop identities are traceable, and static small-size contact sheet exists.

## Checkpoint 5 — CI and **minimal MCP Chrome** end-to-end visual acceptance

**Durable automated checks**

1. Run `flutter test test/game/character_art_contract_test.dart`: expected all 36 files, dimensions, border transparency, directory cleanliness and provenance keys. Check new `face.png` files appear in Flutter's built asset manifest via existing per-ID entries.
2. Run `dart format --output=none --set-exit-if-changed test/game/character_art_contract_test.dart`, `flutter analyze`, `flutter test` and `flutter build web --release` on final head. Verify PR checks. No new Python package, CI workflow, production Dart, or platform-specific code.
3. Review the diff: only image files, the existing test file, provenance, design/plan, and validation/contact-sheet evidence. No separate ticket's art/audio.

**MCP end-to-end and visual check (not a manual gate)**

1. **Always run one small MCP-driven Chrome E2E** against the actual web game: title → Codex → character list/detail. The Codex is readable for **all 12 characters regardless of ownership** and renders their chibis at ~56px; assert that all relevant images load rather than fallback, without starting a stage or restarting the app.
2. Capture Codex screen evidence at **390×844** and **320×568**; scroll/search to see all 12 entries if needed. Use the approved HPA-921/HPA-924 art and HPA-922 mockups to judge character identity/scale, while comparing *unchanged UI chrome* to committed **HPA-922 screenshot baselines** (`docs/superpowers/validation/hpa-922-evidence/`). Ignore known winter-scene differences deferred to HPA-926.
3. Focus additional browser steps **only on files with changed decoded pixels**: changed chibis via their Codex entries (and battle when cheaply reachable); changed starter portraits through Camp/sheet; changed non-starter portraits via an isolated test profile with seeded ownership when practical. If the latter is impractical, document that the contact sheet supplies direct full-colour visual evidence instead of falsely claiming to have viewed a locked portrait in game. Do **not** replay the full HPA-922 battle, test cache reload, repeat pixel-identical screenshot comparisons, or build a face-asset browser preview page.
4. The **12 new `face.png`** files are not wired to the production UI until HPA-926, so their complete visual acceptance is via the static contact sheet; do not invent a temporary production UI or browser page. Screenshot checks and any art-specific deviations are recorded in the committed validation note.
5. **One web platform is enough** (no platform-specific change); no native tests or human sign-off criteria.

**Final gate:** final-head tests/build/CI pass, a minimal **MCP Chrome E2E** with two viewport screenshot sets is documented, and changed artwork is validated against approved reference art. All evidence lives in **this same PR**.

## End-to-end acceptance checklist

- [ ] Exactly **36** PNGs across 12 canonical asset folders; portraits 1024×1536, square opaque faces 512×512, chibis 512×512 PNG type 6 with fully transparent border.
- [ ] The extended **in-repo Flutter contract test** (not one-off Python) pins all 36 assets, clean directory listings, alpha border, provenance and unchanged `OrionArt` paths/manifest.
- [ ] Audit against the approved ZIP, lossless decoded-pixel checks and before/after size changes are recorded; no redundant art generation or unapproved wardrobe changes.
- [ ] Final portraits precede face crops; crop rectangles and final source portrait SHAs are recorded; 40px face thumbnails remain circle-safe and readable; 48px chibi samples readable on dark/light backgrounds.
- [ ] One static **contact-sheet PNG** demonstrates all 36 final images and matches approved Linear identity/wardrobe references.
- [ ] `flutter analyze`, `flutter test`, `flutter build web --release` and final PR CI are green without production Dart changes.
- [ ] **MCP-driven real-game E2E** reaches the Codex and renders the 12 characters, with 390×844/320×568 screenshot comparisons against relevant mockup art and HPA-922 baseline. Any newly pixel-changed runtime art receives targeted visual checking; no browser reload or eight-wave replay requirement.
- [ ] Deliverable and evidence are committed only to **this HPA-924 draft PR**; HPA-925/926/927 stay separate. No human-acceptance criterion.

## Review decisions incorporated (2026-11-21)

Accepted all six findings in [design review #6003901530](https://github.com/cwchanap/orion/pull/52#pullrequestreview-6003901530):

1. Extend existing test in CI instead of running a one-off Pillow audit; test-only Dart is consistent with an art-only production change.
2. Preserve RGBA chibi type 6; palette/indexed optimization only for portraits, with decoded-pixel equality logs.
3. Finalize portraits first, then circle-safe opaque faces; record final portrait SHA/crop rectangle.
4. Use Codex to see all 12 characters, only add asset-specific UI checks for changed pixels, and compare unchanged chrome with HPA-922 evidence. **Project acceptance still requires one minimal MCP E2E**, even if no existing image pixels change.
5. Produce a static contact-sheet PNG, not a page and an extra MCP screenshot.
6. Hash-compare against the approved ZIP before manual identity work; remove the redundant, stale-prone final output hash field.
