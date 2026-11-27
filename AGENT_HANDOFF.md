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

