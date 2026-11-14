#!/usr/bin/env bash
set -e

# --- GUARDRAIL 1: Required Files & Minimum Line-Count Check ---
for f in combat_data.gd dash_vfx.gd character_body_3d.gd gesture_combat.gd dev_studio.gd world_story.gd; do
    if [ ! -f "$f" ]; then
        echo "GUARDRAIL_VIOLATION: Missing core file $f!"
        exit 1
    fi
done

# --- GUARDRAIL 2: Mandatory 7-Tab & Core Feature Presence Check ---
REQUIRED_SIGNATURES=(
    "1. Camera & Physics:dev_studio.gd"
    "2. Profile & Dash:dev_studio.gd"
    "3. Move Slots:dev_studio.gd"
    "4. Spell Maker:dev_studio.gd"
    "5. Shaders & AI:dev_studio.gd"
    "6. World & Char Maker:dev_studio.gd"
    "7. World Map & Story:dev_studio.gd"
    "_register_input_actions:character_body_3d.gd"
    "apply_modular_clothing_slots:character_body_3d.gd"
    "_update_spring_bone_jiggle:character_body_3d.gd"
    "spawn_arena_block:dash_vfx.gd"
    "spawn_story_rival:gesture_combat.gd"
)

for item in "${REQUIRED_SIGNATURES[@]}"; do
    sig="${item%%:*}"
    file="${item##*:}"
    if ! grep -Fq "$sig" "$file"; then
        echo "GUARDRAIL_VIOLATION: Feature '$sig' was removed from $file!"
        exit 1
    fi
done

# --- GUARDRAIL 3: Headless Boot + Runtime C++ ERROR & Shadowed Variable Check ---
OUT=$(godot --path . --headless --quit-after 10 2>&1)
echo "$OUT"

if echo "$OUT" | grep -qE "SCRIPT ERROR|Parse Error|Failed to load script|InputMap action .* doesn't exist|same name as a built-in"; then
    echo "VERIFY_FAILED: Engine or Script Error Detected!"
    exit 1
fi

echo "VERIFY_PASSED: All 7 Tabs, 3D Systems, and Runtime Checks Intact!"
exit 0
