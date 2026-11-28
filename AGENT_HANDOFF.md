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
