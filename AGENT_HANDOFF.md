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

### _next entry_
_(date · agent · what you changed · what you verified · what is left open)_
