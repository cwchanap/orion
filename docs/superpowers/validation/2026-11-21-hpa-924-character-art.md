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

## Status

- Checkpoints 1–2 complete
