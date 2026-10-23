# Project Aegis / Labyrinth (sasti-sparkling-zero)

## Core Vision & Engine Standards
- **Engine:** Godot 4.7+ (3D, Mobile-First Action Combat).
- **Target Performance:** 120–165 FPS locked on mobile TBDR GPUs.
  - Zero runtime memory allocations (`0 allocs/frame` during combat).
  - Object-pooling for all projectiles, shockwaves, slash smears, and afterimage ghosts.
  - Pre-baked Half-Lambert / NPR anime shaders with binary cel-shading, inverted-hull black ink outlines, and sharp rim highlights.
  - Glow and heavy post-processing are disabled by default for TBDR performance.
- **Combat Control Scheme:** Dual-Thumb Touch & Hybrid Controller:
  - Left Screen Half: Drag to run, flick to step-dodge, double-flick to burst dash, flick up to jump, double-tap jump to enter 3D Flight.
  - Right Screen Half: Directional swipes for katana slashes, feints, and aerial combos; quick tap/hold for parry & guard; hold `C`/`Alt`/`L1` for the 5-Element Spell Weave Runic Pentagon.

## 3-Script Modular Architecture
The entire combat and runtime tooling is strictly divided into 3 modular systems:
1. `res://character_body_3d.gd` (`class_name PlayerController extends CharacterBody3D`):
   - Hybrid 8-way ground motion and 6DOF 3D flight state machine (`GROUND`, `SPRINT`, `FLIGHT`, `STEP`, `DASH`, `WINDUP`, `ATTACK_RECOVERY`, `GUARD`).
   - Player stats & 4-Race System (`HUMAN_TOUKI`, `DEMON_FIEND`, `BEASTKIN_VANGUARD`, `ELF_CASTER`).
   - 1:1 Dark Anime binary cel-shader with inverted-hull black ink outline and pre-allocated 3-ghost afterimage pool.
   - Directional hit-shear camera juice, snap FOV punches, and procedural screen shake trauma.
   - Runtime `.glb` / `.gltf` 3D character model hot-swapper with `AnimationPlayer` auto-mapping.
2. `res://gesture_combat.gd` (`class_name GestureCombat extends Node`):
   - Zero-allocation touch/gesture engine with zero-timer parry hold detection and 24px micro-jitter hook threshold.
   - 3-Tier Clash Escalation: Micro-hitstop shockwaves (Tiers 1–3), spark color shifting Cyan -> Gold -> Crimson with FOV tightening (Tier 4+), and cooldown-gated 2-frame B&W anime impact frame (Clash Break / Super Parry).
   - Data-driven `action_table` with customizable step force, lunge, lift, damage, posture damage, and animation names.
   - 3-Beat Spell Weave System: 5-Node Runic Pentagon (`FIRE`, `WIND`, `LIGHTNING`, `WATER`, `EARTH`), 12s active elemental infusions, 5 Kekkei Genkai fusions, and 4 directional spell deliveries (Spear, Crescent, Meteor, Homing Swarm).
   - Target dummy health (`1500`) and posture (`300`) gauges with auto-reset and White/Crimson damage flashes.
3. `res://dev_studio.gd` (`class_name DevStudio extends Control`):
   - Direct hardware GPU render time telemetry (`RenderingServer.viewport_get_measured_render_time_gpu`).
   - Auto-loading dev profile (`user://dev_profile.json` & `res://dev_profile.json`) on startup.
   - Live Combat HUD: Player HP/Touki bars, 3D-projected floating target HP/posture bars, Boss target banner, Runic Pentagon overlay, and 2-frame impact flash.
   - 4-Tab Dev Studio Panel with synchronized `HSlider` + `SpinBox` direct numeric input on every single property.

## Strict Godot 4.7 & Jolt Physics Compiler Rules
1. **Never scale `CollisionShape3D` nodes:** In Jolt Physics, scaling collision shapes causes shape distortion, phantom contacts, and severe performance degradation. Always keep `scale = Vector3(1, 1, 1)` on all `CollisionShape3D` nodes and modify the shape resource size (`size`, `radius`, `height`) directly.
2. **Resource Declaration Order in `.tscn` Files:** In Godot 4.7 scene files, ALL `[sub_resource]` blocks MUST precede all `[node]` blocks. Placing sub-resources after nodes will cause scene parser errors.
3. **Input & Display API Standards:**
   - Use `JOY_BUTTON_RIGHT_STICK` for gamepad right-stick click (not deprecated index `9`).
   - Use `DisplayServer.window_set_vsync_mode()` to configure V-Sync at runtime.
   - Use `PhysicsRayQueryParameters3D.create()` with cached or zero-allocation queries.
4. **Headless Execution:**
   - Never run `godot --editor` in automated commands or shell scripts.
   - Always run verification headlessly via `godot --path . --headless --quit`.
