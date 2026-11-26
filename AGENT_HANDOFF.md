# Agent Handoff — Sasti Sparkling Zero

A shared channel between AI agents working on this project. **Append, never overwrite.**
Newest entry at the bottom of §4. Keep entries short and factual: what you changed, what you
verified, what you left open.

- **Repo:** `Pinkypoopoo/sasti-sparkling-zero`
- **Working branch:** `Pinkypoopoo-patch-1`
- **Protected:** `main` / `freebuff-base`. **Never commit or push to main.** All experiments live on
  their own branch so the user always has a fallback.
- **Engine:** Godot **4.7** (declared in `project.godot`). Mobile renderer, Jolt Physics.
- **Gate:** `bash verify.sh` — must pass before any handoff. It now checks engine version, core
  files, 18 feature signatures, asset import, a 120-frame headless boot, and the touch smoke test.

Read [CODE_REVIEW.md](CODE_REVIEW.md) (evidence, line numbers, bug list) and
[ROADMAP.md](ROADMAP.md) (the plan) before touching code. Do not duplicate that analysis.

---

## 1. What is verified (do not re-investigate)

Confirmed by running Godot 4.7 headless against a scratch copy on 15 Nov 2026:

- The project **boots clean** — no parse errors, no script errors.
- A 30-subsystem drive (4 profiles, model swaps, every move slot and spell sequence, KO path, all 7
  dev tabs, flame awakening, P5 menu, PvP host/join/deny, 4 story origins + choices, ragdoll,
  save/load, block builder, 30× parry/feint/super-parry) produced **no GDScript runtime errors**.
- Two engine-level error sources exist: **Jolt rejects the non-uniform-scaled `PhysicalBone3D`s**
  (12 errors per profile/model swap) and one GLB surface has **no material**.
- **`models/*.blend` aborted the entire headless asset import.** `--import` stopped at the `.blend`
  and never imported `hero.glb` / `boss_veil.glb`. Fixed by moving it to `art/` (+ `.gdignore`).
- `verify.sh` previously **could not** catch any of the above (no import step, 10-frame boot, narrow
  grep). Rewritten — see §2.

If you change anything about physics scaling, shaders or import, re-run the gate and update this list.

---

## 2. State as of 15 Nov 2026 (reviewing agent)

Done on branch `freebuff/9df505384c5b1c5ec2578cb3`, **not committed, not pushed**:

| Change | File |
|---|---|
| New evidence-based review | `CODE_REVIEW.md` (new) |
| New plan / scope / art direction / milestones | `ROADMAP.md` (new) |
| This handoff channel | `AGENT_HANDOFF.md` (new) |
| `verify.sh` rewritten: version assert, import gate, wider `ERROR:` gate, smoke test | `verify.sh` |
| `.blend` moved out of the import path | `models/boss_veil_editable.blend` → `art/`, `.import` deleted, `art/.gdignore` added |
| Dead duplicate module deleted (binds the same UDP port as the live one) | `p2p_pause_manager.gd` (+ `.uid`) |
| Invalid unused scene deleted (missing nodes the player script requires) | `movement_test.tscn` |

Gate output after the changes: `VERIFY_PASSED` (version / files / 18 signatures / import / boot /
smoke). Negative controls, all three proven to fail the gate:
1. append a parse error to `combat_data.gd` → `SCRIPT ERROR: Parse Error`;
2. truncate `models/hero.glb` → `asset import reported engine or script errors`;
3. put a `.blend` back into the import path → `did not import` + root-cause message.
The gate is not a rubber stamp.

`main` was never touched. Godot 4.7 was installed only in the review sandbox, never in the repo.

---

## 3. Open questions for the next agent (Gemini / DeepSeek / whoever)

Answer in §4 with a dated entry. These are decisions, not research tasks.

1. **Tuning layer (`ROADMAP.md` §1).** Agree with "every tunable lives in `data/balance.tres` +
   a reflecting registry", or is there a cheaper path you prefer given the user must tune from a
   phone UI? If you agree, who writes the registry — and does the existing `_add_row()` helper get
   kept as the renderer?
2. **Death/victory flow.** The user wants systems first, refinement later. Does a minimal
   "DEFEAT card + RETRY" (M2) ship before the ranked shell (M3), or does the shell come first
   because it is mostly UI?
3. **Style lock.** I recommend **Dark Seinen Ink** (2-tone ramp + ink hatch + inverted-hull
   outline) over Sparking-Zero-style bloom/speed-lines, because the latter needs 2–3 full-screen
   passes and will not hold 60 fps on mid-range Android. Do you agree, and can you produce the
   one-week art test (1 character, 1 environment piece, 1 VFX) in that style?
4. **Story pipeline.** Recommend: Notion = authoring surface → exported node JSON → engine reads
   JSON, with a schema check inside `verify.sh`. Do you want to own the schema, or should I?
5. **Rival AI.** `s["ai_state"]` string machine is fragile and duplicates `PlayerController.MoveState`.
   Propose a `RivalBrain` enum + data-driven move weights before the 4-rival content pass?
6. **PvP.** Keep the LAN UDP module as a prototype and defer matchmaking/relay, or invest now?
   My read: defer until the single-player loop (M2) exists.

---

## 4. Message log

### 2026-11-16 · Buffy (Freebuff) — V5 Task 2: CanvasLayer impact slash, ring, tier-capped cel smoke

Branch `Pinkypoopoo-patch-1`, based on `f7b60ec`. `main` untouched (`0c80d97`).
Gate: **VERIFY_PASSED**, 7 gates, 68 signatures, 76 combat asserts, zero GDScript warnings.

Audit first (the earlier V5 commit already had most of this; do not rebuild it):
- `gesture_combat.trigger_impact_slash()` existed at `IMPACT_SLASH_TIME = 0.16 s` and already
  fired on a crit, on posture break, on KO (`_kill_rival`) and on super parry.
- The 2D drawing (white impact frame, diagonal ink slash, expanding double ring, 4-point star
  flare) existed in `dev_studio._draw_impact_slash()`.
- `dash_vfx.spawn_cel_smoke()` existed with a 14-quad pooled 2-tone `CEL_SMOKE_SHADER`, already
  called on hard landings, dash bursts, wall-run start, wall kick-off and the ledge vault.

Gaps closed (this commit)
1. The slash now renders on a real `CanvasLayer` (`dash_vfx.ImpactSlashLayer`, layer 20) via an
   inner `ScreenSlash extends Control`, instead of inside the DevStudio Control's `_draw()`.
   Same vectors, but now guaranteed above the 3D world and the HUD. `dev_studio._draw_impact_slash()`
   and its call site are removed; the white impact frame (`impact_flash_timer`) still draws from
   the HUD.
2. Z-Vanish counter never fired a slash. `_check_active_parry_against_enemies()` only spawned a
   sigil; it now triggers the slash, which is one of the triggers the spec named and was missing.
3. Four tab-8 knobs added, auto-generated so no UI code: `impact_slash_enabled`,
   `impact_slash_intensity`, `cel_smoke_enabled`, `cel_smoke_density`.
4. Cel smoke respects the 4-tier budget: `dash_vfx.fx_cap` tracks the tier debris cap
   (LOW 8 / MID 16 / HIGH 28 / ULTRA 28); `spawn_cel_smoke()` refuses when full or disabled and
   scales puff count by density. On LOW the singularity ring and star flare are skipped, leaving
   the slash core, so a phone pays 3 lines instead of 3 lines + 2 arcs + 4 flares.
5. `character_body_3d._push_fx_budget()` pushes tier + knob state to `dash_vfx` every physics tick
   next to `set_water_enabled()`, so the checkboxes are live with no extra polling state.

Verified: 76 asserts (was 67). New ones cover all four defaults, the CanvasLayer, firing, the
toggle disabling it, smoke refusing while off, and the cap bounding the puff count. Gate 7/7 with
real GLB import and the character contract, boot warning scan empty, shader untouched.
Not verified: no on-device run (no GPU or phone here) — slash/ring timing and the smoke read are
unjudged, and `_draw()` never executes because the dummy renderer has no canvas, so the asserts
prove state and lifetime, not pixels.

### 2026-11-16 · Buffy (Freebuff) — V5 Task 3: water floor audit + vault side-edge fix

Branch `Pinkypoopoo-patch-1`, rebased on `ad3c4c0`. `main` untouched (`0c80d97`).
Gate: **VERIFY_PASSED**, 7 gates, 71 signatures, 89 combat asserts, zero GDScript warnings.

Audit result — the water floor was already most of the way there:
- `WATER_SHADER` in `dash_vfx.gd` is `render_mode unshaded, cull_disabled, depth_draw_opaque`
  with a hard 3-band `if` ladder (trough < 0.54, mid < 0.82, crest). Crisp steps, no
  interpolation, no `light()` function at all, so "no return in light()" cannot be violated,
  and zero full-screen post-processing.
- Both contact uniforms already existed: `player_pos` and `boss_pos`, fed from `update_vfx(...)`
  every tick with `global_position` and `_water_focus_pos()` (lock target, else first combat
  target, else the 9999 sentinel).

Three real gaps, closed:
1. No ripple knob. Added `water_ripple_strength` (0–2, default 1.0) to `TUNING_SPEC` +
   `TUNING_DEFAULTS`, pushed to a new `ripple_str` uniform that scales both contact rings.
   Tab 8 generates it automatically.
2. No tier gating. `apply_quality_tier()` showed the plane at every tier including LOW, where
   240x240 at 32x32 subdivisions (2048 quads) is not free on an Adreno 618. New
   `_push_water()` gates on `quality_tier >= 1`: LOW never shows it, MID/HIGH/ULTRA get the
   full shader with both ripples.
3. `_update_water_floor()` blind-set both vec3 uniforms every tick — a RenderingServer
   dirty-mark per frame, contradicting the change-driven comment above `set_water_enabled()`.
   Now cached with a 0.01 m epsilon, so the shader is only touched when a fighter actually moves.

Wall-run side-edge false vault (`character_body_3d.gd`):
- The chest (1.1 m) and head (2.2 m) forward rays are equally clear when running horizontally
  past the SIDE of a pillar into open air, so `_vault_onto_ledge()` launched you into the void.
- Added `_has_floor_below(from_point, depth)`: a downward ray requiring `normal.y > 0.5` (a
  real top surface, not a wall) within `LEDGE_FLOOR_DEPTH = 2.4 m`. `_ledge_vault_clear()` casts
  it from the forward clearance point (+1.1 m up, +0.75 m forward) and refuses over open air.

Hygiene checks, both already correct (no change needed):
- `ScreenSlash._process()` returns immediately while `timer <= 0`, otherwise decrements and
  calls `queue_redraw()` every render frame, hiding at 0 — per-frame while active, silent idle.
- `export_presets.cfg` carries `include_filter="*.json"` on all three presets;
  `.github/workflows/ios_ipa.yml` targets `4.7-stable` (zero references to the old 4.3 pin).
- Handoff was 468 lines over 6 entries. The four oldest moved verbatim to
  `docs/archive/AGENT_HANDOFF_ARCHIVE.md`; the latest three stay here.

Verified: 89 asserts (was 76). New ones cover the water toggle/slider/ripple defaults, MID-on
and LOW-off gating, `player_pos` + `boss_pos` actually landing in the shader, the slash
revealing and hiding, absolute refusal with no floor below, acceptance on the arena floor, and
`_ledge_vault_clear()` refusing a side-edge run. Gate 7/7 with real GLB import.
Not verified: no visual or on-device run — the 3-band silhouette, ripple read and LOW-tier
frame cost are unjudged, and the dummy renderer never executes `fragment()`.

### 2026-11-16 · Buffy (Freebuff) — V5 Task 4: 4-channel vertex colour + hand-crafted art pipeline

Branch `Pinkypoopoo-patch-1`, rebased on `744c515`. `main` untouched (`0c80d97`).
Gate: **VERIFY_PASSED**, 7 gates, 71 signatures, 100 combat asserts, zero warnings.

Audit result — the shader was 3 of 4 channels complete:
- R (shadow bias) reads `v_col.r` through `vertex_bias`; G (outline weight) is read by the
  outline pass's `vcol_weight`; A drives the SDF face branch via `v_col.a > 0.5`.
- **B was documented and packed but never read.** `light()` computed the toe specular from
  N-dot-H alone, so the metallic mask did nothing. Now `* v_col.b`: iron, gold and the visor
  keep their spec, cloth and veil lose it, and unpainted meshes (COLOR = white) are unaffected.
- Compliance verified, no change needed: `COLOR` reaches `light()` through `varying vec4 v_col`
  (with `v_uv` for the SDF sample), the `light()` body has zero `return` statements, both
  character meshes carry `SHADOW_CASTING_SETTING_OFF`, and `swap_custom_model()` already calls
  `_apply_seinen_shader_to_glb()` **before** `visual_root.add_child()` — the comment there
  exists because doing it after logs "Parameter material is null" for a frame.

head_forward / head_right plumbing:
- `_push_head_basis()` ran every physics tick whenever the anime face was active and blind-set
  both vec3 uniforms. Now epsilon-cached (1e-6 squared, ~0.06 degrees) on `_head_fwd_applied` /
  `_head_right_applied`, so animation still drives the uniform while an idle character stops
  dirty-marking the material.

Hand-crafted art pipeline (`art/`):
- `art/.gdignore` already existed; added `art/export_handcrafted.py` and `art/MODELING_CONTRACT.md`.
- `export_handcrafted.py` validates the exact gate-3b contract (6 bones, 5 `Slot_` prefixes,
  5 clips) and prints an `ok`/`MISS` checklist, refusing to export when something is missing
  (`--allow-missing` to override). It creates the `Col` CORNER byte-colour layer, fills
  `RGBA(0.5, 1.0, 0.0, 0.0)` only while the layer is untouched, leaves hand-painted channels
  alone, and optionally runs `proxy_smooth_normals()` (DATA_TRANSFER from `<mesh>_ProxyCage`
  or a generated sphere), then exports with `build_models.py`'s exact gltf kwargs.
- `MODELING_CONTRACT.md` carries the bone table with engine consumers, the slot list, the five
  clips, measured triangle counts (hero 980, boss 940 tris) with mobile ceilings, and the
  `COLOR.rgba` cheat sheet with the real palette values from `tools/build_character.py`.
- `verify.sh` gate 2b now fails on any `.blend` inside `models/`, on a missing `art/.gdignore`,
  and on `python3 -m py_compile art/export_handcrafted.py` failing.

Verified: 100 asserts (was 89). New ones cover the varying, the absence of `return` inside
`light()`, all four channels being read, self-shadow off, the outline next_pass, head_forward
and head_right tracking the head basis, the epsilon cache surviving a tampered uniform, and a
turning head repushing it. Exporter compiles and its contract lists match character_test.gd.
Not verified: no Blender in this sandbox (5.2 LTS absent), so `export_handcrafted.py` was
py_compile- and AST-checked only — its bpy calls have never executed. The B-channel spec change
is a look change on cloth and veil that nobody has seen yet.

### 2026-11-16 · Buffy (Freebuff) — V5 Task 5: merged saves, P5 tap, UDP 7778 hardening

Branch `Pinkypoopoo-patch-1`, rebased on `93e9ac6`. `main` untouched (`0c80d97`).
Gate: **VERIFY_PASSED**, 7 gates, 71 signatures, 116 combat asserts, zero warnings.

Book 3 audit — both writers already merged, but the key was wrong:
- `combat_data.save_to_disk()` and `world_story.save_state()` both do read-modify-write,
  so neither could erase the other. Verified with a round-trip test, not rebuilt.
- **Real bug: the story section was written as `"story"`, while
  `.agents/rules/world-story.md` and the task contract both specify `"story_state"`.** Now
  written as `story_state`, read from `story_state` with a one-time fallback to `story`, and
  the legacy key is erased on save so the two can never diverge.
- Crash paths removed in the story loader: `_origin_start()` replaces an `as Dictionary` cast
  that returned null and then called `.get()` on it; `make_choice()` now type-checks that
  `choices` is an array and the chosen entry is a dictionary; `requires_flags` /
  `grants_unlocks` are type-checked (a malformed gate opens the choice rather than locking
  the player out).
- `gesture_combat.spawn_story_rival()` type-checks `rival_hp` (clamped 1..99999),
  `rival_scale` (0.5..2.0) and `rival_slots` (non-dict becomes empty), so a partial node
  spawns a sane rival instead of erroring.

Book 4 audit:
- `_handle_p5_blade_tap()` already calls `set_input_as_handled()` first; the comment there
  records why (the tap was also reaching `btn_menu`, which closed the menu again). Now
  asserted for real: one tap flips the row's state AND `get_viewport().is_input_handled()`
  is true afterwards.
- 8 tabs, `[ MENU ]`, the 10 Hz HUD throttle and the 4-tier scaler are untouched; the gate
  still reports 8 tabs and zero warnings.
- PvP: port 7778 and `P2P_SEND_HZ = 30.0` (0.0333 s accumulator) confirmed. No cyclic
  `class_name` hints - the module only declares its own; gate 2b now fails on any
  `PlayerController` reappearing in `flame_p5_pvp.gd`.

UDP hardening (`flame_p5_pvp.gd`):
- The inline packet parser was extracted to `_handle_udp_packet(m, sender_ip)` with every
  branch size-checked, plus `_join_verdict()` so the password lock is unit-testable without
  a socket ("IGNORE" wrong room / "DENY" wrong password / "ACCEPT").
- Bounded: 64 packets per frame (a flood used to spin the whole `while` in one tick),
  `discovered_rooms` capped at 16, room codes capped at 16 chars, packets over 512 chars
  dropped, `nan`/`inf` rejected via `_safe_float`, sync coordinates clamped to +/-5000 m and
  reported hp to 0..99999, denial text truncated to 96 chars.

Verified: 116 asserts (was 100) plus a new merged-save round trip in `story_test.gd`
(backing up and restoring the real profile around it). Not verified: no two-device UDP match
was run — hostile packets are proven safe only by calling `_handle_udp_packet()` directly
with `udp_beacon == null`, and the 30 Hz cadence is asserted from the constant, not measured
on a wire.

=== END AI HANDOFF PACKET ===

### 2026-11-26 · Buffy (Freebuff) — V6 Task 1: touch-first Dev Studio + 4.7.2 warning cleanup

Branch `Pinkypoopoo-patch-1`, based on `79da49b`. `main` untouched (`0c80d97`).
Gate: **VERIFY_PASSED**, 7 gates, 79 signatures, 137 combat asserts, zero GDScript warnings
(`--check-only` on `dev_studio.gd` / `character_body_3d.gd` / `combat_test.gd` silent, 120-frame
boot scan empty).

Godot 4.7.2 editor-debugger warnings (all four, `character_body_3d.gd`):
1. `var scale` in `apply_quality_tier()` renamed `render_scale_applied` — it shadowed `Node3D.scale`.
   Gate 2b's shadow regex now also matches *typed* locals (`var scale: float = ...`), which is why
   this one shipped twice: the old pattern only caught `var scale =`.
2. `vp.msaa_3d = int(prof["msaa"])` now casts `as Viewport.MSAA`; gate 2b fails any bare
   `msaa_3d/msaa_2d = int(...)` without the cast.
3. `_update_ragdoll_bones(dt)` → `_dt` (the pose is a function of `stepped_time`, the delta was dead).
   Gate 2b pins the signature.
4. Interpolated-camera warning: the rig (`CameraPivot`, `SpringArm3D`, `Camera3D`) is written every
   *render* frame in `_process()`, so it now opts out with
   `physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF`. Per-render follow/FOV/roll stay
   smooth and the parent capsule still interpolates the rig's base transform. Chosen over moving the
   camera into `_physics_process`, which would quantise 120 Hz camera motion to 60 Hz.

Touch-first Dev Studio (`dev_studio.gd`) — all 8 tabs, Tab 8 auto-generation, `[ MENU ]` and the
single-tap P5 menu untouched:
- `tab_container.tabs_visible = false`; a 2x4 `GridContainer` of `MOBILE_TAB_LABELS` pills (48 px
  tall, expand-fill, toggle highlight) replaces it. `_select_tab()` / `_sync_tab_pills()` keep the
  pills and `current_tab` in lockstep, including the P5 menu's "open Dev Studio at tab N" rows.
- Panel is now full-bleed (8 px inset) instead of a fixed 820x500 box, with a full-rect
  `ColorRect` backdrop on `MOUSE_FILTER_STOP` plus `dev_panel.mouse_filter = STOP`, so no tap
  reaches the MOVE/ATK orbs underneath.
- Header quick controls: live `FPS · ms · time scale · tier` readout on the existing 10 Hz throttle;
  `[ PAUSE / RESUME ]` (`get_tree().paused`, studio is `PROCESS_MODE_ALWAYS`) with a `PAUSED` badge;
  `[ GOD MODE ]` pill wired to `immortal_mode`; `[ COPY ALL ]` → clipboard + `user://balance_values.txt`
  with an on-panel toast; 56x48 `X`.
- `_build_mobile_theme()`: obsidian `StyleBoxFlat` card (1 px border, 12 px radius), button/OptionButton
  pills, dark-vs-crimson CheckBox pills, 14 px track + 30 px round grabber texture for HSliders.
  `_apply_mobile_widgets()` walks each tab (and the rebuilt Tab 8) setting `>= 44 px` heights and
  prefixing every boolean with `[ ON ]` / `[ OFF ]`, so Tab 8 inherits the theme with no per-key code.
  Tab scrolls are vertical-only with 10 px separation; closing the panel always resumes the tree.
- Behaviour change worth knowing: `_toggle_dev_panel()` now force-resumes on close, so the game can
  never be left frozen with the resume button off-screen.

Verified (headless, `combat_test.gd` 19): 8 pills each reach their tab (helper + real `pressed`
signal), Tab 8 sliders/booleans >= 44 px, `PROCESS_MODE_ALWAYS` + pause/resume round trip with badge,
GOD MODE on/off mirrors `immortal_mode`, `_export_all_values()` formats `enemy_damage = 77`, writes
`user://balance_values.txt`, shows the toast, camera rig interpolation mode is OFF, MSAA cast still
applies the tier value.
Not verified: no on-device run — pill/slider ergonomics, the crimson CheckBox contrast in sunlight and
the clipboard (headless has no clipboard feature, so only the file path is asserted) are unjudged.

=== AI HANDOFF PACKET ===
REPO: Pinkypoopoo/sasti-sparkling-zero
BRANCH: Pinkypoopoo-patch-1 (HEAD for this entry: V6 Task 1)
DONE: 4 x 4.7.2 editor-debugger warnings fixed + gate-blocked; Dev Studio rebuilt touch-first
(tab bar hidden, 2x4 pill grid, full-bleed panel + backdrop, telemetry header, pause/god/copy,
mobile theme with >= 44 px controls, Tab 8 still auto-generated).
OPEN: no on-device visual pass (pill ergonomics, sunlight contrast, real clipboard); Blender 5.2
exporter still unrun.
NEXT: playtest the panel on a phone, then continue V6.
=== END AI HANDOFF PACKET ===
