# HPA-924 — Last Hearth character art validation

- **Date:** 2026-11-21
- **Plan:** [character art pack plan](../plans/2026-11-21-hpa-924-character-art-pack.md) · **Design:** [character art pack design](../specs/2026-11-21-hpa-924-character-art-pack-design.md)
- **PR:** [#52](https://github.com/cwchanap/orion/pull/52)

This note validates the 24 character PNGs that already exist under `assets/images/characters/{id}/`. It records the source audit, the chibi border retouch and the portrait optimization experiment. Later checkpoints append their own sections.

## 1. Scope and approved source

- **Approved source:** Linear HPA-924 attachment "Approved character concepts and chibi sprites, full size, with prompts (zip)" (approved concept set; lineup approved 2026-11-17). The ZIP is **not committed**; it stays local and private.
- **ZIP SHA-256:** `7bd5791d230ef8103aa85b9350745f63a1bb74a052c1331a7b5a8952abd8f8e5` (6,317,337 bytes, 25 files).
- **Entry naming:** `character-concepts-v3/{rank}{n}-{given}-{family}.jpg` (12 concept portraits), `character-concepts-v3/chibi/{rank}{n}-{given}-{family}.png` (12 chibis) and `character-concepts-v3/character-prompts.json`. Each repo ID maps to exactly one JPG and one PNG by the given-name segment, for example `e1-haruto-sakaki` → `haruto`.
- **Comparison:** SHA-256 of each repo file against the SHA-256 of its ZIP entry bytes. The portrait source is JPEG and the repo copy is PNG, so portraits are also compared by decoding both to RGB at 1024×1536. Chibi border and bounding-box checks use decoded RGBA. Tooling: Python 3 with Pillow 13.0.0 (no numpy); scripts are not committed.

## 2. Audit of the 24 existing files

Rows are in rank order (E to S). Repo bytes are sizes before this change. 12 of 24 files were SHA-256 identical to their ZIP entry before this change: all 12 chibis, and no portrait. Decisions: **reuse** = byte-identical to the approved entry and left unchanged; **keep** = repo PNG left byte-unchanged because its decoded pixels match the approved JPG; **retouch** = changed, see section 3. Outcome: 12 portraits keep, 7 chibis reuse, 5 chibis retouch.

| ID | File | Repo bytes | Source ZIP entry | SHA-256 identical | Decision | Reason |
| --- | --- | ---: | --- | --- | --- | --- |
| haruto | portrait.png | 1,053,927 | `character-concepts-v3/e1-haruto-sakaki.jpg` | no (JPG vs PNG) | keep | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.76/0.21/1.02, max 34/13/42. Lossless PNG master kept. |
| haruto | chibi.png | 192,583 | `character-concepts-v3/chibi/e1-haruto-sakaki.png` | yes | reuse | Byte-identical to the approved chibi. Border clean; RGBA 512×512, color type 6; minimum opaque margin 5 px. |
| mio | portrait.png | 1,225,337 | `character-concepts-v3/e2-mio-tachibana.jpg` | no (JPG vs PNG) | keep | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.54/0.28/0.49, max 29/14/46. Lossless PNG master kept. |
| mio | chibi.png | 251,405 | `character-concepts-v3/chibi/e2-mio-tachibana.png` | yes (before retouch) | retouch | Byte-identical to the approved chibi, but 45 border pixels on the bottom row carry alpha 1–2, which breaks the fully transparent 1-px border. Border-only clear (section 3). |
| sayo | portrait.png | 1,311,882 | `character-concepts-v3/d1-sayo-kitami.jpg` | no (JPG vs PNG) | keep | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.35/0.16/0.40, max 20/8/26. Lossless PNG master kept. |
| sayo | chibi.png | 274,014 | `character-concepts-v3/chibi/d1-sayo-kitami.png` | yes | reuse | Byte-identical to the approved chibi. Border clean; RGBA 512×512, color type 6; minimum opaque margin 12 px. |
| tetsuo | portrait.png | 1,409,813 | `character-concepts-v3/d2-tetsuo-kanda.jpg` | no (JPG vs PNG) | keep | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.49/0.23/0.66, max 28/12/42. Lossless PNG master kept. |
| tetsuo | chibi.png | 265,750 | `character-concepts-v3/chibi/d2-tetsuo-kanda.png` | yes (before retouch) | retouch | Byte-identical to the approved chibi, but 49 border pixels on the bottom row carry alpha 1–2, which breaks the fully transparent 1-px border. Border-only clear (section 3). |
| rin | portrait.png | 1,379,553 | `character-concepts-v3/c1-rin-fuyutsuki.jpg` | no (JPG vs PNG) | keep | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.75/0.18/1.08, max 15/6/24. Lossless PNG master kept. |
| rin | chibi.png | 264,194 | `character-concepts-v3/chibi/c1-rin-fuyutsuki.png` | yes | reuse | Byte-identical to the approved chibi. Border clean; RGBA 512×512, color type 6; minimum opaque margin 10 px. |
| kaito | portrait.png | 1,488,390 | `character-concepts-v3/c2-kaito-narumi.jpg` | no (JPG vs PNG) | keep | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.76/0.32/1.90, max 31/17/63. Lossless PNG master kept. |
| kaito | chibi.png | 258,416 | `character-concepts-v3/chibi/c2-kaito-narumi.png` | yes (before retouch) | retouch | Byte-identical to the approved chibi, but 23 border pixels on the bottom row carry alpha 1, which breaks the fully transparent 1-px border. Border-only clear (section 3). |
| elena | portrait.png | 1,347,088 | `character-concepts-v3/b1-elena-volkova.jpg` | no (JPG vs PNG) | keep | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.36/0.23/0.74, max 21/9/13. Lossless PNG master kept. |
| elena | chibi.png | 278,705 | `character-concepts-v3/chibi/b1-elena-volkova.png` | yes | reuse | Byte-identical to the approved chibi. Border clean; RGBA 512×512, color type 6; minimum opaque margin 7 px. |
| shiori | portrait.png | 1,306,037 | `character-concepts-v3/b2-shiori-kusanagi.jpg` | no (JPG vs PNG) | keep | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.28/0.15/0.41, max 15/10/37. Lossless PNG master kept. |
| shiori | chibi.png | 263,445 | `character-concepts-v3/chibi/b2-shiori-kusanagi.png` | yes (before retouch) | retouch | Byte-identical to the approved chibi, but 10 border pixels on the top row carry alpha 1, which breaks the fully transparent 1-px border. Border-only clear (section 3). |
| akane | portrait.png | 1,926,556 | `character-concepts-v3/a1-akane-hinomori.jpg` | no (JPG vs PNG) | keep | Decoded RGB matches the approved JPG: mean abs diff R/G/B 1.74/0.94/1.42, max 49/24/49. Lossless PNG master kept. |
| akane | chibi.png | 344,101 | `character-concepts-v3/chibi/a1-akane-hinomori.png` | yes | reuse | Byte-identical to the approved chibi. Border clean; RGBA 512×512, color type 6; minimum opaque margin 6 px. |
| ren | portrait.png | 1,842,705 | `character-concepts-v3/a2-ren-kurosawa.jpg` | no (JPG vs PNG) | keep | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.41/0.39/0.83, max 12/11/34. Lossless PNG master kept. |
| ren | chibi.png | 336,967 | `character-concepts-v3/chibi/a2-ren-kurosawa.png` | yes | reuse | Byte-identical to the approved chibi. Border clean; RGBA 512×512, color type 6; minimum opaque margin 12 px. |
| hikari | portrait.png | 2,268,780 | `character-concepts-v3/s1-hikari-amatsu.jpg` | no (JPG vs PNG) | keep | Decoded RGB matches the approved JPG: mean abs diff R/G/B 1.58/0.78/2.07, max 39/19/48. Lossless PNG master kept. |
| hikari | chibi.png | 392,926 | `character-concepts-v3/chibi/s1-hikari-amatsu.png` | yes (before retouch) | retouch | Byte-identical to the approved chibi, but 6 border pixels on the left column carry alpha 1, which breaks the fully transparent 1-px border. Border-only clear (section 3). |
| jin | portrait.png | 2,172,666 | `character-concepts-v3/s2-jin-kamishiro.jpg` | no (JPG vs PNG) | keep | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.97/0.34/1.16, max 21/9/38. Lossless PNG master kept. |
| jin | chibi.png | 307,766 | `character-concepts-v3/chibi/s2-jin-kamishiro.png` | yes | reuse | Byte-identical to the approved chibi. Border clean; RGBA 512×512, color type 6; minimum opaque margin 8 px. |

**Portrait finding.** All 12 repo portraits are 1024×1536 RGB PNG (color type 2). None is byte-identical to its approved JPG, which is expected for JPG versus PNG. Decoded pixels agree closely: the mean absolute difference is at most 2.07 per channel and the largest single-channel difference is 63 (kaito, blue). At most 0.6 % of channel values differ by more than 16. A 32×32-cell difference map (largest cell mean 13, hikari) shows the residual along figure outlines and textured detail, with no uniform patch, which matches JPEG compression on the approved export. The repo PNGs are kept as the lossless masters of the approved art, byte-unchanged. Outfit, hair and effect continuity follow from the pixel agreement, and no portrait needed retouching.

**Chibi finding.** Before this change, all 12 repo chibis were byte-identical to their approved ZIP entries. Seven are clean. Five (mio, tetsuo, kaito, shiori, hikari) carry stray alpha of 1–2 on one border line, so they are retouched. A 48 px preview of all 12 chibis, downscaled smoothly on dark and light backgrounds, shows distinct, unclipped silhouettes.

## 3. Chibi border retouch

Method: each pixel on the 512×512 border (corners counted once) with alpha greater than 0 was set to `(0, 0, 0, 0)`; no other pixel changed. Files were saved as RGBA PNG with Pillow `optimize=True`, then verified in memory and again after being written to disk. Each file keeps bit depth 8, color type 6 (RGBA), 512×512 and a fully transparent border, and no pixel off the border changed. The originals remain in git history. The seven clean chibis were not rewritten.

| File | Before bytes | After bytes | Δ bytes | Border px cleared | Changed px (off border) | Border alpha max after (top/bottom/left/right) | Color type, size |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `mio/chibi.png` | 251,405 | 251,803 | +398 | 45 | 45 (0) | 0/0/0/0 | 6, 512×512 |
| `tetsuo/chibi.png` | 265,750 | 266,108 | +358 | 49 | 49 (0) | 0/0/0/0 | 6, 512×512 |
| `kaito/chibi.png` | 258,416 | 258,799 | +383 | 23 | 23 (0) | 0/0/0/0 | 6, 512×512 |
| `shiori/chibi.png` | 263,445 | 263,949 | +504 | 10 | 10 (0) | 0/0/0/0 | 6, 512×512 |
| `hikari/chibi.png` | 392,926 | 393,382 | +456 | 6 | 6 (0) | 0/0/0/0 | 6, 512×512 |

Every retouched file grew by 358–504 bytes (0.12–0.19 %). Pillow's `optimize=True` encode is slightly larger than the approved encoding for these files. The increase is recorded, not optimized away, and no size benefit is claimed. None of the chibis carried ancillary chunks before or after (only IHDR, IDAT and IEND), so no metadata was lost.

## 4. Portrait lossless-optimization experiment (not applied)

Method: each repo portrait was decoded, re-saved in memory with Pillow `optimize=True`, and its decoded RGB bytes compared with the original. Nothing was written to the repo. Savings range from 5.04 % to 14.11 % (9.75 % in total).

| ID | Before (bytes) | After (bytes) | Saved | Decoded RGB pixel-equal |
| --- | ---: | ---: | ---: | --- |
| haruto | 1,053,927 | 905,216 | 14.11 % | yes |
| mio | 1,225,337 | 1,063,817 | 13.18 % | yes |
| sayo | 1,311,882 | 1,208,324 | 7.89 % | yes |
| tetsuo | 1,409,813 | 1,272,539 | 9.74 % | yes |
| rin | 1,379,553 | 1,244,392 | 9.80 % | yes |
| kaito | 1,488,390 | 1,311,791 | 11.87 % | yes |
| elena | 1,347,088 | 1,236,894 | 8.18 % | yes |
| shiori | 1,306,037 | 1,170,751 | 10.36 % | yes |
| akane | 1,926,556 | 1,706,059 | 11.45 % | yes |
| ren | 1,842,705 | 1,682,496 | 8.69 % | yes |
| hikari | 2,268,780 | 2,040,149 | 10.08 % | yes |
| jin | 2,172,666 | 2,063,172 | 5.04 % | yes |
| **Total** | 18,732,734 | 16,905,600 | 9.75 % | 12 / 12 |

Every original portrait carries `eXIf` and `sRGB` chunks, and the Pillow re-save drops both. The pixels are identical, but the metadata is not.

**Documented exception: soft size goal not met.** The ~200 KB-per-card goal is soft. Portraits stay at 1.0–2.2 MiB (1,053,927–2,268,780 bytes) and are left byte-unchanged, for these reasons:

1. Lossless re-encoding saves only 5–14 %, far short of the goal.
2. Reaching ~200 KB would need palette or indexed reduction, which changes pixel values. It was rejected to preserve fidelity to the approved art and was not tried.
3. The Pillow re-save drops the `eXIf` and `sRGB` chunks.
4. Rewriting all 12 portraits would add about 16.1 MiB of new blobs (16,905,600 bytes) and would require re-checking Camp portrait rendering (Checkpoint 5) for each changed portrait.

Dimensions, paths and format are unchanged.

## 5. Chibi opaque-bounds margins

Bounding box: pixels with alpha greater than 16, as (left, top, right, bottom) with right and bottom exclusive. Margin: transparent pixels between the canvas edge and the nearest opaque pixel. Flag rule: any margin of 2 px or less. Retouching changed only alpha 1–2 pixels, so these values are identical before and after.

| ID | Opaque bbox (l, t, r, b) | Left | Top | Right | Bottom | Min | Flag |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| haruto | (135, 5, 404, 505) | 135 | 5 | 108 | 7 | 5 | no |
| mio | (73, 12, 418, 509) | 73 | 12 | 94 | 3 | 3 | no |
| sayo | (86, 25, 453, 500) | 86 | 25 | 59 | 12 | 12 | no |
| tetsuo | (30, 7, 477, 508) | 30 | 7 | 35 | 4 | 4 | no |
| rin | (127, 13, 409, 502) | 127 | 13 | 103 | 10 | 10 | no |
| kaito | (98, 5, 373, 507) | 98 | 5 | 139 | 5 | 5 | no |
| elena | (54, 9, 475, 505) | 54 | 9 | 37 | 7 | 7 | no |
| shiori | (94, 3, 426, 507) | 94 | 3 | 86 | 5 | 3 | no |
| akane | (37, 7, 471, 506) | 37 | 7 | 41 | 6 | 6 | no |
| ren | (70, 26, 446, 500) | 70 | 26 | 66 | 12 | 12 | no |
| hikari | (47, 7, 477, 504) | 47 | 7 | 35 | 8 | 7 | no |
| jin | (82, 8, 406, 502) | 82 | 8 | 106 | 10 | 8 | no |

**Flagged chibis: 0.** The tightest margins are mio (bottom 3 px), shiori (top 3 px), tetsuo (bottom 4 px); no sprite comes within 2 px of the canvas edge, so none is clipped.

## 6. Face thumbnails

Method: each `face.png` is a square crop of the committed `portrait.png` at the rectangle in the table (final-portrait pixels, top-left origin, `side` × `side`). The crop is resized to 512×512 with Pillow `LANCZOS` and saved as an 8-bit RGB PNG with `optimize=True`, so every face is fully opaque (color type 2). Method `cropped`. Each crop is circle-safe: the inscribed circle has diameter `side` and the same centre as the crop. No production screen draws `face.png` until HPA-926.

| ID | Crop x | Crop y | Side | Upscale (512 / side) | face.png bytes | Fit |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| haruto | 332 | 0 | 288 | 1.778 | 311,896 | Hair and face inside. Scarf and jacket collar outside (clothing). |
| mio | 310 | 0 | 460 | 1.113 | 355,781 | Largest crop. Hair crown and ribbon inside (closeup checked at checkpoint 3). |
| sayo | 199 | 22 | 352 | 1.455 | 306,856 | Hood, goggles and face inside. Long side braid runs past the bottom rim; bow hand and arrow cross the rim (props). |
| tetsuo | 374 | 0 | 288 | 1.778 | 325,983 | Spiky hair, goggles and beard inside. Background props in the upper-left corner outside. |
| rin | 302 | 0 | 380 | 1.347 | 356,775 | Bob hair, snowflake ornament and blue highlights inside. Cape and hood outside (clothing). |
| kaito | 371 | 0 | 304 | 1.684 | 330,012 | Spiky hair and face inside, tips close to the top rim. Goggles and collar outside (clothing). |
| elena | 355 | 0 | 320 | 1.600 | 379,019 | Face, silver hair and braid top inside. Cap rim corners extend past the circle (headwear). |
| shiori | 274 | 0 | 420 | 1.219 | 333,096 | Bun, hair pins, glasses and right-side hair inside. Coat lapels outside (clothing). Recropped after review. |
| akane | 323 | 38 | 368 | 1.391 | 431,351 | Tiara, bangs and face inside. Long ponytail tips extend past the right rim; fire and tassel props outside. Recropped after review. |
| ren | 393 | 10 | 288 | 1.778 | 323,046 | Head and hair fully inside. Background rock props in the upper corners outside. |
| hikari | 336 | 40 | 288 | 1.778 | 404,684 | Head and upper hair ornament inside. Long hair tails extend past the rim at lower left and right; halo outside. |
| jin | 415 | 0 | 288 | 1.778 | 369,477 | Hair inside, top strands near the rim. The head is small (about 160 px wide in the portrait), so the 288 minimum applies. Fur collar and chain props outside. |

Two crops changed after review in commit `e3d087a`: shiori moved from `245,0,430` to `274,0,420` to drop a clipped prop sliver at the left edge, and akane moved from `323,0,368` to `323,38,368` to centre the head with less empty headroom.

Fit was re-checked for this note on 256 px circle overlays of all 12 faces and on a 512 px overlay of sayo. Hair or headwear that extends past the rim: elena (cap rim), sayo (braid), akane (ponytail tips) and hikari (hair tails). Everything else outside the rim is clothing, props, effects or background.

Verification: each face.png was reproduced from the committed portrait and its rectangle with mean abs diff 0 (max 0 in every channel): 12 of 12. The pre-recrop rectangles do not reproduce the committed shiori or akane files (mean abs diff 42.3 and 52.9), so the table is the record.

Size: the 12 faces total 4,227,976 bytes (4.03 MiB). They are full-detail RGB PNG with no palette or indexed reduction, and no soft size goal is claimed for them.

## 7. Provenance file

`assets/images/characters/provenance.json` (new) has one record per art file: 36 keys `{id}/{filename}` in rank order, following the record-by-asset layout of `assets/audio/music_provenance.json`. Every record has `role` (`card`, `face` or `chibi`), `method`, `approval` (the fixed phrase "HPA-924 approved concept set; HPA-922 repo copy"), `source`, `reference` (the `character-prompts.json` key), `model` and `prompt`. Both are `null` because nothing was generated. Faces also carry `crop` (`x`, `y`, `side` and `resize`), and a short `note` appears only where it adds information.

| Method | Records | Files |
| --- | ---: | --- |
| reused | 19 | 12 portraits (the approved JPG is the reference; the repo PNG is kept as the lossless master) and 7 chibis (byte-identical to the approved PNG) |
| retouched | 5 | chibis for mio, tetsuo, kaito, shiori and hikari; border alpha cleared on 45, 49, 23, 10 and 6 pixels |
| cropped | 12 | every `face.png`, cut from the committed portrait at the section 6 rectangle |
| **Total** | **36** | |

The file has no hash fields. Git pins the final files, and the review rounds dropped unenforced hashes, so the ZIP entry, the reference key and the crop rectangle are the only source identifiers.

The file sits in the parent folder, outside the 12 per-ID directories that `pubspec.yaml` registers, so Flutter does not bundle it. The contract test asserts that `provenance.json` is absent from the `AssetManifest`.

Before commit, a scratch check confirmed that the JSON parses, the 36 keys equal the 12 directory listings × 3 files, each crop lies inside 1024×1536, each ZIP entry exists, and no value contains a local path, URL, signature or hash.

## 8. Contact sheet

`docs/superpowers/validation/hpa-924-evidence/contact-sheet.png` is the only file in its folder. It is a 2024×1638 px RGB PNG of 1,950,521 bytes (1.86 MiB) with no text metadata.

Layout: a 4×3 grid of per-ID cells in rank order (E to S), each labelled with its id.
- Larger renders: portrait at 180×270; face square at 128; face circle at 128 (circle-clipped, on dark); chibi at 128 on dark and on light.
- True-size samples on 64 px swatches, dark `#14171c` and light `#f2f2f2`, with each sample centred: face circle 40 px, face square 40 px and chibi 48 px.

Rendering: Pillow 13.0.0 from the committed `assets/images/characters/{id}/` files, saved with `optimize=True`. Every downscale is Pillow `LANCZOS`. That is a smooth approximation of the app's `FilterQuality.medium`, not a pixel match. The circle clip is an antialiased mask, and the sheet uses no nearest-neighbour. The renderer is not committed, as in sections 1–5. The sheet is static: there is no browser page and no MCP capture.

Visual inspection (my own viewing of every cell at native size, plus a 2x enlargement of the 40 px and 48 px samples as a scratch viewing aid that is not part of the sheet):
- Read well at 40 px on dark: akane (red hair), jin (silver hair and blue eye), kaito, haruto (brown hair and orange scarf), mio, elena (white cap and rifle) and hikari.
- Weakest at 40 px: shiori and rin. Dark hair dominates the chip and the face detail is minimal. ren is readable as dark hair on a lilac disc but has little facial detail.
- On light, the pale backgrounds of rin, jin and hikari lose much of their edge against `#f2f2f2`, for both the circle and the square. The dark swatch is the clearer view for them.
- Chibi 48 on dark: all twelve read as distinct characters. The dimmest are sayo, shiori and ren, whose dark hood, coat and outfit sit close to `#14171c`.
- Chibi 48 on light: all twelve read. hikari (cream and gold dress) and rin (lilac and white) are the faintest and rely on the halo, staff and hair accents.
- No clipping or overlap appeared in any cell or in the header at native size.

These judgments are visual, from the 2x view; I did not measure contrast. Identity, outfit and effects were judged on the sheet itself. A side-by-side against the approved JPG exports was not done in this checkpoint.

## Status

- Checkpoints 1–4 complete. Checkpoint 5 (final-head CI, MCP Chrome E2E at 390×844 and 320×568, Codex/Camp checks of the five retouched chibis) is NOT yet done.
