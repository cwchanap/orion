# HPA-699 — Arcade Command Deck UI Revamp (Design Spec)

Date: 2026-11-06  
Linear: https://linear.app/cwchanap/issue/HPA-699/orion-revamp-the-game-ui-so-it-looks-like-a-real-game  
Repository: cwchanap/orion  
Status: Proposed, documentation-only draft; implementation belongs in this same PR.

## Outcome and source of truth

Turn Orion's portrait Flutter/Flame UI from translucent utility-style panels into a cohesive, legible arcade command deck. This is a presentation redesign across the entire existing game, not a product-feature, game-balance, campaign-data, or persistence change.

The Linear ticket's eight screen mockups, design-kit image, and attached HTML archive (especially kit.css and board.js) are the visual acceptance reference. **Task 0 must transcribe the exact color/gradient/shadow/spacing and board-treatment tokens into a durable table in this spec (with kit.css/board.js selectors or source notes)** before coding; PR comments are not the source of truth. Do not guess or re-create approximate CSS values. The **existing game state and actual rules win** wherever visual mock data disagrees with the game.

This spec explicitly supersedes the **visual system** from the older 2026-09-08 UI Revamp Foundation and the blur-tier art direction. Keep useful architecture (ThemeExtension, OrionTypography, current view switch, sprite/backdrop pipeline, snapshot-driven UI); retire its translucent surface tiers and blur-budget tripwires instead of preserving compatibility layers.

## Verified baseline

- The app opens to _ShellView.worldMap in lib/game/ui/orion_game_page.dart; the same page already switches among worldMap, techTree, codex, and stage. No router is needed.
- OrionUiTheme in lib/game/ui/orion_ui_theme.dart is a single ThemeExtension with the current cyan-centric palette. orion_theme_data.dart and orion_typography.dart already provide the theme and local Oxanium/Chakra Petch faces.
- `orion_surface.dart` is the **single existing rendering path** for ~22 `OrionSurface`, four `OrionInnerSurface` and five `MissionSurface` sites; the latter is already a deprecated adapter. Its shared `_tierDecoration` and `BackdropFilter` make an **in-place solid conversion** possible without an interim second panel API. The t1–t4 blur values must not survive as a public kit API.
- WorldMapView owns the sector plot, crest artwork, routes, header, mission destination, and a utility rail containing Codex/R&D/Reset/Settings. Reset is implemented in OrionGamePage; settings currently live in FeedbackSettingsSheet.
- MissionChrome, MissionStatusHud, MissionPacingControls, MissionCommandDock and TowerBuildRail own battle chrome. The tower rail already supports horizontal scrolling and dragging; reuse its input behavior rather than rebuilding placement logic. `WorldMapAction` currently permits return only during `GamePhase.build`: ordinary build cannot toggle Pause, and `OrionDefenseGame.returnToMap()` rejects return during an active wave. Any map exit redesign must keep the build-phase route reachable.
- TowerInspector is a scrollable sheet with six targeting modes in a horizontal row, progression previews, and sell callbacks; TowerRadialActions lives in mission_chrome.dart.
- TechTreeView renders five **independently purchasable** upgrades in positioned rows without dependency edges. CampaignTechTree.canPurchase only checks ownership and medal budget.
- CodexView already has a working search field and section navigation (HPA-753); retain those behaviors and scroll/focus fixes.
- BoardComponent draws path, lane, build previews and spawn/base markers; BoardBackdropComponent draws the existing art; EnemyComponent paints sprites and overlays. Existing game geometry and combat authority remain untouched.
- Existing UI regression/capture helpers live under test/widget/ and test/support/reactor_rim_visual_capture.dart. Many page-level widget tests use `testGamePage`/`startStageFromBriefing` and intentionally begin on the sector map; give those fixtures a direct map-start seam without changing the product's title-first default.
- HPA-715 Endless Mode **already shipped on `main`** in PR #46 (merged 2026-11-08). Cleared-stage briefings expose the separate Endless run and committed best; HUD/scanner support unbounded waves, and Endless defeat reports have separate save/replay semantics.
- MissionReportPanel's existing return action is **World Map** (`onReturnToMap`), not a next-briefing Continue. FeedbackSettingsSheet keeps sound/music/haptics in a local `_draft`, currently committed only by Done.

## Visual language and design-system boundaries

1. **Semantic colors, one source:** extend OrionUiTheme with the kit's semantic roles: amber = one dominant action per surface, cyan = selection/information, gold = credits, violet = R&D/specializations, green = gains, orange = modifiers, red = danger, bronze/silver/gold = medals. Retain the existing base tokens where correct, with exact new values from kit.css. UI widgets consume theme roles; eliminate raw palette/gradient values in game UI.
2. **Type:** Oxanium for dominant numeric readouts/headlines and Chakra Petch for legible labels/fallback glyphs. Add `fontFamilyFallback: ['ChakraPetch']` centrally to `OrionTypography.readout` and `.title` (Oxanium lacks U+2192; the bundled Chakra Petch contains it); verify rendered arrows in a real-font widget test, **no dedicated arrow helper**. Make `microLabel`/`OrionText.micro` default to **at least 10 logical pixels**, assert explicit sizes >= 10 and migrate smaller callers in the foundation task, preserving readable 360px layouts. Preserve real copy for semantics; do not encode all-caps as accessible labels.
3. **Surfaces:** solid framed panels with lit top edges, restrained corner brackets and intentional depth. In **Task 1**, rewrite existing `OrionSurface` and its shared decoration **in place**; replace every `OrionInnerSurface`/`MissionSurface` use in the same atomic foundation change, then delete those old widgets and their tests. If layout variants are actually required, use a few **semantic roles** (floating control/card/sheet/shelf), not the old t1–t4 blur-tier names. No parallel surface API, deferred tier cleanup or generic variant engine. The existing sprite/backdrop art remains visible behind, not through, panels.
4. **Actions:** one amber primary action per decision surface; secondary cyan and destructive red. Extend existing `OrionPrimaryButton` with only needed variants and loading/disabled behavior; reuse **`orionPressDuration` (90ms)** via `orionMotionDuration`. Consolidate duplicate filled actions when their screen is restyled; remove obsolete map-rail buttons with the rail rather than inventing a universal button for icon-only controls. Do not duplicate interaction semantics or overlay a second button on an existing callback.
5. **Kit:** a pragmatic handful of reused widgets for button, solid panel/card, chip/tag, stat bar, segmented control, menu tab bar, HUD top bar, medals and modal sheet. Split only where two or more real screens benefit; avoid a generic configuration/DSL/theme engine. Replace old components in place when simpler.
6. **Motion:** use existing orionMotionDuration and reduced-motion preferences. Animations are decorative, not required to perceive state. Maintain 48dp-ish targets for controls and deliberate focus/semantics order.

## Reference tokens (Task 0 evidence — transcribed from the attached HTML kit)

Source: Linear HPA-699 attachment "Mockup HTML sources (kit.css has exact tokens)" (id `a4237b0d-d96d-4b87-aea4-6ff11f6b74a3`), a zip of `kit.css`, `board.js`, `hud.inc.js`, `icons.js`, `01-title.html`…`08-codex.html`, `09-kit.html`, `README.md` and `a/*.png` sprites. The download URL is a short-lived signed Linear URL and is deliberately not recorded here. Artboards render at 390×844. `a/rr/` maps to `assets/images/reactor_rim_ui/`; the two `@font-face` files map to `assets/fonts/Oxanium[wght].ttf` (wght 200–800) and `assets/fonts/ChakraPetch-Bold.ttf` (w700), both already bundled. Every value below is transcribed verbatim; nothing is guessed.

### Color roles — `kit.css :root` (lines 4–10) vs `OrionUiTheme.dark`

| Kit var | Value | Source | Existing `OrionUiTheme` token | Match |
|---|---|---|---|---|
| `--void` | `#05080D` | `:root` | `voidBlack` | identical |
| `--sheet` | `#080D13` | `:root` | `sheetBlack` | identical |
| `--hull` | `#0B1118` | `:root` | `hullBlack` | identical |
| `--panel` | `#111B25` | `:root` | `panelBlue` | identical |
| `--raised` | `#182532` | `:root` | `panelRaised` | identical |
| `--steel` | `#2E4658` | `:root` | `frameSteel` | identical |
| `--text` | `#F4F8FB` | `:root` | `textPrimary` | identical |
| `--muted` | `#9DB2C3` | `:root` | `textMuted` `#8EA4B5` | **differs** — kit is lighter |
| `--dim` | `#5F7487` | `:root` | — | **new token needed** |
| `--cyan` | `#46E6FF` | `:root` | `systemCyan` | identical |
| `--cyan2` | `#13B8E6` | `:root` | `systemCyanStrong` | identical |
| `--gold` | `#FFC857` | `:root` | `creditGold` | identical |
| `--amber` | `#FFA62B` | `:root` | — | **new token needed** (role: dominant action; see button gradient) |
| `--violet` | `#A98BFF` | `:root` | `systemViolet` | identical |
| `--green` | `#7BE495` | `:root` | `naniteGreen` | identical |
| `--orange` | `#FF8A3D` | `:root` | `warningOrange` | identical |
| `--red` | `#FF5D6C` | `:root` | `dangerRed` | identical |
| `--bronze` | `#D9925A` | `:root` | — | **new token needed** (medals) |
| `--silver` | `#CFDBE6` | `:root` | — | **new token needed** (medals; gold reuses `--gold`) |

`09-kit.html` "Color roles" confirms semantics: VOID=bg, PANEL=surface, STEEL=border, TEXT=primary, AMBER=main action, CYAN=info·select, GOLD=credits, VIOLET=R&D·spec, GREEN=gain, ORANGE=modifier, RED=danger·hull, MEDALS=bronze/silver/gold.

### Type — `kit.css` + `09-kit.html` "Type scale (min 10px)"

| Role | Exact rule | Source |
|---|---|---|
| Display | Oxanium w800, uppercase, letter-spacing `.04em`, line-height 1 | `.display` |
| Label | Chakra w700, 11px, letter-spacing `.16em`, uppercase, `--muted` | `.label` |
| Body | 13px, line-height 1.35, `#C9D6E1` | `.body` |
| Numeral | Oxanium w800 | `.num` |
| Scale bounds | DISPLAY 28–84, TITLE 18–24, READOUT 26/22 w/ 12 denominator, BODY 13, LABEL 10–11; page note "Type scale (min 10px)" | `09-kit.html` |
| Screen base | Oxanium w500 default; `html, body` 390×844 | `kit.css` lines 12–14 |

### Surfaces — `kit.css` `.panel`, `.panel.br`, `.card`, `.ph`

| Token | Exact value | Source |
|---|---|---|
| Panel shape | `border-radius: 14px`; `border: 1.5px solid #2A4256` | `.panel` |
| Panel fill | `linear-gradient(180deg, #15222F 0%, #0C141D 100%)` | `.panel` |
| Panel shadow | `inset 0 1px 0 rgba(140,225,255,.16)` (lit top edge), `0 8px 22px rgba(0,0,0,.5)` | `.panel` |
| Corner brackets (`.br`) | `::after` `inset:-2px`, radius 14, eight arms each `18px × 2px`/`2px × 18px` offset 10px from each corner, drawn as 8 linear-gradient strips; default arm color `--c: rgba(70,230,255,.75)` | `.panel.br::after` |
| Gold accent panel | `border-color: #6B5320`; brackets `rgba(255,200,87,.85)` | `.panel.gold(.br)` |
| Violet accent panel | `border-color: #43376B`; brackets `rgba(169,139,255,.85)` | `.panel.violet(.br)` |
| Panel header tick | 3×12px, radius 2, `--cyan` fill + `0 0 8px` glow | `.ph i` |
| Card | radius 12, `border: 1.5px solid #253A4C`, `linear-gradient(180deg,#172532,#0F1922)`, `inset 0 1px 0 rgba(255,255,255,.06)`, `0 3px 0 #060A0F` bottom lip | `.card` |

### Buttons — `kit.css` `.btn` + `09-kit.html` states

| Token | Exact value | Source |
|---|---|---|
| Base | Chakra w700 15px, letter-spacing `.14em`, uppercase, radius 14, height 54px, gap 10px; icon 18px | `.btn` |
| Primary | text `#2B1600`; fill `linear-gradient(180deg,#FFE493 0%,#FFBB3D 52%,#FF9A1F 100%)`; `0 5px 0 #A3570A` (bottom lip), `0 10px 24px rgba(255,160,30,.38)`, `inset 0 1.5px 0 rgba(255,255,255,.75)`, `inset 0 -2px 0 rgba(150,70,0,.35)` | `.btn.primary` |
| Secondary | text `#03141B`; fill `linear-gradient(180deg,#9AF6FF 0%,#3CD8F5 52%,#14B2E2 100%)`; `0 5px 0 #0A6380`, `0 10px 22px rgba(30,200,240,.3)`, `inset 0 1.5px 0 rgba(255,255,255,.7)` | `.btn.secondary` |
| Ghost | text `--text`; fill `linear-gradient(180deg,#1C2C3A,#111C27)`; `border: 1.5px solid #34506A`; `0 4px 0 #060A10`, `inset 0 1px 0 rgba(255,255,255,.1)` | `.btn.ghost` |
| Danger | text `#FFE9EC`; fill `linear-gradient(180deg,#3A1820,#241015)`; `border: 1.5px solid #8A2A3A`; `0 4px 0 #12070A`, `inset 0 1px 0 rgba(255,120,140,.18)` | `.btn.danger` |
| Icon-only | `.btn.round` 46×46 50%; `.btn.sq` 46×46 radius 13 | `.btn.round/.sq` |
| Pressed | `translateY(4px)` + `box-shadow: 0 1px 0 #A3570A, inset 0 2px 4px rgba(150,70,0,.4)` — heading "press = sink 4px" | `09-kit.html` |
| Disabled | `filter: grayscale(1) brightness(.55)` + `box-shadow: 0 5px 0 #222` | `09-kit.html` |

### Chips, tags, bars, top/tab bars — `kit.css`

| Token | Exact value | Source |
|---|---|---|
| Chip | height 28, padding 0 10, radius 14, `rgba(10,18,26,.82)` fill, `1.5px solid #2E4658`, Oxanium w800 14px; icon 16px | `.chip` |
| Tag | height 20, padding 0 7, radius 6, Chakra w700 10px, ls `.12em`, uppercase | `.tag` |
| Stat bar | height 8, radius 4, fill `#0A121A`, `1px solid #22384A`; `<b>` = value fill, `<u>` = delta overlay | `.bar` |
| Bar gradients | damage `90deg #FF5D6C→#FF8A9A`; fire rate `90deg #FFB534→#FFE08A`; range `90deg #13B8E6→#46E6FF`; wave progress `90deg #FF5D6C→#FF8A3D`; delta `rgba(123,228,149,.8)` | `05/08/09/04` inline `<b>`/`<u>` |
| Top bar | height 64, padding 0 14, `linear-gradient(180deg,rgba(5,8,13,.92),rgba(5,8,13,0))` fade | `.topbar` |
| Tab bar | height 72, `linear-gradient(180deg,#0E1822,#070C12)`, `border-top:1.5px solid #22384A`; tab = Chakra 11 ls `.14em` `--dim`, icon 24 | `.tabbar`, `.tab` |
| Active tab | color `--cyan` + top indicator 3px tall, inset 30% sides, `0 0 12px` cyan glow; R&D variant violet | `.tab.on::before`, `07-rnd.html` override |
| Glow utils | `.glow-c` `drop-shadow(0 0 6px rgba(70,230,255,.8))`; `.glow-g` gold `rgba(255,200,87,.8)` | `kit.css` |

### Battle HUD — `hud.inc.js hudHtml(o)`

| Token | Exact value | Source |
|---|---|---|
| Frame | `.panel.br` at left/right 10, top 8, height 58, padding 0 12, gap 10; fill override `linear-gradient(180deg,rgba(21,34,47,.96),rgba(10,17,25,.96))` | `hud.inc.js` line 5 |
| Hull block | width 118; shield icon 26px cyan `drop-shadow(0 0 6px rgba(70,230,255,.7))`; numeral 20px + `/20` at 11px `--dim` | lines 6–9 |
| Hull segments | 10 segments, height 6 radius 2, gap 2; filled `linear-gradient(180deg,#8AF4FF,#2FC6EA)` when `i < hull/2` (one segment = 2 hull), else `#1A2A38` | line 3 |
| Wave cell | flex 1, 1px `#22384A` side dividers, height 38; "WAVE" label 9px; numeral 22px + `/8` at 12px `--dim`; phase tag — BUILD `rgba(123,228,149,.15)`/`--green`, else `rgba(255,93,108,.16)`/`--red` | lines 13–17 |
| Gold block | width 96, right-aligned; hex icon 24px gold glow `.6`; numeral 24px `--gold` | lines 18–21 |

### Board draw parameters — `board.js drawBoard(el, opts)`

| Token | Exact value | Source |
|---|---|---|
| Grid | cell `C = 46.75`; `W = 8*C` (374), `H = 12*C` (561) — matches `BoardLayout` 8×12 | `board.js` line 3 |
| Path | `[[0,1],[3,1],[3,4],[6,4],[6,6],[2,6],[2,9],[7,9],[7,10]]` — waypoint polyline of `BoardLayout.pathCells` (Outpost Alpha) | line 4 |
| Lead-in | `M -C*.2 → first waypoint` (enters from left edge at row 1) | line 9 |
| Backdrop | `a/rr/boards/nebula.png` cover, `filter: brightness(.62) saturate(1.1)` | line 28 |
| Vignette | `radial-gradient(75% 60% at 50% 50%, transparent 40%, rgba(3,6,10,.75) 100%)` | line 29 |
| Cell grid lines | 1px `rgba(70,230,255,.07)`, at each of 7 vertical + 11 horizontal inner boundaries | lines 20–22, 32 |
| Lane stroke stack | four centered strokes on the same path: `#46E6FF` `C*.92` opacity `.22` gaussian blur 6 (glow); `#2C6F86` `C*.8` (outer rim); `#08121B` `C*.72` (inner dark); `#0E2230` `C*.5` (lane core) | lines 31–38 |
| Flow chevrons | glyph `M -5 -7 L 4 0 L -5 7`, `#46E6FF` `stroke-width 2.6`, round caps/joins, one per `~C` of segment length centered per slot, opacity `.75` (`.35` when `opts.dimLane`) | lines 11–19 |
| Spawn marker | `a/spawn.png` at cell (0,1), size `C*1.35`, `drop-shadow(0 0 12px rgba(70,230,255,.9))` | line 42 |
| Core marker | `a/core.png` at cell (7,10), size `C*1.45`, `drop-shadow(0 0 16px rgba(255,200,87,.95))` | line 43 |
| Tower render | sprite size `C*(t.s \|\| 1.02)`; ground shadow ellipse `C*.92 × C*.36` at `+C*.12` below center, `radial-gradient(rgba(0,0,0,.65),transparent 70%)`; level badge `L{lv}` height 14, padding 0 4, radius 4, `#0B1118` fill, 1px border + text in `--cyan` (lv ≤ 2) or `--violet` (lv > 2), Oxanium w800 9px | lines 44–49 |
| Enemy render | sprite size `C*(e.s \|\| .78)`, `drop-shadow(0 3px 4px rgba(0,0,0,.8))`, rotation via `e.rot` | lines 50–52 |
| Enemy HP bar | width `s*.8`, height 5, radius 3, fill `#1A0A0E` + 1px `rgba(0,0,0,.6)` border, 7px above sprite top; fill color `#7BE495` (hp > .5) / `#FFC857` (> .25) / `#FF5D6C` (else) | line 54 |
| Shield ring | circle `s*1.24`, 2px `rgba(70,170,255,.7)` border, `0 0 10px rgba(70,170,255,.6)` + `inset 0 0 10px rgba(70,170,255,.4)` | line 55 |
| Board frame | `#board` left 8 top 74, `border-radius: 14px`, `overflow: hidden` | `03/04/05` styles |

### Scene treatments — per-artboard `<style>` blocks

| Scene | Exact values not covered above | Source |
|---|---|---|
| Title (01) | wordmark Oxanium 84px ls `.14em`, gradient text `#FFF 0%→#DDF8FF 45%→#46E6FF 100%`, drop-shadows `0 0 18px rgba(70,230,255,.55)` + `0 4px 0 rgba(4,40,60,.9)`; kicker Chakra 12 ls `.5em` cyan glow; sub Chakra 13 ls `.32em` `--gold` flanked by 44×2 gold gradient rules; crest thumb 56px radius 12 border `#3A5A74`; CTA h66 fs19; ghost row h62 fs11 icons 22; shade `radial-gradient(120% 60% at 50% 22%, rgba(70,230,255,.10), transparent 60%)` + bottom `#05080D` ramp | `01-title.html` |
| Map (02) | node orb 68px (next 80px) circular, 3px `--steel` border, `0 6px 16px rgba(0,0,0,.6)`; cleared = `--gold` border + `0 0 0 2px rgba(255,200,87,.25), 0 0 18px rgba(255,200,87,.45)`; next = `--cyan` border + `0 0 0 4px rgba(70,230,255,.22), 0 0 30px rgba(70,230,255,.7)` + pulse rings 108px (2px `rgba(70,230,255,.45)`) and 132px (1.5px `rgba(70,230,255,.18)`); side = `--violet` border + `0 0 18px rgba(169,139,255,.45)`; locked = `grayscale(1) brightness(.45)` + 26px lock badge; name chip `rgba(5,8,13,.85)` + 1px `#2A4256`, Chakra 11 `#D7E3EC`; medal pips 15px (bronze/silver/gold, empty `#2A3A48`); routes — cleared gold w3 + w5 `.35` glow; current cyan w3 `dasharray 9 6` + w6 `.45` glow; side violet w2.5 `dasharray 7 6` `.9`; locked `#5F7487` w2 `dasharray 4 7` `.7`; "NEXT" tag `--cyan` fill `#03141B` text; mission panel thumb 80px, chips h26 fs13, Deploy h50 | `02-map.html` |
| Battle build (03) | fabs 42px circle `rgba(11,17,24,.88)`, `1.5px #34506A`, `0 3px 0 #05080D` at right 14, tops 80/130/180; tray h132, `linear-gradient(180deg,#101B26,#070C12)`, `border-top 1.5px #22384A`, cards 66×104 radius 12 `#1A2A38→#0F1922` border `#2A4256` `0 4px 0 #04070B` + inset, sprite 48, name Chakra 9.5 `#C9D6E1`, cost Oxanium 15 `--gold` (`.poor` = `--red`; `.locked` sprite `grayscale(1) brightness(.4)`, cost Chakra 11 `--dim`); right fade `linear-gradient(90deg,transparent,#070C12)` 40px; intel panel left 10 top 642 right 140 h58; Start primary w122 h58 fs16 | `03-battle-build.html` |
| Battle wave (04) | seg control padding 4 gap 4 radius 14 `#0A121A` + `1.5px #22384A`; cells h46 radius 10 Oxanium 16 `--muted`; `.on` `#03141B` on `linear-gradient(180deg,#9AF6FF,#2FD2F2 55%,#14B2E2)` + `0 3px 0 #0A6380` + inset; toast tag h30 radius 15 `rgba(255,93,108,.18)` fill/`rgba(255,93,108,.6)` border/`#FFB3BB` text/`0 0 18px rgba(255,93,108,.35)`; wave panel top 646 h62; "+45 clear" chip; Auto ghost w96 h56 fs10 `--orange`/`#6A3A1E`; beam FX: stroke w*3 `.35` blur 2 + white core; impact sprite `hue-rotate(-70deg) saturate(1.6)` gold glow; floating "+8" Oxanium 14 `--gold` `text-shadow 0 2px 0 #000` | `04-battle-wave.html` |
| Tower sheet (05) | sheet top edge 352px, radius `22px 22px 0 0`, fill `linear-gradient(180deg,#152331 0%,#0B131C 40%,#080D13 100%)`, `border-top 1.5px #34506A`, `0 -12px 30px rgba(0,0,0,.6)` + `inset 0 1px 0 rgba(140,225,255,.2)`; grab 44×5 radius 3 `#34506A`; targeting 3-col grid gap 6, cells h32 radius 9 `#0E1822`/`#22384A` Chakra 11 uppercase, `.on` cyan border + `rgba(70,230,255,.1)` fill + `0 0 10px rgba(70,230,255,.25)`; stat grid `84px 1fr 52px` h21; spec cards `.panel.violet.br`; sell = small `.btn.danger` h38 fs11 with animated fill overlay | `05-tower-sheet.html` |
| Report (06) | hero 330px `results/victory.png` 62% cover + shade to `#05080D` at 64%; ribbon 300×64 `linear-gradient(180deg,#FFE493,#FFB534 55%,#F08A12)` `clip-path: polygon(0 0,100% 0,94% 50%,100% 100%,0 100%,6% 50%)`, text Oxanium 34 ls `.16` `#2B1600` + `0 1.5px 0 rgba(255,255,255,.5)`; medals 74px circle, 4px border, `0 6px 0 rgba(0,0,0,.45)` + `0 0 24px var(--g)` + dashed inner ring; bronze `#F2B886`/`radial-gradient(circle at 35% 30%,#F7C79B,#B86A35)`/`#4A230A` glyph; silver `#F1F6FA`/`#FFFFFF→#8FA3B5`/`#3A4652`; gold `#FFE7A8`/`#FFF1B8→#E8A21E`/`#6B4400`; stat cards h74 3-col; rewards `.panel.gold.br`; actions ghost w120 + primary flex h58 | `06-report.html` |
| R&D (07) | hex node 74×82 `clip-path: polygon(50% 0,100% 25%,100% 75%,50% 100%,0 75%,0 25%)` + 3px inset same clip; own = `#D5C7FF→#7A5CE6` shell / `#2A2150→#17122E` core + violet check badge; avail = `#8AF4FF→#13B2E2` shell + `drop-shadow(0 0 12px rgba(70,230,255,.6))` / `#123042→#0A1822` core; lock = `#2E4658` shell / `#0C141D` core, dim text, sprite `grayscale(1) brightness(.5)`; name Chakra 10.5 ls `.08em` + effect Oxanium 13 `--green`; connectors `#A98BFF` w3 `.85` solid + `#46E6FF` w3 `.7` `dasharray 6 6`; bank chip h34 fs18 violet `#43376B`; Research secondary h50 | `07-rnd.html` |
| Codex (08) | seg tabs h36 Chakra 11; tiles 4-col h92 radius 12, sprite 50, name Chakra 9.5 `#C9D6E1`, `.sel` cyan border + `0 0 0 1px var(--cyan), 0 0 16px rgba(70,230,255,.35), 0 3px 0 #060A0F`; wave badge Oxanium 9 `--dim` top-right; stat grid `78px 1fr 44px` h22; spec rows `.card` h auto sprite 34; backdrop `map-room.png` opacity `.35` | `08-codex.html` |
| Icons | 24×24 stroke/fill icon font in `icons.js` (play, pause, ff, gear, map, flask, book, lock, shield, hex, gem, waves, bolt, medal, back, close, target, up, trash, search, replay, radar, auto, info, check, arrow, chip) — code-drawn glyphs, no new art | `icons.js` |

### Artboard data verification (mock vs game truth)

"Matches" = identical to `OrionCampaign`/`GameBalance`/`BoardLayout`/enum labels. Everything else is illustrative and **non-authoritative** — real snapshot data wins per the Outcome section.

| Artboard | Matches game data | Illustrative / non-authoritative |
|---|---|---|
| 01-title | Stage "Nebula Relay" is the real `recommendedStage` after Outpost Alpha clears; `/21` denominator = 7 stages × 3 medal ranks; backdrop + crest assets exist | "3 / 21" medal and "4" gem counts; "SPACE TOWER DEFENSE"/"HOLD THE SECTOR" copy (no current equivalent); "v1.0" |
| 02-map | 7 nodes = the 7 real stages (5 main + 2 side) with real short labels (ALPHA/RELAY/RIFT/FOUNDRY/GATE/BASTION/CORE); cleared/next/side/locked state set is a legal `CampaignProgress` shape; mission card 8 waves + 20 hull = real values; "Armored" ≈ Foundry's `reinforcedArmor` modifier | "5/21" and "4" chips; "Armored" wording (real modifier title is "Reinforced Armor"); node positions/hand-drawn route geometry |
| 03-battle-build | Tower costs 50/80/70/110/95 are exact `_towerCosts`; "Nanite WAVE 4" matches `towerUnlockWave(nanite) = 4`; hull `/20` and wave `/8` bounds are real; board path = `BoardLayout.pathCells` | Tray shows 6 of 8 tower types; gold 95, hull 18, wave 3; intel "drone ×12, heavy ×4" composition; 1× speed label (real control cycles 1×/2×/3×) |
| 04-battle-wave | 1×/2×/3× speed set = real speed options; "+45 clear" chip shape is plausible (clear-bonus model exists) | hull 16, gold 140, "9 hostiles left", 44% progress, beam/impact FX overlays — presentation only |
| 05-tower-sheet | L2 laser stats 18 dmg / 0.34s / 160 are exact; six targeting labels First/Strongest/Weakest/Closest/Shielded/Armored exact; Pulse Laser & Prism Laser + cost 120 exact; Pulse delta FIRE 0.34→0.24, RANGE 160→165 and Prism DAMAGE 18→20 exact; "Sell +84" = 70% of 120 invested, exact; hold-progress sell treatment matches the existing hold gesture | Prism range delta 160→170 omitted on card (mock shows only damage/split); "Lv 2" pip row style is presentation |
| 06-report | "Outpost Alpha"/"SECTOR 01" real; 3 medal kinds = clear/silver(≥10 hull)/gold(no leaks); stats 20/20 hull and 8/8 waves real; "+3 R&D" consistent with a gold (rank-3) first clear; "Blueprint: Relay Calibration · All towers +8% range, −8% attack interval" = exact `runModuleCatalog` effect text; hero art `results/victory.png` exists | "120 credits"; "Continue →" label — the real primary action is **World Map** (see Report contract); "New best" tag |
| 07-rnd | All five upgrades exact: Solar Capacitors +15g (cost 3), Hardened Core +3 hull (4), Salvage Crew +25% (4), Laser Tuning +10% (4), Cryo Coolant +0.3s (5); "Research 4" matches Hardened Core cost | Connector lines imply prerequisite edges — real upgrades are independent; render connectors as decoration only (already constrained in §E); "+25% kill credits" wording (real effect label is "+25% Wave Clear Gold"); "4 TO SPEND" |
| 08-codex | Tabs Towers/Enemies/Effects/Stages = real sections; W1–W6 tile badges = exact `towerUnlockWave` values; laser detail 12 dmg / 0.42s / 145 range + spec costs 120 exact; spec descriptions paraphrase real `role` strings | Mock shows only a search icon (real codex has an inline search field — HPA-753); tile art is the mockup's extracted sprites |

## Scene contract

### A. Title / menu shell

- Add _ShellView.title and make it the **production** initial post-load view. Text-styled Orion wordmark and existing backdrop art; no new image asset. To preserve existing world-map-first test fixtures, allow a minimal **test-only map-start option** on `OrionGamePage` (default false); the fixture helper opts in, while dedicated title-entry tests exercise the real default. Do not expose the private `_ShellView` enum in a public constructor or introduce a router.
- **Reuse `CampaignProgress.recommendedStage(OrionCampaign.stages)`** for the title's next-stage card, matching the sector-map destination. An **unlocked (uncleared)** recommendation opens its existing briefing on Continue (never starts combat directly); on first launch it is Outpost Alpha. If the main path is complete but an optional stage remains unlocked/unfinished, Continue targets that optional stage, matching the map. If no unfinished recommendation exists (null or the helper's **already-cleared replay fallback**), show a **Sectors** action instead of calling replay "Continue"; use `isCampaignComplete` for campaign-complete copy, not a second stage-selection algorithm. **Title Continue is unrelated to the Mission Report's World Map action.**
- A single menu shell owns the top resource chips, Settings entry, and bottom Map / R&D / Codex tabs. Title provides direct shortcuts. Keep the current enum-based page switch; no Navigator router, parallel app state or persistent tab cache.
- Move Reset Campaign out of the map's four-icon rail and into Settings, retaining the existing confirmation, saving gates and reset action. No reset icon remains in the sector map. On Reset, return the current sound/music/haptics draft and reset intent to the page, persist changed preferences **before** invoking the existing reset confirmation, and **abort Reset if preference persistence fails**. This small success/failure result is intentional: the existing preference error lives in `_mapFeedback`, which a successful campaign reset would overwrite with "Campaign reset.", silently concealing the unsaved toggles. If confirmation is cancelled, already-saved preferences remain saved; ordinary sheet dismissal without Done/Reset still discards the draft. Avoid a second preference-persistence path.

### B. Sector map and briefing

- Reuse SectorMapLayout and the seven existing stage crests. Visualize cleared / next available / side-route / locked states with gold / cyan pulse / violet / muted lock treatments; medal pips and readable numbered labels; clearer routes.
- Keep world-map scrolling/tap geometry, unlock calculation, campaign-completion copy and destination-card behavior. A mission card shows a clear Deploy action and opens the existing briefing.
- StageBriefingSheet receives a new visual treatment only: identity, difficulty, reward, modifiers, and deployment remain sourced from committed campaign progress, with current tutorial-tip behavior intact. On **cleared stages**, retain the existing Replay Mission / Endless choices, the committed Endless best, and each button's `RunMode` result; locked or uncleared stages must not gain Endless access.

### C. Battle HUD, dock and board

- One framed top status area combines hull, wave and phase label, and credits. Never obscure the playable board with redundant surfaces. For Endless snapshots (`missionWaveTotal == null`), retain an **unbounded** wave readout and accessible Endless label; never render a finite denominator from the stage's scripted wave count.
- One source of pause/speed/auto callbacks is presented near the board; build uses a compact pacing presentation and wave phase may render speed as kit-style segments. Avoid duplicate active controls in HUD and dock.
- Build phase has pre-wave enemy intel beside a prominent Start action and a **single horizontal scrollable row** of all towers, showing cost, unaffordable, and unlock-wave states. Preserve tap, press-drag, selection and guide-anchor mechanics, including first-mission onboarding.
- Wave phase instead emphasizes progress, hostiles remaining, clear bonus, auto and speed states. Do not invent counts; consume GameSnapshot and existing scanner/readout models. Endless scanner previews must continue showing their actual unbounded wave number, enemy composition and **health-scaling copy** from existing preview data; never fall back to finite-stage totals or invented scaling. Preserve Endless auto/pause/speed behavior and its suppression of first-mission tutorial guidance.
- Keep the **World Map** action directly reachable throughout **build phase** (in the top status area or a persistent dock position, including when a tower/cell is selected), with the existing `game.returnToMap` callback. During an **active wave**, the action is disabled or absent: pausing does not permit leaving mid-wave, and the existing `returnToMap()` guard still applies. **Do not** put the only exit inside a Pause menu, label an in-wave no-op as Exit, or add a new abandon/surrender mechanic as part of this visual ticket. Preserve existing save/result exit gates.
- BoardComponent paints a darker, vignetted field and a readable illuminated route with flow chevrons; enlarge the **render-only** silhouettes of spawn/core/enemies as the attached board.js prescribes (for enemies, adjust the draw-size multiplier rather than `EnemyComponent.radius`). **Do not alter** BoardLayout, enemy positions, hit areas/radii, targeting, timing, path cells, collisions or any game rules. Check sprite, hit bar, trait overlay and tap alignment after visual scaling.

### D. Tower sheet / radial / report

- Restyle TowerRadialActions, preserving radial activation and interactions. TowerInspector header contains Close and the current Sell action; if selling currently requires a hold gesture, preserve the protection. Six targeting choices are a visible 3-by-2 grid, not a horizontally clipped list.
- Show clear current-to-next stat bars and upgrade/specialization cards with accurately computed values and price/disabled states. The sheet is bounded by available height and scrolls its content, not its footer action offscreen.
- MissionReportPanel uses existing victory/defeat hero art, a clear outcome ribbon, code-drawn medals **only when a medal exists**, stat/reward cards and Replay/**World Map** actions. Preserve committed save-state gating, retry behavior, blueprint copy and campaign progression. **Do not add next-stage navigation here.**
- **Report action/state contract** (the existing `onReturnToMap` invokes `_returnFromMissionReport`, then the map; even a fully completed campaign returns to the map):

  | Report state | Visible actions and destination |
  |---|---|
  | Normal defeat | **Retry** restarts the same mission; **World Map** returns to the sector map. |
  | Mission victory, saving | **Replay Mission** and **World Map** stay disabled until the save settles. |
  | Mission victory, saved | **Replay Mission** restarts the same mission; **World Map** returns to map (not the next briefing). |
  | Mission victory, failed | **Retry Save** retries persistence; **World Map (Unsaved)** returns with the existing unsaved-result warning, while Replay stays unavailable. |
  | Endless defeat, saving | **Replay Endless** and **World Map** are disabled until the best-save settles. |
  | Endless defeat, saved (including zero-wave "No result to save") | **Replay Endless** starts another Endless run; **World Map** returns to map. Show waves **cleared**, prior/saved best and save message; no medals, R&D points or campaign rewards. |
  | Endless defeat, failed | **Retry Save** retries the best save; **World Map (Unsaved)** returns with current best-save failure/retained-best feedback; Replay stays unavailable. |

- Keep text-arrow rendering safe. Do not substitute screenshots or raw mockup numbers for live stats.

### E. R&D, Codex and smaller surfaces

- TechTreeView displays a legible visual network of hex nodes and connector/conduit lines, plus a bottom detail panel with Research action. **Those lines are decorative grouping, not prerequisite edges:** the five upgrades are currently independent, so the UI must not claim that one purchase unlocks another. Paint connectors **behind** interactive nodes using a decoration-only background (`CustomPainter` if useful), wrapped in `IgnorePointer` and `ExcludeSemantics`; no hit targets or screen-reader nodes may be added by the artwork. Preserve point-bank arithmetic and current available/owned/locked-by-budget states. A real dependency tree would require a separate gameplay ticket.
- CodexView presents single-row section tabs, sprite tile grids and details with readable stat bars/specializations. Retain HPA-753 search terms, clear button, per-tab scroll restoration, keyboard focus and empty state.
- Apply the same solid tokens to FeedbackSettingsSheet, CommandToast, first-mission guide, contextual tips, module-draft panel, next-wave scanner, and other remaining UI surfaces. Do not rebuild their logic.

## Integration / exclusions

- **One PR for HPA-699**: this docs-only draft grows into the sole implementation PR after review. Implementation can use multiple logical commits, not multiple pull requests.
- HPA-715 Endless Mode is **already merged on `main`** (PR #46, 2026-11-08). The HPA-699 restyle must preserve its existing briefing, HUD/scanner, wave-health scaling, record-save statuses and medal-free Endless loss report. This is regression preservation, **not** implementing or redesigning Endless rules or persistence. Base implementation on current `main`; keep it in the same HPA-699 PR.
- Do not add art, SFX, packages, navigation infrastructure, campaign data, persistence migrations, rebalance, or orientation/tablet layouts. If a future review establishes that a new logo/medal/board asset is essential, create a **separate art-only ticket** instead of embedding asset generation in this code task.
- Remove obsolete blur widgets, surface-tier API and deprecated `MissionSurface` adapter **together in Task 1** while converting the existing `OrionSurface` implementation in place. Later tasks modify layout and remaining raw color usages, not the surface rendering API. Do not add compatibility shims. Historical docs remain historical; do not modify them.

## Acceptance and evidence

- Compare every ticket mockup (title, map, build, combat, inspector, report, R&D, Codex) and the remaining sheets against its reference at **390×844**; verify **360×640** for clipping and touch/focus reachability. Safe areas and software keyboard are part of layout.
- Normal label sizing is at least 10 logical pixels, dominant action hierarchy is obvious, all glyphs render, every input remains reachable, and controls reflect real disabled/locked/saving state.
- From Task 1 onward, design-system source-scan tests forbid `BackdropFilter`/`ImageFilter.blur` in game UI, the deprecated `MissionSurface`/`OrionInnerSurface`/old `OrionSurfaceTier` API, and direct `Color(0x...)` values in `lib/game/ui` outside `OrionUiTheme`. Keep an explicit **shrinking file allowlist** only for raw colors awaiting migration in Tasks 2–5; Task 6 removes the final exceptions. Move shared typography-shadow literals into theme tokens. Test font fallback and 10px minimum at the foundation stage, not only via screenshot review.
- Confirm product launches to Title while legacy page-level test fixtures can start on Map; title Continue opens a briefing. Verify **World Map stays reachable in build, even after cell selection, and is not an active-wave exit** (including when paused), stage selection, cleared-stage Endless launch/best, briefing, build/tower drag, pause/auto/speed, unbounded Endless HUD/scanner/health-scaling copy, tutorial anchors, radial and targeting, settings toggle → Reset (cancel/confirm/save failure), Codex search, independent R&D purchase and **tap/semantics-transparent decorative conduits**, and mission/Endless report replay/map/save gates. Include a completed-campaign victory still returning to World Map.
- Run dart format, flutter analyze, flutter test, and CI. Capture **before + after** images for every scene, including a cleared-stage Endless briefing, an unbounded Endless HUD/scanner and an Endless defeat report, not just a single happy-path board. The review PR remains a draft until the screenshots and green checks exist.
