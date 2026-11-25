#!/usr/bin/env bash
# =============================================================================
#  Sasti Sparkling Zero — verification gate
#  Usage:  bash verify.sh
#          GODOT_BIN=/path/to/godot bash verify.sh
#          SKIP_IMPORT=1 bash verify.sh      (fast re-run; import is NOT verified)
# =============================================================================
set -uo pipefail

REQUIRED_GODOT="4.7"
GODOT_BIN="${GODOT_BIN:-godot}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Environment noise that is not a project defect.
BENIGN='Unable to load fontconfig|Blender path is invalid'

fail() { echo; echo "VERIFY_FAILED: $*"; exit 1; }
ok()   { echo "  ok   $*"; }

# Anything in a Godot log that means the project is broken.
scan() { # $1 = gate label, $2 = log file
    local label="$1" log="$2" hits
    hits="$(grep -nE '^ERROR:|SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|Cannot open file .res://\.godot/imported|Failed to correctly scale body|InputMap action .* doesn.t exist|same name as a built-in|Invalid access to property or key|Invalid get index|Invalid set index|Invalid call\.|Cannot convert argument' "$log" 2>/dev/null | grep -vE "$BENIGN" || true)"
    if [ -n "$hits" ]; then
        echo "$hits"
        fail "$label reported engine or script errors (see above)"
    fi
}

# --- GUARDRAIL 0: engine version ---------------------------------------------
echo "[0/7] engine"
command -v "$GODOT_BIN" >/dev/null 2>&1 \
    || fail "Godot not found. Install Godot ${REQUIRED_GODOT}.x or run: GODOT_BIN=/path/to/godot bash verify.sh"
GODOT_VER="$("$GODOT_BIN" --version 2>/dev/null | head -n1)"
case "$GODOT_VER" in
    "$REQUIRED_GODOT"*) ok "Godot $GODOT_VER" ;;
    *) fail "project targets Godot ${REQUIRED_GODOT}.x but '$GODOT_BIN --version' reported '$GODOT_VER'" ;;
esac

# --- GUARDRAIL 1: required files ---------------------------------------------
echo "[1/7] required files"
for f in combat_data.gd dash_vfx.gd character_body_3d.gd gesture_combat.gd dev_studio.gd world_story.gd flame_p5_pvp.gd smoke_test.gd data/story_nodes.json; do
    [ -f "$f" ] || fail "GUARDRAIL_VIOLATION: missing core file $f"
done
ok "8 core scripts + story data present"

# --- GUARDRAIL 2: feature presence (blocks silent AI deletions) ---------------
echo "[2/7] features"
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
    "_setup_physical_ragdoll:character_body_3d.gd"
    "is_target_in_blade_arc:character_body_3d.gd"
    "spawn_arena_block:dash_vfx.gd"
    "spawn_story_rival:gesture_combat.gd"
    "try_vanish_counter_on_dash:gesture_combat.gd"
    "toggle_flame_awakening:flame_p5_pvp.gd"
    "host_custom_room:flame_p5_pvp.gd"
    "make_choice:world_story.gd"
    "8. Combat Feel:dev_studio.gd"
    "TUNING_SPEC:combat_data.gd"
    "tuning_get:combat_data.gd"
    "take_damage:character_body_3d.gd"
    "result_state:gesture_combat.gd"
    "reset_duel:gesture_combat.gd"
    "_pop_damage_number:gesture_combat.gd"
    "_boss_anim:gesture_combat.gd"
    "_move_body:gesture_combat.gd"
    "MAX_USER_BLOCKS:dash_vfx.gd"
    "COMBAT_TEST_PASS:combat_test.gd"
    "STORY_SCHEMA_PASS:story_test.gd"
    # V4: device quality tiers, SDF face pipeline, typed AI state, story loader
    "QUALITY_TIERS:combat_data.gd"
    "detect_quality_tier:combat_data.gd"
    "tier_profile:combat_data.gd"
    "apply_quality_tier:character_body_3d.gd"
    "sdf_face_tex:character_body_3d.gd"
    "face_sdf_enabled:character_body_3d.gd"
    "debris_cap:dash_vfx.gd"
    "AIState:gesture_combat.gd"
    "ai_state_label:gesture_combat.gd"
    "_cycle_quality_tier:dev_studio.gd"
    "_rebuild_combat_feel:dev_studio.gd"
    "load_story_data:world_story.gd"
    "save_state:world_story.gd"
    "paint_vertex_channels:build_models.py"
    "proxy_smooth_normals:build_models.py"
    # V5: safe legacy profile load, parkour wall-run, anime water, celestial eye,
    # NOBI_2D screen-space impact slash + 2-tone cel smoke
    "ensure_tuning:combat_data.gd"
    "wall_run_gate:character_body_3d.gd"
    "_apply_wall_run_velocity:character_body_3d.gd"
    "wall_run_enabled:combat_data.gd"
    "wall_kick_force:combat_data.gd"
    "WALL_RUN_MIN_SPEED:character_body_3d.gd"
    "_ledge_vault_clear:character_body_3d.gd"
    "_vault_onto_ledge:character_body_3d.gd"
    "water_floor_enabled:combat_data.gd"
    "water_wave_height:combat_data.gd"
    "set_water_enabled:dash_vfx.gd"
    "spawn_cel_smoke:dash_vfx.gd"
    "trigger_impact_slash:gesture_combat.gd"
    "impact_slash_timer:gesture_combat.gd"
    "trigger_screen_slash:dash_vfx.gd"
    "ScreenSlash:dash_vfx.gd"
    "set_fx_budget:dash_vfx.gd"
    "impact_slash_enabled:combat_data.gd"
    "cel_smoke_density:combat_data.gd"
    "CELESTIAL_CONSTELLATION:dev_studio.gd"
    # V5 character pipeline: dependency-free GLB generator + contract test
    "Slot_VeilCloak_:tools/build_character.py"
    "_apply_wall_run_velocity:character_body_3d.gd"
    "CHARACTER_TEST_PASS:character_test.gd"
)
for item in "${REQUIRED_SIGNATURES[@]}"; do
    sig="${item%%:*}"
    file="${item##*:}"
    grep -Fq "$sig" "$file" || fail "GUARDRAIL_VIOLATION: feature '$sig' was removed from $file"
done
ok "${#REQUIRED_SIGNATURES[@]} signatures intact"

# --- GUARDRAIL 2b: project invariants ---------------------------------------
echo "[2b/7] invariants"
# 60 Hz physics is only smooth on a 120-165 Hz panel WITH interpolation enabled.
grep -q "physics_interpolation=true" project.godot \
    || fail "physics/common/physics_interpolation is OFF: 60 Hz physics will micro-stutter on a 120 Hz+ panel"
# PhysicalBone3D under a non-uniformly scaled model root = 12 Jolt scale errors per swap.
if grep -q "PhysicalBone3D.new(" character_body_3d.gd; then
    fail "PhysicalBone3D reintroduced in character_body_3d.gd (Jolt rejects bones under a non-uniformly scaled model root)"
fi
# Enemy AI / projectiles must not run on the render tick (framerate-dependent speed).
if ! grep -q "func _physics_process" gesture_combat.gd; then
    fail "gesture_combat.gd lost its _physics_process: enemies and projectiles would run at render rate and speed up with refresh rate"
fi
# Wall-running must never tilt the capsule: only VisualRoot + the camera roll.
if grep -nE '^[[:space:]]*up_direction[[:space:]]*=' character_body_3d.gd | grep -vq 'Vector3\.UP'; then
    fail "up_direction is reassigned away from Vector3.UP (character_body_3d.gd): a tilted capsule slides down the wall"
fi
grep -q 'deg_to_rad(-8.0 \* wall_run_side)' character_body_3d.gd \
    || fail "wall-run camera roll lost its 8 degree limit"
grep -q '_ledge_vault_clear()' character_body_3d.gd \
    || fail "auto ledge-vault lost its chest/head clearance raycast"
ok "interpolation on, no physics bone bodies, combat on the physics tick, capsule stays upright"

# GDScript hygiene: these are compiler WARNINGS, so they never fail a headless boot
# and they were shipped twice already (snapped/scale shadowing in the phone log).
SHADOW_HITS="$(grep -nE '^[[:space:]]*var[[:space:]]+(snapped|snappedf|scale|rotation|position|basis|transform|visible|velocity|lerp|clamp|abs|sign|min|max|str|range|print)[[:space:]]*:?=' ./*.gd 2>/dev/null || true)"
if [ -n "$SHADOW_HITS" ]; then
    echo "$SHADOW_HITS"
    fail "a local variable shadows a built-in (SHADOWED_VARIABLE): rename it"
fi
# INT_AS_ENUM_WITHOUT_CAST: assigning int() straight to a typed enum var.
if grep -nE 'dash_style[[:space:]]*=[[:space:]]*int\(' ./*.gd 2>/dev/null | grep -v 'as DashStyle'; then
    fail "int assigned to an enum without an \`as DashStyle\` cast (INT_AS_ENUM_WITHOUT_CAST)"
fi
ok "no shadowed built-ins, no bare int-to-enum cast"

# Every agent must leave a handoff entry (protocol rule, enforced here so it
# cannot be skipped by the next model in the chain).
[ -f AGENT_HANDOFF.md ] || fail "AGENT_HANDOFF.md is missing, the AI handoff channel must exist"
grep -qE '=== AI HANDOFF|^### ?\[?2026-' AGENT_HANDOFF.md \
    || fail "AGENT_HANDOFF.md has no dated entry or '=== AI HANDOFF' packet"
ok "AGENT_HANDOFF.md present with a dated entry"

# --- GUARDRAIL 3: assets actually import -------------------------------------
echo "[3/7] asset import"
# A .blend anywhere in the import path aborts the whole import batch (verified on 4.7).
STRAY_BLEND="$(find . -name '*.blend' -not -path './art/*' -not -path './.godot/*' 2>/dev/null | head -n1)"
[ -z "$STRAY_BLEND" ] || fail "blender source inside the import path: $STRAY_BLEND - move it to art/ (it aborts headless asset import)"

if [ "${SKIP_IMPORT:-0}" = "1" ]; then
    echo "  WARN import skipped (SKIP_IMPORT=1) — assets are NOT verified"
else
    "$GODOT_BIN" --headless --path . --import > "$TMP_DIR/import.log" 2>&1
    IMPORT_RC=$?
    scan "asset import" "$TMP_DIR/import.log"
    [ "$IMPORT_RC" -eq 0 ] || fail "asset import exited with $IMPORT_RC"
    for glb in models/*.glb; do
        [ -f "$glb" ] || continue
        dest="$(grep -o 'res://\.godot/imported/[^"]*' "$glb.import" 2>/dev/null | head -n1)"
        if [ -z "$dest" ] || [ ! -f "${dest#res://}" ]; then
            fail "$glb did not import (expected ${dest:-no import path}) - open the project once in the Godot editor"
        fi
    done
    ok "models/*.glb imported"
fi

# The import above can pass while the model quietly loses a bone or a Slot_ node,
# so the engine-facing names get their own check.
echo "[3b/7] character contract"
"$GODOT_BIN" --headless --path . --script res://character_test.gd > "$TMP_DIR/chars.log" 2>&1
CHARS_RC=$?
scan "character contract" "$TMP_DIR/chars.log"
grep -q "CHARACTER_TEST_PASS" "$TMP_DIR/chars.log" \
    || fail "character contract test failed (exit $CHARS_RC): $(grep -m2 'FAIL' "$TMP_DIR/chars.log" | tr '\n' ' ')"
ok "hero + boss expose the bones, Slot_ nodes and clips the engine asks for"

# --- GUARDRAIL 4: headless boot ----------------------------------------------
echo "[4/7] headless boot (120 frames)"
"$GODOT_BIN" --headless --path . --quit-after 120 > "$TMP_DIR/boot.log" 2>&1
scan "headless boot" "$TMP_DIR/boot.log"
ok "booted clean"

# --- GUARDRAIL 5: smoke test (touch input + dev panel) -----------------------
echo "[5/7] smoke test"
"$GODOT_BIN" --headless --path . --script res://smoke_test.gd > "$TMP_DIR/smoke.log" 2>&1
SMOKE_RC=$?
scan "smoke test" "$TMP_DIR/smoke.log"
grep -q "SMOKE_TEST_PASS" "$TMP_DIR/smoke.log" \
    || fail "smoke test did not reach SMOKE_TEST_PASS (exit $SMOKE_RC)"
ok "touch input + dev panel"

# --- GUARDRAIL 6: combat loop (damage, KO, retry, tuning, save/load) ---------
echo "[6/7] combat loop"
"$GODOT_BIN" --headless --path . --script res://combat_test.gd > "$TMP_DIR/combat.log" 2>&1
COMBAT_RC=$?
# The dummy renderer (servers/rendering/dummy) logs a null theme/font material when
# fontconfig is missing in CI. That file only exists in --headless builds, so the
# message cannot occur on the mobile/Vulkan renderer. Drop only that exact pair of
# lines; the same message from any other source still fails the gate below.
sed -i '/^ERROR: Parameter "material" is null\.$/{N;/at: material_get_instance_shader_parameters (servers\/rendering\/dummy\//d}' "$TMP_DIR/combat.log"
scan "combat loop" "$TMP_DIR/combat.log"
grep -q "COMBAT_TEST_PASS" "$TMP_DIR/combat.log" \
    || fail "combat loop test did not reach COMBAT_TEST_PASS (exit $COMBAT_RC)"
ok "combat checks (hit, combo, KO, retry, immortal, defeat, tuning, tiers, menu)"

# --- GUARDRAIL 7: story schema ----------------------------------------------
echo "[7/7] story schema"
"$GODOT_BIN" --headless --path . --script res://story_test.gd > "$TMP_DIR/story.log" 2>&1
STORY_RC=$?
scan "story schema" "$TMP_DIR/story.log"
grep -q "STORY_SCHEMA_PASS" "$TMP_DIR/story.log" \
    || fail "story schema test did not reach STORY_SCHEMA_PASS (exit $STORY_RC): $(grep -m2 'FAIL' "$TMP_DIR/story.log" | tr '\n' ' ')"
ok "data/story_nodes.json valid (origins, nodes, choices, links)"

echo
echo "VERIFY_PASSED: 8 tabs, ${#REQUIRED_SIGNATURES[@]} signatures, invariants, import, boot, smoke, combat loop, story schema."
exit 0
