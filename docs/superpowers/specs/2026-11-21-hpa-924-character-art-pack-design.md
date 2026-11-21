# HPA-924 — Last Hearth character art pack (Design Spec)

Date: 2026-11-21  
Linear: https://linear.app/cwchanap/issue/HPA-924/orion-produce-the-last-hearth-character-art-pack  
Parent: https://linear.app/cwchanap/issue/HPA-921/orion-pivot-to-last-hearth-an-anime-character-tower-defense  
Follow-on integration: HPA-926  
Baseline: `main` @ `3616b232425bf340ea63d1e0a609b25ba3ac66b2`

## Outcome and boundaries

Supply the 12 approved Last Hearth characters with three final images each (**36 PNGs**): portrait/card, face thumbnail and transparent on-board chibi. Audit and reuse already approved files first, retouch or regenerate only demonstrated failures. This is **one art-delivery PR**, initially containing this spec and the implementation plan; assets, a small contract-test extension, provenance and validation evidence go into **the same PR**.

No production Dart or gameplay changes, navigation/renderer/loader edits, new mechanics, balance, UI redesign, stage art or sound. HPA-925 owns enemies and boards; HPA-927 owns SFX; HPA-926 wires the new face image into UI and performs the winter retheme. A small `test/game/character_art_contract_test.dart` change is **allowed and required** to make the final asset contract durable in CI; “asset-only” applies to production behavior, not test coverage.

## Verified existing baseline

- `assets/images/characters/{id}/` has all 12 directories with `portrait.png` (1024 × 1536) and `chibi.png` (512 × 512): 24 existing approved-source placeholder files totaling approximately 21.14 MiB. There are currently **no face images**.
- `pubspec.yaml` registers each of the 12 directories; this already includes any new `face.png` under that directory. The parent `assets/images/characters/` is not directly registered, so `provenance.json` at the parent stays out of the app bundle.
- `lib/game/ui/orion_atlas_sprite.dart` uses full-frame `characters/{character.name}/portrait.png` and `chibi.png` descriptors, including `FilterQuality.medium`. Do not rename the files or add an art loader.
- `test/game/character_art_contract_test.dart` pins the existing 24 paths, dimensions, RGBA chibi PNG type (6), `pubspec.yaml` registration text and descriptor behavior; it does not yet verify the compiled Flutter asset manifest or full PNG decoding. **Extend that one test** instead of adding a separate Python audit or a duplicated string-ID registry.
- HPA-922 and HPA-923 are merged. The current Camp hides unowned characters behind a grayscale silhouette; the Codex displays every character's chibi irrespective of ownership. Neither existing UI nor this ticket displays `face.png` yet.

## Canonical output contract

| Role | One file per `assets/images/characters/{Character.name}/` | Required properties |
| --- | --- | --- |
| Card / full-body portrait | `portrait.png` (existing runtime name, **not** `card.png`) | 1024 × 1536 PNG (2:3), full-body approved silhouette, readable against dark Camp/sheet background |
| Face thumbnail | `face.png` (**new**) | 512 × 512 **opaque** PNG, approved face, distinctive hair and upper shoulders on portrait-derived background; **essential hair and facial features fit inside the centered inscribed circle** even though the file stays square, to allow HPA-926 to clip member chips as needed; readable at 40 logical px |
| Chibi / battle | `chibi.png` (existing runtime name) | 512 × 512 **RGBA color type 6**, fully transparent 1-px border and visible transparent exterior, centered complete body with no clipped limbs/effects, ~2.5-heads-tall three-quarter-front idle pose; legible at 48 logical px on dark/light backgrounds |

**Exactly 12 IDs** from the current `Character` enum: `haruto`, `mio`, `sayo`, `tetsuo`, `rin`, `kaito`, `elena`, `shiori`, `akane`, `ren`, `hikari`, `jin`. All 36 final files live in these existing directories; do not commit alternate variants into the asset tree. The ticket's word “card” describes `portrait.png`'s job, not an additional file. The source of IDs for production checks is `Character.values`, never a second hand-maintained list.

## Art direction and source decisions

- Approved inputs: HPA-924 source ZIP (including `character-prompts.json`), HPA-921 approved lineup/chibi examples, and the approved files already present in HPA-922. Match the crisp, cel-shaded anime style and per-character facial features, colors and wardrobe.
- **Summer outfits stay:** Hikari, Akane, Mio and Kaito; the other eight keep their stylish approved v2 outfits. All characters are adults; no oversized winter gear or unapproved character redesigns.
- E/D are plain, C/B have restrained effects, A/S have stronger ability effects, with no rank labels/text burned into the images.
- **Audit first:** SHA-256/byte-compare each of the 24 current files with its ZIP source. If identical, skip redundant source-identity review and check only its final 40/48px readability; otherwise inspect the approved pair and record a specific keep/retouch/regenerate decision. Check RGBA border as a durable test. Avoid unconditional batch generation.
- **Finalize current portraits/chibis before creating faces.** The face crop must be taken from the *final* approved portrait. Use a centered circle-safe crop preserving hair and face, with its exact source crop rectangle recorded so a replacement portrait can be re-cropped deliberately. Do not add an unenforced `source_portrait_sha256` field: Git pairs the final face and source portrait, while the test checks crop completeness, not source hashes. Never crop from the 512px chibi. Generate a new reference-conditioned face only if an approved portrait cannot yield a recognizable 40px thumbnail.
- Reuse approved chibi samples or generate/retouch individual per-ID files as needed; never ship a combined atlas.

## Optimization and provenance

- Around 200 KB per card remains a **best-effort size goal**; existing portraits are ~1–2.2 MiB, so preserve image quality, fixed resolution and PNG extension over arbitrary compression. Record before/after file sizes and reasons for outliers.
- For portraits, try lossless PNG optimization first; palette reduction is optional **for portraits only** and needs visible quality comparison. For chibis, **no color-type reduction or indexed palette**: use lossless optimization that preserves PNG color type 6 (e.g. `oxipng --nc`) or keep unchanged. After any claimed lossless rewrite, compare **decoded RGBA pixel values** before/after and record pixel equality. Pixel-identical assets need no repeated in-game visual review.
- Write `assets/images/characters/provenance.json` as a JSON object keyed once per canonical `{id}/{filename}` (36 keys), broadly following the existing `assets/audio/music_provenance.json` convention. Each record identifies the approved source ZIP/entry or current approved artifact, method (reused, optimized, cropped, retouched, generated), reference ID, and any crop rectangle (source coordinates) for cropped faces. Do **not** record an unenforced `source_portrait_sha256`. Include generation model and exact prompt **only when generation actually occurred**; say no model for local crops/reuse. **Do not store output hashes**: Git already pins the final files, and an unvalidated duplicate hash becomes stale.
- Do not commit original reference ZIPs, temporary candidates, API keys, source credentials or local/private paths.

## Permanent CI contract

Extend `test/game/character_art_contract_test.dart` **in the same asset PR**. No new production dependencies or separate Python package/CI job.

1. Continue looping over `Character.values`. Assert exactly three files in every per-ID directory, `portrait.png` 1024×1536, `face.png` 512×512, and `chibi.png` 512×512 RGBA (PNG color type 6). Reject any stray files in registered folders; Flutter bundles the entire directory.
2. **Decode all 36 PNGs**, not merely the signature/IHDR. Use one async `dart:ui` `instantiateImageCodec` → `getNextFrame` → frame dimension assertion, disposing codecs/images after each file. For faces, inspect decoded alpha for fully opaque pixels; for chibis, use `toByteData(format: ImageByteFormat.rawRgba)` to assert all four 1-pixel borders have zero alpha. This catches damaged IDAT/palette files missed by `_pngInfo`, including portrait re-encodes. Keep the contact sheet for silhouette/detail judgment.
3. Load provenance JSON and assert its key set equals exactly `Character.values × {portrait.png,face.png,chibi.png}`. No duplicate 12-ID table, Pillow CI dependency or unenforced SHA check.
4. **Verify the actual asset bundle**: `AssetManifest.loadFromAssetBundle(rootBundle)` (from `package:flutter/services.dart`) must include all 36 paths under `assets/images/characters/{id}/` and must **exclude** `assets/images/characters/provenance.json`; preserve the existing `pubspec.yaml` text registration test separately. Keep the `OrionArt` descriptor/path assertions. `face.png` has no runtime descriptor until HPA-926.
5. Write the test first within this one PR; it will fail while face images/provenance are missing. **Do not merge the PR until it is green.** Run `flutter analyze`, `flutter test` and `flutter build web --release` on the final head.

## Visual evidence and MCP E2E acceptance

- Generate **one static PNG contact sheet**, with all 36 finals plus 40px face and 48px chibi samples on dark/light backgrounds (smooth scaling consistent with `FilterQuality.medium`). Use local temporary image processing under ignored `tmp/` and commit only the composite PNG under `docs/superpowers/validation/hpa-924-evidence/`, not a separate browser page.
- Compare character *identity, outfit, effects and relative sprite scale* against the approved HPA-921/HPA-924 art and relevant HPA-922 mockups. **There is no committed HPA-922 Codex baseline or 320×568 screenshot.** For Codex, inspect the new captures directly against approved character art; optionally use HPA-923 evidence for current navigation chrome. Use HPA-922/HPA-923 screenshot baselines only for matching Camp, character sheet, Flare, briefing or battle surfaces. Do not flag the unfinished winter retheme as an HPA-924 defect.
- **Always execute a minimal MCP Chrome E2E** through the real game (title → Codex → inspect the 12-character **four-column grid** at standard text scale and selected-detail chibis; no reload or victory). All 12 are visible regardless of ownership. Capture and check **390×844** and **320×568**; compare against approved art and the current UI, never an invented Codex baseline. Verify no fallback/broken assets.
- For additional MCP checks, inspect changed chibis via Codex (battle only when cheaply reachable). **If any `portrait.png` file bytes change, including pixel-identical re-encodes**, visit Camp to exercise the separate cached `Image.asset`/`cacheWidth` rendering path. If Jin, Hikari or Akane portraits change, also use the existing Flare marquee to view them in full color without ownership seeding; for other changed portraits, use Camp/sheet when owned or an isolated test profile when practical, otherwise note the static contact-sheet evidence. Skip repeat full-wave/reload tests and unchanged-art visual checks.
- The new `face.png` is not visible in a production screen until HPA-926, so validate all faces through the static contact sheet, not by inventing a temporary UI. Record screenshots, comparisons and deviations in `docs/superpowers/validation/2026-11-21-hpa-924-character-art.md`. **MCP is required** for E2E, and one web platform is enough.

## End-to-end acceptance (no human gate)

1. All **36 canonical PNG files** pass the **extended in-repo Flutter contract** in CI: correct names, dimensions, **full successful `dart:ui` image decoding** (including portraits), opaque faces, chibi RGBA/transparent edges, exact directory contents, 36 provenance keys, all images present in `AssetManifest`, and provenance absent from the bundled assets.
2. Every final image derives from or is compared with the approved source; changed artwork and 40/48px legibility are visible in the static contact sheet, with circle-safe opaque faces and original summer/v2 outfits. Per-image keep/redo decisions, byte sizes and decoded-pixel equality for losslessly optimized files are recorded.
3. The **MCP browser E2E** reaches the real Codex four-column grid and checks all 12 chibis at both sizes against approved art. Codex has no HPA-922 baseline; use current HPA-923 shell evidence if applicable. When any portrait **file bytes change**, also visit Camp to exercise cached decoding; targeted extra captures cover changed runtime art and relevant real HPA-922/HPA-923 screens.
4. Final-head `flutter analyze`, `flutter test`, `flutter build web --release` and CI pass. Production `lib/`, image paths, `pubspec.yaml` and mechanics stay unchanged.
5. Planning, final art, provenance, contact sheet, test extension and evidence remain in **this same HPA-924 PR**; HPA-925/926/927 are separate. No native acceptance or manual sign-off criterion.
