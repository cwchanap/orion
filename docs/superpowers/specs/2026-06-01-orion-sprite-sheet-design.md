# Orion Sprite Sheet Asset Design

## Goal

Generate and integrate one project-owned raster sprite sheet for the Orion tower defense MVP. The asset should make the playable Flame scene read less like placeholder geometry while preserving the current game rules, balance, layout, and UI behavior.

## Asset Scope

Create a single top-down sci-fi sprite sheet PNG for in-game objects:

- Laser tower
- Rocket tower
- Cryo tower
- Basic drone enemy
- Heavy drone enemy
- Laser bolt projectile
- Rocket projectile
- Cryo projectile
- Spawn marker
- Base marker
- Two compact impact effects

The sheet should use a consistent top-down perspective, crisp silhouettes, generous padding, no labels, no text, and no watermark. The visual direction is polished but readable: compact orbital-defense hardware, teal/green laser energy, orange rocket accents, and blue cryo energy.

## Generation Strategy

Use the built-in image generation tool first. Prompt it to place the sheet on a perfectly flat chroma-key background so the background can be removed locally into an alpha PNG. The final project asset should be copied into `assets/images/` and must not remain only in the image tool's default output directory.

If chroma-key removal produces unacceptable edges, regenerate once with clearer padding and flatter background. Do not switch to a native-transparency CLI fallback unless explicitly approved later.

## Integration Strategy

Register the PNG in `pubspec.yaml`. Load it through Flame image loading and slice the fixed 4x3 sheet into sprites. Replace only the current placeholder rendering for towers, enemies, projectiles, spawn marker, and base marker where the sprite maps cleanly. Keep the existing canvas fallback simple enough that tests and web smoke verification remain understandable.

The implementation should avoid changing gameplay state, wave timing, targeting, rewards, health, placement rules, or upgrade rules. This is a visual asset pass, not a rules pass.

## Verification

Run formatting, static analysis, and Flutter tests. Then start the web server and smoke-test that the game opens, tower placement still works, a wave can start, sprites render, and there are no runtime asset-load errors.
