class_name CombatData
extends Node

const SAVE_PATH: String = "user://dev_profile.json"

var profiles: Dictionary = {
	"Profile_1": {
		"max_hp": 1000.0, "hp_regen": 15.0, "max_mana": 100.0, "mana_regen": 14.0,
		"physical_strength": 1.0, "base_power": 1.0, "step_mult": 1.15,
		"dash_style": 0, "afterimage_on": false, "aura_color": [0.95, 0.12, 0.18], "model_path": ""
	},
	"Profile_2": {
		"max_hp": 1350.0, "hp_regen": 20.0, "max_mana": 90.0, "mana_regen": 10.0,
		"physical_strength": 1.3, "base_power": 1.0, "step_mult": 1.0,
		"dash_style": 4, "afterimage_on": false, "aura_color": [0.85, 0.15, 0.25], "model_path": ""
	},
	"Profile_3": {
		"max_hp": 1100.0, "hp_regen": 16.0, "max_mana": 120.0, "mana_regen": 15.0,
		"physical_strength": 1.15, "base_power": 1.15, "step_mult": 1.35,
		"dash_style": 2, "afterimage_on": true, "aura_color": [1.0, 0.78, 0.15], "model_path": ""
	},
	"Profile_4": {
		"max_hp": 900.0, "hp_regen": 12.0, "max_mana": 160.0, "mana_regen": 20.0,
		"physical_strength": 0.95, "base_power": 1.45, "step_mult": 1.2,
		"dash_style": 5, "afterimage_on": false, "aura_color": [0.2, 0.9, 0.75], "model_path": ""
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

func save_to_disk(player: Node) -> void:
	var payload := {
		"profiles": profiles,
		"move_slots": move_slots,
		"spell_slots": spell_slots,
		"player_tunables": {}
	}
	if player:
		for prop in [
			"run_speed", "sprint_speed", "dash_speed", "dash_duration", "dash_cooldown",
			"jump_velocity", "air_combo_gravity_scale", "camera_distance", "camera_offset_x",
			"camera_offset_y", "camera_pitch_bias", "base_fov", "anim_step_fps",
			"cel_cut_threshold", "hatch_width", "outline_width", "rim_strength", "afterimage_enabled"
		]:
			payload["player_tunables"][prop] = player.get(prop)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(payload, "\t"))

func load_from_disk(player: Node) -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f: return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY: return
	if parsed.has("profiles"): profiles = parsed["profiles"]
	if parsed.has("move_slots"): move_slots = parsed["move_slots"]
	if parsed.has("spell_slots"): spell_slots = parsed["spell_slots"]
	if player and parsed.has("player_tunables"):
		var pt: Dictionary = parsed["player_tunables"]
		for k in pt.keys():
			player.set(k, pt[k])
