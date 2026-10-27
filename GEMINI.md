# Project Aegis / Labyrinth (sasti-sparkling-zero)

## Core Vision & Engine Standards
- **Engine:** Godot 4.7+ (3D, Mobile-First Action Combat).
- **Target Performance:** 120–165 FPS locked on mobile TBDR GPUs.
- **Symmetric Input Architecture:** Driven by an `InputFrame` struct for identical behavior across Keyboard, Touchscreen, and AI.

## Modular Architecture
1. `res://character_body_3d.gd` (`PlayerController`):
   - Hybrid Ground/Flight locomotion.
   - Dual-thumb touch partitioning (Left: Move/Dash, Right: Camera/Combat).
   - Non-inverted 8-way flicks and vertical Sky/Dive dashes.
   - Toon Cel-Shader + Inverted Hull Outlines.
2. `res://gesture_combat.gd` (`GestureCombat`):
   - AssistiveTouch Hover Dots (Left: Spell Weave, Right: 3-Zone Melee).
   - 3-Zone Flow: Parry (Center), Feint (Mid), Commit (Outer).
   - Target Dummy Stats (HP/Posture) and Mirror-Brain AI Simulator.
3. `res://dev_studio.gd` (`DevStudio`):
   - 144/165Hz Telemetry & Action Bar.
   - 4-Tab Tuner Suite (Physics, Combat, Shaders, AI).
   - AssistiveTouch UI and 3D-to-2D Floating Bars.

## Strict Godot 4.7 & Jolt Physics Rules
1. **Never scale `CollisionShape3D` nodes:** Keep `scale = (1, 1, 1)`. Modify shape size resources directly.
2. **Resource Order in `.tscn`:** All `[sub_resource]` blocks MUST precede all `[node]` blocks.
3. **Touch Safety:** Always handle `InputEventScreenTouch` and `InputEventScreenDrag` explicitly. Never rely on mouse emulation for mobile-specific partitioning.
4. **No Placeholders:** All scripts must be fully implemented. Do not use `pass` or truncated methods.
