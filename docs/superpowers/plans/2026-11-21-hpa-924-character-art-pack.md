# HPA-924 — Last Hearth character art pack (Implementation Plan)

Date: 2026-11-21  
Linear: https://linear.app/cwchanap/issue/HPA-924/orion-produce-the-last-hearth-character-art-pack  
Design: [HPA-924 character art pack](../specs/2026-11-21-hpa-924-character-art-pack-design.md)  
Baseline: `main` @ `3616b232425bf340ea63d1e0a609b25ba3ac66b2` (HPA-922 and HPA-923 merged)  
Reviews: [round 1](https://github.com/cwchanap/orion/pull/52#pullrequestreview-6003901530) · [round 2](https://github.com/cwchanap/orion/pull/52#pullrequestreview-6003995785)

**One ticket → one PR.** This draft begins with design and plan. Add the final art, minimal CI contract extension, provenance and validation notes **to this same PR**. Checkpoints are work slices, not new PRs. Keep the plan YAGNI: use existing paths and tests; no production Dart, new art registry, separate Python audit, CI job, asset format change, or new Flutter dependency.

## Existing baseline and contract

All 12 `assets/images/characters/{Character.name}/` directories already have `portrait.png` at **1024×1536** and `chibi.png` at **512×512**; the 24 files total **~21.14 MiB**. All directories are already registered in `pubspec.yaml`. The existing `OrionArt` descriptors and `test/game/character_art_contract_test.dart` use those exact paths and enforce RGBA (PNG type 6) for chibis.

Deliver **exactly 36 images** after this ticket: **`portrait.png` = ticket “card”, `face.png` = new opaque square image, `chibi.png` = existing full-body RGBA battle sprite** in each directory. No `card.png`, path/manifest changes or face widget yet; HPA-926 owns face UI integration and the winter retheme. HPA-925 owns enemies/boards; HPA-927 SFX.

## Checkpoint 0 — Extend the existing test, first

Modify **only** `test/game/character_art_contract_test.dart` (not `lib/`):

1. Keep looping over the existing `Character.values` and existing descriptor/`pubspec.yaml` registration assertions. For each registered directory, assert the **exact set** `{portrait.png,face.png,chibi.png}` (no extra variants). Assert the PNG header dimensions: portrait 1024×1536, face 512×512, chibi 512×512 with IHDR color type 6. No duplicate 12-ID list.
2. **Decode every one of the 36 PNGs, including all portraits,** using one async `dart:ui` helper (`instantiateImageCodec` → `getNextFrame` → assert decoded frame dimensions → dispose codec/image). Check **every decoded face alpha == 255**, and inspect each decoded chibi's `ImageByteFormat.rawRgba` bytes for a **fully transparent 1px border** on all four sides. No Pillow package in CI. Both PNG header and full pixel decode must pass, including portrait files re-encoded without changing pixel values.
3. Decode/read `assets/images/characters/provenance.json` and assert its key set equals `Character.values × {portrait.png,face.png,chibi.png}` (36 distinct entries), without a new filename registry or unvalidated SHA assertion.
4. Use `AssetManifest.loadFromAssetBundle(rootBundle)` (`package:flutter/services.dart`) in **this existing test** to verify **all 36 canonical image keys are in Flutter's actual asset bundle** and `assets/images/characters/provenance.json` is **not**. Keep the existing textual `pubspec.yaml` registration check. A registered directory includes any stray variant, so the exact-directory assertion matters.
5. A test-only Dart change is allowed in this art-production PR. No additional Python/Pillow CI job, new dependency or production Dart code. The test starts red until faces/provenance exist, then becomes a permanent green CI gate before merge.

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
4. For every file claimed “losslessly optimized”, compare **decoded RGBA pixels** before/after and record pixel-equal yes/no plus before/after bytes. Pixel-identical chibis require no additional art visual comparison; **any changed `portrait.png` file bytes still trigger the small Camp browser smoke** in Checkpoint 5, because a byte-level re-encode can break the separate cached `Image.asset`/`cacheWidth` decoder even when RGBA pixels match. Keep the permanent test decoding **all** files.
5. The card-size suggestion (~200 KB) is a **soft** optimization goal, not a reason to shrink dimensions, change format or damage fidelity. Document exceptions.

**Gate:** the 24 final-path runtime assets are fixed; the old 24-file test assertions pass; the new 36-file check still waits for faces and provenance. No production Dart diff.

## Checkpoint 3 — Create 12 opaque, circle-safe face thumbnails **from finalized portraits**

Paths: `assets/images/characters/{id}/face.png`.

1. Use the **final** 1024×1536 approved portrait as the crop/reframe source, not a draft portrait and **never** the 512px chibi. Save **512×512 opaque PNG** with portrait-derived background; preserve hairstyle, face and upper shoulders.
2. Compose essential hair and face **inside the centered inscribed circle**, even though output stays a square image. This allows HPA-926 to choose a circular squad chip without clipping the character's defining features. Do not pre-mask into a circle; retain a complete square.
3. Record the **crop rectangle in final-portrait pixel coordinates** and any reframe transform in provenance. **Do not record an unenforced `source_portrait_sha256` field:** Git pins the portrait and its face together, and the crop rectangle suffices for a deliberate re-crop if the portrait is later edited. No `crypto` dev dependency or hash check is needed.
4. At 40 logical px, compare each face against the approved lineup on dark and light mock backgrounds. If the final portrait cannot yield a recognizable crop, make a **reference-conditioned face generation** using the same approved character concept; record prompt/model, preserve outfit/hair/identity. Keep only the final `face.png` in each registered directory.

**Gate:** all 12 faces are distinct, readable, 512×512 and opaque, with circle-safe framing and accurate crop provenance.

## Checkpoint 4 — Final provenance and a **single static** contact sheet

Files to commit:
- `assets/images/characters/provenance.json`: JSON object with **36 keys**, one per `{id}/{filename}`. Include role/source approval, method (`reused`/`optimized`/`cropped`/`retouched`/`generated`), stable source ZIP entry or art reference and **crop rectangle for cropped faces**. Record generation model and actual prompt **only if generated**. Match the record-by-asset style of `assets/audio/music_provenance.json`. **No unenforced output hash or portrait-source hash fields**: Git already pins the final assets.
- `docs/superpowers/validation/2026-11-21-hpa-924-character-art.md`: keep/redo audit, source ZIP compare results, decoded-pixel equality for lossless optimization, before/after bytes, test/CI evidence, MCP screenshot references and justified deviations.
- `docs/superpowers/validation/hpa-924-evidence/contact-sheet.png`: exactly one composed PNG showing all 12 IDs × three variants, 40px faces and 48px chibis on both dark and light backgrounds. Render locally with Pillow/comparable tool via ignored `tmp/`, using smooth downscale that approximates current `FilterQuality.medium`. **No temporary web page** or MCP capture of the contact sheet.

Do not commit the source ZIP, prompt archive, source images, generator scripts or experimental output folders. Do not place temporary working files in any registered per-ID directory.

**Gate:** all 36 provenance keys match the final files, all image/crop identities are traceable, and static small-size contact sheet exists.

## Checkpoint 5 — CI and **minimal MCP Chrome** end-to-end visual acceptance

**Durable automated checks**

1. Run `flutter test test/game/character_art_contract_test.dart`: this verifies all **36 decoded PNG images** and frame dimensions, opaque faces, type-6 chibis with transparent borders, exact per-ID directory contents, 36 provenance keys, and **actual Flutter `AssetManifest` membership for all 36 images plus exclusion of `provenance.json`**. `pubspec.yaml` text registration is still checked. No extra manual manifest verification step is necessary.
2. Run `dart format --output=none --set-exit-if-changed test/game/character_art_contract_test.dart`, `flutter analyze`, `flutter test` and `flutter build web --release` on final head. Verify PR checks. No new Python package, CI workflow, production Dart, or platform-specific code.
3. Review the diff: only image files, the existing test file, provenance, design/plan, and validation/contact-sheet evidence. No separate ticket's art/audio.

**MCP end-to-end and visual check (not a manual gate)**

1. **Always run one minimal MCP-driven Chrome E2E** against the real game: **Title → Codex → 12-character four-column grid** at standard text scale, with ~46px chibis in tiles and ~56px in the selected detail. No owned roster is needed. Inspect each tile/detail for broken or fallback art. No stage battle or reload.
2. Capture the Codex at **390×844** and **320×568** and compare character art directly to HPA-921/HPA-924 approvals. **Do not claim HPA-922 Codex or 320px baselines:** `docs/superpowers/validation/hpa-922-evidence/` contains six **390px Camp/sheet/briefing/battle** shots, no Codex or compact captures, and predates the HPA-923 four-tab shell. Use HPA-923 evidence only for current shell chrome where applicable; use HPA-922/HPA-923 screenshots only for the **same actual surface** when extra Camp/Flare/sheet/battle captures are needed. Do not relog known winter-retheme gaps from HPA-926.
3. **Whenever ANY `portrait.png` file bytes change** (including lossless/pixel-identical re-encodes), navigate to **Camp** during the MCP smoke and verify the separate Flutter `Image.asset` with `cacheWidth` renders. If `jin`, `hikari` or `akane` portraits changed, check those **full-color portraits through the existing Flare marquee** without needing ownership seeding. For changed starter portraits, inspect Camp/sheet; for other changed portraits, optionally use an isolated seeded profile if practical or document contact-sheet-only full-color evidence. For **pixel-changed chibis**, inspect the corresponding Codex grid/detail entries, and battle only when trivially reachable. No mandatory replay, reload or unchanged-art screenshot duplication.
4. The **12 new `face.png`** files are intentionally not wired to production UI until HPA-926: accept them with the static contact sheet, not a temporary game screen. Record MCP captures, real reference comparisons, and concrete discrepancies in the committed validation note.
5. One browser platform is sufficient for this asset-only cross-platform change. Do not add native acceptance or human sign-off.

**Final gate:** final-head tests/build/CI pass, a minimal **MCP Chrome E2E** with two viewport screenshot sets is documented, and changed artwork is validated against approved reference art. All evidence lives in **this same PR**.

## End-to-end acceptance checklist

- [ ] Exactly **36** PNGs across 12 canonical asset folders; portraits 1024×1536, square opaque faces 512×512, chibis 512×512 PNG type 6 with fully transparent border.
- [ ] The extended **in-repo Flutter contract test** fully decodes all 36 PNGs, checks dimensions/face opacity/chibi alpha edges, exact directory listings and provenance keys, and asserts all 36 images are present in actual `AssetManifest` while `provenance.json` is absent; `OrionArt` paths and `pubspec.yaml` registration remain unchanged.
- [ ] Audit against the approved ZIP, lossless decoded-pixel checks and before/after size changes are recorded; no redundant art generation or unapproved wardrobe changes.
- [ ] Final portraits precede face crops; accurate crop rectangles (no unenforced hash fields) are recorded; 40px face thumbnails remain circle-safe and readable; 48px chibi samples are readable on dark/light backgrounds.
- [ ] One static **contact-sheet PNG** demonstrates all 36 final images and matches approved Linear identity/wardrobe references.
- [ ] `flutter analyze`, `flutter test`, `flutter build web --release` and final PR CI are green without production Dart changes.
- [ ] **MCP-driven real-game E2E** reaches the Codex four-column grid with all 12 characters, captures 390×844/320×568 and compares art against the approved character references (no invented HPA-922 Codex/320px baseline). Any changed portrait **file bytes** trigger a Camp `Image.asset` smoke, and Jin/Hikari/Akane portrait changes use the existing Flare marquee. Pixel-changed chibis receive targeted Codex visual checks. No browser reload or eight-wave replay.
- [ ] Deliverable and evidence are committed only to **this HPA-924 draft PR**; HPA-925/926/927 stay separate. No human-acceptance criterion.

## Review decisions incorporated (2026-11-21)

Accepted all six findings in [design review #6003901530](https://github.com/cwchanap/orion/pull/52#pullrequestreview-6003901530):

1. Extend existing test in CI instead of running a one-off Pillow audit; test-only Dart is consistent with an art-only production change.
2. Preserve RGBA chibi type 6; palette/indexed optimization only for portraits, with decoded-pixel equality logs.
3. Finalize portraits first, then circle-safe opaque faces; record source crop rectangles. Round two subsequently removes the unenforced portrait SHA field.
4. Use Codex to see all 12 characters and add asset-specific checks for changed pixels; HPA-922 has no Codex/320px baseline, so compare to approved art and matching real HPA-923 shell evidence. **Project acceptance still requires one minimal MCP E2E**, even if no existing pixels change.
5. Produce a static contact-sheet PNG, not a page and an extra MCP screenshot.
6. Hash-compare against the approved ZIP before manual identity work; remove the redundant, stale-prone final output hash field.

## Round-two review disposition (2026-11-21)

Accepted all three follow-up findings in [review #6003995785](https://github.com/cwchanap/orion/pull/52#pullrequestreview-6003995785) without adding new subsystems:

1. The existing asset test now **plans a complete decode of all 36 PNGs** (not PNG-header checks alone). Any changed portrait **file bytes**, including lossless recompression, trigger a minimal Camp/`Image.asset` smoke; use Flare's full-color marquee for Jin/Hikari/Akane when appropriate.
2. Dropped unenforced `source_portrait_sha256` from face provenance. The source crop rectangle is sufficient for regeneration; no new `crypto` dependency or stale check.
3. Added a true Flutter `AssetManifest.loadFromAssetBundle(rootBundle)` test for all 36 bundled images and absent provenance, and replaced nonexistent HPA-922 Codex/320px comparisons with approved character art plus matching current screenshots if present. The Codex uses a four-column 12-tile grid at standard text size.

Plan edits only; no claim that tests/art or MCP E2E have run yet. Everything will land on this existing HPA-924 PR.
