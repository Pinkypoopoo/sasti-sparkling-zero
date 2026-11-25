---
trigger: glob
globs: "combat_data.gd, gesture_combat.gd, character_body_3d.gd, combat_test.gd"
description: "Combat physics, AI state machine, Tab 8 tuning specs, legacy save safety, and V5 wall-running invariants."
---
# Book 1: Combat Feel, AI & Movement Invariants

## Physics & Tick Separation
- Enemy AI, projectiles, hitboxes, hitstop timers, and movement MUST run in `_physics_process` (60 Hz), NEVER `_process` (breaks at 120–165 Hz).
- Procedural audio synth MUST pump on the render tick so hitstop never starves audio.
- NEVER use `PhysicalBone3D` on rigged characters (causes Jolt scale errors on swap).

## Tuning & Save-File Safety (Anti-Crash Guard)
- Add new knobs as single entries in `TUNING_SPEC`, `TUNING_BOOLS`, and `TUNING_DEFAULTS` in `combat_data.gd`; never hand-code Tab 8 slider UI.
- `load_from_disk()`, `save_to_disk()`, and `refresh_auto_quality()` MUST guarantee `if not data.has("tuning") or not (data["tuning"] is Dictionary): data["tuning"] = TUNING_DEFAULTS.duplicate()` before accessing `"tuning"`.
- `save_to_disk()` MUST merge into existing `user://dev_profile.json` so `combat_data.gd` and `world_story.gd` never erase each other.

## Combat & Stakes Invariants
- Use `enum AIState` across all call sites; never revert to raw state strings.
- HP 0 transitions to `DEAD` + Victory/Defeat result card (no silent full heal). `sandbox_immortal` clamps damage at 1 HP for combo practice.
- Preserve Lock-On, Z-Vanish, Sonic Sway, Riptide Spell Weaver, floating damage/crit numbers, combo grace bar, KO slow-mo, and Flame Awakening + 2-Layer Flame Dome.

## Wall-Running Rules (V5)
- Strictly intent-gated: activate only when `wall_run_enabled`, `is_on_wall()`, `absf(normal.y) < 0.35`, holding Sprint/Dash (speed > 11.0), and NOT attacking or in hitstun.
- Keep `CharacterBody3D.up_direction = Vector3.UP`; tilt only `VisualRoot` + `±8°` camera roll. Add auto ledge-vault (chest + head clearance rays) and jump wall kick-off.
- APPROVED Intent gate: a new agent must keep `sprint_held or h_speed > WALL_RUN_MIN_SPEED`. Harden this into `and` and the feature stops working: `move_and_slide()` absorbs the normal component on contact, so tangential speed when sprinting straight into a wall is only ~4 m/s. The OR is deliberate; the test suite asserts both halves.
