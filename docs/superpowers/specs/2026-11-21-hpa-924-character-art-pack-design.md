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
- `test/game/character_art_contract_test.dart` pins the existing 24 paths, dimensions, RGBA chibi PNG type (6), manifest entries and descriptor behavior. **Extend that one test** instead of adding a separate Python audit or a duplicated string-ID registry.
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
- **Finalize current portraits/chibis before creating faces.** The face crop must be taken from the *final* approved portrait. Use a centered circle-safe crop preserving hair and face, with its exact source rectangle and final portrait SHA-256 recorded so any later portrait edit triggers a mechanical re-crop check. Never crop from the 512px chibi. Generate a new reference-conditioned face only if an approved portrait cannot yield a recognizable 40px thumbnail.
- Reuse approved chibi samples or generate/retouch individual per-ID files as needed; never ship a combined atlas.

## Optimization and provenance

- Around 200 KB per card remains a **best-effort size goal**; existing portraits are ~1–2.2 MiB, so preserve image quality, fixed resolution and PNG extension over arbitrary compression. Record before/after file sizes and reasons for outliers.
- For portraits, try lossless PNG optimization first; palette reduction is optional **for portraits only** and needs visible quality comparison. For chibis, **no color-type reduction or indexed palette**: use lossless optimization that preserves PNG color type 6 (e.g. `oxipng --nc`) or keep unchanged. After any claimed lossless rewrite, compare **decoded RGBA pixel values** before/after and record pixel equality. Pixel-identical assets need no repeated in-game visual review.
- Write `assets/images/characters/provenance.json` as a JSON object keyed once per canonical `{id}/{filename}` (36 keys), broadly following the existing `assets/audio/music_provenance.json` convention. Each record identifies the approved source ZIP/entry or current approved artifact, method (reused, optimized, cropped, retouched, generated), reference ID, and any crop rectangle and **source portrait SHA-256**. Include generation model and exact prompt **only when generation actually occurred**; say no model for local crops/reuse. **Do not store output hashes**: Git already pins the final files, and an unvalidated duplicate hash becomes stale.
- Do not commit original reference ZIPs, temporary candidates, API keys, source credentials or local/private paths.

## Permanent CI contract

Extend `test/game/character_art_contract_test.dart` **in the same asset PR**. No new production dependencies or separate Python package/CI job.

1. Continue looping over `Character.values`. Assert exactly three files in every per-ID directory, `portrait.png` 1024×1536, `face.png` 512×512 with fully opaque decoded alpha, `chibi.png` 512×512 RGBA (color type 6), all valid PNGs. No stray file is allowed in a registered directory because Flutter bundles it.
2. Decode chibi pixels in the existing Flutter test with `dart:ui` (for example `instantiateImageCodec` and `toByteData(format: ImageByteFormat.rawRgba)`); require the 1-pixel border's alpha to be zero on all four edges. This is a persistent transparent-edge and gross-clipping guard; the contact sheet still checks the actual silhouette and detail.
3. Load provenance JSON and assert that its key set equals exactly `Character.values × {portrait.png,face.png,chibi.png}`. Do not hard-code a parallel 12-ID table or bring in Pillow to CI.
4. Preserve existing `OrionArt` descriptor/path, chibi color-type and manifest assertions. The new `face.png` is intentionally not required to have a UI descriptor until HPA-926.
5. Write the test first within this one PR; it will fail while face images/provenance are missing. **Do not merge the PR until it is green.** Run `flutter analyze`, `flutter test` and `flutter build web --release` on final head.

## Visual evidence and MCP E2E acceptance

- Generate **one static PNG contact sheet**, with all 36 finals plus 40px face and 48px chibi samples on dark/light backgrounds (smooth scaling consistent with `FilterQuality.medium`). Use local temporary image processing under ignored `tmp/` and commit only the composite PNG under `docs/superpowers/validation/hpa-924-evidence/`, not a separate browser page.
- Compare changed artwork's *identity, outfit, effects and relative sprite scale* with the approved HPA-921/HPA-924 art and HPA-922 mockups 10/11/14/15. For **current UI layout/background**, compare MCP captures against the existing `docs/superpowers/validation/hpa-922-evidence/` screenshots; do not relog the deliberately unfinished winter retheme as an HPA-924 defect.
- **Always execute a minimal MCP Chrome end-to-end smoke** through the real game (title → Codex → view character entries, no reload or stage victory). The Codex shows **all 12 chibis** without a recruited roster, fixing the starter-only visibility gap. Capture at **390 × 844** and **320 × 568** and assert no fallback/broken art.
- Concentrate **additional** MCP visual checks only on assets whose **decoded pixels changed**, not retained or pixel-identical optimized files: changed chibis via the relevant Codex entries; changed starter portraits via Camp/sheet, changed non-starter portraits via an isolated profile with seeded ownership (if practical), otherwise via the contact sheet with that limitation recorded; changed deployable chibis may also be observed on battle board if reachable without new gameplay setup. No repeat of HPA-922 full eight-wave run, cache/reload checks, or contact-sheet browser screenshot.
- The new `face.png` is not visible in a production screen until HPA-926, so validate all faces through the static contact sheet, not by inventing a temporary UI. Record screenshots, comparisons and deviations in `docs/superpowers/validation/2026-11-21-hpa-924-character-art.md`. **MCP is required** for E2E, and one web platform is enough.

## End-to-end acceptance (no human gate)

1. All **36 canonical PNG files** pass the **extended in-repo Flutter contract** in CI: correct names, dimensions, chibi RGBA/transparent edges, directory cleanliness and exactly 36 provenance keys.
2. Every final image derives from or is compared with the approved source; changed artwork and 40/48px legibility are visible in the static contact sheet, with circle-safe opaque faces and original summer/v2 outfits. Per-image keep/redo decisions, byte sizes and decoded-pixel equality for losslessly optimized files are recorded.
3. The **MCP browser E2E** reaches the real Codex and verifies all 12 chibis. Screenshot checks at both sizes are compared with HPA-922 baseline UI evidence and relevant approved Linear mockups; targeted extra captures address only pixel-changed runtime art.
4. Final-head `flutter analyze`, `flutter test`, `flutter build web --release` and CI pass. Production `lib/`, image paths, `pubspec.yaml` and mechanics stay unchanged.
5. Planning, final art, provenance, contact sheet, test extension and evidence remain in **this same HPA-924 PR**; HPA-925/926/927 are separate. No native acceptance or manual sign-off criterion.
