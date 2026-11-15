# Sasti Sparkling Zero — Code Review & Roadmap

Reviewed: 15 Nov 2026 · branch `freebuff/9df505384c5b1c5ec2578cb3` (main untouched)
Scope: all 9 GDScript files (~4,100 lines), 3 scenes, export presets, `verify.sh`, CI, `build_models.py`.

## How this was checked

I did not just read the code. I installed **Godot 4.7-stable** in a scratch copy of the repo and:

1. Ran `--headless --import` → **found that asset import aborts** (see BUG-1).
2. Booted the game headless for 200 frames → clean, no parse/script errors.
3. Ran `bash verify.sh` → **VERIFY_PASSED** (their gate still passes, but see BUG-4 about how weak it is).
4. Wrote a throwaway harness that drove ~30 subsystems (all 4 profiles, model swaps, all move slots, all spell sequences, KO path, dev studio tabs, flame awakening, P5 menu, PvP host/join/deny, all 4 story origins + choices, ragdoll, save/load, block builder, 30× parry/feint/super-parry). Result: **no GDScript runtime errors** — the code is genuinely robust. Two *engine-level* error sources did appear (BUG-2, BUG-3).

So: the architecture is sound and nothing is on fire. The problems are a handful of logic bugs, a skewed save/load order, several unfinished game loops, and avoidable CPU/GPU cost.

---

## A. What is right (keep doing this)

- **`renderer/rendering_method="mobile"` + no glow/SSAO** — correct renderer choice for a phone target, and the biggest single GPU win you already made.
- **`project.godot` uses Jolt Physics** — good with 120+ Hz tick rates.
- **Bolted-on `render_mode diffuse_toon, specular_toon, ambient_light_disabled` cel shader** — cheap and stylised; no textures needed.
- **`verify.sh` guardrails exist at all.** Most hobby projects have nothing. The "don't delete features" grep list is a genuinely good idea against AI-driven regressions.
- **`build_models.py`** — procedural Blender rigs with baked anims (idle / slash_up / slash_down / slash_side / guard_sway) exported to GLB. This is the right shape: models are reproducible, not hand-made binaries.
- **Object pooling is already done** (afterimages, sigils, slash arcs, debris, craters, projectiles). You are not allocating per-frame. Most people get this wrong.
- **`class_name` + typed GDScript throughout**, `preload` for local scripts — clean, fast, and it makes a local AI far more useful on this codebase.
- **Synthesised SFX via `AudioStreamGenerator`** — zero audio files, zero memory. Clever.
- **Spring-bone veil physics done in code** instead of `PhysicalBone` chains — much cheaper and stable.
- **Player attacks use a bone-attached `Area3D` *plus* a directional cone fallback** (`is_target_in_blade_arc`). The cone fallback is exactly how you stop tunnelling at low FPS. Good instinct.

---

## B. Bugs (verified or high-confidence)

### BUG-1 · Asset import aborts because of `models/boss_veil_editable.blend` — *verified*
```
ERROR: Blender path is invalid or not set ... Cannot configure blender path in headless mode
```
When `--import` hits the `.blend`, the whole import batch stops. Reproduced: with the `.blend` present, `hero.glb` and `boss_veil.glb` never import and `.godot/imported/` stays empty. Remove it and all three import fine.
**Why it matters:** any CI, any fresh clone, any `--import` run leaves the game with unimported models. `verify.sh` cannot see this because it never imports.
**Fix:** keep `.blend` out of the runtime project (put it in `art/` with an `.gdignore`, or delete it — `build_models.py` regenerates it), and add `--import` as `verify.sh` step 0.

### BUG-2 · Jolt rejects the scaled physics bones — *verified, 12 errors per profile swap*
```
ERROR: Failed to correctly scale body 'PhysBone_Head' ... A scale of (0.92, 1.04, 0.92)
       is not supported by Jolt Physics for this shape/body
```
`apply_character_proportions()` ([character_body_3d.gd:350](character_body_3d.gd#L350)) applies a **non-uniform** scale (`char_width, char_height, char_width`) to `custom_model_root`, and `_setup_physical_ragdoll()` has already parented `PhysicalBone3D` + capsule children under that skeleton. Jolt cannot scale a capsule non-uniformly, so every bone screams. You get the same flood on every profile switch and every model swap.
**Fix:** keep the visual non-uniform scale on `VisualRoot`, and put the ragdoll `PhysicalBoneSimulator3D` under a separate *unscaled* node — or set `pb.custom_integrator`/scale the capsule `height`/`radius` numerically instead of scaling the transform.

### BUG-3 · A GLB surface has no material
`ERROR: Parameter "material" is null` from `material_get_instance_shader_parameters`, emitted once per model swap. Some surface in `hero.glb`/`boss_veil.glb` has no material assigned (Blender `add_part` assigns only slot 0). `_apply_seinen_shader_to_glb()` handles the null safely, so it is cosmetic — but it means one mesh surface is rendering with the engine default. Fix in `build_models.py`: append the material to every slot, and add a fallback `else` branch.

### BUG-4 · `verify.sh` cannot actually fail for the things that break this game
- It only imports nothing, so BUG-1 passes.
- It boots `--quit-after 10` — 10 frames, before `swap_custom_model`, ragdoll, PvP or any shader path is reached.
- Its error grep misses `Failed to correctly scale body`, `Failed loading resource`, `Cannot open file 'res://.godot/imported/...'`, and `Parameter "material" is null`.
- It does not run `smoke_test.gd` (which already exists and simulates touch input!) nor any tap/swipe coverage.
- It hard-codes `godot` from `PATH` with no version assertion, while `project.godot` declares `4.7`.
**Fix:** step 0 `--import`; assert the major.minor version; extend the grep to `ERROR:` generally (with an allowlist for the Blender line); and run `smoke_test.gd` as step 3.

### BUG-5 · Player can never die, boss can never be beaten
```gdscript
player.hp = maxf(100.0, player.hp - 55.0)      # gesture_combat.gd:669
player_ref.set("hp", maxf(100.0, ...))          # flame_p5_pvp.gd:522
```
HP is floored at 100, so you cannot lose. And in `apply_damage()` a boss at 0 HP instantly does `hp = max_hp` + `RAGDOLL_KO` + `1.65s` later it stands up again — so you cannot win either. There is no win/lose state, no restart, no reward. This is the single biggest *game* gap: the combat has no stakes.

### BUG-6 · `SAVE JSON` doesn't survive a restart (wrong load order)
```gdscript
data_store.load_from_disk(self)     # character_body_3d.gd:151  ← restores saved tunables
apply_race_by_name(active_race_name) # :154                      ← overwrites them from profile defaults
```
`save_to_disk` stores `char_height`, `weapon_scale`, `cel_cut_threshold`, `outline_width`, `rim_strength`, `eye_*`, slots… and then `apply_race_by_name()` immediately overwrites most of them from the profile dictionary. Same for the shader: values are assigned with `player.set()` but `update_cel_shader()` / `update_eye_shader()` / `apply_character_proportions()` are never called after load, so nothing looks different until you touch a slider.
**Fix:** load → apply tunables → `apply_race_by_name()` for identity, then re-apply the tunables after it; finish with `update_cel_shader/update_eye_shader/apply_character_proportions`. Also `hp = max_hp` inside `apply_race_by_name()` means switching profile is a free full heal.

### BUG-7 · Enemy AI walks through geometry
```gdscript
td.global_position.x += move_dir.x * spd * delta   # gesture_combat.gd:607
td.global_position.z += move_dir.z * spd * delta
```
Dummies are `CharacterBody3D` but the AI writes `global_position` directly, so they phase through pillars, arches and your placed blocks, and never fall (Y is pinned to `1.0`). Combined with `_update_enemy_ai` rotating `td.rotation.x` for telegraphs, the collision capsule tilts with the body.
**Fix:** `td.velocity = move_dir * spd; td.move_and_slide()` (or `NavigationAgent3D` when you have a real level), and put telegraph tilt on a `visual` child, not the body.

### BUG-8 · Boss weapon never animates
```gdscript
if wp and wp.name == "DummyWeaponPivot": wp.rotation_degrees = ...
```
Once `BossVeilModel` is attached (`_attach_dummy_weapon`), `wp.name == "BossVeilModel"`, so every attack telegraph/strike *pose* is skipped for the actual boss — you only get the material colour flip. Give the boss a bone-attached weapon node with the same interface, or drive `AnimationPlayer` attack clips.

### BUG-9 · Dash spam / dash is not gated
`dash_cooldown = 0.04` but `dash_duration = 0.20` ([character_body_3d.gd:17](character_body_3d.gd#L17)). `trigger_dash()` only checks `dash_cd_timer > 0` and never checks `state == DASH`, so you can re-trigger dash every 40 ms *during* a dash → effectively infinite travel, and `check_destruction()` fires on every re-trigger. Clamp cooldown ≥ duration or reject while `state == DASH`.

### BUG-10 · PvP sends a UDP packet every rendered frame
[flame_p5_pvp.gd:534-536](flame_p5_pvp.gd#L534) — string-formatting a `P2PSYNC` packet and `put_packet()`ing it inside `_process`. At 165 fps that is 165 packets/s *per peer*, with a `%`-format allocation each time. On a hotspot this will hitch and burn battery for no benefit — 20–30 Hz is indistinguishable for this kind of sync.
**Fix:** throttle to ~0.05 s, and build the string with `%` only when the timer fires.

### BUG-11 · Audio pops exactly on impact
`_pump_synth_audio()` is only reached through `update_vfx()`, which is at the very end of `_physics_process` — *after* the `hitstop_timer > 0.0: return` early-out ([character_body_3d.gd:793](character_body_3d.gd#L793) region). During hitstop (precisely when `clash`/`hit` fire) nothing feeds the generator, so the buffer underruns. Also there is only one generator, so `hit` + `shatter` cut each other off. Move the pump to `_process` and use 2–3 `AudioStreamPlayer`s round-robin.

### BUG-12 · Unmatched swipes silently cast `Spell_Slot_1`
`_cast_matched_spell()` falls back to `Spell_Slot_1` if no sequence matches, so any random 3-swipe mash casts a real spell with slot 1's stats. Either don't fire, or mark it "WHIFF WEAVE".

### BUG-13 · PvP room code → IP fallback is guesswork
`SZ148` → `192.168.0.148` by parsing digits, plus broadcast. It works on a simple hotspot; it breaks on any subnet that isn't `/24` matching the host's IP, and the room password is sent in **plaintext UDP**. Fine for a prototype with friends — just know it is not a security boundary, and the auto-guess can connect you to an unrelated device on the LAN.

### BUG-14 · `udp_beacon.bind(7778)` failure is ignored
`PacketPeerUDP.bind()` return value is discarded in both `flame_p5_pvp.gd` and `p2p_pause_manager.gd`. If the port is taken you get "HOSTING… awaiting challenger" forever with no error. Check the result. (Also: both files bind 7778 — see DEAD-1.)

### BUG-15 · Cosmetic/logic nits
- `world_story.gd`: `"SILICON NOMADEXECUTIONER"` — missing space (it renders in the boss title).
- `Slot_8_Counter` exists in `move_slots` and in the Tab 3 dropdown but `_commit_strike()` can never select it → dead move.
- Story choices can loop (`node_eclipse_summit` → `node_start_sanctuary`) forever; `story_flags` is collected but never read, and never saved.
- `flame_p5_pvp.toggle_flame_awakening()` restores the rim colour to a hard-coded red instead of the active profile's `aura_color`.
- `dev_studio._refresh_story_ui()` reaches a region by `region_idx = (reg_i + 2) % 3; _cycle_region()` — a modulo trick that only works because there are exactly 3 regions.

---

## C. Missing / unfinished (what you forgot to implement)

Ranked by how much they block "this is a game":

1. **Death, defeat and restart.** No lose condition (BUG-5), no KO screen, no respawn, no "retry duel". Without this the arena is a tech demo.
2. **Win condition + progression.** Beating a rival changes nothing. `story_flags` and `completed_nodes` are collected and thrown away; `origins` are cosmetic. Tie `spawn_story_rival` → boss HP reaching 0 → unlock the *next* node, and persist it.
3. **Persistence of anything except tunables.** No save slot for story progress, unlocks, or which abilities you have. `p2p_pause_manager` even has `unlocked_p5_pause`, but the P5 menu it now uses in `flame_p5_pvp` is unconditional.
4. **A real options/pause menu.** `Esc` only toggles mouse capture. There is no volume slider (the synth SFX is fixed at −6 dB), no sensitivity, no FPS cap that survives a restart, no quality preset, no "quit".
5. **Onboarding.** Two-orb swipe weaves + tap-both super parry + half-swipe feint is a *lot* to infer in silence. One overlay on first launch, three arrows, done.
6. **Gamepad support.** `InputMap` is registered with WASD/Shift/Space/Q only; there is no `InputEventJoypad*` anywhere. You are shipping to Android/iOS/desktop with no controller path, which is the default way people play this genre on PC.
7. **Audio buses.** One `AudioStreamPlayer` for everything, no `Music` bus, no ducking, no listener positioning (SFX are 2D `AudioStreamPlayer`, not `AudioStreamPlayer3D`).
8. **Enemy variety.** `AIMode` changes numbers only; every rival is the same boss mesh with different slot visibility. The story promises 4 distinct rivals.
9. **Mobile UI polish.** No safe-area handling (`DisplayServer.get_display_safe_area()`), no notch/punch-hole offsets for the orbs, no orientation lock, no pause on `NOTIFICATION_APPLICATION_PAUSED` / `WM_GO_BACK_REQUEST` (Android back button does nothing).
10. **Export read-through.** `export_presets.cfg` has no `package/icon`, no Android keystore/`min_sdk`/`target_sdk`, no `gradle_build`, no iOS `application/icon`/storyboard, and no `build/` in `.gitignore` — APK/IPA output will land untracked in the repo.

---

## D. Performance: where the CPU/GPU actually goes

Your instinct is right that this is expensive — but almost none of it is the shader. Ranked by real cost:

### D-1 · `physics_ticks_per_second` up to 165 — the biggest CPU lever
```gdscript
Engine.physics_ticks_per_second = 120 / 144 / 165     # dev_studio.gd:192-202
```
All gameplay runs in `_physics_process`: `move_and_slide`, `update_vfx` (occlusion loop over every block, all pooled FX timers, debris integration, audio pumping, `check_destruction` over every block), stepped animation, spring-bone. At 165 Hz that is **2.75× the work of 60 Hz**, on a phone, for physics precision nobody can perceive in this game. The "FPS mode" button is really a "burn my battery" button.
**Do:** default to `60`. Add one 120 Hz option, delete 165. Since the physics step is `1/60` and delta-based, feel is unchanged.

### D-2 · `apply_character_proportions()` runs 12× per second, forever
```gdscript
if active_anim_player:
    active_anim_player.advance(advance_time)
    apply_character_proportions()      # character_body_3d.gd:918
    _update_spring_bone_jiggle(...)
```
`apply_character_proportions()` writes a scale, sets a bone pose scale, **and then calls `apply_modular_clothing_slots()`**, which recursively walks the entire GLB hierarchy and, for every `MeshInstance3D`, loops all 5 slot prefixes doing string compares (`_set_slot_visibility_recursive`). Once per stepped frame at `anim_step_fps` (12), for both the player and any swapped model.
**Do:** only call it when a proportion or slot actually changes (on slider drag / slot change / model swap). Cache the slot-name→node list once at swap time. This is free FPS.

### D-3 · `queue_redraw()` every frame in the DevStudio overlay
`dev_studio.gd:557` — the full HUD (orb rings, direction labels, HP/TOKI bars, per-target HP/posture/telegraph rings, boss titles, P5 menu polygons) is redrawn every frame, each `draw_string` re-shaping text with `ThemeDB.fallback_font`. Plus `telemetry.text = "..." % [...]` re-layouts a Label every frame, and `DisplayServer.screen_get_refresh_rate()` is a platform query called every frame.
**Do:** cache the refresh rate once; throttle the overlay to ~10 Hz (or only redraw when a value changes); consider moving the static parts into a `CanvasLayer` with normal Controls so they are only laid out when dirty.

### D-4 · Draw calls grow without bound in build mode
`spawn_arena_block()` builds **fresh `MeshInstance3D`s + `BoxMesh`/`CylinderMesh`** per block, and `custom_block_nodes` is never capped. The 8 default pillars are already ~24 draw calls; a player placing 50 monoliths adds ~50 more, plus `check_destruction`/occlusion now iterate 58 entries per physics tick (×165/s).
**Do:** share the meshes (create once in `_ready`), cap placed blocks (e.g. 64 with the oldest removed), and convert the flora patch — already a `MultiMesh`, good — pattern to the pillars too.

### D-5 · Transparency overdraw
Afterimages (3 capsules), sigils (4 discs), slash arcs (4 torus 24×8), `blend_add` flame aura cone, and the `TRANSPARENCY_ALPHA_HASH` veil/stone materials. Alpha-hash in particular forces per-pixel discard on the mobile renderer for every veil surface, on every pixel it covers. This is your main *GPU* cost after resolution.
**Do:** switch the afterimages/sigils/slash arcs to `TRANSPARENCY_ALPHA` (not hash) where you don't need depth sorting tricks; keep the boss veil as hash but it's one surface. Consider dropping the torus `rings`/`ring_segments` (24×8 → 16×6) — invisible at that scale.

### D-6 · Shadows
`DirectionalLight3D.shadow_enabled = true` over a 400×400 floor with default `directional_shadow_max_distance` (100 m) spends shadow-map resolution on empty ground.
**Do:** set `directional_shadow_max_distance ≈ 25`, `directional_shadow_mode = PSSM_4_SPLITS` → actually for mobile use *2 splits*, and disable shadows on the floor material.

### D-7 · Uncapped framerate at boot
`_cycle_fps()` starts at `fps_mode_idx = 0` = `Engine.max_fps = 0`, `VSYNC_ENABLED` on desktop but nothing on Android/iOS/Web. A phone will render at whatever it can, get hot, and thermally throttle — then your 165 Hz physics makes it worse.
**Do:** `Engine.max_fps = 60` on mobile by default (or `DisplayServer.screen_get_refresh_rate()` capped at 120), with the button as an override.

### D-8 · Small ones worth a line each
- `gesture_combat._input()` calls `_update_dot_positions()` on **every** input event, including mouse motion.
- `_update_dot_positions()` also runs `get_viewport().get_visible_rect()` per event; the `size_changed` signal is already connected.
- `hit_flash`/`whiff_timer` decrement in `_process` but the material colour is re-assigned in `_update_enemy_ai` every frame regardless of change — a `StandardMaterial3D.albedo_color` write per enemy per frame forces a material update.
- `RenderingServer.viewport_set_measure_render_time(..., true)` enables measurement permanently — it's not free; only enable while the overlay is visible.
- `swap_custom_model()` never frees the old `Material` duplicates (`anime_mat.duplicate()` per GildedFiligree/PorcelainLily surface) — minor, but it grows with every model swap.

---

## E. Architecture / hygiene

### DEAD-1 · `p2p_pause_manager.gd` (278 lines) is referenced by nothing
Verified: zero references in any `.gd`, `.tscn`, `.cfg` or `.sh`. It is the *previous* generation of `flame_p5_pvp.gd` (ENet on port 7777 + P5 menu). It also binds **the same UDP port 7778** as the live module — if it is ever instantiated, the live PvP silently breaks. Delete it (git history keeps it), or it will get "fixed" by a future AI pass and quietly fight the real implementation.

### DEAD-2 · Two near-identical scenes, one broken
- `main.tscn` and `character_movement_test.tscn` are copies (`project.godot` points at the latter).
- `movement_test.tscn` is **invalid**: it has no `VisualRoot`, `CameraPivot`, `SpringArm3D` or `Camera3D`, all of which `character_body_3d.gd` requires with `@onready var visual_root: Node3D = $VisualRoot`. Opening or running it errors.
**Do:** delete `movement_test.tscn`, keep one scene, rename it `main.tscn` and point `run/main_scene` at it. "character_movement_test" as the shipping main scene will confuse every future contributor and every AI agent you hand the repo to.

### ARCH-1 · `character_body_3d.gd` is a 961-line god object
It owns: movement state machine, camera rig, cel/normal shaders, eye shader, weapon rig, modular clothing, spring bones, physical ragdoll, hitbox, save/load, model swapping, and touch input. Everything else reaches into it with `player_ref.get("...")` / `player_ref.call("...")` string duck-typing (`flame_p5_pvp.gd` alone has ~40 of these).
**Do (in order of payoff):**
1. Replace `get()/call()` string access with typed references or **signals** (`damaged`, `ko`, `awakened`, `slot_changed`). String duck-typing is the #1 way an AI agent breaks this repo — nothing warns you at parse time.
2. Extract `PlayerShaderRig` (shaders + eye + cel), `PlayerRagdoll` (physical bones + KO), `PlayerOutfit` (slots + proportions). Movement stays in `PlayerController`.
3. Move the DevStudio UI out of `_build_ui()` (≈500 lines of runtime-built Controls) into a `.tscn` + a Theme resource. It will look better, take less code, and become editable.

### ARCH-2 · Magic numbers everywhere
`1.65`, `0.22`, `2.2`, `0.09`, `5.5`… spread across combat. Not urgent, but the moment you want to balance, a single `Balance` resource (or `const` block per system) pays for itself.

### ARCH-3 · `.gitignore` is too thin
`build/` (APK/IPA/web output), `*.apk`, `*.ipa`, `*.tmp`, `.DS_Store`, `*.blend1`, and `models/*.blend.import` should be ignored. Right now an Android export drops an untracked APK in your repo.

### CI-1 · `ios_ipa.yml` downloads Godot **4.3** for a **4.7** project
`Godot_v4.3-stable`, `export_templates/4.3.stable`, but `project.godot` declares `4.7`. The export will refuse or produce a mismatched build. Also: no import step, `|| true` swallows export errors, and the artifact upload can succeed with zero files. No Android workflow exists at all.
**Do:** pin the version in one place (a `GODOT_VERSION` env at the top), add `--headless --import` before export, drop `|| true`, and add an Android `workflow_dispatch` job mirroring the iOS one.

---

## F. Local AI on your laptop (Precision 5550, 16 GB RAM, 4 GB VRAM)

Reality check first: **4 GB VRAM is the binding constraint**, not the CPU. The model + context has to live somewhere, and on this machine most of it will live in system RAM. That is fine — it just means slow-ish tokens, not "can't run".

### What actually fits

| Goal | Model | Disk | Where it runs | Expect |
|---|---|---|---|---|
| Daily driver: explain, patch one file, write GDScript | `qwen2.5-coder:7b-instruct-q4_K_M` | 4.7 GB | ~3.2 GB in VRAM + rest in RAM | 6–12 tok/s, 8–16k ctx |
| Faster/weaker fallback for autocomplete | `qwen2.5-coder:1.5b` | ~1 GB | fully in VRAM | 30–60 tok/s |
| "One hard question", design review, refactor plan | `gpt-oss:20b` (MXFP4) | ~12 GB | almost all CPU | 1–3 tok/s, 4–8k ctx only |

If you can spend ~₹4–6k on **one 16 GB SODIMM** (the 5550 has two slots; used DDR4-3200 16 GB is cheap), `qwen2.5-coder:14b` (~9 GB) becomes the sweet spot and the whole experience changes. That is by far the highest-value upgrade for local AI on this machine — more than any GPU.

Do **not** try to run 20B+ agentically on 16 GB. It will thrash, and an agent that edits files at 2 tok/s is worse than copy-pasting into me.

### The setup (Windows, 20 minutes)

```powershell
winget install Ollama.Ollama          # or the installer from ollama.com
ollama pull qwen2.5-coder:7b
ollama pull qwen2.5-coder:1.5b
ollama run qwen2.5-coder:7b "explain this GDScript: ..."
```
Pin the GPU layers so you don't spill needlessly — create a `Modelfile`:
```
FROM qwen2.5-coder:7b
PARAMETER num_gpu 22          # tune: raise until it OOMs, then back off 1
PARAMETER num_ctx 8192
PARAMETER temperature 0.2
```
`ollama create sasti-coder -f Modelfile`

### Editor / terminal wiring (pick two)

- **Aider** (closest to your current copy-paste-into-terminal workflow):
  `pip install aider-chat` then
  `$env:OLLAMA_API_BASE="127.0.0.1:11434"; aider --model ollama_chat/sasti-coder`
  Aider does repo-map + git commits per change, so a small model punches above its weight because it only sees relevant files.
- **Continue** (VS Code / Cursor extension): provider `ollama`, chat model `sasti-coder`, autocomplete model `qwen2.5-coder:1.5b`. This is the one that replaces your "copy paste to terminal" loop entirely.
- Keep **Godot MCP** for editor-side work — your `.gemini/settings.json` still points at `@coding-solo/godot-mcp`. MCP calls cost no tokens and can open scenes, read the remote inspector, and run the project; that is exactly the context a 7B model is missing.

### The strategy that saves you the most tokens

1. **Retrieval beats context stuffing.** This repo is ~60k tokens of GDScript — it does not fit a 16k-32k local window, and a 7B model degrades past ~8k anyway. Never paste the repo. Paste `character_body_3d.gd` + the one function you're changing, or let Aider's repo-map pick.
2. **Keep a `CONTEXT.md` in the repo** (30 lines: what each file owns, the two-orb control scheme, the 7 dev tabs, the save format, "GDScript 4.7, mobile renderer, Jolt, 60 Hz physics"). Paste it as the system prompt every session. It is worth more than 10k tokens of code.
3. **Let the gate do the reviewing.** `bash verify.sh` (after BUG-4's fixes) is the cheapest correctness check you own. Workflow: local model writes a patch → `verify.sh` → if it fails, paste *only the error* back. You never need a big model for that loop.
4. **Split the work by tier.** Local 7B: mechanical edits, renames, doc-comments, writing the `.tscn` boilerplate, explaining an error, drafting `build_models.py` tweaks. Cloud/me: architecture, the bugs in section B, anything touching physics/shader interactions. That is how you stop running out of tokens.

---

## G. Suggested order

**This week (bugs, ~2 h):** BUG-1 (.blend import), BUG-4 (harden `verify.sh`: import + version + `ERROR:` grep + run `smoke_test`), DEAD-1/DEAD-2 (delete `p2p_pause_manager.gd`, `movement_test.tscn`), BUG-11 (audio pump), BUG-10 (PvP throttle).
**Next (feel + cost, about half a day):** D-1 (physics 60), D-2 (cache `apply_character_proportions`), D-3 (overlay 10 Hz), BUG-9 (dash gate), BUG-2 (ragdoll scale).
**Then (game loops):** BUG-5 + section C.1/C.2 — death, victory, story persistence. This is the difference between a demo and a game.
**Then:** BUG-6 (save order), BUG-7 (enemy collision), BUG-8 (boss weapon), CI-1, ARCH-1 step 1 (kill the string duck-typing).
**Polish last:** D-4/D-5/D-6 GPU work, section C.4/C.5/C.6.

---

*Nothing in this review has been committed or pushed. `main` was never touched; all observations were made on `freebuff/9df505384c5b1c5ec2578cb3` with a scratch copy of the project and a throwaway harness that is not part of the repo.*
