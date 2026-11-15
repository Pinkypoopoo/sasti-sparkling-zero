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
    hits="$(grep -nE '^ERROR:|SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|Cannot open file .res://\.godot/imported|Failed to correctly scale body|InputMap action .* doesn.t exist|same name as a built-in' "$log" 2>/dev/null | grep -vE "$BENIGN" || true)"
    if [ -n "$hits" ]; then
        echo "$hits"
        fail "$label reported engine or script errors (see above)"
    fi
}

# --- GUARDRAIL 0: engine version ---------------------------------------------
echo "[0/5] engine"
command -v "$GODOT_BIN" >/dev/null 2>&1 \
    || fail "Godot not found. Install Godot ${REQUIRED_GODOT}.x or run: GODOT_BIN=/path/to/godot bash verify.sh"
GODOT_VER="$("$GODOT_BIN" --version 2>/dev/null | head -n1)"
case "$GODOT_VER" in
    "$REQUIRED_GODOT"*) ok "Godot $GODOT_VER" ;;
    *) fail "project targets Godot ${REQUIRED_GODOT}.x but '$GODOT_BIN --version' reported '$GODOT_VER'" ;;
esac

# --- GUARDRAIL 1: required files ---------------------------------------------
echo "[1/5] required files"
for f in combat_data.gd dash_vfx.gd character_body_3d.gd gesture_combat.gd dev_studio.gd world_story.gd flame_p5_pvp.gd smoke_test.gd; do
    [ -f "$f" ] || fail "GUARDRAIL_VIOLATION: missing core file $f"
done
ok "8 core scripts present"

# --- GUARDRAIL 2: feature presence (blocks silent AI deletions) ---------------
echo "[2/5] features"
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
)
for item in "${REQUIRED_SIGNATURES[@]}"; do
    sig="${item%%:*}"
    file="${item##*:}"
    grep -Fq "$sig" "$file" || fail "GUARDRAIL_VIOLATION: feature '$sig' was removed from $file"
done
ok "${#REQUIRED_SIGNATURES[@]} signatures intact"

# --- GUARDRAIL 3: assets actually import -------------------------------------
echo "[3/5] asset import"
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

# --- GUARDRAIL 4: headless boot ----------------------------------------------
echo "[4/5] headless boot (120 frames)"
"$GODOT_BIN" --headless --path . --quit-after 120 > "$TMP_DIR/boot.log" 2>&1
scan "headless boot" "$TMP_DIR/boot.log"
ok "booted clean"

# --- GUARDRAIL 5: smoke test (touch input + dev panel) -----------------------
echo "[5/5] smoke test"
"$GODOT_BIN" --headless --path . --script res://smoke_test.gd > "$TMP_DIR/smoke.log" 2>&1
SMOKE_RC=$?
scan "smoke test" "$TMP_DIR/smoke.log"
grep -q "SMOKE_TEST_PASS" "$TMP_DIR/smoke.log" \
    || fail "smoke test did not reach SMOKE_TEST_PASS (exit $SMOKE_RC)"
ok "touch input + dev panel"

echo
echo "VERIFY_PASSED: 7 tabs, core systems, asset import, boot and smoke test all clean."
exit 0
