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
