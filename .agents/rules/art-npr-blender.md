---
trigger: glob
globs: "build_models.py, dash_vfx.gd, character_body_3d.gd, *.gdshader"
description: "Dark Seinen Ink art bible, Godot 4.7 shader rules, 4-channel vertex colors, SDF face shading, Blender pipeline, and V5 VFX/water."
---
# Book 2: Dark Seinen Ink Art, Shaders & Blender Pipeline

## Visual Lock
- 2-band hard cel cut + narrow screen-space diagonal ink hatch in shadow + inverted-hull outline (`MID`/`HIGH`/`ULTRA`).
- Color discipline (70/20/10): 70% obsidian/pitch shadow, 20% bone/porcelain, 10% single saturated accent per character.
- ZERO full-screen post-processing on mobile (no bloom, DOF, SSAO, SSR).

## Godot 4.7 Shader & Material Gotchas
- Godot 4.7 rejects `return` inside `light()` — always use `if/else` branching.
- Vertex `COLOR` is unavailable directly in `light()` — pass it from `vertex()` via a `varying`.
- Apply GLB material overrides BEFORE `add_child()`.
- Disable character self-shadowing (`SHADOW_CASTING_SETTING_OFF`) so low-poly self-shadows never fight cel bands.

## Zero-Texture 4-Channel Vertex Color Contract (`COLOR.rgba`)
- `R`: Shadow threshold bias (`0.0` permanent crevice shadow, `0.5` neutral, `1.0` highlight).
- `G`: Distance-scaled outline weight (`0.0` eyes/inner details, `1.0` outer silhouette).
- `B`: Specular / view-space MatCap metallic mask (weapons, gold filigree, hair ring).
- `A`: SDF Face switch (`> 0.5` activates procedural 64x64 horizontal SDF face lighting driven by `Head` bone `head_forward`/`head_right` vectors).

## Blender (`build_models.py`, Blender 5.2 LTS) & VFX Rules
- Bake `paint_vertex_channels()` + `proxy_smooth_normals()` (`DATA_TRANSFER`) before GLB export.
- NEVER place `.blend` files inside `models/` (aborts `verify.sh` headless import). All `.blend` sources live in `art/` with `art/.gdignore`.
- Preserve 5-slot clothing (`HERO`/`VEIL`/`NONE`), 12-FPS stepped animation + SpringBone veil, 2D UV Eye Shader (`eye_shape` 0..4 incl. Celestial Constellation), and NO skeleton bones or Susanoo rings in Flame Awakening.
- V5 VFX: 2D screen-space diagonal impact slash + singularity ring on crits/parries/KOs (`0.16s`, 0 3D fill-rate cost), 2-tone cel-smoke puffs, and toggleable 3-band anime water floor with `player_pos`/`boss_pos` contact ripples.
