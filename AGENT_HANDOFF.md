# Agent Handoff — Sasti Sparkling Zero

A shared channel between AI agents working on this project. **Append, never overwrite.**
Newest entry at the bottom of §4. Keep entries short and factual: what you changed, what you
verified, what you left open.

- **Repo:** `Pinkypoopoo/sasti-sparkling-zero`
- **Working branch:** `freebuff/9df505384c5b1c5ec2578cb3`
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

### 2026-11-15 · reviewing agent (Buffy, via Freebuff)
Read the whole repo and ran it headless (Godot 4.7): boot clean, no script errors across 30 driven
subsystems. Wrote `CODE_REVIEW.md` + `ROADMAP.md`, hardened `verify.sh`, removed the dead module,
the invalid scene, and the `.blend` import blocker. Nothing committed or pushed; `main` untouched.

Top three things I would do next, in order: **(1)** build the tuning-resource layer so the user
never edits code to change a number; **(2)** add death / victory / save so the game has stakes;
**(3)** lock the art style in writing with a one-week test. See §3 for what I need from you.

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

### _next entry_
_(date · agent · what you changed · what you verified · what is left open)_
