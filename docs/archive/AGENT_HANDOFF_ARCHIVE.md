# AGENT_HANDOFF ARCHIVE

Entries moved verbatim out of `AGENT_HANDOFF.md` section 4 once the live file
passed 150 lines (AGENTS.md section 3). Chronological order. The live file keeps
the latest three verified entries.

---

### 2026-11-15 · reviewing agent (Buffy, via Freebuff)
Read the whole repo and ran it headless (Godot 4.7): boot clean, no script errors across 30 driven
subsystems. Wrote `CODE_REVIEW.md` + `ROADMAP.md`, hardened `verify.sh`, removed the dead module,
the invalid scene, and the `.blend` import blocker. Nothing committed or pushed; `main` untouched.

Top three things I would do next, in order: **(1)** build the tuning-resource layer so the user
never edits code to change a number; **(2)** add death / victory / save so the game has stakes;
**(3)** lock the art style in writing with a one-week test. See §3 for what I need from you.

---

### 2026-11-15 · reviewing agent (Buffy) — V2 build
Pushed as the **V2** version on branch `Pinkypoopoo-patch-1`. Two user-requested changes, both verified:

1. **In-game menu replaces the top action bar.** The 11-button bar was clipping and its tap targets
   were too small on a phone. There is now one 140×58 `[ MENU ]` button top-right; everything else
   (awaken, lock-on, switch target, pose, PvP, build, region, AI mode, FPS cap, save, dev studio,
   tabs 6/7, resume) is a row inside the P5 pause menu in `dev_studio.gd` + `flame_p5_pvp.gd`.
   Row height is computed from the viewport, so **the list cannot clip on any aspect ratio**;
   draw and hit-test both use `_p5_row_rect()`, so they cannot drift apart.
2. **Native refresh rate.** `_apply_display_mode()` caps rendering at
   `DisplayServer.screen_get_refresh_rate()` (clamped 60–240) and pins physics to **60 Hz**.
   `FPS_CAPS = [0 (= display), 60, 120, 165]` is cycled from the menu. `project.godot` now also sets
   `physics/common/physics_ticks_per_second=60`, so a fresh run without touching the menu is sane.

Verified: `bash verify.sh` passes all five gates; a throwaway harness tapped all 14 menu rows
headless with zero script errors and confirmed no row overflows the viewport. **Not** verified:
visual layout, real 120/144/165 Hz behaviour, and touch feel — those need a device.

---

### 2026-11-15 · reviewing agent (Buffy) — V3 combat feel + M2 stakes
Branch `Pinkypoopoo-patch-1` (local commit; **not pushed** — this session had read-only GitHub access).
Read `CODE_REVIEW.md` / `ROADMAP.md` first, then this.

**Answers to §3 open questions**
1. *Tuning layer* — AGREE, implemented in the cheap form that ships now: `combat_data.gd` has
   `TUNING_SPEC` (min/max/step/label), `TUNING_BOOLS`, `TUNING_DEFAULTS` and `tuning: Dictionary`.
   Dev Studio tab 8 builds its sliders/checkboxes by iterating those dicts. **Adding a knob is one
   line in `TUNING_SPEC`** — no UI code, no new `@export`. This is the same idea as `balance.tres`
   without a custom Resource class or registry, and it already covers hitstop, shake, damage,
   posture, parry windows, combo grace, KO slow-mo, vignette, damage numbers and immortal mode.
   The `_add_row()` helper is kept for the older hand-written tabs.
2. *M2 before M3* — AGREE, and M2 is done below. Ranked arena is still the right M3.
3. *Style lock* — AGREE on **Dark Seinen Ink**; nothing here changes the art. No new full-screen
   pass was added (impact flash is one `draw_rect`, combo/damage numbers are 2D text).
4. *Story pipeline* — still open. Recommend Notion → node JSON → `world_story.gd` loader + schema
   check in `verify.sh`. Not started; `story_flags` are still collected and discarded.
5. *RivalBrain* — PARTIAL. `ai_state` is still a string machine, but movement, animation and the
   death state are now sane (see below). The enum refactor is still worth doing before 4-rival
   content; don't do it in the same pass as a behaviour change.
6. *PvP* — DEFER matchmaking; the LAN module is now throttled to 30 Hz and uses real damage.

**What changed**
| Area | Change |
|---|---|
| Stakes (M2) | `player.take_damage()` / `revive()` / `is_defeated`; rival HP 0 → `DEAD` + **VICTORY** (no more instant full heal); player HP 0 → **DEFEAT**; result card with `[ RETRY DUEL ]` / `[ COMBAT FEEL ]`; `GestureCombat.reset_duel()` |
| Combat feel | damage-scaled hitstop, hitstop/shake tuning, floating damage numbers (crit variant), combo counter + grace bar, red hurt vignette, KO slow-motion, boss plays its baked `slash_*` animations, real damage from the rival |
| Tuning | `combat_data.gd`: `TUNING_SPEC` / `TUNING_BOOLS` / `TUNING_DEFAULTS` / `tuning_get()` / `tuning_bool()` / `reset_tuning()`; saved in JSON; Dev Studio **tab 8** auto-generates the UI |
| Menu | `[ MENU ]` rows 13 `COMBAT FEEL (TAB 8)`, 14 `SANDBOX IMMORTAL`, 15 `REMATCH DUEL`, 16 `RESUME` |
| Perf | enemy AI + projectiles moved to `_physics_process` (they were **2.75× faster at 165 Hz** than 60 Hz); HUD redraw throttled to 10 Hz with instant redraw during flashes; `apply_character_proportions()` no longer walks the GLB 12×/s; `_screen_max_hz()` cached; PvP sync 30 Hz; build-mode blocks capped at 120 |
| Engine errors | `PhysicalBoneSimulator3D` + 4 `PhysicalBone3D` per character **removed** (12 Jolt scale errors per swap, and they fought the procedural ragdoll) → one deterministic procedural ragdoll; GLB material overrides applied *before* `add_child` |
| Correctness | save/load order fixed (`apply_race_by_name` → `load_from_disk` → re-apply shader/proportions), so SAVE JSON really restores; `project.godot` gets `physics/common/physics_interpolation=true` for 60 Hz physics on 120–165 Hz panels |
| Gate | `verify.sh` now also asserts invariants (interpolation on, no `PhysicalBone3D.new(`, combat has `_physics_process`) and runs `combat_test.gd` as gate 6 |

**Verified (Godot 4.7 headless, this sandbox)**
`bash verify.sh` → `VERIFY_PASSED` twice in a row (idempotent): engine 4.7 assert, 8 core files,
29 signatures, invariants, asset import, 120-frame boot, touch smoke test, and **25 combat asserts**
in `combat_test.gd` (damage→combo→damage number, KO→VICTORY, retry resets, immortal survives 12
lethal hits and clamps at 1 HP, mortal lethal→DEFEAT, tuning survives save→profile switch→load,
`hitstop_scale` 0/1, 8 tabs, 17 menu rows all on screen).

**Not verified** — needs a device: how the hitstop/slow-mo/impact feel, real 120/144/165 Hz with
interpolation, the actual look of damage numbers/combo/vignette, the result card layout on a 20:9
phone, and two-device PvP. Nothing was visually inspected.

**Next, in order** — (1) push V3 and play it on the phone; (2) a per-device quality tier system
(see below); (3) `story_flags` + Notion→JSON story loading; (4) `RivalBrain` enum refactor; (5)
ranked arena shell (M3); (6) a real `data/*.tres` balance resource once the phone UI proves the
dictionary approach.

**Target devices (from the user, 2026-11-15)**
| Device | Hardware | Realistic ceiling for this content |
|---|---|---|
| iPad Pro M4 | M4, 120 Hz ProMotion | 120 fps at 1.0 render scale, shadows on |
| iQOO 12 | Snapdragon 8 Gen 3, 144 Hz panel | 120 fps at 1.0 scale, shadows on |
| Redmi Note 10 Pro | Snapdragon 732G / Adreno 618, 120 Hz panel | **not 120** — ~45-60 fps at 0.65-0.75 scale, shadows off. The panel is 120 Hz; the GPU is not. |
| Dell Precision 5550 | i7 + Quadro T2000 4 GB, 16 GB RAM | 60-90 fps at 1080p, 1.0 scale |

The user asks for "120 on every device". Do not promise it on the 732G. The honest design is a
4-tier quality profile chosen at boot and overridable in the menu:
`ULTRA` (iPad M4, 8 Gen 3): panel rate, `scaling_3d_scale 1.0`, shadows on, afterimages on.
`HIGH`: panel rate, 0.9 scale, shadows on.
`MID`: 60-90 fps, 0.8 scale, shadows off.
`LOW` (Adreno 618 class): 60 fps cap, 0.65-0.75 scale, shadows off, no afterimages, fog off.
Detect with `RenderingServer.get_video_adapter_name()` (`Apple M`, `Adreno 7xx/8xx`, `Adreno 6xx`)
plus `OS.get_name()`, and store the result in the same tuning dictionary so it appears in tab 8 and
saves. Physics stays 60 Hz on every tier; rendering interpolates.

**Delivery note** — this session had no git push credentials. V3 was delivered as
`V3-min.patch` + `apply_v3.sh` committed onto `Pinkypoopoo-patch-1`, and `apply_v3.sh` removes both
after committing. If you are reading this inside commit `V3`, the patch landed correctly.

---

### 2026-11-16 · Buffy (Freebuff) — V4: quality tiers, NPR face pipeline, story JSON, typed AI state

Branch `Pinkypoopoo-patch-1`. `main` untouched. Gate: **VERIFY_PASSED**, 7 gates, 45 signatures,
34 combat asserts (was 25), full asset import (not `SKIP_IMPORT`).

**1. Single-tap menu (task from the phone video).** Root cause was not the row loop: the row loop
already executed on the first tap. `_handle_p5_blade_tap()` never consumed the touch, so the same
tap was *also* delivered to the `Button` layer under the menu (`btn_menu`), which toggled the pause
menu shut again — every row therefore looked like it needed a second tap. Fix: `set_input_as_handled()`
is now called before any row logic; row hits select + execute immediately; only taps on the left
character-preview side (or row 04 CAMERA POSE) roll a pose; taps in the right-side gutter do nothing.
Verified by three headless asserts (one tap → one action, selection follows the tap, outside-row tap →
no action).

**2. 4-tier device quality (tab 8 + `[ MENU ]` rows 15/16).** `CombatData.QUALITY_TIERS` holds
LOW 0.65 / MID 0.85 / HIGH 0.92 / ULTRA 1.00 with msaa, shadow, fog, outline and debris caps
(8/16/28/28). `detect_quality_tier()` maps `RenderingServer.get_video_adapter_name()` + `OS.get_name()`:
iOS/`Apple M` → ULTRA, Adreno 7xx/8xx + Mali-G7/G9 + Xclipse + desktop RTX/RX → HIGH, other desktop
→ MID, Adreno 5xx/6xx + Mali-G5/G6 + PowerVR → LOW. `auto_quality` is a checkbox in tab 8; turning it
off (or tapping either menu row) keeps manual values, and auto never overwrites a saved `render_scale`.
`apply_quality_tier()` in `character_body_3d.gd` applies viewport `scaling_3d_scale`/`msaa_3d`, sun
shadows, `Environment.fog_enabled`, the outline `next_pass`, afterimage gating and the debris cap. It
re-runs on the next physics tick when `quality_tier` changes, so the tab-8 slider is a live preview.
Physics stays 60 Hz + interpolation on every tier.

**3. NPR face/vertex pipeline.** The cel shader now reads a packed vertex COLOR via two varyings
(`COLOR` is a vertex built-in — docs: fragment built-ins need a varying to reach `light()`, and
`return` is illegal inside `light()`, so the branches are if/else). R = shadow threshold bias,
G = outline weight, B = spec mask, A = 1 on unmasked anime-face skin, which switches `light()` to a
horizontally-shifted 64×64 SDF face ramp (procedural, `res://assets/sdf_face.png` overrides it) with
the head basis fed every frame. Outline extrusion now supports per-vertex weight + camera-distance
falloff. Characters no longer cast self-shadows, which stops cel-band flicker. `build_models.py`
gained `paint_vertex_channels()`, `proxy_smooth_normals()` (DATA_TRANSFER custom normals from a proxy
sphere) and an opt-in `ANIME_FACE_MODE = "plate"`. **Three new tab-8 knobs**: SDF Face Softness,
Vertex Shadow Bias, Outline Distance Falloff.
**IMPORTANT — the shipped GLBs were NOT re-exported** (no Blender in the sandbox). They carry no COLOR
layer yet, so `vertex_shadow_bias` defaults to 0.0 and the current look is bit-identical. Run
`blender --background --python build_models.py` once, then raise Vertex Shadow Bias to 1.0.
`face_sdf_*` only activates when `slot_head == "ANIME_FACE"`.

**4. Story graph externalised.** `res://data/story_nodes.json` (`schema_version: 1`) holds origins,
nodes, choices, `requires_flags`, `grants_unlocks`. `world_story.gd` lost its hardcoded dicts, gained
`load_story_data()`/`save_state()`/`load_state()`, and persists origin + node + flags + unlocks under
`"story"` in `user://dev_profile.json`. `CombatData.save_to_disk()` now reads the old file first and
merges, so the two writers cannot erase each other. Flag gating exists but every `requires_flags` is
empty, so no current path changed. New `story_test.gd` validates schema, origin targets, choice links
and slot names from gate 7. `export_presets.cfg` now has `include_filter="*.json"` on all three
presets so the file actually ships.

**5. `ai_state` string machine → `enum AIState`** (27 call sites). `AI_STATE_LABELS` + `ai_state_label()`
keep the HUD text identical; a legacy string in a save is still accepted. `match` now switches on
`int(s["ai_state"])`.

**6. `ios_ipa.yml`** downloads Godot **4.7-stable** (was 4.3, which could not open this project).

**Verified**: gate 7/7 green with real asset import; combat asserts 25→34; shader compiles in the dummy
renderer (the failure mode that would have shipped a magenta character was caught here); `python3 -m
py_compile build_models.py`; JSON parsed and schema-checked. **Not verified**: anything visual (no GPU,
no phone), the Blender path (never executed), and on-device tier selection (adapter strings on the real
Redmi/iQOO were never observed — `detect_quality_tier()` may need a fragment added).

**Still open**: (a) run `build_models.py` in Blender and inspect the vertex-colour look; (b) the ~40
`get()`/`call()` string bridges in `flame_p5_pvp.gd` were deliberately **not** rewritten to typed
access — `player_ref` would need a `PlayerController` static type, and with no on-device run a typo'd
member is a silent no-op today but a hard parse break then; do it behind a compile check; (c) P2PSYNC
throttling already existed (`P2P_SEND_HZ = 30`, accumulator) — verified, no change needed; (d) ranked
arena shell (M3).

### [2026-11-17] Buffy (Freebuff, 3rd agent) — V5: phone crash fixed, wall-run, water, celestial eye, impact slash

Branch `Pinkypoopoo-patch-1`, `main` untouched. Gate: **VERIFY_PASSED**, 58 signatures,
**58 combat asserts** (was 34).

**Task 0 — the phone crash (root cause confirmed in this codebase, not from the log alone).**
The V4 script is `load_from_disk()` ending in
`refresh_auto_quality(not (parsed["tuning"] as Dictionary).has("render_scale"))`. When
`user://dev_profile.json` predates the `tuning` key, that line throws
`Invalid access to property or key 'tuning' on a base object of type 'Dictionary'` and
`PlayerController._ready()` stops half-way — camera still inside the mesh. Fix: a single
`CombatData.ensure_tuning(src)` normaliser (defaults + only recognised keys + only numeric/bool
values) is now the first statement of `load_from_disk()`, `save_to_disk()` and
`refresh_auto_quality()`; `load_from_disk()` type-checks every section (`profiles`, `move_slots`,
`spell_slots`, `placed_blocks`, `tuning`, `*_tunables`) instead of trusting the file;
`quality_tier_index()` replaces every bare `int(tuning["quality_tier"])`.
**Proven, not assumed:** a negative control (buggy line restored) makes `combat_test.gd` print the
exact phone error and fail on `legacy profile reaches the end of load_from_disk()`. The test writes a
legacy `{"run_speed": 18.0, "player_tunables": {...}}` profile and asserts a player tunable — which
is applied at the *end* of the function — actually landed.
**Compiler warnings:** `var snapped` in `dash_vfx.gd` was the real `SHADOWED_VARIABLE` (it is not in
`combat_data.gd` in this revision; `world_story.gd` has no `_process_story_cinematics`). Renamed to
`snap_pos`. `verify.sh` now greps for shadowed built-ins and for a bare `int()`-to-enum assignment,
and the log scanner gained `Invalid access to property or key` / `Invalid get|set index` /
`Cannot convert argument`, i.e. the crash class itself. The gate also enforces this handoff file.

**Task 1 — parkour wall-run.** `wall_run_gate()` is a pure, unit-tested gate (wall + `|ny| < 0.35` +
sprint or >11 m/s + not busy + the tab-8 toggle). Physics keeps `up_direction = UP`: velocity is the
input slid along the wall, plus an inward push so the capsule keeps contact; pushing into the wall
climbs, running along it gets `wall_run_gravity_scale` (0.15) gravity. Only `VisualRoot.rotation.z`
(±9°) and the camera Dutch roll (±8°) tilt. Auto ledge-vault on losing the wall mid-climb
(`vy 11.5`, forward 14). Jump while wall-running = kick-off (`wall_kick_force`). **Pillars had no
collision at all** — `spawn_arena_block()` now adds a `StaticBody3D` per solid block, disabled when
the block shatters and restored by `reset_destructibles()`, so `is_on_wall()` can finally see them.

**Task 2 — anime water floor + celestial eye.** One 240×240 plane, 32×32 subdiv, unshaded 3-band
cel shader (`#050914`/`#10254C`/`#5CE6FF`), two uniforms (`player_pos`, `boss_pos`) feed two stepped
contact-ripple rings with no extra draw calls and no reflection pass. `water_floor_enabled` +
`water_wave_height` are tab-8 rows and are live (no tier change needed). `eye_shape = 4`
(CELESTIAL_CONSTELLATION) added: cyan-white radial iris, one concentric dark ring, six starlight
dots, with an `awaken` uniform that Flame Awakening multiplies by 2.4. `story_test.gd` now accepts
0..4.

**Task 3 — @NOBI_2D impact slash + cel smoke.** `GestureCombat.trigger_impact_slash()` records the
3D hit point, a jittered screen angle and a 0.16 s timer on crits, posture breaks, super parries and
KOs. `DevStudio._draw_impact_slash()` unprojects that point and draws: a 0.04 s binary flash, a
full-viewport diagonal bisect, an expanding singularity ring and a 4-point star — 2D canvas vectors
only. Cel smoke is a 14-quad preallocated pool with a hard-stepped violet/white shader
(`#6E5AE6`/`#F2F0FF`), emitted on dashes, wall-run entry/vault/kick-off and every cratering hit.

**Verified:** `bash verify.sh` → `VERIFY_PASSED` (engine 4.7, 58 signatures, invariants, hygiene,
import, 120-frame boot, touch smoke, 58 combat asserts, story schema). Negative control above.
**Not verified — needs the phone:** how the wall-run arc *feels* (contact retention on Jolt, the
vault timing), water/ripple look and cost on the 732G, the impact-slash framing on a 20:9 screen,
and cel-smoke density. Nothing visual was inspected; there is no GPU in this sandbox.

**Characters are still the Blender primitive proxies** (`models/hero.glb`, `models/boss_veil.glb`,
both built by `build_models.py`, the hero mesh is literally named `Cone`). No Blender here, so the
repaint is not done, and the style must come from the user's Pinterest board + T-pose orthos before
anything is rebuilt. Two structural gaps found while reading: the GLBs contain **no `Slot_*` nodes**,
so the Tab 6 modular-clothing switcher is a no-op today, and `_attach_hitbox_to_skeleton()` grabs an
`Arm_R` bone that exists but no `Veil_Back` bone does, so the spring-bone jiggle never runs.

### [2026-11-17] Buffy — V5 characters: Dark Seinen Ink, built without Blender

Style locked from the user's reference board (Google Drive `Game dev` folder, ~60 Pinterest
saves): monochrome ink, heavy hatching, one saturated accent, silhouette-first. The three
through-lines are a hooded/wide-hatted dark wanderer with a sword (Berserk-ish ink piece), a
one-accent duotone (the dragon piece: ink + periwinkle), and a silhouette against a saturated
sky (the red torii piece). That is the same **Dark Seinen Ink** lane ROADMAP.md recommended.

**Blender is not available in this sandbox** (the official Linux build needs `libXrender`,
`libXi`, `libXxf86vm`… and there is no root or apt index here). So the character pipeline was
rewritten as `tools/build_character.py`: stdlib-only, writes `models/hero.glb` and
`models/boss_veil.glb` directly (glTF JSON + binary chunk), ~100 KB each, 643 / 598 verts.
`python3 tools/build_character.py` is the whole build.

**What the models now have that they did not before**
- 21 joints: Root, Hips, Spine, Chest, Neck, Head, Arm/Elbow/Hand L+R, Hip/Knee/Foot L+R,
  **Veil_Back**, Veil_L, Veil_R. `Veil_Back` was missing entirely, so
  `_update_spring_bone_jiggle()` returned early every frame and the cloak never moved.
- Real `Slot_*` nodes: `Slot_HeadMask_HERO`, `Slot_VeilCloak_HERO`, `Slot_UpperGarb_HERO`,
  `Slot_LowerSkirt_HERO`, `Slot_Weapon_HERO` (+ `_VEIL` variants). The Tab 6 modular outfit
  switcher was a complete no-op because the old GLBs had no such nodes; it works now.
- Five baked clips per model: idle, slash_up, slash_down, slash_side, guard_sway.
- 4-channel NPR vertex colours per surface, `Slot_`-aware, with the weapon skinned to `Hand_R`
  so the blade follows the swing the animation actually plays.
- `_apply_seinen_shader_to_glb()` now gives each surface its own cel material
  (`CEL_ALBEDO` + `_cel_material_for`), because the shader takes albedo from a *uniform*, not
  from the GLB material — every surface used to render the same blue-grey. `_sync_cel_materials()`
  keeps those copies following the Tab-8 sliders and the quality tier.

**How it was checked without a GPU:** `tools/preview_character.py` is a numpy software
rasterizer that skins the GLB and writes a 3-view PNG contact sheet. The first pass rendered a
white lab-coat apron, white shins and a wizard cone, which is exactly the kind of thing a
headless gate cannot see — it was fixed by eye from those renders (dark coat edges, iron shins,
swept-back hood, shorter blade). `character_test.gd` is the permanent gate: it asserts both GLBs
expose the bones, `Slot_*` nodes and clips the engine asks for (gate `[3b/7]`).

**Verified:** `bash verify.sh` → `VERIFY_PASSED`, 61 signatures, character contract, import,
boot, smoke, 58 combat asserts, story schema. **Not verified:** any of it in the engine renderer
(no GPU) — the look in-game is unconfirmed, and the pose blending at 12 fps stepping is unseen.

**Source material is finally readable.** `sasti sparkling zero_261116153237.pdf` (the 472-page Gemini export in the Drive `Game dev` folder) extracts cleanly with pypdf in a venv — 2.25 M chars; `tools/read_source_docs.py` re-dumps it. What it actually specifies, and what this build is held to: `custom_races: Dictionary` in `dev_profile.json` with per-race `max_hp / max_mana / physical_strength / base_power / run_mult / dash_mult / flight_mult / feint_recovery_speed` (that is the Tab 8 tuning tab), the **Cursed Rags Swordsman** as the first fighter (hooded, rags, katana — the model now matches it), and hard mobile budgets: **under 80 draw calls**, one directional sun, no real-time omni/spot shadows, 256x256 palette textures, test at 60/90/120 Hz. It recommends VRoid Studio for the character, which needs a PC; that is the one recommendation this pipeline deliberately does not follow. `GodotEngine.epub` is 211 MB and still unread — it is the docs bundled as a zip of XHTML, so `tools/read_source_docs.py` will read it once downloaded, but godot-docs online covers the same ground.

**Left open:** `build_models.py` now exports to `art/` so a Blender run cannot clobber the
shipped GLBs; it is kept only as the reference for the vertex-colour packing. The two characters
are still primitive-assembled — good silhouette, simple forms. Next art step is either more
geometry per slot or a Blender pass at home against these proportions.

=== AI HANDOFF PACKET ===
REPO: Pinkypoopoo/sasti-sparkling-zero
BRANCH: Pinkypoopoo-patch-1 (HEAD for this entry: V5)
DONE: Task 0 crash + warnings (+ regression test proven by negative control), Task 1 wall-run,
Task 2 water floor + eye_shape 4, Task 3 impact slash + cel smoke. Gate 7/7, 58 asserts.
OPEN: character art (needs T-pose orthos + style board), `Slot_*` nodes missing from the GLBs,
`Veil_Back` bone missing so jiggle never runs, no on-device verification of any new visual.
NEXT: rebuild `build_models.py` output for one locked style with Slot_ nodes + Veil_Back, then
re-run `blender --background --python build_models.py` and raise Vertex Shadow Bias to 1.0.

---

## Archived from section 4 (V5 Task 1 entries, 26 Nov 2026)

### [2026-11-26] Buffy (Freebuff) — V5 Task 1: Intent-Gated Wall-Running, Wall Kick-Off, and Auto Ledge-Vault

Branch `Pinkypoopoo-patch-1`. `main` untouched (`0c80d97`). Gate: **VERIFY_PASSED** (8 tabs, 64 signatures, invariants, import, boot, smoke, combat loop, story schema).

- Verified `wall_run_enabled` tuning spec/defaults/bools in `combat_data.gd`, intent gating in `character_body_3d.gd` (`is_on_wall()`, `absf(wall_normal.y) < 0.35`, speed > 11.0 or sprint held, not busy), up_direction fixed to Vector3.UP with VisualRoot ±9° and camera ±8° roll, reduced gravity wall tangent movement, jump wall kick-off with re-attach cooldown, auto ledge-vault clearance checks, and clean cancellation on attack/hitstun/slowdown/loss of wall contact.
- Verified regression test in `combat_test.gd` (item 13).
- Ran `bash verify.sh` -> `VERIFY_PASSED` with 0 errors and 0 warnings.

=== AI HANDOFF PACKET ===
REPO: Pinkypoopoo/sasti-sparkling-zero
BRANCH: Pinkypoopoo-patch-1
DONE: V5 Task 1 Wall-Running, Wall Kick-Off, and Auto Ledge-Vault verified against all gates and combat tests.
OPEN: none for this task.
NEXT: continue V5 tasks or M3 ranked arena.
=== END AI HANDOFF PACKET ===



### 2026-11-16 · Buffy (Freebuff) — V5 Task 1 wall-run: audit + 3 fixes

Branch `Pinkypoopoo-patch-1`. `main` untouched (`0c80d97`).

Wall-running was already implemented in `4148982`, so this entry records an audit against the V5
Task 1 spec instead of a rebuild. **Gate: VERIFY_PASSED, 7 gates, 64 signatures, 67 combat asserts,
zero GDScript warnings.**

Already satisfied and re-verified (do not rebuild): `wall_run_enabled` in `TUNING_BOOLS` +
`TUNING_DEFAULTS` (default true); `wall_run_speed` / `wall_run_gravity_scale` / `wall_kick_force` in
`TUNING_SPEC` so tab 8 generates them with no UI code; the intent gate (`is_on_wall()`,
`absf(normal.y) < 0.35`, busy = hitstun/dash/windup/defeated); tangent movement with reduced gravity
plus a `WALL_RUN_STICK` inward push so contact survives; jump kick-off along the wall normal with a
0.35 s latch; smooth `±8°` camera roll (`camera.rotation.z` lerp) with `VisualRoot` `±9°`; clean
cancel on attack, hitstun, time-out and contact loss.

Closed gaps (this commit)
1. `up_direction = Vector3.UP` is now set explicitly in `_ready()` and enforced by a new gate 2b
   invariant: the capsule must never tilt, only `VisualRoot` and the camera roll.
2. Auto ledge-vault is clearance-gated: `_ledge_vault_clear()` raycasts forward at chest (1.1 m) and
   head (2.2 m) height and both must be open before `_vault_onto_ledge()` fires. The old version
   vaulted on raw contact loss, so it launched the player into overhangs and low arches.
3. The run cancels when the player drops all stick input and is not sprinting (intent release),
   completing the "slows down" cancel rule.

Deliberate deviation, with the measurement: the spec reads "holding Sprint/Dash *with* speed >
11.0". The gate is `sprint_held or h_speed > 11.0`, not `and`. Requiring both makes sprinting into a
wall unengageable, because `move_and_slide()` absorbs the normal component on contact and the
tangential speed at that instant is small (the sprint-into-wall test case is `h_speed = 4.0`). The OR
is what makes the primary input work. Asserted in `combat_test.gd` 13.

Verified: gate 7/7 with real GLB import and the character contract; 67 asserts (was 58) including
`wall_run_enabled` present-and-on in `TUNING_DEFAULTS`, the 11.0 gate, and a toggle round-trip; boot
warning scan empty; shader still compiles.
Not verified: no on-device run (no GPU or phone here) — the feel of the run, the vault arc height and
the ±8° roll are unjudged, and `_ledge_vault_clear()` only ever raycast into empty space headless.

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
Gate: **VERIFY_PASSED**, 7 gates, 79 signatures, 136 combat asserts, zero GDScript warnings
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

---

### 2026-11-26 · Buffy (Freebuff) — V6 Task 2A: curated 3-region arena layouts

Branch `Pinkypoopoo-patch-1`, based on `9c20947`. `main` untouched (`0c80d97`).
Gate: **VERIFY_PASSED**, 7 gates, 79 signatures, 147 combat asserts, zero GDScript warnings
(`--check-only` on `dash_vfx.gd` / `dev_studio.gd` / `combat_test.gd` silent, boot scan empty).

`dash_vfx.gd` — no new file; data + helpers only:
- `CURATED_REGION_LAYOUTS` maps 0 `INK_CATHEDRAL` (12 props: the 8 nave pillars + 4 ruined arches),
  1 `BLAME_MEGASTRUC` (7: 4 staggered monoliths, one raised to 4 m, an 8 m arch, 2 flora patches)
  and 2 `GOTHIC_ECLIPSE` (7: 3 arches, 2 pillars, 2 flora). Specs are `[kind, x, y, z, rot]` and go
  through `spawn_arena_block()`, so every curated piece is solid, destructible and palette-driven.
- `load_curated_region(idx) -> int`, `clear_curated_region()`, `curated_prop_count()`. Curated
  entries are flagged `curated` and tracked in `curated_region_props`, never in
  `custom_block_nodes`, so a region switch cannot eat a Tab 6 build and a saved build cannot eat
  the region.
- `clear_curated_region()` walks `destructible_pillars` backwards, detaches the root
  (`remove_child`) and `free()`s it — not `queue_free`, which would leave the outgoing region's
  Jolt bodies alive at exit. Tab 6 `spawn_arena_block()` still layers on any loaded region.
- `_setup_destructible_arena()` no longer carries the hardcoded 8-pillar loop; it calls
  `load_curated_region(0)`, so boot and the cycler build the arena through one path.

Bug found on the way (pre-existing, only reachable through curated flora): `spawn_arena_block()`
allocated the `StaticBody3D` + `CollisionShape3D` for every kind but parented them only when the
kind collides, so each `ANIME_FLORA_PATCH` leaked one body + shape at exit — exactly the
2 × `P10JoltBody3D` leaks the gate reported. Now freed when `has_collision` is false.

`dev_studio.gd` — `_cycle_region()` (also reached by the story tab's region jump) loads the curated
layout after the palette swap, then sets `water_floor_enabled = (region_idx == 2)` and calls the
existing `player._push_water()`. GOTHIC_ECLIPSE therefore floods, while the `quality_tier >= 1`
gate stays where it was: LOW is dry, MID/HIGH/ULTRA get the plane. No new `WorldEnvironment`, no new
mesh, no shortcut gate.

Verified (headless, `combat_test.gd` §20, 11 new asserts): the three layouts exist; cycling 0→1→2
twice spawns exactly each layout's prop count with live roots; each region swaps `stone_mat`;
returning to region 0 leaves the same non-queued child count (no orphan nodes); region 2 keeps water
hidden on LOW and shows it on MID; a Tab 6 monolith places on top, is never counted as curated, and
removing it leaves the sanctum intact; `clear_curated_region()` empties the set.
Not verified: no visual run — nave spacing, the raised monolith ledges, the obsidian sanctum read
and the flooded floor are unjudged (headless has no canvas or GPU).

=== AI HANDOFF PACKET ===
REPO: Pinkypoopoo/sasti-sparkling-zero
BRANCH: Pinkypoopoo-patch-1 (HEAD for this entry: V6 Task 2A)
DONE: curated 3-region arena layouts in dash_vfx (12/7/7 props, load/clear/count, curated tracked
apart from Tab 6), region-2 water through the existing tier-gated _push_water(), 11 new asserts,
flora StaticBody leak fixed.
OPEN: no on-device visual pass (layout spacing, sanctum read, flooded floor); Blender 5.2 exporter
still unrun. Task 2B (story_nodes.json / story_test.gd) untouched.
NEXT: Task 2B story regions.
=== END AI HANDOFF PACKET ===

---

### 2026-11-27 · Buffy (Freebuff) — V6 Task 2B: physical shortcut gates + flag-gated travel

Branch `Pinkypoopoo-patch-1`, based on `eeeb407`. `main` untouched (`0c80d97`).
Gate: **VERIFY_PASSED**, 7 gates, 79 signatures, 163 combat asserts, zero GDScript warnings
(`--check-only` on `dash_vfx.gd` / `character_body_3d.gd` / `dev_studio.gd` / `world_story.gd` /
`gesture_combat.gd` / `combat_test.gd` silent, 120-frame boot scan empty), zero RID/orphan leaks.

`combat_data.gd` — one line in `TUNING_BOOLS` + `TUNING_DEFAULTS`
(`unlock_all_shortcuts: false`). Tab 8 generated its checkbox with no UI code, which is the whole
point of the tuning layer.

`dash_vfx.gd` — gates ride the curated-region lifecycle, no new file:
- `SHORTCUT_GATE_LAYOUTS` specs `[target_region, flag, x, z, rot]`: hub 2 (-> 1 `shortcut_blame_unlocked`,
  -> 2 `shortcut_eclipse_unlocked`), megastruc 2 (return -> 0 with `""`, -> 2 eclipse), eclipse 1
  (return -> 0). Empty flag = permanent return gate.
- Each gate is a `Node3D` (`top_level`, like the curated props) with two posts, a lintel and an
  unshaded beacon slab. **No `StaticBody3D` and no `CollisionShape3D` at all**, so there is nothing
  for Jolt to leak and nothing that can trap the player; zero post-processing.
- `_spawn_shortcut_gates()` is called from `load_curated_region()`; `clear_shortcut_gates()` runs
  first inside `clear_curated_region()` with the same `remove_child()` + `free()` rule, because
  `queue_free` left RIDs alive at headless exit in 2A.
- `refresh_shortcut_gate_visuals(unlock_all, flags) -> int` recomputes `locked` and repaints only
  when the colour actually changes (dim crimson `(0.42,0.05,0.09)` sealed -> gold `(1,0.82,0.24)` open).

`world_story.gd` — still a pure loader; the graph stays in `data/story_nodes.json` (`schema_version: 1`,
untouched). Added `shortcut_flag_for_region()` (0 -> blame, 1 -> eclipse, 2 -> none), `has_flag()`
and `unlock_shortcut()`, which sets `story_flags` and persists through the existing merged
`"story_state"` writer. Nothing writes `"tuning"`, so neither block can erase the other.

`dev_studio.gd` — `_cycle_region()` is now `_apply_region((region_idx + 1) % 3)`; the new
`travel_to_region(idx)` goes through the same `_apply_region()`, so palette, curated props, gates and
the tier-gated water all change in one place (a gate can never land on a half-applied arena). The
story tab's boot-time region jump still reuses `_cycle_region()`. Banner + status are drawn in the
existing `_draw()`; `_process()` now also redraws while a banner is live.

`character_body_3d.gd` — `_tick_shortcut_gates(delta)` is called from `_physics_process` (60 Hz,
never `_process`): 3.2 m radius, 0.85 s dwell, 2.0 s arrival cooldown. WINDUP / DASH / HITSTUN /
GUARD / STEP or `is_defeated` cancel a dwell. A sealed gate refuses travel and reports
`"SEALED GATE — Defeat rival to unlock"` without touching input. An open gate accumulates dwell,
then `_travel_through_shortcut()` calls `travel_to_region()`, re-seats the player and every rival at
`(0, 1.6, 6)` (never on the gate edge), resets dwell, starts the cooldown and shows the region
banner (`INK CATHEDRAL` / `BLAME! MEGASTRUCTURE` / `GOTHIC ECLIPSE`).

`gesture_combat.gd` — `_kill_rival()` calls `player.unlock_shortcut_for_region(current_region_index())`
before the VICTORY state, so a KO in Region 0 grants `shortcut_blame_unlocked` and a KO in Region 1
grants `shortcut_eclipse_unlocked` (both persisted, both repaint the gates).

Verified (headless, `combat_test.gd` §21, 16 new asserts -> 163): the bool exists with a `false`
default and toggles; the three regions spawn 2/2/1 gates and no gate targets its own region; with
both flags absent 3 progression gates read sealed and the 2 return gates read open; repeated region
switches leave the same non-queued child count (0 orphan nodes); a sealed gate refuses travel and
never accumulates dwell; a real Region-0 KO grants blame only, the flag lands in `story_state` while
`tuning.enemy_damage = 91` survives in the same `user://dev_profile.json`, and the hub gate repaints
gold; 0.4 s of dwell does not travel, a further 0.5 s does (banner `BLAME! MEGASTRUCTURE`, cooldown
armed); `unlock_all_shortcuts = true` opens the eclipse gate with no story flag at all.
Not verified: no visual or on-device run — beacon read through fog, arch scale against the 14 m
pillars and the 214 px banner placement are unjudged, and the dummy renderer never runs `_draw()`,
so the banner and status text are proven as state, not pixels.

=== AI HANDOFF PACKET ===
REPO: Pinkypoopoo/sasti-sparkling-zero
BRANCH: Pinkypoopoo-patch-1 (HEAD for this entry: V6 Task 2B)
DONE: physical shortcut gates (2/2/1, body-less arch + unshaded lock beacon, spawned and freed with
the curated region), flag persistence via story_state, rival-KO unlock, 60 Hz dwell travel with
2 s arrival cooldown + region banner, unlock_all_shortcuts Tab 8 override, 16 new asserts.
OPEN: no on-device visual pass (beacon readability, gate scale, banner placement); Blender 5.2
exporter still unrun.
NEXT: playtest the gates on a phone, then continue V6.
=== END AI HANDOFF PACKET ===

---

### 2026-11-27 · Buffy (Freebuff) — V6 Task 3: 2-phase rival boss, regional telegraphs, stagger finishers

Branch `Pinkypoopoo-patch-1`, based on `45ef77d`. `main` untouched (`0c80d97`).
Gate: **VERIFY_PASSED**, 7 gates, 79 signatures, 185 combat asserts, zero GDScript warnings
(`--check-only` on `combat_data.gd` / `gesture_combat.gd` / `dev_studio.gd` /
`character_body_3d.gd` / `combat_test.gd` silent), zero RID/orphan leaks.

`combat_data.gd` — three lines, no UI code: `boss_phase2_enabled: true` in `TUNING_BOOLS` +
`TUNING_DEFAULTS`, and `boss_phase2_speed_mult: [1.0, 1.6, 0.02, "Boss Phase 2 Speed x"]` in
`TUNING_SPEC` with default `1.22`. Tab 8 generated the checkbox and slider itself.

`gesture_combat.gd` — one boss brain, three regional reads:
- `BOSS_PROFILES` — 0 `INK_DUELIST` (speed 1.0, telegraph 1.0, 3-hit combo, phase-2 THRUST),
  1 `BLAME_RUSHDOWN` (1.24 / 0.82, 3-hit, LUNGE), 2 `GOTHIC_SANCTUM` (0.86 / 1.3, 2-hit, SLAM).
  `apply_region_boss_profile()` is called from `DevStudio._apply_region()`, so palette, curated
  props, gates and the rival's cadence all change in one beat. It rewrites the rival name only
  when `story_override` is false, so a story-authored rival keeps its name, scale and slots.
- Phase 2: `apply_damage()` checks `hp <= 50% of max` once (`boss_phase == 1` and the bool on).
  `_awaken_phase_two()` fires `trigger_impact_slash` + the pooled `spawn_cel_smoke` (so the cue
  respects the active GPU tier cap), bumps `phase2_awakenings`, and `_boss_cadence()` applies
  `boss_phase2_speed_mult` to wind-up, recovery, pursuit speed and lunge together — never one half.
- Telegraphs: `_begin_telegraph()` stamps `PARRIABLE` with a **gold/white** sigil and body tint on
  regions 0/1, and every second wind-up in region 2 phase 2 becomes `UNBLOCKABLE` with a **crimson**
  sigil/tint. `_resolve_enemy_strike_on_player()` lets a raised guard negate `PARRIABLE`, but an
  `UNBLOCKABLE` slam breaks the guard (damage + `GUARD BROKEN — UNBLOCKABLE SLAM!`); a live Sonic
  Sway window (`player.sway_timer`), a parry window and a dash all still avoid it.
- Stagger finisher: posture break now goes through `_break_posture()` -> 2.0 s `STAGGERED`. A melee
  hit inside that window is a finisher: `2.0x` damage, impact slash + cel smoke + hitstop, the
  window is consumed, and a 1.1 s `stagger_immunity` chain-lock empties the posture bar so it
  cannot infinitely re-break.
- Mirrors `boss_phase`, `region_archetype` and `telegraph_kind` on the primary duelist each physics
  tick, with `current_boss_phase()` / `current_region_archetype()` / `current_telegraph_kind()` for
  HUD and tests. All three reset in `reset_duel()`, `spawn_story_rival()` and on region travel.

`dev_studio.gd` — one call in `_apply_region()` (`combat.apply_region_boss_profile(region_idx)`),
after the curated layout loads.

`character_body_3d.gd` — shortcut arrival now uses `SHORTCUT_RIVAL_SEPARATION = 7.0` m instead of a
hardcoded 6.0, so the pair never lands on the exact threshold.

Verified (headless, `combat_test.gd` §22, 22 new asserts -> 185): both tuning knobs exist with the
required defaults/range and update live; a hit crossing 50% HP awakens phase 2 exactly once and
further damage never re-fires it; retry returns to phase 1 and `boss_phase2_enabled = false` never
awakens; regions 0/1/2 assign INK_DUELIST / BLAME_RUSHDOWN / GOTHIC_SANCTUM and region 2 owns the
SLAM; shortcut travel leaves player and rival 7 m apart and resets phase + stagger; `UNBLOCKABLE`
breaks a raised guard while `PARRIABLE`, dash and a timed Sonic Sway all still avoid it; a posture
break opens exactly 2.0 s `STAGGERED`, the next strike lands >= 1.9x the baseline damage, exits
`STAGGERED`, empties posture and arms the chain-lock.
Not verified: no visual or on-device run — the gold-vs-crimson telegraph read, the phase-2 smoke
burst and the 2 s stagger weight are unjudged, and the headless dummy renderer never draws the
sigil rings.

=== AI HANDOFF PACKET ===
REPO: Pinkypoopoo/sasti-sparkling-zero
BRANCH: Pinkypoopoo-patch-1 (HEAD for this entry: V6 Task 3)
DONE: 2-phase rival boss at 50% HP with a pooled-VFX awakening cue and a TUNING_SPEC speed
multiplier; three regional boss profiles (INK duelist / BLAME rushdown / GOTHIC guardian) applied
with the curated arena; gold PARRIABLE vs crimson UNBLOCKABLE telegraphs, guard-fail on the slam;
2 s posture-break stagger with a 2x-damage finisher and a chain-lock; 7 m travel separation;
22 new asserts.
OPEN: no on-device visual pass (telegraph readability, awakening burst, stagger feel); Blender 5.2
exporter still unrun.
NEXT: playtest the fight on a phone, then continue V6.
=== END AI HANDOFF PACKET ===

---

### 2026-11-27 · Buffy (Freebuff) — V6 Task 4: Dark Seinen playable HUD + gate dwell readout
Branch `Pinkypoopoo-patch-1`, based on `f87ddc5`. `main` untouched (`0c80d97`).
Gate: **VERIFY_PASSED**, 7 gates, 79 signatures, 204 combat asserts, zero GDScript warnings
(`--check-only` on `combat_data.gd` / `character_body_3d.gd` / `gesture_combat.gd` /
`dev_studio.gd` / `combat_test.gd` silent), zero RID/orphan leaks.

`combat_data.gd` — one bool in `TUNING_BOOLS` + `TUNING_DEFAULTS` (`seinen_hud_enabled: true`).
Tab 8 builds the checkbox with no UI code, so the cinematic mode is a single tap on a phone.

Read-only hooks (no new gameplay state, nothing written from the HUD):
- `character_body_3d.shortcut_dwell_ratio()` = dwell / 0.85, clamped; `guard_ratio()` = the
  player's poise, read from the hitstun recovery window (1.0 steady, falling for 0.36 s after a hit).
  The player has no separate posture meter, so the HUD derives it instead of inventing one.
- `gesture_combat.primary_rival()`, `boss_display_name()`, `boss_hp_ratio()`,
  `boss_posture_ratio()`, `is_boss_staggered()`. `current_boss_phase()` and
  `current_telegraph_kind()` now read the primary rival's state directly (the physics-tick mirrors
  remain for anything else), and `_physics_process` picks its `primary_duelist` through the same
  `primary_rival()` helper, so the HUD and the AI can never disagree about who the boss is.

`dev_studio.gd` — pure data first, then one draw pass:
- `_seinen_hud_active()` is the single visibility rule: `seinen_hud_enabled`, no full-bleed Dev
  Studio panel, no P5 pause menu. `_sync_seinen_visibility()` (10 Hz, beside `_refresh_telemetry()`)
  hides the debug telemetry label while it is on, because that line was the only thing sitting
  under the player cluster.
- `get_hud_snapshot()` returns `visible` + `player` (hp ratio, guard ratio, combo) + `boss` (name,
  phase, archetype, hp ratio, posture ratio, telegraph kind, staggered, present) + `world` (region
  title from `SHORTCUT_REGION_BANNERS`, gate status, gate dwell ratio). No nodes, no engine reads
  the HUD would have to guess at.
- `_draw_seinen_hud()` draws slanted `draw_colored_polygon` ink bars (obsidian fill, bone-white
  border, crimson/gold accents, 9 px lean): top-left VITAL + GUARD + combo badge; top-centre
  region title, rival name, `[ ARCHETYPE ]` tag, boss HP (border/accent shifts crimson in phase 2),
  boss posture, a crimson `PHASE II — AWAKENED` badge, and a centred callout pill that reads
  `[ STAGGERED — STRIKE FOR FINISHER! ]` (gold) / `[ UNBLOCKABLE — DODGE! ]` (crimson) /
  `[ PARRIABLE ]` (bone-gold). The dwell bar sits at `vp.y - 136` with `TRAVELING...` above it.
- Layout safety: the boss cluster is clamped to `vp.x - 176` so it can never reach `[ MENU ]`, the
  player bar is `min(300, 24% width)` so the two top clusters cannot touch on a phone-width
  viewport, and every centred element reuses the same clamp. Zero new shaders, zero new nodes.
- No duplicated readouts: while the cinematic HUD is on, the old bottom-left HP/TOUKI strip and the
  old `N HIT` combo counter are skipped (they are exactly what the player cluster replaces). The
  world-anchored per-rival mini bars, damage numbers, hurt vignette, sealed-gate status and region
  banner still draw as before.

Verified (headless, `combat_test.gd` §23, 19 new asserts -> 204): the bool exists with a `true`
default; the snapshot reports player HP 0.5, a guard ratio strictly between 0 and 1 at 0.18 s of
hitstun, and the live combo count; boss HP 0.5 / posture 0.25 plus the `INK_DUELIST` archetype and
`KATANA…` name; a hit that crosses 50% HP reports `phase == 2`; `PARRIABLE` and `UNBLOCKABLE`
round-trip; a posture break reports `staggered` with an empty posture bar and `NONE` telegraph;
0.4 s in an unlocked gate reports `0 < gate_dwell_ratio < 1`, the `SHORTCUT OPEN…` status and the
`INK CATHEDRAL` title; and `visible` goes false for the bool off, the studio panel open and the P5
menu open, and true again once both are closed.
Not verified: no visual run — headless uses the dummy renderer, so `_draw()` never executes and the
ink-bar geometry, the gold-vs-crimson read, the bar/text fit at real font sizes and the on-phone
safe margins are all unjudged.

=== AI HANDOFF PACKET ===
REPO: Pinkypoopoo/sasti-sparkling-zero
BRANCH: Pinkypoopoo-patch-1 (HEAD for this entry: V6 Task 4)
DONE: `seinen_hud_enabled` Tab 8 bool; pure-data `get_hud_snapshot()`; slanted Dark Seinen ink HUD
(player VITAL/GUARD/combo, boss name/archetype/phase-2/HP/posture, stagger/unblockable/parriable
callout, gate dwell bar) on the 10 Hz throttle; read-only dwell/guard/boss hooks; legacy duplicated
readouts suppressed while it is on; 19 new asserts.
OPEN: no on-device visual pass (bar geometry, text fit, safe margins, contrast); Blender 5.2
exporter still unrun.
NEXT: look at the HUD on a phone and tune sizes, then continue V6.
=== END AI HANDOFF PACKET ===
