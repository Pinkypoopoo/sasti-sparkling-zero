# Project Aegis / Labyrinth (sasti-sparkling-zero)

## Core Vision & Engine Standards
- **Engine:** Godot 4.7+ (3D, Mobile-First Action Combat).
- **Target Performance:** 120–165 FPS locked on mobile TBDR GPUs.
  - Zero runtime memory allocations (`0 allocs/frame` during combat).
  - Object-pooling for all projectiles, shockwaves, VFX slots, and dash ghosts.
  - Pre-baked Half-Lambert / NPR anime shaders with binary cel-shading and inverted-hull outlines.
- **Symmetric Input Architecture:** All locomotion and combat is driven by an `InputFrame` struct, ensuring identical behavior across Keyboard, Touchscreen, Mirror-Brain AI, and local P2P multiplayer.

## Modular 3-Script Architecture
1. `res://character_body_3d.gd` (`class_name PlayerController`):
   - **Locomotion:** Hybrid Ground/Flight state machine with Momentum Coasting.
   - **Mobile Touch:** Left-thumb spammable 8-way flicks and Left-edge vertical altitude dashes (+Y/-Y).
   - **Custom Race Builder:** Database-driven races with 6 Anime Dash Styles (`DBZ_VANISH`, `SONIDO`, `SANDEVISTAN`, etc.) and hot-swappable `.glb` models.
   - **Juice:** Camera whip-lag, behind-the-back Z-Vanish, and 3-bone procedural Spring Jiggle Physics.
2. `res://gesture_combat.gd` (`class_name GestureCombat`):
   - **Hover Dots:** Dual AssistiveTouch sigils (Left = Spell Weave, Right = 3-Zone Physical Arena).
   - **Combat Logic:** 3-Zone Feint/Windup engine (No attack lines). Zone 0 (Parry/Guard), Zone 1-2 (Windup/Feint), Zone 3 (Commit).
   - **VFX Slot System:** Data-driven mapping of moves to pooled .glb/.tscn effects.
   - **AI:** Mirror-Brain Anti-Cheese Enemy AI with habit memory and adaptive counter-vanish.
3. `res://dev_studio.gd` (`class_name DevStudio`):
   - **Telemetry:** 144/165Hz FPS and Physics Tick Unlocker.
   - **HUD:** Custom-drawn AssistiveTouch dots, HP/Posture bars, and B&W Impact Stencil.
   - **Studio:** 5-Tab Creation Suite for Physics, Races, Gestures/VFX, Models/Jiggle, and AI.

## Strict Godot 4.7 & Jolt Physics Rules
1. **Collision Shape Scale:** ALL `CollisionShape3D` nodes MUST have `scale = (1, 1, 1)`. Modify shape size resources directly.
2. **Resource Order:** In `.tscn` files, ALL `[sub_resource]` blocks MUST precede all `[node]` blocks.
3. **Headless Execution:** Always verify changes via `godot --path . --headless --quit`.
