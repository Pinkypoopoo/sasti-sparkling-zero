# Project Aegis / Labyrinth (sasti-sparkling-zero)

## Core Vision
- **Engine:** Godot 4.7+ (3D, Mobile-First Action Combat).
- **Target Performance:** 120–165 FPS on mobile hardware. Avoid heavy post-processing; use static light-baking, Half-Lambert/Vertex coloring for environments, and hand-painted NPR textures with stepped animation for characters.
- **Combat System:** Dual-thumb gesture controls:
  - Left Screen Half: Drag to run, quick flick to step-dodge, double-flick to burst dash, flick up to jump.
  - Right Screen Half: Directional swipes for katana slashes, parries, feints, aerial combos, and stationary Chant Stance.

## Agent Instructions & Rules
1. Always inspect existing `.tscn` and `.gd` files before editing or replacing them.
2. Keep scripts modular, strictly typed in GDScript 2.0 (Godot 4 syntax), and free of runtime allocation spikes.
3. After making changes, use the Godot MCP tools (`run_project`, `get_debug_output`) to validate that the scene builds and runs without script errors.
4. Keep the repository clean; do not stage `.godot/` or `.gemini/` cache files.
