# Sasti Sparkling Zero — Agent Constitution

## 1. Branch & Gate Rules (NON-NEGOTIABLE)
- Repo: `Pinkypoopoo/sasti-sparkling-zero` | Active branch: `Pinkypoopoo-patch-1`.
- NEVER checkout, commit, merge, or push to `main` (`0c80d97` fallback).
- Code changes MUST pass `bash verify.sh` on PC/CI before committing (Termux has no Godot CLI).
- Zero new GDScript warnings: never shadow built-ins (`snapped`, `scale`), cast ints to enums with `as`, prefix unused args with `_`.

## 2. Engine Lock
- Godot 4.7-stable, Mobile renderer, Jolt Physics, `physics_ticks_per_second = 60`, `physics_interpolation = true`, render FPS matched to display refresh rate.
- Solo dev workflow: every tunable gameplay/visual parameter belongs in `combat_data.gd` (`TUNING_SPEC` / `TUNING_BOOLS`) so Tab 8 auto-generates UI controls.

## 3. Modular Playbooks (Read ONLY the book matching your task)
- Combat, AI, Tuning, Wall-Run -> `.agents/rules/combat-feel.md`
- Shaders, Blender, NPR, VFX, Water -> `.agents/rules/art-npr-blender.md`
- Story JSON, Regions, Arenas -> `.agents/rules/world-story.md`
- Pause Menu, 4-Tier GPU Perf, PvP, CI -> `.agents/rules/ui-pvp-perf.md`
- Rolling state (last 3–5 verified commits) -> `AGENT_HANDOFF.md` (archive older entries to `docs/archive/` once >150 lines).

## 4. Mandatory Handoff Protocol
- Append verified changes + gate status to `AGENT_HANDOFF.md §4` when committing.
- End every chat turn with a compact `=== MANDATORY AI HANDOFF PACKET ===`.
