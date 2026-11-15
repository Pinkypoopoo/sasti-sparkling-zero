# Sasti Sparkling Zero — Senior Dev Plan

Written 15 Nov 2026 by the reviewing agent, on branch `freebuff/9df505384c5b1c5ec2578cb3`.
Read with [CODE_REVIEW.md](CODE_REVIEW.md) (evidence + line numbers). This file is the *plan*.

---

## 0. The verdict, in one paragraph

You have built something unusual for a solo/AI project: a real 3D combat sandbox with a working
gesture control scheme, a live tuning studio, procedurally generated characters, a story graph and
LAN PvP — all in 5 files and under 5,000 lines, and it *boots clean*. The engineering instinct is
good. What you do not have is a **game**: there is no way to lose, no way to win, nothing persists,
and every number lives inside a function body. The plan below fixes the last thing first, because
"tune everything from the UI" is not a nice-to-have for someone with an internship — it is the only
way this project survives contact with your free time.

---

## 1. The one architectural decision that matters

> **Every tunable belongs to a data object, never to a function body.**

Right now a new mechanic costs: a new `@export` var → a new slider row hand-written in `dev_studio.gd`
→ a new entry in `save_to_disk`'s property list. That is three code edits per number, and it is
why tuning feels like a programming task.

Replace it with one pattern and every future system becomes ~free to tune:

```
res://data/balance.tres          ← Godot Resource, the single source of truth
    ├─ MovementTuning   (run_speed, dash_speed, dash_duration, cooldown, gravity, cam_*)
    ├─ CombatTuning     (damage, posture, hitstop, parry_window, buffer_time, knockback)
    ├─ AITuning         (telegraph_time, cooldown, adaptation, aggression, spacing)
    ├─ VFXTuning        (pool sizes, afterimage count, sigil lifetime, shake scale)
    └─ CharacterTuning  (proportions, shader bands, outline, eye)
```

Then a **registry** (`tuning_registry.gd`) that reflects over those resources:

```gdscript
# one line per tuning class, added once — the UI builds itself from this
const CLASSES := [MovementTuning, CombatTuning, AITuning, VFXTuning, CharacterTuning]
```

`dev_studio.gd` stops containing 500 lines of hand-written sliders and instead loops
`CLASSES` → `get_property_list()` → build a slider per float with its `hint_range`. Adding
`parry_heal_amount` to `CombatTuning` makes a slider appear, and it saves, loads and syncs to PvP
with zero UI code. **This is the difference between "I add systems" and "I add systems and tune
them on the bus."**

Two follow-ons that cost almost nothing once the above exists:

- **Presets, not one balance.** `data/presets/story_ch1.tres`, `ranked_casual.tres`,
  `boss_brutal.tres`. Story chapters get their own feel; you tweak per chapter from the UI.
- **Live-edit from the running game.** A `[SAVE]` button in the studio already exists — make it
  write the `.tres` (or a JSON overlay) instead of 40 scattered player properties.

Rule to enforce from now on: **a mechanic is not "in" until it has (a) a tuning field, (b) a
studio row that appears automatically, (c) a line in the save file, (d) a `verify.sh` signature.**
That rule is what keeps you out of the code and in the UI.

---

## 2. Things to add (in priority order)

### Tier 1 — makes it a game (do these before anything else)
1. **Death + defeat.** Remove the `maxf(100.0, ...)` floor. On `hp <= 0`: hitstop → slow-mo 0.35×
   for 0.6 s → "DEFEAT" card → `[ RETRY ] [ BACK ]`. Everything already exists except the card.
2. **Victory + progression.** Boss `hp <= 0` must *stay* 0. Award: posture medals, unlock the next
   story node, unlock an ability (your `p2p_pause_manager` already had `unlocked_p5_pause` — reuse
   that idea), regenerate the rival with +1 tier. `story_flags` finally gets read.
3. **One save file for progress** (`user://save_slot_0.json`): origin, current node, story flags,
   unlocked abilities, win/loss record, equipped slots, balance-preset name. `CombatData` keeps
   tunables; this is the *game* save. Autosave on node change and on defeat.
4. **Pause / options screen** (not the dev panel): Resume · Options (master/music/SFX volume, stick
   sensitivity, FPS cap, quality) · Controls diagram · Return to title. `Esc`/back button opens it.
   This single screen also fixes the Android back-button hole.

### Tier 2 — makes it feel like the game you described
5. **Ranked arena shell.** You already have the fight; you need the frame: opponent select →
   best-of-3 → rank points → leaderboard (local JSON first, online later). This is 90% UI and 10%
   logic, so it is the cheapest big "this is a game now" win.
6. **Training/tutorial overlay.** Three pages on first launch: move, two orbs (sway/strike), weaves.
   First 15 seconds decide whether a mobile player ever sees your combat system.
7. **Combo/rank feedback.** Damage numbers, "PARRY", "PERFECT SWAY", a combo counter, a rank letter
   at the end (`S/A/B/C`). Fighting games live on this feedback; it is pure UI data.
8. **Enemy variety through data, not code.** `rival_def.tres`: model, colours, move weights,
   telegraph multiplier, phase thresholds. Four rivals = four `.tres` files, not four scripts.
9. **Gamepad support.** `InputEventJoypadButton/Motion` in `_register_input_actions`, with a
   deadzone and remap screen. Your whole control scheme maps cleanly to face buttons + right stick.
10. **Audio buses** (`Master/Music/SFX/UI`), 3–4 round-robin SFX players, `AudioStreamPlayer3D` for
    world impacts. The synth engine stays — it just needs a mixer.

### Tier 3 — the story/world dream (only after Tier 1 + 2)
11. **Story as data, not code.** `data/story/*.json` nodes: `id, title, desc, region, rival,
    choices[], requires_flags[], grants_unlocks[]`. `world_story.gd` shrinks to a loader; you (or a
    local AI) author content forever without touching GDScript.
12. **The ebook → story pipeline.** Local model + retrieval over your ebooks, but the *output* must
    be your node JSON, validated by a schema check in `verify.sh`. Never let generated prose enter
    the engine directly. Wire your Notion database as the authoring surface: story nodes live there,
    an export step writes the JSON.
13. **Interconnected world (souls-like) at a sane scale.** See §4 — do not build an open world.

---

## 3. Things to remove / stop doing

| Remove | Why |
|---|---|
| `p2p_pause_manager.gd` | dead 278-line duplicate that binds the same UDP port as the live module. **Deleted.** |
| `movement_test.tscn` | structurally invalid scene (missing the nodes the player requires). **Deleted.** |
| `.blend` inside `models/` | aborts headless asset import (verified). **Moved to `art/`** with `.gdignore`. |
| 165 Hz mode | 2.75× CPU cost for nothing perceivable. 60 default, 120 as the single "high" option. |
| `main.tscn` *or* `character_movement_test.tscn` | two near-identical scenes. Keep one, name it `main.tscn`. |
| `Slot_8_Counter` (or wire it) | unreachable from `_commit_strike`; either map it or delete it, don't leave a slider that does nothing. |
| the `get()/call()` string bridge | ~40 string lookups in `flame_p5_pvp.gd` alone; it is the #1 way an AI edit silently breaks the game. Replace with typed refs + signals. |
| hard-coded design numbers in functions | move into `data/balance.tres` per §1. |
| `|| true` in CI | it is how a broken export uploads an empty artifact. |

Also stop: **adding a system without a tuning field + studio row + save entry + verify signature.**
And stop writing the same state machine twice (`player.state` vs `s["ai_state"]` strings) — move the
rival to a small `RivalBrain` with an enum, or you will spend 2027 on string typos.

---

## 4. Scope: what I would build instead of an open world

You asked for Sparking Zero ranked + Elden Ring world + Dark Souls 1 interconnectedness, on phones.
Those three pull in different directions and the combination is a 40-person game. The senior move is
not to cut the *feeling*, it is to cut the *square kilometres*.

**Build this instead: a hub + three arenas, with souls-like shortcuts.**

```
            INK CATHEDRAL (hub: NPCs, arena gate, story board)
              ↕ shortcut: broken lift shaft you unlock from below
        MEGASTRUCTURE DESCENT ─── one-way drop ──→ GOTHIC ECLIPSE
              ↕ loop back via the Cathedral's west stair
           ARENA (ranked)  ←→  TRAINING (tutorial + move lab)
```

- Each area is **one connected space about 150×150 m**, not an open world. Load in < 1 s, hold
  60 fps on a mid-range phone, and *feel* vast because of verticality and sightlines.
- Interconnectedness is **three shortcuts + one hub**, exactly like Dark Souls' Firelink. That is
  what players remember; nobody remembers the walk between zones.
- Ranked arena is its own scene, no streaming, no NPCs — this is your replayable core and it must be
  flawless before any world work.
- World streaming, LODs for terrain, NPC schedules, weather: **not now.** They are the first things
  that make a mobile build unshippable.

Rough content budget for the vertical slice: hub, 1 arena, 1 story boss, 1 ranked ladder, 20 min of
authored story. If that is fun, everything else is duplication. If it is not, more world would not
have saved it.

---

## 5. Art direction: how to actually decide the anime style

You cannot decide because "anime" is not one look. Decide by **constraint**, and you already own
half of the answer: your shader is a cel ramp + inverted-hull outline + rim light, and your two
existing models are "obsidian/lace cathedral" and "gilded veil". That is a coherent direction.

**Pick A: Dark Seinen Ink** (recommended — matches what you already built)
- 2-tone ramp (lit / shadow) + a third band only on skin and metal; ink hatch in the shadow band.
- Bold black inverted-hull outline (0.02–0.03), no colour grading pass.
- Palette: bone white, obsidian, one saturated accent per character (crimson / gold / cyan).
- Reference: Berserk, Blame!, Claymore. Mobile cost: **low** — 1 shader, 1 ramp texture, outlines
  are geometry (already free-ish).
- Risk: it can read "muddy" on a phone screen in sunlight → keep the accent colour saturated.

**Pick B: Sparking Zero Anime** — needs rim-light passes, bloom, speed-line post FX, per-character
gradient ramps and outline thickness over distance. That is 2–3 full-screen passes; on mobile it
means 4 GB RAM phones at 30 fps. Take it only if you accept desktop-only visuals.

**Pick C: Arcane/Stylised-PBR** — expensive, needs art you cannot generate procedurally.

**The decision process (one week, no more):**
1. Build a 1-page **style guide** with 6 reference images you can name the source of, and the exact
   shader/material rules for each surface class (skin, cloth, metal, hair, VFX).
2. Make **one** character, **one** 20 m environment piece, **one** VFX (dash + hit) in that style.
3. Screenshot on the actual phone at lowest brightness, outdoors. If the silhouette and the accent
   colour still read, it is the style. Lock it in writing and stop revisiting.
4. Encode the rules in `data/art_style.tres` so the studio can tweak bands/outline live (§1) and so
   any future AI agent produces *consistent* assets.

Consistency beats novelty. "Looks like an anime from every side" on mobile means: strong
silhouettes, limited palette, one accent colour, no full-screen post FX, outlines scaled by distance.

---

## 6. Milestones (each one ends with something playable and a green `verify.sh`)

| # | Milestone | Done when | UI deliverable (no code to tune) |
|---|---|---|---|
| M0 | **Gate** | `bash verify.sh` runs import + version + boot + smoke test | — *(done this session)* |
| M1 | **Tuning layer** | `data/balance.tres` + registry; studio builds itself | every tunable has a slider, preset save/load |
| M2 | **Stakes** | you can lose, win, retry, and progress persists | defeat/victory cards, save-slot panel |
| M3 | **Shell** | title → arena → rank points → title | options screen, ladder, rank card |
| M4 | **Feel** | 60 fps cap, 60 Hz physics, cached proportions, overlay at 10 Hz, per-area budgets | performance panel showing ms/draw calls |
| M5 | **World slice** | hub + 1 story boss + 1 shortcut that loops | story-node editor panel (JSON in/out) |
| M6 | **Content** | story JSON authored from Notion + ebook pipeline with schema validation | story page in studio |

Do not start M5 before M2. A beautiful world with no loop is the most common way projects like this die.

---

## 7. What I would do specifically, as the person taking this over

1. **Freeze features for two days.** Do M0–M1 only. Every number becomes data.
2. **Delete before you add.** Dead files, dead move slots, dead `_rpc`s, the duplicate scene, the
   165 Hz mode. A small repo is a fast repo — and an AI-agent-friendly one.
3. **Set budgets and put them on screen.** Per area: ≤ 120 draw calls, ≤ 150k triangles, ≤ 8 unique
   shaders, ≤ 3 transparent layers, 60 fps on a 2020 mid-range Android. Your telemetry already
   measures GPU/CPU ms — show draw calls too and treat a red number as a bug.
4. **One scene, one entry point.** `main.tscn` → `World` → subscrenes. Rename the test scene.
5. **Kill the string bridge.** Signals and typed refs between Player ↔ Combat ↔ Flame ↔ Story.
   Before you hand the repo to any AI again, this is what stops silent breakage.
6. **Never tune in code again.** If you catch yourself editing `character_body_3d.gd` to change a
   number, add the field to the tuning resource instead. That habit *is* the productivity plan.
7. **Write the style guide before the next character**, or you will redo every asset twice.
8. **Ship a 20-minute vertical slice to your own phone** and play it 10 times before adding anything
   new. Every bug you feel in those 10 runs is worth more than a feature.

---

## 8. Risks I would track

- **Animation.** You have 5 baked clips at 12 fps stepped. That is a *style*, but it cannot express
  hit reactions, so combat will feel stiff before it feels stylish. Budget 2–3 reaction clips
  (hit_light, hit_heavy, knockdown) before adding more VFX.
- **Two implementations of everything** (PvP, P5 menu, story state). Each new feature currently gets
  a second copy. One module, one owner.
- **PvP security.** Plaintext password over LAN broadcast, room code → IP guessing. Fine for friends
  on a hotspot; do not market it as online ranked until there is real matching.
- **Mobile thermal.** 120 Hz physics + 165 fps + alpha-hash transparency = a phone that throttles in
  4 minutes. Cap early, not later.
- **Token/agent churn.** Every AI pass that "improves" code without a signature gate risks deleting
  a feature. `verify.sh`'s feature grep is your seatbelt — keep extending it.
