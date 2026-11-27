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

### 2026-11-27 · Buffy (Freebuff) — V6 Task 5: procedural Seinen synth cues + V6 feedback polish

Branch `Pinkypoopoo-patch-1`, based on `9212dae`. `main` untouched (`0c80d97`).
Gate: **VERIFY_PASSED**, 7 gates, 79 signatures, 223 combat asserts, zero GDScript warnings
(`--check-only` on `combat_data.gd` / `dash_vfx.gd` / `character_body_3d.gd` /
`gesture_combat.gd` / `combat_test.gd` silent), zero RID/orphan leaks.

Audit first: `dash_vfx.gd` already had one `AudioStreamPlayer` + `AudioStreamGenerator`, a
`play_sfx(kind)` `match` of 6 hardcoded frequency pairs, and `_pump_synth_audio(delta)` writing
samples on the render tick. **No** SFX tuning knobs existed in `combat_data.gd`, and
`_setup_synth_audio()` returns early on headless, so `play_sfx` was a no-op with no way to test it.

`combat_data.gd` — the two missing knobs, no UI code: `sfx_enabled: true` in `TUNING_BOOLS` +
`TUNING_DEFAULTS`, and `sfx_volume: [0.0, 1.0, 0.05, "SFX Volume"]` with default `0.75`.

`dash_vfx.gd` — one pipeline, not a second one:
- `SYNTH_CUES` replaces the inline `match`: cue -> `[duration_s, [[start_hz, end_hz, gain,
  noise_mix, partial], ...]]`, so the 6 legacy cues and the 7 new V6 cues (`boss_awaken`,
  `unblockable_warn`, `stagger_break`, `stagger_finisher`, `gate_travel`, `gate_sealed`,
  `wall_kick`) share one table and one oscillator. Constants `SFX_BOSS_AWAKEN` … `SFX_WALL_KICK`
  are the clean identifiers call sites use.
- `_bake_synth_cue()` renders each cue once into a seeded `PackedVector2Array` (22.05 kHz, 2 ms
  attack, exponential decay, integrated frequency sweep so a sweep never clicks). The bank is
  baked at `_ready` (~3.2 s / ~560 KB) instead of hitching the frame a boss awakens on;
  `_synth_frames_for()` still lazily bakes anything missing.
- `_pump_synth_audio()` keeps running on the render tick — the documented invariant — but now
  pushes the pre-baked frames through `push_buffer()` instead of synthesising per sample. Still
  exactly one `AudioStreamPlayer`, so no new RID to leak.
- `play_sfx()` records `last_sfx_cue`, `sfx_play_count` and an 8-deep `sfx_history` (so a test can
  see two cues fired by one action), returns before all of that when `sfx_enabled == false`, and
  sets volume through `synth_volume_db()` = `linear_to_db(max(0.001, volume))`. It records the cue
  even with no audio device, which is what makes the headless assertions meaningful.
- `set_sfx_tuning(enabled, linear_volume)` is pushed from the player, because `dash_vfx` has no
  `player`/`data_store` reference and reaching back would add a node lookup per shot.

`character_body_3d.gd` — `_push_fx_budget()` now also pushes the SFX state. `GATE_SEALED` fires
inside `_tick_shortcut_gates()` (called from `_physics_process`) behind
`SHORTCUT_SEALED_SFX_CD = 1.2 s`, decremented on the same tick, so standing on a sealed gate
thuds once and then stays silent. `GATE_TRAVEL` fires in `_travel_through_shortcut()`. The
wall-run jump kick-off and `_vault_onto_ledge()` now use `WALL_KICK` in place of the old
`clash`/`vanish` cues.

`gesture_combat.gd` — `_awaken_phase_two()` fires `BOSS_AWAKEN` and adds camera trauma with
`trigger_hitstop(0.0, 0.9)`: zero duration means no hitstop, so the boss is never frozen
mid-transition. `_begin_telegraph()` fires `UNBLOCKABLE_WARN` only for the crimson slam (a
`PARRIABLE` wind-up stays silent). `_break_posture()` fires `STAGGER_BREAK`. `_stagger_finisher_fx()`
fires `STAGGER_FINISHER` and raises the kick from shake `0.8` to `1.0` alongside its existing
`0.075 s` hitstop, slash, smoke and sigil.

Verified (headless, `combat_test.gd` §24, 19 new asserts -> 223): `sfx_enabled` / `sfx_volume`
exist with the required defaults and range and reach the host through `_push_fx_budget()`; all 7
V6 cues bake non-silent buffers with a device-less run (frame count >= 256, peak > 0.01); a cue
records name/count/history, `sfx_enabled = false` leaves count, last cue and history untouched, and
`sfx_volume = 0.5` maps to `linear_to_db(0.5)`; crossing 50% HP fires `BOSS_AWAKEN`; a direct
`_awaken_phase_two()` raises `cam_shake_trauma` while leaving `hitstop_timer` at 0; an
`UNBLOCKABLE` wind-up fires `UNBLOCKABLE_WARN` and a `PARRIABLE` one stays silent; a posture break
fires `STAGGER_BREAK`; the finisher fires `STAGGER_FINISHER` with hitstop and trauma; a sealed gate
fires `GATE_SEALED` exactly once, six further 1/60 s ticks add nothing, and 1.3 s later it thuds
again; open travel fires `GATE_TRAVEL`; wall kick-off and the auto ledge-vault both fire `WALL_KICK`.
Not verified: no audio was heard — headless runs `--audio-driver Dummy` and `_setup_synth_audio()`
still skips device setup there, so buffer validity, cue selection and count/cooldown throttling are
proven, but the actual timbre, loudness balance against the existing cues and phone-speaker
readability are unjudged.

=== AI HANDOFF PACKET ===
REPO: Pinkypoopoo/sasti-sparkling-zero
BRANCH: Pinkypoopoo-patch-1 (HEAD for this entry: V6 Task 5)
DONE: Tab 8 `sfx_enabled` + `sfx_volume`; 7 new V6 synth cues (boss awaken gong, unblockable
twin-tone sting, stagger crack, finisher sub-impact, gate travel chime, gate sealed thud, wall kick)
baked once into the existing generator pipeline; cue name/count/history for headless verification;
1.2 s sealed-gate audio throttle; camera trauma on awakening and a heavier finisher kick; 19 new
asserts.
OPEN: no on-device listening pass (timbre, mix balance, phone speaker); Blender 5.2 exporter still
unrun.
NEXT: listen on a phone and balance `sfx_volume`, then continue V6.
=== END AI HANDOFF PACKET ===

### 2026-11-27 · Buffy (Freebuff) — V6 Task 6: regional mastery loop, S/A/B/C duel grading, eclipse finale

Branch `Pinkypoopoo-patch-1`, based on `754ae4b`. `main` untouched.
Gate: **VERIFY_PASSED**, 7 gates, 79 signatures, 245 combat asserts (+22 in §25), zero GDScript
warnings (`--check-only` on `world_story.gd` / `gesture_combat.gd` / `dev_studio.gd` silent).

`gesture_combat.gd` — 60 Hz duel metrics + deterministic grading, no new file:
- `duel_elapsed` / `duel_damage_taken` / `duel_parries_landed` / `duel_stagger_finishers` +
  `last_victory_summary`. `_tick_duel_metrics()` runs at the top of `_physics_process` and only
  accumulates while a duel is live: no `result_state`, no `player.is_defeated`, no
  `hitstop_timer`, rival not `AIState.DEAD`. `_reset_duel_metrics()` fires from `reset_duel()`,
  `spawn_story_rival()` and `apply_region_boss_profile()` (region travel).
- Damage comes from the `take_damage()` delta (`hp_before - player.hp`), not the tuning number, so
  immortal/overkill hits cannot inflate it. Parries count on: the Z-Vanish counter, the super
  parry, and both Sonic Sway evasion paths (unblockable sway + guarded sway).
- `compute_duel_rank()` is pure: `1000 + parries*90 + finishers*140 - round(elapsed*20) -
  round(taken*2)`, clamped 0..1600, bands `S>=900 / A>=650 / B>=400 / else C`. Verified: 9 s, 0 dmg,
  2 parries, 1 finisher = 1140 → S; 35 s, 800 dmg = 0 → C.
- `_kill_rival()` now grades, caches `last_victory_summary` (`region`, `region_title`, `rank`,
  `score`, `elapsed`, `damage_taken`, `parries`, `finishers`, `unlock_note`, `best_rank`,
  `clears`) and calls `world_story.record_region_victory()` before `result_state = "VICTORY"`, so
  the RETRY card and the rank stamp read one cached snapshot.

`world_story.gd` — still a pure loader:
- `ECLIPSE_SANCTUM_FLAG`, `REGION_CLEAR_FLAGS` (`[blame, eclipse, eclipse_sanctum_cleared]`),
  `REGION_CLEAR_NOTES`, `RANK_VALUE` (`S`=4 … `C`=1).
- `shortcut_flag_for_region(2)` now returns `"eclipse_sanctum_cleared"` (it returned `""`), so the
  existing `player.unlock_shortcut_for_region(2)` grants the finale flag through one path instead
  of a second KO hook.
- `record_region_victory(idx, rank, elapsed)` sets the clear flag and writes
  `region_mastery[str(idx)] = {best_rank, best_time, clears, last_rank}`: rank only moves up
  (`S>A>B>C`), `best_time` only takes a faster positive time, `clears` always increments. Saves
  through the merged `story_state` writer, so `"tuning"` is never dropped.
- `get_region_mastery()`, `is_vertical_slice_cleared()` (all 3 flags), `region_clear_note()`,
  `reset_progression_flags()` (erases the 3 flags + `region_mastery`, then merged-saves).
  `region_mastery` round-trips through `save_state()` / `load_state()`.

`dev_studio.gd`:
- `get_hud_snapshot()["victory"]` = `active, region_title, rank, score, elapsed, damage_taken,
  parries, finishers, unlock_note, best_rank, vertical_slice_cleared` (defaults present before any
  KO). `active` needs `result_state == "VICTORY"` *and* a non-empty summary, so the card cannot
  outlive `reset_duel()`.
- `_draw_seinen_hud()` draws the Dark Seinen Victory Rank Card after the dwell bar: ink panel,
  92 px rank stamp (gold S / bone A / crimson B-C), region + CLEARED, time/parries/finishers,
  damage/score, `BEST <rank>`, the unlock line, and `VERTICAL SLICE CLEARED`. It is placed above the
  existing centred RETRY overlay, and flips below it when the viewport is too short (`card_y < 150`),
  so the two victory cards never overlap at 720p or 1080p. Same 10 Hz snapshot, no new nodes,
  shaders or allocations, still hidden while the Dev Panel / P5 menu is open.
- Story/World tab: chunky `[ RESET PROGRESSION ]` button (+ one-line note) at the top of the tab,
  wired to `_reset_progression()` → `reset_progression_flags()`,
  `player._refresh_shortcut_visuals()`, toast, `_refresh_story_ui()`.

Test coverage is §25 of `combat_test.gd` (22 asserts): metrics tick/freeze/record/reset, S and C
grading with the reported dictionary, region-2 flag + summary + `region_mastery` on disk beside
`tuning` (91.0 sentinel), HUD snapshot contents, S never downgraded on a 40 s / 900 dmg repeat,
`is_vertical_slice_cleared()` after all three clears, reset relocking both hub gates, and reset
keeping the 91.0 tuning value. The test leaves no flags, mastery or tuning behind.

Unverified: the card's pixels (headless `_draw()` never runs) and the reset button's touch size on a
real device; both read only from the snapshot verified above.

### 2026-11-27 · Buffy (Freebuff) — V7 Task 1: story-to-progression bridge (origins, story rivals, mastery)

Branch `Pinkypoopoo-patch-1`, based on `3625526`. `main` untouched.
Gate: **VERIFY_PASSED**, 7 gates, 79 signatures, 260 combat asserts (+15 in §26), zero GDScript
warnings (`--check-only` on `world_story.gd` / `gesture_combat.gd` / `dev_studio.gd` silent).
`data/story_nodes.json` untouched.

Audit first: V6 Task 6 already had `_reset_duel_metrics()` in `spawn_story_rival()`, the
`boss_phase = 1` / stagger / telegraph reset, and a 7.5 m spawn offset, so V7 added no duplicate
spawn code — only the missing read surface and the origin/story bridge.

`world_story.gd` — still a pure loader (no narrative in GDScript):
- `active_origin_title()` reads `origins[active_origin_id]["title"]` from the JSON; falls back to the
  stored id (and to `""` when nothing is selected) instead of inventing a label.
- `record_region_victory(region_idx, rank, elapsed, origin_id = "", is_story_rival = false,
  rival_name = "")` — the three original arguments still work, so the existing callers are
  untouched. It now also stores `"best_origin"` (stamped when the rank improves or on the first
  clear) and `"cleared_origins"` (deduplicated ids) inside `region_mastery[str(idx)]`.
- Authored story-choice KOs append the node's `rival_name` to the new deduplicated
  `story_rivals_defeated` array in `story_state` (`_note_story_rival()`,
  `story_rivals_defeated_count()`). Both new keys round-trip through `save_state()` / `load_state()`.
- `reset_progression_flags()` also clears `story_rivals_defeated`; every write still goes through the
  merged `"story_state"` writer, so `"tuning"` and the active origin selection are preserved.

`gesture_combat.gd`:
- `is_story_rival_duel()` reads `story_override` off `primary_rival()` (false when there is no rival).
- `_kill_rival()` now pulls `active_origin_id` + `active_origin_title()` from the story manager, passes
  them plus `story_override` and the KO'd `boss_name` into `record_region_victory(...)`, and caches
  `origin_id`, `origin_title`, `story_rival`, `best_origin`, `cleared_origins` and
  `story_rivals_defeated` in `last_victory_summary` for the HUD.
- `apply_region_boss_profile()` still preserves `story_override` on purpose (a story choice owns its
  name/scale/slots), which is why the test drives the flag explicitly instead of relying on travel.

`dev_studio.gd` — existing keys unchanged, new ones additive:
- `player.origin_id` / `player.origin_title`; `boss.story_rival`; `victory.origin_title`,
  `victory.story_rival`, `victory.story_rivals_defeated_count` (defaults included before any KO).
- Seinen HUD: a bone-ink `ORIGIN · <title>` tag under the VITAL/GUARD cluster (drops below the combo
  badge when one is showing); a crimson-on-gold `[ STORY RIVAL ]` plate on the boss name row that
  replaces the archetype tag for authored encounters; the Victory Rank Card gains an
  `ORIGIN · <title>` line and a `STORY RIVAL DEFEATED` ink stamp, with the card growing 20 px taller
  for it (176 → 196) so the stamp never touches the unlock line or the centred RETRY overlay.
  Same 10 Hz snapshot, no new nodes or shaders, still hidden behind the Dev Panel / P5 menu.

Test coverage is §26 (15 asserts): origin switch moves `active_origin_title()` and the snapshot
`player.origin_id`/`origin_title`; a guardian without the override is not a story duel while
`spawn_story_rival()` flips it, resets `boss_phase` to 1 and lands at 7.50 m separation; the KO writes
`best_origin` + `cleared_origins` + `story_rivals_defeated` into `user://dev_profile.json` beside
`tuning` (93.0 sentinel); the victory snapshot carries origin title, story flag and count; a repeat
encounter is deduplicated; `reset_progression_flags()` clears rivals + mastery, keeps the origin and
keeps the 93.0 tuning value.

Unverified: the origin tag, `[ STORY RIVAL ]` plate and card stamp pixels (headless never runs
`_draw()`); all three read only from the snapshot values asserted above.

