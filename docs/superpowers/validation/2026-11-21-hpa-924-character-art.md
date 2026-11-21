# HPA-924 — Last Hearth character art validation

- **Date:** 2026-11-21
- **Plan:** [character art pack plan](../plans/2026-11-21-hpa-924-character-art-pack.md) · **Design:** [character art pack design](../specs/2026-11-21-hpa-924-character-art-pack-design.md)
- **PR:** [#52](https://github.com/cwchanap/orion/pull/52)

This note validates the Last Hearth character art pack under `assets/images/characters/{id}/`: the source audit and chibi border retouch of the 24 pre-existing PNGs, the portrait optimization experiment, the 12 new face thumbnails, the provenance file and contact sheet, and the automated checks plus the MCP Chrome Codex run.

## 1. Scope and approved source

- **Approved source:** Linear HPA-924 attachment "Approved character concepts and chibi sprites, full size, with prompts (zip)" (approved concept set; lineup approved 2026-11-17). The ZIP is **not committed**; it stays local and private.
- **ZIP SHA-256:** `7bd5791d230ef8103aa85b9350745f63a1bb74a052c1331a7b5a8952abd8f8e5` (6,317,337 bytes, 25 files).
- **Entry naming:** `character-concepts-v3/{rank}{n}-{given}-{family}.jpg` (12 concept portraits), `character-concepts-v3/chibi/{rank}{n}-{given}-{family}.png` (12 chibis) and `character-concepts-v3/character-prompts.json`. Each repo ID maps to exactly one JPG and one PNG by the given-name segment, for example `e1-haruto-sakaki` → `haruto`.
- **Comparison:** SHA-256 of each repo file against the SHA-256 of its ZIP entry bytes. The portrait source is JPEG and the repo copy is PNG, so portraits are also compared by decoding both to RGB at 1024×1536. Chibi border and bounding-box checks use decoded RGBA. Tooling: Python 3 with Pillow 13.0.0 (no numpy); scripts are not committed.

## 2. Audit of the 24 existing files

Rows are in rank order (E to S). Repo bytes are sizes before this change. 12 of 24 files were SHA-256 identical to their ZIP entry before this change: all 12 chibis, and no portrait. Decisions (matching `provenance.json` `method` values): **reuse** = repo PNG left byte-unchanged from HPA-922 (either byte-identical to the approved PNG entry, or decoded-pixel-matched to the approved JPG reference within JPEG tolerance); **retouch** = changed, see section 3. Outcome: 12 portraits reuse (decoded RGB matches the approved JPG), 7 chibis reuse (byte-identical to the approved PNG), 5 chibis retouch.

| ID | File | Repo bytes | Source ZIP entry | SHA-256 identical | Decision | Reason |
| --- | --- | ---: | --- | --- | --- | --- |
| haruto | portrait.png | 1,053,927 | `character-concepts-v3/e1-haruto-sakaki.jpg` | no (JPG vs PNG) | reuse | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.76/0.21/1.02, max 34/13/42. Repo PNG reused byte-unchanged. |
| haruto | chibi.png | 192,583 | `character-concepts-v3/chibi/e1-haruto-sakaki.png` | yes | reuse | Byte-identical to the approved chibi. Border clean; RGBA 512×512, color type 6; minimum opaque margin 5 px. |
| mio | portrait.png | 1,225,337 | `character-concepts-v3/e2-mio-tachibana.jpg` | no (JPG vs PNG) | reuse | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.54/0.28/0.49, max 29/14/46. Repo PNG reused byte-unchanged. |
| mio | chibi.png | 251,405 | `character-concepts-v3/chibi/e2-mio-tachibana.png` | yes (before retouch) | retouch | Byte-identical to the approved chibi, but 45 border pixels on the bottom row carry alpha 1–2, which breaks the fully transparent 1-px border. Border-only clear (section 3). |
| sayo | portrait.png | 1,311,882 | `character-concepts-v3/d1-sayo-kitami.jpg` | no (JPG vs PNG) | reuse | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.35/0.16/0.40, max 20/8/26. Repo PNG reused byte-unchanged. |
| sayo | chibi.png | 274,014 | `character-concepts-v3/chibi/d1-sayo-kitami.png` | yes | reuse | Byte-identical to the approved chibi. Border clean; RGBA 512×512, color type 6; minimum opaque margin 12 px. |
| tetsuo | portrait.png | 1,409,813 | `character-concepts-v3/d2-tetsuo-kanda.jpg` | no (JPG vs PNG) | reuse | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.49/0.23/0.66, max 28/12/42. Repo PNG reused byte-unchanged. |
| tetsuo | chibi.png | 265,750 | `character-concepts-v3/chibi/d2-tetsuo-kanda.png` | yes (before retouch) | retouch | Byte-identical to the approved chibi, but 49 border pixels on the bottom row carry alpha 1–2, which breaks the fully transparent 1-px border. Border-only clear (section 3). |
| rin | portrait.png | 1,379,553 | `character-concepts-v3/c1-rin-fuyutsuki.jpg` | no (JPG vs PNG) | reuse | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.75/0.18/1.08, max 15/6/24. Repo PNG reused byte-unchanged. |
| rin | chibi.png | 264,194 | `character-concepts-v3/chibi/c1-rin-fuyutsuki.png` | yes | reuse | Byte-identical to the approved chibi. Border clean; RGBA 512×512, color type 6; minimum opaque margin 10 px. |
| kaito | portrait.png | 1,488,390 | `character-concepts-v3/c2-kaito-narumi.jpg` | no (JPG vs PNG) | reuse | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.76/0.32/1.90, max 31/17/63. Repo PNG reused byte-unchanged. |
| kaito | chibi.png | 258,416 | `character-concepts-v3/chibi/c2-kaito-narumi.png` | yes (before retouch) | retouch | Byte-identical to the approved chibi, but 23 border pixels on the bottom row carry alpha 1, which breaks the fully transparent 1-px border. Border-only clear (section 3). |
| elena | portrait.png | 1,347,088 | `character-concepts-v3/b1-elena-volkova.jpg` | no (JPG vs PNG) | reuse | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.36/0.23/0.74, max 21/9/13. Repo PNG reused byte-unchanged. |
| elena | chibi.png | 278,705 | `character-concepts-v3/chibi/b1-elena-volkova.png` | yes | reuse | Byte-identical to the approved chibi. Border clean; RGBA 512×512, color type 6; minimum opaque margin 7 px. |
| shiori | portrait.png | 1,306,037 | `character-concepts-v3/b2-shiori-kusanagi.jpg` | no (JPG vs PNG) | reuse | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.28/0.15/0.41, max 15/10/37. Repo PNG reused byte-unchanged. |
| shiori | chibi.png | 263,445 | `character-concepts-v3/chibi/b2-shiori-kusanagi.png` | yes (before retouch) | retouch | Byte-identical to the approved chibi, but 10 border pixels on the top row carry alpha 1, which breaks the fully transparent 1-px border. Border-only clear (section 3). |
| akane | portrait.png | 1,926,556 | `character-concepts-v3/a1-akane-hinomori.jpg` | no (JPG vs PNG) | reuse | Decoded RGB matches the approved JPG: mean abs diff R/G/B 1.74/0.94/1.42, max 49/24/49. Repo PNG reused byte-unchanged. |
| akane | chibi.png | 344,101 | `character-concepts-v3/chibi/a1-akane-hinomori.png` | yes | reuse | Byte-identical to the approved chibi. Border clean; RGBA 512×512, color type 6; minimum opaque margin 6 px. |
| ren | portrait.png | 1,842,705 | `character-concepts-v3/a2-ren-kurosawa.jpg` | no (JPG vs PNG) | reuse | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.41/0.39/0.83, max 12/11/34. Repo PNG reused byte-unchanged. |
| ren | chibi.png | 336,967 | `character-concepts-v3/chibi/a2-ren-kurosawa.png` | yes | reuse | Byte-identical to the approved chibi. Border clean; RGBA 512×512, color type 6; minimum opaque margin 12 px. |
| hikari | portrait.png | 2,268,780 | `character-concepts-v3/s1-hikari-amatsu.jpg` | no (JPG vs PNG) | reuse | Decoded RGB matches the approved JPG: mean abs diff R/G/B 1.58/0.78/2.07, max 39/19/48. Repo PNG reused byte-unchanged. |
| hikari | chibi.png | 392,926 | `character-concepts-v3/chibi/s1-hikari-amatsu.png` | yes (before retouch) | retouch | Byte-identical to the approved chibi, but 6 border pixels on the left column carry alpha 1, which breaks the fully transparent 1-px border. Border-only clear (section 3). |
| jin | portrait.png | 2,172,666 | `character-concepts-v3/s2-jin-kamishiro.jpg` | no (JPG vs PNG) | reuse | Decoded RGB matches the approved JPG: mean abs diff R/G/B 0.97/0.34/1.16, max 21/9/38. Repo PNG reused byte-unchanged. |
| jin | chibi.png | 307,766 | `character-concepts-v3/chibi/s2-jin-kamishiro.png` | yes | reuse | Byte-identical to the approved chibi. Border clean; RGBA 512×512, color type 6; minimum opaque margin 8 px. |

**Portrait finding.** All 12 repo portraits are 1024×1536 RGB PNG (color type 2). None is byte-identical to its approved JPG, which is expected for JPG versus PNG. Decoded pixels agree closely: the mean absolute difference is at most 2.07 per channel and the largest single-channel difference is 63 (kaito, blue). At most 0.6 % of channel values differ by more than 16. A 32×32-cell difference map (largest cell mean 13, hikari) shows the residual along figure outlines and textured detail, with no uniform patch, which matches JPEG compression on the approved export. The repo PNGs are reused byte-unchanged from the HPA-922 repo copy, as their decoded RGB pixels match the approved JPG references within JPEG tolerance. Outfit, hair and effect continuity follow from the pixel agreement, and no portrait needed retouching.

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

1. Pillow lossless re-encoding (`optimize=True`) saves only 5–14 % (oxipng and zopfli were not tried), far short of the goal.
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

Method: each `face.png` is a square crop of the committed `portrait.png` at the rectangle in the table (final-portrait pixels, top-left origin, `side` × `side`). The crop is resized to 512×512 with Pillow `LANCZOS` and saved as an 8-bit RGB PNG with `optimize=True`, so every face is fully opaque (color type 2). Method `cropped`. Each crop frames the essential face, crown hair and defining headgear inside the centred inscribed circle (diameter `side`); five accepted circle-rim overflows for trailing hair tails, outer cap corners or hair-pin tips are recorded in the table and below so that face scale stays readable at 40 px. No production screen draws `face.png` until HPA-926.

| ID | Crop x | Crop y | Side | Upscale (512 / side) | face.png bytes | Fit and decision |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| haruto | 332 | 0 | 288 | 1.778 | 311,896 | Hair and face inside. Scarf and jacket collar outside (clothing). |
| mio | 310 | 0 | 460 | 1.113 | 355,781 | Largest crop. Hair crown and ribbon inside (closeup checked at checkpoint 3). |
| sayo | 199 | 22 | 352 | 1.455 | 306,856 | Hood, goggles and face inside. Accepted circle-rim overflow: long side braid runs past the bottom rim; bow hand and arrow cross the rim (props). |
| tetsuo | 374 | 0 | 288 | 1.778 | 325,983 | Spiky hair, goggles and beard inside. Background props in the upper-left corner outside. |
| rin | 342 | 0 | 304 | 1.684 | 357,866 | Bob hair, snowflake ornament, blue highlights and face fully inside. Cape and hood outside (clothing). Tightened from `302,0,380` for 40 px legibility. |
| kaito | 371 | 0 | 304 | 1.684 | 330,012 | Spiky hair and face inside, tips close to the top rim. Goggles and collar outside (clothing). |
| elena | 355 | 0 | 320 | 1.600 | 379,019 | Face, silver hair and braid top inside. Accepted circle-rim overflow: outer cap rim corners extend past the circle (headwear; `y=0` is already at the top portrait edge). |
| shiori | 328 | 0 | 320 | 1.600 | 357,652 | Bun, glasses, white hair streak and right-side hair inside. Coat lapels outside (clothing). Tightened from `274,0,420` for 40 px legibility; accepted circle-rim overflow on outer left hair-pin tips. |
| akane | 323 | 38 | 368 | 1.391 | 431,351 | Tiara, bangs and face inside. Accepted circle-rim overflow: long ponytail tips extend past the right rim; fire and tassel props outside. Recropped after review. |
| ren | 393 | 10 | 288 | 1.778 | 323,046 | Head and hair fully inside. Kept at the minimum 288 px crop (crown hair fills the circle). Background rock props in the upper corners outside. |
| hikari | 336 | 40 | 288 | 1.778 | 404,684 | Head and upper hair ornament inside. Kept at the minimum 288 px crop; accepted circle-rim overflow on long hair tails at lower left and right; halo outside. |
| jin | 415 | 0 | 288 | 1.778 | 369,477 | Hair inside, top strands near the rim. Kept at the minimum 288 px crop (the head is about 160 px wide in the portrait). Fur collar and chain props outside. |

Crop revisions across reviews: in commit `e3d087a`, shiori moved from `245,0,430` to `274,0,420` to drop a clipped prop sliver at the left edge, and akane moved from `323,0,368` to `323,38,368` to centre the head with less empty headroom. In the follow-up review pass, shiori was tightened to `328,0,320` (+31 % face scale) and rin from `302,0,380` to `342,0,304` (+25 % face scale) so their facial features, glasses and snowflake hair ornament read at 40 px without cropping the crown hair or bun.

Fit and accepted circle-rim overflows (re-checked on 256 px circle overlays of all 12 faces and on a 512 px overlay of sayo):
- **elena** (outer cap rim corners), **sayo** (lower side braid), **shiori** (outer left hair-pin tips), **akane** (far ponytail tips) and **hikari** (long lower hair tails) extend past the inscribed circle rim and are recorded as accepted exceptions. In the source portraits, sayo's braid, akane's ponytail and hikari's hair tails reach waist level (`y = 550..600+`) or the 1024 px portrait edge; widening their crops to contain the full tails would turn the face crop into a half-body shot (`side` 550–900 px) and shrink the face at 40 px to ~6–10 px. For elena (`y = 0, side = 320`), the cap crown sits 8 px below the top edge of the portrait, so the crop cannot shift higher, and widening `side` to tuck in the outer brim tips would shrink the face. For shiori (`328,0,320`), letting the two outer left hair-pin tips cross the rim allows a 320 px crop instead of 420 px so her glasses and eyes are legible at 40 px.
- Everything else outside the rim is clothing, props, effects or background.

Verification: each `face.png` was reproduced from the committed portrait and its recorded rectangle with mean abs diff 0 (max 0 in every channel): 12 of 12.

Size: the 12 faces total 4,253,623 bytes (4.06 MiB). They are full-detail RGB PNG with no palette or indexed reduction, and no soft size goal is claimed for them.

## 7. Provenance file

`assets/images/characters/provenance.json` (new) has one record per art file: 36 keys `{id}/{filename}` in rank order, following the record-by-asset layout of `assets/audio/music_provenance.json`. Every record has `role` (`card`, `face` or `chibi`), `method`, `approval`, `source`, `reference` (the `character-prompts.json` key), `model` and `prompt` (both `null` because nothing was generated). The `approval` field distinguishes pre-existing HPA-922 files from assets produced or modified in this PR: `"HPA-924 approved concept set; HPA-922 repo copy"` for the 19 `reused` files, `"HPA-924 approved concept set; cropped in HPA-924 from HPA-922 portrait.png"` for the 12 `cropped` faces, and `"HPA-924 approved concept set; 1px border retouched in HPA-924"` for the 5 `retouched` chibis. Faces also carry `crop` (`x`, `y`, `side` and `resize`), and `note` records the pixel/audit details, tightening history, or accepted circle-rim overflow and 40 px keep rationale.

| Method | Records | Files |
| --- | ---: | --- |
| reused | 19 | 12 portraits (repo PNG reused byte-unchanged; decoded RGB matches the approved JPG within JPEG tolerance) and 7 chibis (byte-identical to the approved PNG) |
| retouched | 5 | chibis for mio, tetsuo, kaito, shiori and hikari; border alpha cleared on 45, 49, 23, 10 and 6 pixels |
| cropped | 12 | every `face.png`, cut from the committed portrait at the section 6 rectangle |
| **Total** | **36** | |

The file has no hash fields. Git pins the final files, and the review rounds dropped unenforced hashes, so the ZIP entry, the reference key and the crop rectangle are the only source identifiers.

The file sits in the parent folder, outside the 12 per-ID directories that `pubspec.yaml` registers, so Flutter does not bundle it. The contract test asserts that `provenance.json` is absent from the `AssetManifest` and validates every record's `role`, `method`, `approval`, `source`, `reference` and `model`/`prompt` fields.

Before commit, a scratch check confirmed that the JSON parses, the 36 keys equal the 12 directory listings × 3 files, each crop lies inside 1024×1536, each ZIP entry exists, and no value contains a local path, URL, signature or hash.

## 8. Contact sheet

`docs/superpowers/validation/hpa-924-evidence/contact-sheet.png` is the only contact sheet in its folder (the folder also holds the four Codex captures from section 9). It is a 2024×1638 px RGB PNG of 1,956,955 bytes (1.87 MiB) with no text metadata.

Layout: a 4 columns × 3 rows of per-ID cells in rank order (E to S), each labelled with its id.
- Larger renders: portrait at 180×270; face square at 128; face circle at 128 (circle-clipped, on dark); chibi at 128 on dark and on light.
- True-size samples on 64 px swatches, dark `#14171c` and light `#f2f2f2`, with each sample centred: face circle 40 px, face square 40 px and chibi 48 px.

Rendering: Pillow 13.0.0 from the committed `assets/images/characters/{id}/` files, saved with `optimize=True`. Every downscale is Pillow `LANCZOS`. That is a smooth approximation of the app's `FilterQuality.medium`, not a pixel match. The circle clip is an antialiased mask, and the sheet uses no nearest-neighbour. The renderer is not committed, as in sections 1–5. The sheet is static: there is no browser page and no MCP capture.

Visual inspection and 40 px keep/re-crop decisions (from viewing every cell at native size plus a 2x enlargement of the 40 px and 48 px samples as a scratch viewing aid that is not part of the sheet):
- Read well at 40 px on dark: akane (red hair), jin (silver hair and blue eye), kaito, haruto (brown hair and orange scarf), mio, elena (white cap and rifle), hikari, and — after tightening their crops from `420→320` and `380→304` — shiori (glasses, white hair streak and bun) and rin (eyes, snowflake ornament and blue hair highlight).
- Tightened in follow-up review: shiori (`274,0,420` → `328,0,320`) and rin (`302,0,380` → `342,0,304`). The earlier 420 and 380 crops included mid-chest coat/cape area that shrank the face inside the 40 px chip; the tighter 320 and 304 crops enlarge the face by 31 % and 25 % while keeping the full head, bun/bob and ornaments inside the circle.
- Explicit **keep** decision for ren, jin and hikari at `side = 288`: all three are already at the minimum 288 px head crop where crown hair reaches the inscribed circle, so tighter cropping would clip their hair. ren reads as dark hair and purple eyes on a lilac disc (inherent to the approved portrait palette). On the light `#f2f2f2` swatch, the pale portrait backgrounds of rin, jin and hikari have lower edge contrast than on dark, though rin's tighter crop removes most of her white hood; all three are kept without background retouching or regeneration because Last Hearth squad chips and HUD chrome render on dark surfaces (where `#14171c` gives clear edge separation) and preserving portrait-derived backgrounds is required by the spec.
- Chibi 48 on dark: all twelve read as distinct characters. The dimmest are sayo, shiori and ren, whose dark hood, coat and outfit sit close to `#14171c`.
- Chibi 48 on light: all twelve read. hikari (cream and gold dress) and rin (lilac and white) are the faintest and rely on the halo, staff and hair accents.
- No clipping or overlap appeared in any cell or in the header at native size.

These judgments are visual, from the 2x view; I did not measure contrast. Identity, outfit and effects were judged on the sheet itself. A side-by-side against the approved JPG exports was not done in this checkpoint.

## 9. Automated checks and MCP Chrome E2E

The initial Part A and E2E passes ran on `735beb5` (repeating an earlier `9928729` pass). Commits `0367893` and `6cc3a6e` then added the 15th test (`every face entry names its source portrait and crop rectangle`) and formatted `test/game/character_art_contract_test.dart`; PR #52's remote CI checks passed on `6cc3a6e`. In the final review follow-up, the provenance test was extended to validate every record's `role`, `method`, `approval`, `source`, `reference`, and `model`/`prompt` presence and values; `rin/face.png` and `shiori/face.png` were tightened (`contact-sheet.png` and `provenance.json` updated); and the incidental `pubspec.lock` refresh from the host's newer Flutter was reverted so this PR carries no dependency changes. The contract test and format check were re-run locally (`+15: All tests passed!`), and final-head PR CI passed every check (see Part A). None of the runtime assets requested by the Codex E2E (`chibi.png`) or Camp (`portrait.png`) changed after `735beb5`.

### Part A: automated checks (local focused rerun; final-head CI is authoritative)

| Command | Result | Notes |
|---|---|---|
| `flutter test test/game/character_art_contract_test.dart` | `+15: All tests passed!`, exit 0 | Re-run on the final review-follow-up head: all 36 decoded PNGs, face opacity, chibi border alpha, provenance schema/crop rectangles and `AssetManifest` membership |
| `dart format --output=none --set-exit-if-changed test/game/character_art_contract_test.dart` | exit 0, `Formatted 1 file (0 changed)` | Re-run on the final review-follow-up head |
| `flutter analyze` | exit 1: `67 issues found`, 0 warnings, 0 errors | All 67 are info-level `deprecated_member_use` on `package:flutter/material.dart`. The contract test's import at line 6 is the same import on `main`. Remote `Build & lint` passes on the final head. |
| `flutter test` (whole suite) | `+1845 -133` (1,978 tests at `735beb5`; 1,979 tests with the 15th contract test), exit 1 locally; **remote `Unit test` passes on the final head** | All 133 local failures are in widget tests (see below). `test/game/`, components, feedback and the contract test all pass. |
| `flutter build web --release` | `✓ Built build/web`, exit 0, 1m25s | Local run at `735beb5` (CanvasKit from the gstatic CDN; `build/` is git-ignored). Final-head CI repeats the release web build. |

Full-suite failures (133): `widget/mission_chrome_test.dart` 33, `widget/camp_view_test.dart` 27, `widget/stage_briefing_sheet_test.dart` 21, `widget/codex_view_test.dart` 19, `widget/flare_view_test.dart` 14, `widget/tower_inspector_test.dart` 7, `widget/mission_command_dock_test.dart` 5, `widget/scene_parity_regression_test.dart` 3, `widget/orion_typography_test.dart` 3, `widget/world_map_command_deck_test.dart` 1. Every failure has the same message: `An animation is still running even after the widget tree was disposed.`, with a pending `RelayoutWhenSystemFontsChangeMixin` frame callback. The same 133 test names fail on a `git archive main` snapshot run with the same resolved packages (`+333 -133` for those ten files), and they also failed on the earlier full pass, which started at `9928729` and overlapped the `735beb5` commit. They therefore predate this change and were not touched here. The remote unit job passes on both `38c44eb` and `6cc3a6e`, which confirms a host-specific difference (this host re-resolves `clock`, `test_api` and `stack_trace` to newer versions than `pubspec.lock` pins, and runs Flutter 3.50.0 while CI pins 3.47.9). The authoritative run of the whole suite is the PR's CI (`gh pr checks 52`).

Remote PR checks on the final head: Build & lint, Unit test, Integration test (Android), Android and iOS debug builds, Audio asset contract and codecov/patch all passed. The earlier `38c44eb`, `c9e2f8d` and `6cc3a6e` heads passed the same jobs.

### E2E method (MCP Chrome)

- **Browser:** browser-use MCP `browser_exec` in local mode. The tool drove its own Chromium on a temp profile, not a user Chrome. No cloud browser, no login, and no site other than the local app was opened.
- **Build:** `flutter build web --release --no-web-resources-cdn` (1m30s), so CanvasKit is served locally. Browser `performance.getEntriesByType('resource')` recorded 64 subresource fetches to `127.0.0.1` (50 uncached subresource HTTP GETs served by `http.server` plus 14 repeat asset fetches satisfied from Chromium's in-memory cache during widget rebuilds and detail selections).
- **Server:** `python3 -m http.server 8917 --bind 127.0.0.1 --directory build/web`, stopped after the captures.
- **Viewports:** 390×844 and 320×568, device scale 2, mobile emulation with touch on. The viewport changed through CDP without a reload.
- **Path:** Title → Codex. The Codex button was located through Flutter's semantics tree. No stage, no wave, no reload.
- **Checks:** every tile at 390 and 320 was compared side by side with its approved chibi. The six inspected details (Hikari, Kaito, Mio, Shiori, Tetsuo, Haruto) were checked at 390, and Mio at 320.

### Per-character comparison

Approved references are `character-concepts-v3/chibi/*.png`. "Identical" means the repo chibi is byte-identical to `main` and its decoded RGBA equals the approved file.

| Character (rank) | Tile 390 | Tile 320 | Detail (56 px) | Versus approved chibi | Retouched? |
|---|---|---|---|---|---|
| Hikari (S) | OK | OK | 390 OK | Matches: white and gold robe, golden sun staff | Yes, 6 px (alpha 1→0, left edge x=0, y 86–93). No visible change. |
| Jin (S) | OK | OK | not opened | Matches: silver hair, navy coat, blue flame | No, identical |
| Akane (A) | OK | OK | not opened | Matches: red hair, red and gold outfit, flame staff | No, identical |
| Ren (A) | OK | OK | not opened | Matches: purple hair and dark coat | No, identical |
| Elena (B) | OK | OK | not opened | Matches: white cap, white coat, rifle | No, identical |
| Shiori (B) | OK | OK | 390 OK | Matches: dark hair, white coat, green magic | Yes, 10 px (alpha 1→0, top row y=0, x 194–203). No visible change. |
| Rin (C) | OK | OK | not opened | Matches: lavender hair and robe | No, identical |
| Kaito (C) | OK | OK | 390 OK | Matches: blond spiky hair, gold and black outfit, staff | Yes, 23 px (alpha 1→0, bottom row y=511). No visible change. |
| Sayo (D) | OK | OK | not opened | Matches: dark hair, green hat, bow | No, identical |
| Tetsuo (D) | OK | OK | 390 OK | Matches: brown outfit, rifle, drones | Yes, 49 px (43 alpha 1→0, 6 alpha 2→0, bottom row). No visible change. |
| Haruto (E) | OK | OK | 390 OK | Matches: brown hair, orange scarf, rifle | No, identical |
| Mio (E) | OK | OK | 390 OK, 320 OK | Matches: orange ponytail, red and white outfit, flame staff | Yes, 45 px (33 alpha 1→0, 12 alpha 2→0, bottom row). No visible change. |

For the five retouched chibis, every pixel off the outermost 1-px border is identical to the approved file. The only changes are border pixels with alpha 1 or 2 (some carried non-zero RGB) set to `(0,0,0,0)`, on the outermost image row or column, outside each subject's bounding box. At alpha 1 or 2 the pixels are essentially invisible. Tile chibi size (46 px) comes from the code (`Size.square(46)`), not from pixel measurement. The detail chibi measures 56×56 CSS px in the semantics tree.

### Captures (native pixels, no annotations)

- [`hpa-924-evidence/codex-grid-390x844.png`](hpa-924-evidence/codex-grid-390x844.png): 780×1688, 532,335 bytes. Full 390×844 viewport, Characters tab, Hikari selected. All 12 tiles visible.
- [`hpa-924-evidence/codex-grid-320x568.png`](hpa-924-evidence/codex-grid-320x568.png): 640×1136, 371,192 bytes. Full 320×568 viewport, Haruto selected. All 12 tiles visible without scrolling.
- [`hpa-924-evidence/codex-detail-retouched-390x844.jpg`](hpa-924-evidence/codex-detail-retouched-390x844.jpg): 2372×1084, 289,917 bytes, JPEG q85. Six native crops of the 390 detail card (CSS y 505–772), in a 3×2 layout: Hikari, Kaito, Mio, then Shiori, Tetsuo, Haruto.
- [`hpa-924-evidence/codex-detail-320x568.png`](hpa-924-evidence/codex-detail-320x568.png): 640×490, 112,434 bytes. Native crop of the Mio detail card at 320×568 (CSS y 251.5–496).

### Asset requests and manifest

- Server log: 53 requests, all HTTP 200, zero 404s (2 pre-session readiness probe GETs for `/` and `haruto/chibi.png`, plus 51 browser requests during the E2E session: 1 document `GET /` and 50 subresource GETs; the remaining 14 of the 64 browser `resource-timing` entries were repeat subresource fetches served from Chromium's in-memory cache). The page requested all 12 `chibi.png` files (`haruto` twice on the server, when its tile was rebuilt, still 200) and `AssetManifest.bin.json` (200).
- `face.png`, `portrait.png` and `provenance.json` were never requested by the page.
- `AssetManifest.bin` (identical to the decoded `AssetManifest.bin.json`) contains all 36 character keys (12 folders × chibi, face, portrait). The string `provenance` does not occur in it.

### Deviations and known gaps

- **Full suite (local):** 133 failures in 10 widget test files, identical on a `main` snapshot run on the same host; not fixed here (see above).
- **Lock file:** `pubspec.lock` was modified locally by the host's Flutter re-resolution and is NOT part of the PR (never committed; restored before the push). Flutter re-resolves transitive packages on each `flutter test`: `clock` 1.1.2→1.1.3, `stack_trace` 1.12.1→1.12.2, `test_api` 0.7.12→0.7.14, a new `listen` 1.0.1, and a changed `vector_math` hash. The `main` snapshot re-resolved to the same versions, so the comparison is fair.
- **Two web builds:** the default build (1m25s, gstatic CanvasKit) and the local-CanvasKit build used for E2E (1m30s).
- **Head moved during the run:** `735beb5` landed during the first pass, so Part A was repeated on it. The E2E build was made from the same bundled inputs.
- **Detail composite format:** JPEG q85. The PNG version was 688 KB, above the ~600 KB budget.
- **Detail crop limits:** the Signature card sits below the fold and the bottom nav at both sizes, so the crops stop above it.
- **Grid selection:** the grid captures show different selected tiles (Hikari at 390, Haruto at 320). The selection highlight is the only non-art difference.
- **Visual judgement:** comparisons were made by eye on side-by-side crops at reduced size. There is no automated image diff, and no HPA-922 Codex or 320px baseline exists.
- **No Camp portrait smoke:** no `portrait.png` bytes changed on this branch (zero files in `git diff main..HEAD`), so the Camp `Image.asset` check is not required.
- **Faces:** the 12 `face.png` files are bundled but not requested, which is by design until HPA-926. They are validated through the contact sheet only.

## Status

- Checkpoints 1–5 complete locally. The final-head CI result is shown by the PR's checks after the push.
