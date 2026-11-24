# HPA-922 character squad validation

Evidence retention: representative captures remain alongside this note. Other linked captures refer to the pinned historical revision; the recorded verification is unchanged.

- **PR:** [#50](https://github.com/cwchanap/orion/pull/50)
- **Code tested:** `90b39f33ad9c7d1bba9f3093e5dcaa2a0ea076d0`;
  battle rank colors rechecked at `4fa3053c2f999335c3053b0d0d893210f71c9861`
**Environment:** Flutter web debug server, Chrome DevTools MCP, isolated browser
context, 390 x 844 logical pixels at device pixel ratio 2 with touch emulation.
The initial walkthrough, sheet and briefing screenshots were taken at
`5f4d9739315084fbd5128b81f9d9fb18871cff54`; subsequent fixes did not change
those two screens. Camp was recaptured and combat/save failure retested at
`90b39f3`. Battle was recaptured after aligning rank rings with the roster.

## Visual comparison

The screenshots below were compared with the HPA-922 Linear mockups; the
references are design guidance, not exact replicas.

| Reference | Evidence | Observations |
| --- | --- | --- |
| 10 Camp | [Top](hpa-922-evidence/10-camp-fixed.jpg), [scrolled](https://github.com/cwchanap/orion/blob/b3ae929ea56f1be266c5219a1bd218b7197a595c/docs/superpowers/validation/hpa-922-evidence/10-camp-bottom.jpg) | Twelve rank-ordered portraits; only Haruto and Mio are owned on a fresh profile. Locked cards use dark, contrast-crushed grayscale and `???`. Both owned cards show full `SQUAD` tags. The roster scrolls under the fixed navigation. |
| 11 Character sheet | [Haruto](https://github.com/cwchanap/orion/blob/b3ae929ea56f1be266c5219a1bd218b7197a595c/docs/superpowers/validation/hpa-922-evidence/11-sheet.png) | Portrait, E rank, level, combat stats, signature and bio are visible. No level-up action. The approved full-size placeholder art occupies the left of the sheet rather than the mockup's full-width hero. |
| 14 Briefing | [Squad draft](https://github.com/cwchanap/orion/blob/b3ae929ea56f1be266c5219a1bd218b7197a595c/docs/superpowers/validation/hpa-922-evidence/14-briefing.jpg) | Ordered member chips, count, edit and deploy actions are visible with the existing stage details. |
| 15 Battle | [Deployed squad](hpa-922-evidence/15-battle-final.jpg) ([earlier capture](https://github.com/cwchanap/orion/blob/b3ae929ea56f1be266c5219a1bd218b7197a595c/docs/superpowers/validation/hpa-922-evidence/15-battle.jpg)) | Approved chibi sprites appear on the board and in squad order in the dock. Both deployed cards show `ON FIELD` and cannot deploy again; E-rank rings match the roster palette. |

The current Orion theme, space board and Camp bay backdrop are intentionally
retained until the separate retheme work. The mockups' Scrip, recruitment,
Flare and level-up controls belong to later work and are not present here.
Camp layout tests load the bundled fonts and exercise 390/1x and 320/2x text,
including full badge glyphs, text growth and non-overlap. Scene-parity tests
also exercise the compact viewport with enlarged text.

## MCP flow

- A fresh profile showed 12 roster entries, Haruto and Mio at E rank and level
  1, and no R&D tab. The read-only sheet exposed the starter's fixed signature.
- Removing both draft members displayed `0 / 6`, explained that one member is
  required and disabled launch. Dismissing the briefing discarded edits.
  Removing and re-adding a member changed the committed order, which survived a
  page reload and appeared in the battle dock.
- With an isolated test profile, the browser's `localStorage` getter was
  temporarily made to throw a quota error. Launch stayed on the briefing,
  retained the draft and showed a retry message; the previously saved order
  remained unchanged. Restoring storage and retrying launched with the draft
  order. The override was removed and no saved data was deleted.
- Both starters deployed once. Haruto upgraded to tier 2 for 70 credits and to
  tier 3 for 120; the inspector showed Steady Volley without a specialization
  choice. Recall refunded 168 credits, and redeployment returned him at tier 1.
- An eight-wave Stage 1 run won gold with 20/20 hull and 1,791 credits after
  three module choices. The result showed `Saved.` and remained gold after
  reload. An intentionally undefended Endless run saved a best of two waves,
  which remained visible after a second reload.
- Codex character search for Cryo returned Jin and Rin; Hunter Bay returned no
  playable character. The Pierce effect listed Elena and Sayo. The first-wave
  guide and signature/boss tips used member-oriented wording.
- The original walkthrough exposed a Flutter build-phase notification
  assertion. The fix has a mounted `GameWidget` regression; after hot restart,
  a replay deployed both starters and cleared two waves with no console errors.
  Browser autoplay and unlabeled-route semantics warnings were observed.

## Automated evidence

At `90b39f3`, `flutter test` passed 1,803 tests, including the deterministic
eight-wave starter and five-stage balance fixtures. `flutter analyze` was
clean. A separate Chrome run used Flutter's temporary profile and successfully
hot restarted. The updated integration smoke test passed on an isolated
Android API 36 emulator: it deploys Haruto by tap and Mio by drag, checks
duplicate and off-board rejection, and exercises the wave, Camp and report.
The final PR checks tab is authoritative for CI on the pushed head; a local
test or older green run does not establish final-head CI status.
