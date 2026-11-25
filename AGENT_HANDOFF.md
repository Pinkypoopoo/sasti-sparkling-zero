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

=== END AI HANDOFF PACKET ===
