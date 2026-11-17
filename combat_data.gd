class_name CombatData
extends Node

const SAVE_PATH: String = "user://dev_profile.json"

# =============================================================================
#  COMBAT FEEL TUNING
#  One place for every feel number. Dev Studio tab 8 builds its sliders by
#  reflecting over these three dictionaries: add a line here and a live slider
#  appears, saves to disk and loads again. No UI code, no new @export.
#  Read at runtime with tuning_get() / tuning_bool().
# =============================================================================
const TUNING_SPEC: Dictionary = {
	# key: [min, max, step, label]
	"enemy_damage":        [5.0,  300.0, 1.0,  "Enemy Hit Damage"],
	"player_damage_mult":  [0.1,  5.0,   0.05, "Your Damage x"],
	"posture_damage_mult": [0.1,  5.0,   0.05, "Posture Damage x"],
	"hitstop_scale":       [0.0,  3.0,   0.05, "Hitstop Length x"],
	"shake_scale":         [0.0,  3.0,   0.05, "Camera Shake x"],
	"parry_window":        [0.05, 1.0,   0.01, "Parry Window (s)"],
	"super_parry_window":  [0.02, 0.5,   0.01, "Super-Parry Window (s)"],
	"combo_grace":         [0.3,  5.0,   0.1,  "Combo Grace (s)"],
	"ko_slowmo_scale":     [0.05, 1.0,   0.05, "KO Slow-Mo Speed"],
	"ko_slowmo_time":      [0.0,  2.0,   0.05, "KO Slow-Mo (s)"],
	"hurt_vignette":       [0.0,  1.0,   0.05, "Hurt Vignette"],
		"dmg_number_size":     [0.5,  2.0, 0.1,  "Damage Number Size"],
	"quality_tier":        [0.0,  3.0, 1.0,  "Quality Tier (0 LOW-3 ULTRA)"],
	"render_scale":        [0.5,  1.0, 0.01, "Render Scale"],
	"sdf_face_softness":   [0.01, 0.25, 0.01, "SDF Face Softness"],
	"vertex_shadow_bias":  [0.0,  2.0, 0.05, "Vertex Shadow Bias"],
	"outline_dist_scale":  [0.0,  1.0, 0.05, "Outline Distance Falloff"],
	# V5 parkour + water floor
	"wall_run_speed":      [14.0, 48.0, 1.0,  "Wall Run Speed"],
	"wall_run_gravity_scale": [0.0, 1.0, 0.05, "Wall Run Gravity"],
	"wall_kick_force":     [8.0,  32.0, 1.0,  "Wall Kick-Off Force"],
	"water_wave_height":   [0.0,  0.65, 0.02, "Water Wave Height"],
}

const TUNING_BOOLS: Dictionary = {
	"immortal_mode":       "Sandbox Immortal (cannot die)",
	"show_damage_numbers": "Floating Damage Numbers",
	"show_combo_counter":  "Combo Counter",
	"auto_lock_on":        "Auto Lock-On Near Rival",
	"auto_quality":        "Auto Quality (detect GPU on boot)",
	"wall_run_enabled":    "Parkour Wall-Run (sprint into a wall)",
	"water_floor_enabled": "Stylized Anime Water Floor",
}

const TUNING_DEFAULTS: Dictionary = {
	"enemy_damage": 55.0, "player_damage_mult": 1.0, "posture_damage_mult": 1.0,
	"hitstop_scale": 1.0, "shake_scale": 1.0,
	"parry_window": 0.24, "super_parry_window": 0.09, "combo_grace": 1.4,
	"ko_slowmo_scale": 0.28, "ko_slowmo_time": 0.55, "hurt_vignette": 0.55,
	"dmg_number_size": 1.0,
	"quality_tier": 2, "render_scale": 0.92,
	"sdf_face_softness": 0.06, "vertex_shadow_bias": 0.0, "outline_dist_scale": 0.0,
	"wall_run_speed": 26.0, "wall_run_gravity_scale": 0.15, "wall_kick_force": 18.0,
	"water_wave_height": 0.12,
	"immortal_mode": false, "show_damage_numbers": true,
	"show_combo_counter": true, "auto_lock_on": true,
	"auto_quality": true, "wall_run_enabled": true, "water_floor_enabled": false,
}

# =============================================================================
#  DEVICE QUALITY TIERS
#  The panel can be 120 Hz and the GPU still cannot feed it. Each tier is a
#  complete preset; render_scale is what the tier stamps and what the viewport
#  actually uses, so a user can pick a tier and then fine-tune the one number
#  that matters. msaa: 0 = off, 1 = 2x. debris = simultaneous rubble chunks.
# =============================================================================
const QUALITY_TIERS: Array = [
	{"label": "LOW",   "scale": 0.65, "msaa": 0, "shadow": false, "fog": false, "outline": false, "afterimage": false, "debris": 8},
	{"label": "MID",   "scale": 0.85, "msaa": 0, "shadow": true,  "fog": true,  "outline": true,  "afterimage": false, "debris": 16},
	{"label": "HIGH",  "scale": 0.92, "msaa": 1, "shadow": true,  "fog": true,  "outline": true,  "afterimage": true,  "debris": 28},
	{"label": "ULTRA", "scale": 1.00, "msaa": 1, "shadow": true,  "fog": true,  "outline": true,  "afterimage": true,  "debris": 28},
]

func tier_profile(tier: int) -> Dictionary:
	return QUALITY_TIERS[clampi(tier, 0, QUALITY_TIERS.size() - 1)]

func tier_label(tier: int) -> String:
	return str(tier_profile(tier).get("label", "MID"))

# Pick a tier from the actual GPU, not from the panel refresh rate.
# Adreno 618 (Redmi Note 10 Pro) is a LOW device even though its panel is 120 Hz.
func detect_quality_tier() -> int:
	var adapter: String = RenderingServer.get_video_adapter_name().to_lower()
	var os_name: String = OS.get_name()

	if os_name == "iOS" or adapter.contains("apple m"):
		return 3
	for frag in ["adreno (tm) 7", "adreno (tm) 8", "mali-g7", "mali-g9", "xclipse", "immortalis", "rtx", "radeon rx"]:
		if adapter.contains(frag):
			return 2
	if os_name in ["Linux", "Windows", "macOS"]:
		return 1
	for frag in ["adreno", "mali-g5", "mali-g6", "powervr", "img gpu"]:
		if adapter.contains(frag):
			return 0
	return 1

# A save written by any earlier build can be missing keys, or hold a value of the
# wrong type (a string, a nested dict). Every read and write path funnels through
# here first, because the V4 phone crash was exactly this: load_from_disk() read
# parsed["tuning"] straight out of a pre-V3 profile and aborted PlayerController
# ._ready() mid-way, leaving the camera inside the mesh.
func ensure_tuning(src: Dictionary = {}) -> void:
	if typeof(tuning) != TYPE_DICTIONARY:
		tuning = {}
	for k in TUNING_DEFAULTS.keys():
		if not tuning.has(k):
			tuning[k] = TUNING_DEFAULTS[k]
	for k in src.keys():
		if TUNING_DEFAULTS.has(k) and typeof(src[k]) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
			tuning[k] = src[k]

func quality_tier_index() -> int:
	var v = tuning.get("quality_tier", 2)
	if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
		return clampi(int(round(float(v))), 0, QUALITY_TIERS.size() - 1)
	return 2

# Auto mode stamps the detected tier at boot. Turning the box off keeps whatever
# the user picked, which is the whole point of having the box.
func refresh_auto_quality(stamp_scale: bool = true) -> void:
	ensure_tuning()
	if not tuning_bool("auto_quality", true):
		return
	tuning["quality_tier"] = detect_quality_tier()
	if stamp_scale:
		tuning["render_scale"] = float(tier_profile(quality_tier_index())["scale"])

func _ready() -> void:
	refresh_auto_quality()

var tuning: Dictionary = TUNING_DEFAULTS.duplicate(true)

func tuning_get(key: String, fallback: float = 0.0) -> float:
	var v = tuning.get(key, TUNING_DEFAULTS.get(key, fallback))
	if typeof(v) == TYPE_BOOL:
		return 1.0 if v else 0.0
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return float(v)
	return fallback

func tuning_bool(key: String, fallback: bool = false) -> bool:
	var v = tuning.get(key, TUNING_DEFAULTS.get(key, fallback))
	if typeof(v) == TYPE_BOOL:
		return v
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return float(v) > 0.5
	return fallback

func reset_tuning() -> void:
	tuning = TUNING_DEFAULTS.duplicate(true)

var profiles: Dictionary = {
	"Profile_1": {
		"max_hp": 1000.0, "hp_regen": 15.0, "max_mana": 100.0, "mana_regen": 14.0,
		"physical_strength": 1.0, "base_power": 1.0, "step_mult": 1.15,
		"dash_style": 0, "afterimage_on": false, "aura_color": [0.95, 0.12, 0.18],
		"model_path": "res://models/hero.glb", "char_height": 1.0, "char_width": 1.0, "weapon_scale": 1.0, "slot_head": "HERO", "slot_veil": "HERO", "slot_upper": "HERO", "slot_lower": "HERO", "slot_weapon": "HERO"
	},
	"Profile_2": {
		"max_hp": 1350.0, "hp_regen": 20.0, "max_mana": 90.0, "mana_regen": 10.0,
		"physical_strength": 1.3, "base_power": 1.0, "step_mult": 1.0,
		"dash_style": 4, "afterimage_on": false, "aura_color": [0.85, 0.15, 0.25],
		"model_path": "res://models/boss_veil.glb", "char_height": 1.08, "char_width": 0.95, "weapon_scale": 1.15, "slot_head": "VEIL", "slot_veil": "VEIL", "slot_upper": "VEIL", "slot_lower": "VEIL", "slot_weapon": "VEIL"
	},
	"Profile_3": {
		"max_hp": 1100.0, "hp_regen": 16.0, "max_mana": 120.0, "mana_regen": 15.0,
		"physical_strength": 1.15, "base_power": 1.15, "step_mult": 1.35,
		"dash_style": 2, "afterimage_on": true, "aura_color": [1.0, 0.78, 0.15],
		"model_path": "res://models/hero.glb", "char_height": 0.94, "char_width": 1.05, "weapon_scale": 1.25, "slot_head": "VEIL", "slot_veil": "HERO", "slot_upper": "HERO", "slot_lower": "VEIL", "slot_weapon": "HERO"
	},
	"Profile_4": {
		"max_hp": 900.0, "hp_regen": 12.0, "max_mana": 160.0, "mana_regen": 20.0,
		"physical_strength": 0.95, "base_power": 1.45, "step_mult": 1.2,
		"dash_style": 5, "afterimage_on": false, "aura_color": [0.2, 0.9, 0.75],
		"model_path": "res://models/boss_veil.glb", "char_height": 1.04, "char_width": 0.92, "weapon_scale": 1.0, "slot_head": "HERO", "slot_veil": "VEIL", "slot_upper": "VEIL", "slot_lower": "HERO", "slot_weapon": "VEIL"
	}
}

var move_slots: Dictionary = {
	"Slot_1_Up": {"dir": "UP", "step_force": 14.0, "lunge_force": 18.0, "vertical_lift": 13.5, "dmg": 95.0, "posture": 45.0, "knockback": 6.0, "launch_y": 13.5, "roll_deg": 90.0},
	"Slot_2_Down": {"dir": "DOWN", "step_force": 12.0, "lunge_force": 22.0, "vertical_lift": -16.0, "dmg": 130.0, "posture": 65.0, "knockback": 10.0, "launch_y": -14.0, "roll_deg": -90.0},
	"Slot_3_Left": {"dir": "LEFT", "step_force": 16.0, "lunge_force": 16.0, "vertical_lift": 1.5, "dmg": 85.0, "posture": 35.0, "knockback": 5.0, "launch_y": 1.5, "roll_deg": 180.0},
	"Slot_4_Right": {"dir": "RIGHT", "step_force": 16.0, "lunge_force": 16.0, "vertical_lift": 1.5, "dmg": 85.0, "posture": 35.0, "knockback": 5.0, "launch_y": 1.5, "roll_deg": 0.0},
	"Slot_5_Diag_UL": {"dir": "DIAG_UL", "step_force": 15.0, "lunge_force": 20.0, "vertical_lift": 6.0, "dmg": 105.0, "posture": 50.0, "knockback": 8.0, "launch_y": 6.0, "roll_deg": 135.0},
	"Slot_6_Diag_UR": {"dir": "DIAG_UR", "step_force": 15.0, "lunge_force": 20.0, "vertical_lift": 6.0, "dmg": 105.0, "posture": 50.0, "knockback": 8.0, "launch_y": 6.0, "roll_deg": 45.0},
	"Slot_7_Burst": {"dir": "DIAG_DL", "step_force": 18.0, "lunge_force": 26.0, "vertical_lift": 0.0, "dmg": 140.0, "posture": 80.0, "knockback": 22.0, "launch_y": 4.0, "roll_deg": -35.0},
	"Slot_8_Counter": {"dir": "COUNTER", "step_force": 0.0, "lunge_force": 14.0, "vertical_lift": 2.0, "dmg": 190.0, "posture": 120.0, "knockback": 16.0, "launch_y": 5.0, "roll_deg": 20.0}
}

var spell_slots: Dictionary = {
	"Spell_Slot_1": {"sequence": "UP,UP", "step_force": 20.0, "vertical_hop": 4.5, "dmg": 145.0, "posture": 60.0, "proj_speed": 48.0, "color": [0.95, 0.15, 0.2]},
	"Spell_Slot_2": {"sequence": "LEFT,RIGHT,UP", "step_force": 24.0, "vertical_hop": 6.0, "dmg": 185.0, "posture": 85.0, "proj_speed": 56.0, "color": [1.0, 0.78, 0.15]},
	"Spell_Slot_3": {"sequence": "DOWN,UP", "step_force": 18.0, "vertical_hop": 14.0, "dmg": 165.0, "posture": 95.0, "proj_speed": 40.0, "color": [0.9, 0.1, 0.35]},
	"Spell_Slot_4": {"sequence": "LEFT,LEFT", "step_force": 28.0, "vertical_hop": 3.0, "dmg": 120.0, "posture": 50.0, "proj_speed": 62.0, "color": [0.25, 0.85, 1.0]},
	"Spell_Slot_5": {"sequence": "RIGHT,RIGHT", "step_force": 28.0, "vertical_hop": 3.0, "dmg": 120.0, "posture": 50.0, "proj_speed": 62.0, "color": [0.25, 0.85, 1.0]},
	"Spell_Slot_6": {"sequence": "DOWN,LEFT,UP", "step_force": 22.0, "vertical_hop": 9.0, "dmg": 220.0, "posture": 110.0, "proj_speed": 52.0, "color": [0.95, 0.92, 0.88]}
}

var placed_blocks: Array = []

func save_to_disk(player: Node, combat: Node = null) -> void:
	ensure_tuning()
	# Read the old file first: world_story.gd writes its own "story" section into
	# the same profile, and a blind overwrite would delete every saved choice.
	var payload: Dictionary = {}
	if FileAccess.file_exists(SAVE_PATH):
		var old_f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if old_f:
			var old = JSON.parse_string(old_f.get_as_text())
			if typeof(old) == TYPE_DICTIONARY:
				payload = (old as Dictionary).duplicate(true)
	payload["profiles"] = profiles
	payload["move_slots"] = move_slots
	payload["spell_slots"] = spell_slots
	payload["placed_blocks"] = placed_blocks
	payload["tuning"] = tuning
	payload["player_tunables"] = {}
	payload["combat_tunables"] = {}
	if combat:
		for prop in ["ai_telegraph_time", "ai_attack_cooldown", "ai_adaptation_rate", "auto_lock_enabled"]:
			payload["combat_tunables"][prop] = combat.get(prop)
	if player:
		for prop in [
			"run_speed", "sprint_speed", "dash_speed", "dash_duration", "dash_cooldown",
			"jump_velocity", "air_combo_gravity_scale", "camera_distance", "camera_offset_x",
			"camera_offset_y", "camera_pitch_bias", "base_fov", "anim_step_fps",
			"cel_cut_threshold", "hatch_width", "outline_width", "rim_strength",
			"afterimage_enabled", "char_height", "char_width", "weapon_scale", "jiggle_stiffness", "jiggle_damping", "jiggle_gravity", "slot_head", "slot_veil", "slot_upper", "slot_lower", "slot_weapon", "eye_shape", "eye_hue", "eye_pupil_scale", "eye_glow_strength", "ragdoll_bouncy"
		]:
			payload["player_tunables"][prop] = player.get(prop)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(payload, "\t"))

func load_from_disk(player: Node, combat: Node = null) -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f: return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY: return
	var doc: Dictionary = parsed
	# Every branch below is type-checked. A hand-edited or pre-V3 profile must
	# degrade to defaults, never abort _ready() with a key/type error.
	if typeof(doc.get("profiles", null)) == TYPE_DICTIONARY and not (doc["profiles"] as Dictionary).is_empty():
		profiles = doc["profiles"]
	if typeof(doc.get("move_slots", null)) == TYPE_DICTIONARY and not (doc["move_slots"] as Dictionary).is_empty():
		move_slots = doc["move_slots"]
	if typeof(doc.get("spell_slots", null)) == TYPE_DICTIONARY and not (doc["spell_slots"] as Dictionary).is_empty():
		spell_slots = doc["spell_slots"]
	if typeof(doc.get("placed_blocks", null)) == TYPE_ARRAY:
		placed_blocks = doc["placed_blocks"]
	# Build the tuning dict from defaults, then overlay only keys this build knows
	# and only values whose type we can actually use.
	var saved_tuning: Dictionary = {}
	if typeof(doc.get("tuning", null)) == TYPE_DICTIONARY:
		saved_tuning = doc["tuning"]
	tuning = TUNING_DEFAULTS.duplicate(true)
	ensure_tuning(saved_tuning)
	# Auto quality: re-detect the GPU, but never throw away a render scale the
	# user set by hand in an earlier session.
	refresh_auto_quality(not saved_tuning.has("render_scale"))
	if combat and typeof(doc.get("combat_tunables", null)) == TYPE_DICTIONARY:
		var ct: Dictionary = doc["combat_tunables"]
		for k in ct.keys():
			combat.set(k, ct[k])
	if player and typeof(doc.get("player_tunables", null)) == TYPE_DICTIONARY:
		var pt: Dictionary = doc["player_tunables"]
		for k in pt.keys():
			player.set(k, pt[k])
