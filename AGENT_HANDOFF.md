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

### 2026-11-27 · Buffy (Freebuff) — V7 Task 2: decoupled PvP match state, KO rounds & rematch

Branch `Pinkypoopoo-patch-1`, based on `f849a36`. `main` untouched.
Gate: **VERIFY_PASSED**, 7 gates, 79 signatures, 275 combat asserts (+15 in §27), zero GDScript
warnings (`--check-only` on `flame_p5_pvp.gd` / `dev_studio.gd` silent), zero RID/orphan leaks.

`flame_p5_pvp.gd` — inner `class PvpMatchState extends RefCounted` owns the match:
`active`, `room_code`, `round_state` (`IDLE/ACTIVE/KO/REMATCH_READY`), `local_wins`, `remote_wins`,
`local_hp_ratio`, `remote_hp_ratio`, `remote_name`, `local_rematch_ready`, `remote_rematch_ready`,
with `reset_round()`, `reset_match()`, `record_ko(local_won)` and `to_hud_dict()`. The module keeps
zero player-controller type hints (Gate 2b still greps 0). `_on_link_established()` activates a
clean round, `disconnect_p2p()` resets the match.
- Packets: `P2PSYNC` keeps its 7 legacy fields and appends `hp_ratio:ko:rematch`. Every incoming
  field is still clamped (coords +-5000, HP to the rival's `max_hp`, ratio 0..1, flags by
  `>= 0.5`), so a truncated/hostile datagram can only fail to do something. The ratio is
  authoritative when present; raw HP stays as the legacy fallback.
- KO: `_process` reads both fighters' HP and `record_ko()` only fires from `ACTIVE`, so a burst of
  repeated packets cannot double-count a round. On receive, a sender at 0% HP scores the local win;
  a sender that signals KO while alive scores the remote win.
- Rematch: `request_rematch()` (local flag, sent on the next 30 Hz tick), `begin_next_round()`
  (solo/test helper) and the two-sided `_start_next_round()` which resets HP/duel state, clears both
  flags, restores `ACTIVE` and respawns the rival at 7.5 m. Port 7778, the 30 Hz throttle, the room
  code + password lock and the packet budget are unchanged.

`dev_studio.gd` — `get_hud_snapshot()["pvp"]` is the `PvpMatchState.to_hud_dict()` (inactive
defaults offline, so no key is missing). `_draw_seinen_hud()` swaps the top-centre cluster for a
**PvP Duel Bar** while `pvp.active`: `PVP DUEL — <opponent>`, a `ROOM <code>` badge, the remote HP
bar + percentage, the local HP bar, `LOCAL n — m REMOTE`, and a KO/rematch pill
(`ROUND OVER — TAP REMATCH`, then `WAITING FOR OPPONENT...`). The AI boss / story-rival cluster and
its telegraph pill are untouched when PvP is inactive. `[ REQUEST REMATCH ]` is a 44 px mobile
button added to the existing PvP lobby panel from `_attach_pvp_rematch_button()`
(`fp_mod.request_rematch()`) — there is no 9th tab; the 8 tabs and the P5 single-tap menu are
unchanged.

Test coverage is §27 (15 asserts): `match_state is RefCounted`; `flame_p5_pvp.gd` contains zero
`PlayerController` text; snapshot inactive offline and ACTIVE after a link; a sync packet moves the
opponent HP ratio (0.4) onto the rival and onto the HUD; an out-of-range ratio is clamped; room
code / password verdicts still IGNORE and DENY; a 0% opponent KO scores exactly one local win and
three repeated KO packets keep the tally at 1; `request_rematch()` waits alone; the peer's
`rematch_ready` packet starts the next round, restores local HP to max and puts the rival >= 7 m
away; `disconnect_p2p()` clears the snapshot.

Unverified: the PvP Duel Bar and rematch button pixels (headless never runs `_draw()`), and real
two-device UDP traffic (no network in the gate) - the receive path is driven in-process instead.

### 2026-11-28 · Buffy (Freebuff) — V8 Task 1B: Dark Seinen SFX retune, one rival, 2-tap BOSS RUSH

Branch `Pinkypoopoo-patch-1`, based on `07ae381` (the V7 Task 3 tip). There is **no V8 Task 1A
commit on this branch**, so 1B is built directly on that tip. `main` untouched.
Gate: **VERIFY_PASSED**, 7 gates, 79 signatures, 302 combat asserts (+27 in §30), zero GDScript
warnings (`--check-only` on `dash_vfx.gd` / `gesture_combat.gd` / `dev_studio.gd` /
`flame_p5_pvp.gd` / `combat_test.gd` silent), zero RID/orphan leaks.
`data/story_nodes.json` and `story_test.gd` untouched.

Audit first: `SYNTH_CUES` / `_bake_synth_cue()` / the single `AudioStreamGenerator` were already the
only SFX path (V6 Task 5), so this task retunes the table and adds no second pipeline. The duplicate
rival was **not** a spawn bug: `main.tscn` ships TWO `lock_on_targets` dummies, `_init_targets()`
registered both, and `apply_region_boss_profile()` stamped the same regional name on each — that is
why Region 1 showed two `MONOLITH STALKER`s. There was also no Boss Rush anywhere in the repo (the
V7 Task 3 commit deleted 290 lines of `combat_data.gd` and nothing else; `07ae381` restored them), so
1B had to provide the state its new row exposes.

`dash_vfx.gd` — same one player, one baker, zero new RIDs:
- All 14 cues retuned to steel / stone / sub-bass. `slash`, `hit`, `clash`, `parry`, `vanish`,
  `shatter` and `build` lost their sine sweeps: transients now use a 0.35-0.65 noise mix over the
  inharmonic partials 2.76 / 3.41 and decay in 0.06-0.16 s.
- New `SFX_PARRY` ("parry") cue, fired from `_trigger_super_parry()` — the one place a parry lands.
- `boss_awaken` 42 Hz, `stagger_finisher` 62 Hz and `gate_sealed` 55 Hz fundamentals under a dark
  metallic shimmer; `unblockable_warn` is a 196 / 233 / 392 Hz low-mid ring with no upward sweep;
  `gate_travel` is a 0.60 s 110 -> 132 Hz chime swell.

`gesture_combat.gd` — the single-active-rival invariant:
- `parked_rivals` + `enforce_single_active_rival()` (primary = lock target, else the first
  registered), `_park_rival()` (hidden, out of `target_stats`, out of `lock_on_targets`, collision
  0) and `set_multi_enemy_sandbox(enabled)`, the only path back, returning the live count.
- `_init_targets()` ends with the invariant and `apply_region_boss_profile()` applies it before it
  stamps a name, so boot, every region tram and every Boss Rush stage host exactly one rival.
- `clear_story_override()`: a gauntlet stage is the regional guardian, so Boss Rush drops the
  authored story name/scale lock that `_apply_region()` deliberately preserves.

`dev_studio.gd` — 2-tap BOSS RUSH:
- `BOSS_RUSH_STAGES = 3`, `boss_rush_active` / `boss_rush_stage` / `boss_rush_clears`,
  `boss_rush_value_text()` = `START 3-STAGE` or `ACTIVE X/3`, `start/abort/toggle_boss_rush()`, and
  `_tick_boss_rush()` on the existing 10 Hz telemetry tick: the graded KO ends a stage, stage N is
  region N, the third clear ends the run, a DEFEAT or a paused tree aborts it.
- `_p5_menu_action(18)` closes the menu and toggles the rush in the same tap; index 19 is now
  RESUME COMBAT. `_p5_value_text(18)` returns the value above.
- `_handle_p5_blade_tap()` now returns bool so a test can prove the consume-first path ran;
  `set_input_as_handled()` is still its first statement.
- Tab 5 gains the `Multi-Enemy Sandbox` checkbox — the explicit multi-enemy exception — wired to
  `set_multi_enemy_sandbox()`.

`flame_p5_pvp.gd` — `MENU_ITEMS` is 20 rows (`19 // BOSS RUSH`, `20 // RESUME COMBAT` last), still
with zero `PlayerController` text (Gate 2b greps 0).

Test coverage is §30 (27 asserts): every `SYNTH_CUES` entry bakes >= 256 frames with peak > 0.01 and
the parry cue bakes; `clash` is <= 0.16 s with every layer inside the 0.35-0.65 noise band and a
2.76/3.41 partial; `unblockable_warn` sweeps <= 25% of its start frequency; the three impact cues
start at <= 45/90/100 Hz and `gate_travel` at <= 132 Hz; the blade list has 20 rows with BOSS RUSH
above RESUME COMBAT and the last row still fits the viewport; one tap is consumed, closes the menu,
starts stage 1 in region 0 with one rival and reads `ACTIVE 1/3`; the graded KO rolls stage 1 into
region 1 as exactly one `MONOLITH STALKER`; stage 2 reaches region 2; the third clear ends the rush;
a second tap aborts and the row reads `START 3-STAGE`; regions 0 -> 1 -> 2 -> 0 keep one rival each,
the second dummy stays parked, and the sandbox toggle is the only way to 2 and back to 1.

Unverified: no audio was heard (headless runs `--audio-driver Dummy` and `_setup_synth_audio()` still
skips device setup), so the new timbres, the mix against the old cues and phone-speaker readability
are unjudged; the BOSS RUSH row and its value text were never drawn (headless `_draw()` never runs);
and no real two-device playtest of the duplicate-rival fix happened — the invariant is asserted
through `target_stats` / `parked_rivals` instead.

=== AI HANDOFF PACKET ===
REPO: Pinkypoopoo/sasti-sparkling-zero
BRANCH: Pinkypoopoo-patch-1 (HEAD for this entry: V8 Task 1B on 07ae381)
DONE: retuned the whole procedural synth bank to gritty steel/stone/sub-bass plus a new parry
transient; single-active-rival invariant (park/restore) across boot, region travel and Boss Rush;
3-stage BOSS RUSH with a 2-tap `19 // BOSS RUSH` blade row (`ACTIVE X/3` / `START 3-STAGE`) and a
Tab 5 multi-enemy sandbox escape hatch; 20-row menu; 27 new asserts.
OPEN: no listening pass on the retuned cues; no on-phone look at the 20-row menu; V8 Task 1A is not
on this branch (V7 Task 3 shipped no Boss Rush).
NEXT: listen on a phone and rebalance `sfx_volume`, then check the 20-row blade list on a narrow
phone.
=== END AI HANDOFF PACKET ===
### 2026-11-28 · Buffy (Freebuff) — V8 Task 1A: editor warning fix, Dark Seinen water, hollow ring

Branch `Pinkypoopoo-patch-1`, based on `170d2d0` (V8 Task 1B). `main` untouched.
Gate: **VERIFY_PASSED**, 7 gates, 79 signatures, 315 combat asserts (+13 in §31), zero GDScript
warnings (`--check-only` on `dash_vfx.gd` / `dev_studio.gd` / `character_body_3d.gd` /
`combat_test.gd` silent), zero RID/orphan leaks. `SYNTH_CUES`, `flame_p5_pvp.gd`,
`data/story_nodes.json` and `story_test.gd` untouched.

`AGENTS.md` — one new branch rule: cloud sandboxes never `git rebase`, `git pull --rebase` or detach
HEAD; integrate with `git merge --ff-only` (or `--no-rebase`) because siblings share the branch.

`SHADOWED_VARIABLE_BASE_CLASS` (the 4.7.2 editor errors):
- `dev_studio.gd`: `_ink_quad(pos, size, slant)`, `_draw_ink_bar(pos, size, ...)` and
  `_draw_ink_panel(pos, size, ...)` now take `box_size` / `bar_size` / `panel_size`. Those were the
  only three Control-property parameters in the file (grep is 0 now).
- `character_body_3d.gd`: `_build_sdf_face_texture()`'s `var size := 64` is `var tex_size := 64`
  (BaseMaterial3D owns `size`).
- `verify.sh` Gate 2b: `size` joined the local-var shadow list (it had been missing, which is why
  `var size` survived), and a new `PARAM_SHADOW` rule fails on any
  `^func ...[size|position|scale|rotation]...` parameter in `dev_studio.gd`. Negative control run:
  the pre-fix `_ink_quad` signature is caught by the new pattern.

`dash_vfx.gd` — water (still one plane, one unshaded shader, no `light()`, no post-processing):
- `water_mesh.position.y` 0.03 -> **0.14**, and the vertex stage clamps
  `VERTEX.y += max(h * wave_height, -0.10)` so troughs can never dip under the floor plane.
- 3-band cel palette retuned to the Dark Seinen set: trough `vec4(0.03, 0.04, 0.07, 1.0)`, mid
  `vec4(0.08, 0.13, 0.19, 1.0)`, crest `vec4(0.58, 0.66, 0.72, 1.0)` — cold ink instead of cyan.
- `contact_ring` tightened to foot-level: `step(0.84, band)`, reach **2.2** m player / **2.8** m boss
  (was 6.5 / 8.5), weights **0.55** / **0.40** (was 0.85 / 0.55).
- Region gating was already correct (`_apply_region` writes `water_floor_enabled = region_idx == 2`
  and `_push_water()` requires `tier >= 1`); §31 now proves 0/1 dry, 2 wet on MID, 2 dry on LOW.

`dash_vfx.gd` — telegraph ring:
- The solid `CylinderMesh` + `TRANSPARENCY_ALPHA_HASH` disc is a hollow `TorusMesh`
  (`inner_radius` 1.15, `outer_radius` 1.38, `rings` 24, `ring_segments` 8) on `TRANSPARENCY_ALPHA`
  with `depth_draw_mode = DEPTH_DRAW_DISABLED`, flattened by `SIGIL_FLATTEN` (`scale.y = 0.08`).
  The hash-stipple against the floor was the flicker.
- `spawn_step_sigil()` pins the ring at `y = maxf(pos.y, 0.18)` (`SIGIL_FLOOR_CLEARANCE`) and keeps
  the flattened Y scale, so it clears both the floor and the raised water sheet while it expands.

Test coverage is §31 (13 asserts): `water_mesh.position.y >= 0.10`; the shader carries the 2.2/2.8
reaches, `step(0.84, band)` and the `-0.10` trough clamp; the palette literals match the spec;
region 0 dry at boot, region 1 dry, region 2 wet on MID, back to region 0 dry, region 2 dry on LOW;
`sigil_rings[0].mesh is TorusMesh` with the 1.15 / 1.38 profile; a `spawn_step_sigil(Vector3.ZERO)`
ring sits at `y >= 0.15` with `scale.y == 0.08`.

Unverified: no visual run — headless uses the dummy renderer, which never compiles or draws a spatial
shader, so the palette, the contact rings, the water height and the ring flicker fix are all
unjudged in pixels, and the GLSL itself was not compiler-checked here (it only changes literals,
`max()`/`step()` arguments inside the already-shipping shader).

=== AI HANDOFF PACKET ===
REPO: Pinkypoopoo/sasti-sparkling-zero
BRANCH: Pinkypoopoo-patch-1 (HEAD for this entry: V8 Task 1A on 170d2d0)
DONE: AGENTS.md no-rebase rule; 4.7.2 shadow fixes (`box_size`/`bar_size`/`panel_size`, `tex_size`)
plus a `verify.sh` Gate 2b parameter rule and `size` in the local list; water raised to 0.14 with
clamped troughs, Dark Seinen 3-band palette and 2.2/2.8 m contact rings; hollow flattened torus
telegraph rings with a 0.18 m floor clearance; 13 new asserts.
OPEN: no on-device/mobile look at the water or the rings; the shader was never compiled by a real
renderer in this sandbox.
NEXT: open Gothic Eclipse on a phone and confirm the ring stops flickering and the water no longer
z-fights the floor.
=== END AI HANDOFF PACKET ===

### 2026-11-28 · Buffy (Freebuff) — V8 Task 2: full 3-stage gauntlet, mobile thermal auto-guard

Branch `Pinkypoopoo-patch-1`, based on `e307ef4` (V8 Task 1A). `main` untouched.
Gate: **VERIFY_PASSED**, 7 gates, 79 signatures, **358 combat asserts** (+43 in §32), zero GDScript
warnings (`--check-only` on `character_body_3d.gd` / `world_story.gd` / `dev_studio.gd` /
`combat_test.gd` silent), zero RID/orphan leaks. `data/story_nodes.json`, `story_test.gd`,
`flame_p5_pvp.gd` and `combat_data.gd` untouched.

Audit first: `thermal_guard_enabled` / `thermal_fps_floor` already existed in `TUNING_BOOLS` /
`TUNING_SPEC` / `TUNING_DEFAULTS` (V7 Task 3), so Tab 8 needed nothing. V8 Task 1B's
`start/abort/toggle_boss_rush()` + `_tick_boss_rush()` were extended in place, never duplicated.

`character_body_3d.gd` — step-down-only thermal guard:
- `tick_thermal_guard(dt, measured_fps)` returns true only on the tick that stepped. Skips when the
  checkbox is off (and clears the accumulator/status), the tree is paused, the sample is `<= 0.0`,
  or `quality_tier <= 0` (LOW is the floor).
- `thermal_low_accum` grows only under the floor; at or above `floor + 5.0` it is zeroed outright
  (hysteresis), and inside the 5 FPS band it only decays, so a device parked on the floor cannot
  ratchet itself down. `>= 4.0 s` plus `thermal_step_cooldown <= 0.0` writes the next tier into
  `data_store.tuning` (tier + its `render_scale`), calls the existing `apply_quality_tier()`, arms a
  `10.0 s` cooldown and raises `THERMAL GUARD: TIER -> <label>` for `3.5 s`. It never steps back up.
- Called from `_physics_process` (skipped while the P5 camera override is on) with
  `Engine.get_frames_per_second()`.
- `boss_rush_live()` probe plus a guard at the top of `_tick_shortcut_gates()`: while a gauntlet is
  live the dwell is zeroed and the status cleared before any gate lookup, so an edge gate cannot
  tram the run into another region.

`world_story.gd` — still a pure loader/writer:
- `boss_rush_mastery` + `record_boss_rush_result(rank, elapsed)` / `get_boss_rush_mastery()`. Same
  contracts as the region mastery: `best_rank` only moves up (S>A>B>C), `best_time` only takes a
  faster positive time, `clears` always increments.
- It is written as `"boss_rush"` **inside** `"story_state"`, through the same merged
  `user://dev_profile.json` writer, so `"tuning"`, `"region_mastery"` and
  `"story_rivals_defeated"` survive. `load_state()` round-trips it and
  `reset_progression_flags()` clears it.

`dev_studio.gd` — the gauntlet loop:
- New ledger (`elapsed`, `damage_taken`, `parries`, `finishers`, `heals`), `boss_rush_complete`,
  `boss_rush_rank`, `boss_rush_score`, `last_boss_rush_summary`. `start_boss_rush()` and
  `abort_boss_rush()` both reset it, so an abort never leaks a score into the next run.
- `_tick_boss_rush()` reads `compute_duel_rank()` **before** it touches the arena (the stage grade is
  still live), accumulates it, and on stages 0 -> 1 and 1 -> 2 runs `_apply_region()` ->
  `reset_duel()` -> `_heal_player_for_next_stage()` -> `_seat_boss_rush_stage()`.
- The heal is `min(max_hp, hp_at_clear + 35% max_hp)` and is deliberately stamped **after**
  `reset_duel()`, because that path revives to full the way a RETRY does: a gauntlet stage is not a
  retry, so it never pays a free full heal.
- `_seat_boss_rush_stage()` re-seats the next guardian exactly 7.0 m from the re-seated player and
  rewrites its `home_pos`, so a later RETRY reads the same gap. `enforce_single_active_rival()` still
  owns the count, so no duplicate rival and no new nodes.
- `_finish_boss_rush()` stores `compute_boss_rush_rank()` (`1000 + parries*90 + finishers*140 -
  12*elapsed - 1.2*damage`, clamped 0..1700, on the duel's own `DUEL_RANK_BANDS`), then persists it
  through `record_boss_rush_result()`; the victory card is left standing so the completion stamp can
  read it. A `DEFEAT` aborts the run without touching the region or the card.
- `get_hud_snapshot()` gains `"boss_rush"` (`active`, `stage`, `total_stages`, `complete`, `rank`,
  `score`, `best_rank`, `clears`, read live from world_story) and `"thermal_status"`.
- `_draw_seinen_hud()` adds a crimson `[ GAUNTLET X/3 ]` plate under the player cluster (it steps
  below the combo badge and the origin tag), a `GAUNTLET COMPLETE — RANK X` footer on the victory
  card (the card grows 22 px so it cannot overlap the duel grade or the RETRY overlay) and a
  bottom-centre thermal toast while `thermal_status` is non-empty. Same 10 Hz snapshot, no new nodes
  or shaders, no `size`/`position`/`scale`/`rotation` parameter shadows.
- Story/World tab gains `[ BOSS RUSH ]` / `[ ABORT RUSH ]` (44 px, beside `[ RESET PROGRESSION ]`)
  driving the same `toggle_boss_rush()` as the `19 // BOSS RUSH` blade row. Still 8 tabs, still 20
  P5 rows, `flame_p5_pvp.gd` untouched.

Test coverage is §32 (43 asserts): both Tab 8 knobs and their 45-110 / 5.0 spec range; a 3 s dip only
accrues; one window above floor + 5 FPS wipes the debt; 4 s sustained steps 2 -> 1 and raises the
toast (`get_hud_snapshot()["thermal_status"]` included); the 10 s cooldown blocks a second step
inside 5 s and the next one lands after it; 20 s more never goes below 0; a 0.0 FPS sample is a
no-op; the checkbox makes it inert. On the gauntlet: the progression reset clears the record; a live
rush freezes a 0.6 dwell to 0.0 and 20 gate ticks keep the region; stage 0 -> 1 and 1 -> 2 each roll
the region and pay exactly `hp + 35% max_hp` with the next guardian 7 m away and still one
registered rival; the third clear completes, grades S, and writes
`story_state.boss_rush = {best_rank S, clears 1}` beside the 91.0 tuning sentinel and the surviving
`region_mastery` / `story_rivals_defeated`; the pure ledger grades S / A / B / C at 0 / 250 / 400 /
600 damage; `get_hud_snapshot()["boss_rush"]` reports complete + rank + best + clears with the
victory card still up; a DEFEAT aborts without moving the region and an explicit abort keeps the
persisted record. The test leaves no flags, mastery or tuning behind.

Unverified: no pixels — headless never runs `_draw()`, so the GAUNTLET badge, the completion stamp
and the thermal toast were never looked at; no real device, so the 4 s / 10 s thermal timing and the
render-target resize cost of the tier step are unmeasured; and no real 3-stage playthrough — the loop
is driven by KOs in-process.

=== AI HANDOFF PACKET ===
REPO: Pinkypoopoo/sasti-sparkling-zero
BRANCH: Pinkypoopoo-patch-1 (HEAD for this entry: V8 Task 2 on e307ef4)
DONE: step-down-only thermal auto-guard (4 s hold, +5 FPS hysteresis, 10 s cooldown, tier-0 floor,
3.5 s toast) wired to the live physics tick and the Tab 8 knobs; gauntlet shortcut-gate suspension;
3-stage Boss Rush with a cumulative ledger, +35% inter-stage partial heal, 7 m re-seat, S/A/B/C
gauntlet grade persisted as `story_state.boss_rush` beside `tuning`; GAUNTLET badge, completion
stamp and thermal toast; Story-tab BOSS RUSH button; 43 new asserts.
OPEN: no visual run (badge/stamp/toast pixels), no on-device thermal or FPS measurement, no real
three-stage playtest.
NEXT: play a full gauntlet on a phone and check the badge never collides with the boss cluster, then
watch whether the 4 s hold fires on a thermally throttled Adreno 618.
=== END AI HANDOFF PACKET ===


### 2026-11-28 · Buffy (Freebuff) — V8 Task 3: Perfect Dodge (SHADOW STEP), Strike-Recovery Dash Cancel & Arena Bounds Safety

Branch `Pinkypoopoo-patch-1`, based on `39b2dcc` (V8 Task 2). `main` untouched.
Gate: **VERIFY_PASSED**, 7 gates, 79 signatures, **390 combat asserts** (+32 in §33), zero GDScript
warnings (`--check-only` on `combat_data.gd` / `character_body_3d.gd` / `gesture_combat.gd` /
`dev_studio.gd` / `combat_test.gd` silent), zero RID/orphan leaks. `data/story_nodes.json`,
`story_test.gd` and `flame_p5_pvp.gd` untouched.

Audit first: `perfect_dodge_enabled` is a new Tab 8 knob (auto-generated, default true) in
`combat_data.gd` `TUNING_BOOLS` / `TUNING_DEFAULTS`; the arena-bounds and dash-cancel surface lives
in `character_body_3d.gd`; the SHADOW STEP logic, `duel_perfect_dodges` / `perfect_dodge_banner_timer`
tracking and rival bounds live in `gesture_combat.gd`; the Seinen HUD callout pill lives in
`dev_studio.gd`. Nothing in `flame_p5_pvp.gd` or `combat_data.gd` beyond the one new bool.

`combat_data.gd` — one auto-generated Tab 8 knob:
- `perfect_dodge_enabled` (bool, default true) added to `TUNING_BOOLS` and `TUNING_DEFAULTS`. No UI
  code: Tab 8 reflects over the dicts and the slider appears, saves to disk and loads again.

`character_body_3d.gd` — arena bounds + dash-cancel hygiene:
- `const ARENA_MAX_RADIUS: float = 46.0` plus `clamp_arena_bounds() -> bool`, called from live
  `_physics_process` (after the thermal guard, before shortcut gates). When horizontal distance exceeds
  46.0 m it clamps XZ back onto the perimeter and strips outward radial velocity; when `y < -4.0` it
  rescues the player to `(clampf(x, -20, 20), 1.6, clampf(z, -20, 20))` with `velocity = ZERO` so
  knockbacks never soft-lock a duel or Boss Rush. Returns true when a correction fired.
- `trigger_dash(...)` now cancels active player windup/swing recovery (`state == MoveState.WINDUP` or
  `swing_anim_timer > 0.0`) so dash-canceling mid-combo feels instant and responsive, without bypassing
  `MoveState.HITSTUN` or defeat locks. `swing_anim_timer` is zeroed as part of the cancel.

`gesture_combat.gd` — SHADOW STEP + rival arena bounds:
- `duel_perfect_dodges: int = 0` and `perfect_dodge_banner_timer: float = 0.0` added, both reset to
  0 / 0.0 inside `_reset_duel_metrics()`, with the banner timer ticking down cleanly.
- Inside `_resolve_enemy_strike_on_player(td, s)`, when the player avoids an incoming strike via
  `player.state == MoveState.DASH` (both `PARRIABLE` and `UNBLOCKABLE` slams):
  - If `tune_bool("perfect_dodge_enabled", true)` is true, fire a **SHADOW STEP** Perfect Dodge:
    increment `duel_perfect_dodges`, set `perfect_dodge_banner_timer = 1.0`, restore +18.0 mana
    (clamped to `player.max_mana`), deal +25.0 posture damage to `s` (triggering `_break_posture()` if
    `s["posture"] >= s["max_posture"]`), apply a crisp hitstop/camera kick
    (`player.trigger_hitstop(0.045, 0.45)`), trigger `dash_vfx.play_sfx("vanish")` +
    `spawn_cel_smoke(...)`, and set `last_combat_action = "SHADOW STEP!!"` (or
    `"SHADOW STEP — SLAM EVADED!"` on `UNBLOCKABLE`).
  - When `perfect_dodge_enabled == false`, keep the existing plain `"DASH EVADE!"` / `"DASH EVADE — SLAM WHIFFED!"`
    path with zero bonus mana, posture damage, or counter increment.
- `compute_duel_rank()` is additive: each perfect dodge adds +60 score (when `duel_perfect_dodges == 0`,
  the score and rank formula is 100% identical to the pre-task formula, so §25 assertions remain exact).
  `"perfect_dodges": duel_perfect_dodges` included in `compute_duel_rank()` and `last_victory_summary`.
- `clamp_rival_bounds(td: Node3D, s: Dictionary) -> bool` added and run inside `_physics_process` for
  every active rival, so launched/knocked-back bosses never exit `ARENA_MAX_RADIUS` (46.0 m) or fall
  below `y = -4.0`.

`dev_studio.gd` — Seinen HUD snapshot & SHADOW STEP callout pill:
- `get_hud_snapshot()["player"]` extended additively with `"perfect_dodges": int` and
  `"evade_callout": String` (`"SHADOW STEP!!"` while `perfect_dodge_banner_timer > 0.0`, else `""`).
- `_draw_seinen_hud()` (same 10 Hz throttle, instant redraw while `perfect_dodge_banner_timer > 0.0`,
  zero new shaders/nodes, zero `size`/`position`/`scale`/`rotation` parameter shadows): renders a
  compact bone-gold ink pill (`[ SHADOW STEP ]`) near the player cluster whenever `player.evade_callout`
  is non-empty.
- `_process` redraws while `perfect_dodge_banner_timer > 0.0` so the callout appears and fades crisply.

Test coverage is §33 (32 asserts): `perfect_dodge_enabled` exists in `TUNING_BOOLS` + `TUNING_DEFAULTS`
(default true); dashing through both a `PARRIABLE` strike and an `UNBLOCKABLE` slam fires SHADOW STEP,
restores mana, adds rival posture damage, increments `duel_perfect_dodges`, raises
`compute_duel_rank()["score"]`, exposes `"perfect_dodges"` + `"evade_callout"` in
`get_hud_snapshot()["player"]`, and is suppressed when `perfect_dodge_enabled == false`;
`compute_duel_rank()` with 2 perfect dodges scores 1120 (1000 + 2×60) and still lands S, while 0
perfect dodges scores 1000 — identical to the pre-task formula; `player.clamp_arena_bounds()` and
`combat.clamp_rival_bounds(...)` clamp XZ positions beyond 46.0 m (XZ distance, not 3D distance) and
rescue fall-throughs (`y = -10.0`) back to safe arena height (`y >= 1.0`); `trigger_dash()` cancels
active `MoveState.WINDUP` cleanly and zeroes `swing_anim_timer`; `reset_duel()` resets
`duel_perfect_dodges` to 0 and `perfect_dodge_banner_timer` to 0.0.

Unverified: no pixels — headless never runs `_draw()`, so the `[ SHADOW STEP ]` callout pill was never
looked at; the real feel of dash-cancelling mid-combo on a phone and a real three-stage playthrough with
perfect dodges were never verified.

=== AI HANDOFF PACKET ===
REPO: Pinkypoopoo/sasti-sparkling-zero
BRANCH: Pinkypoopoo-patch-1 (HEAD for this entry: V8 Task 3 on 39b2dcc)
DONE: auto-generated Tab 8 `perfect_dodge_enabled` knob (default on); SHADOW STEP perfect dodge through
both PARRIABLE and UNBLOCKABLE strikes (+18 mana, +25 rival posture, hitstop, vanish SFX + cel smoke,
last_combat_action set, duel_perfect_dodges incremented); suppressed when the knob is off; additive
+60/perfect dodge in compute_duel_rank() with the 0-dodge formula unchanged; Seinen HUD
`[ SHADOW STEP ]` bone-gold callout pill + snapshot `perfect_dodges`/`evade_callout`; arena-bounds
clamp for the player (`clamp_arena_bounds()`, 46 m perimeter + fall-through rescue to 1.6 m) and for
every active rival (`clamp_rival_bounds()`, 46 m perimeter + fall-through rescue to 1.0 m); dash-cancel
of active WINDUP/swing recovery in `trigger_dash()`; 32 new asserts.
OPEN: no visual run (callout pill pixels); no on-device dash-cancel feel; no real playthrough with
perfect dodges.
NEXT: play a duel on a phone and confirm the SHADOW STEP pill reads and fades, then try dash-cancelling
a windup mid-combo.
=== END AI HANDOFF PACKET ===
