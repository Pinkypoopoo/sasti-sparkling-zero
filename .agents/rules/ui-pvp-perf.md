---
trigger: glob
globs: "dev_studio.gd, flame_p5_pvp.gd, export_presets.cfg, .github/workflows/*"
description: "Single-tap P5 pause menu, 4-tier GPU quality auto-scaler, UDP 7778 PvP sync, and iOS/Android CI rules."
---
# Book 4: UI, 4-Tier Mobile Performance, PvP & CI

## Touch & UI Invariants
- Top-right `[ MENU ]` opens the viewport-scaled Persona 5 pause menu.
- `_handle_p5_blade_tap()` MUST call `set_input_as_handled()` before row execution so taps never bleed through to the GUI layer underneath. Every row executes on a single tap.
- Preserve all 8 Dev Studio tabs and the 10 Hz HUD redraw throttle.
- Do NOT add cyclic `class_name` type hints (e.g., `PlayerController`) inside `flame_p5_pvp.gd` until a shared `RefCounted` state object is extracted.

## 4-Tier GPU Quality Auto-Scaler (Honest Hardware Ceilings)
- `0: LOW` (Redmi Note 10 Pro / Adreno 5xx–6xx / Mali-G5x floor): `scale 0.65`, MSAA/shadows/fog/outline/afterimages OFF, debris cap `8` (45–60 fps).
- `1: MID` (Dell Precision 5550 4GB VRAM / mid Android): `scale 0.85`, MSAA OFF, shadows/fog/outline ON, afterimages OFF, debris cap `16` (60–90 fps).
- `2: HIGH` (iQOO 12 / Adreno 740–8xx): `scale 0.92`, MSAA 2X, all effects ON, debris cap `28` (120+ fps).
- `3: ULTRA` (iPad Pro M4 / high-end desktop): `scale 1.00`, MSAA 2X, all effects ON, debris cap `28` (120 fps).

## PvP & Export Invariants
- Custom Room Code + optional Password Lock runs over UDP port `7778`, throttled to `30 Hz` (`0.033s` accumulator).
- `.github/workflows/ios_ipa.yml` MUST target Godot `4.7-stable`.
