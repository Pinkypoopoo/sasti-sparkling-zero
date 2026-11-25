---
trigger: glob
globs: "world_story.gd, data/story_nodes.json, story_test.gd, *.tscn"
description: "Interconnected arena scope, story_nodes.json schema invariants, persistence, and regional palettes."
---
# Book 3: World Architecture, Story JSON & Arena Builder

## World Scope
- Interconnected hub + 2–3 tight arenas with Dark Souls-style shortcuts. Do NOT introduce open-world chunk streaming.
- Preserve all 3 regional palettes (`INK_CATHEDRAL`, `BLAME_MEGASTRUC`, `GOTHIC_ECLIPSE`) and the Tab 6 Destructible Arena / Level Builder (`GOTHIC_PILLAR`, `BLAME_MONOLITH`, `RUINED_ARCH`, `ANIME_FLORA_PATCH` MultiMesh).

## Story Data & Validation Invariants
- `world_story.gd` is a pure loader; never hardcode narrative graphs back into GDScript.
- All origins, nodes, rival loadouts, `requires_flags`, `grants_flags`, and `grants_unlocks` live in `data/story_nodes.json` (`schema_version: 1`).
- Every `origin.start_node` and every choice `"next"` target MUST resolve to an existing key in `nodes` (verified by `story_test.gd` inside `verify.sh`).
- Persist `story_flags`, `completed_nodes`, `active_origin_id`, and `current_node_id` in `user://dev_profile.json` under `"story_state"` via merged writes.
- Keep `*.json` included in `export_presets.cfg` non-resource filters so `data/story_nodes.json` ships inside Android/iOS exports.
