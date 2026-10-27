class_name GestureCombat
extends Node

enum AIMode { STATIC_BAG, FEINT_TESTER, COMBO_ATTACKER, ADAPTIVE_RIVAL }

# --- AssistiveTouch Dots ---
var left_dot_pos: Vector2 = Vector2.ZERO
var right_dot_pos: Vector2 = Vector2.ZERO
var left_dot_expanded_r: float = 135.0
var right_dot_expanded_r: float = 135.0
var is_left_dot_active: bool = false
var is_right_dot_active: bool = false

# --- Combat Engine ---
var action_table: Dictionary = {
	"STRIKE_UP": {"dmg": 95, "posture": 40}, "STRIKE_DOWN": {"dmg": 120, "posture": 60},
	"STRIKE_LEFT": {"dmg": 85, "posture": 35}, "STRIKE_RIGHT": {"dmg": 85, "posture": 35}
}
var target_stats: Dictionary = {}
var parry_window_timer: float = 0.0
var impact_flash_timer: float = 0.0
var ai_mode: AIMode = AIMode.STATIC_BAG

# --- Touch Tracking ---
var right_touch_start: Vector2 = Vector2.ZERO
var right_touch_current: Vector2 = Vector2.ZERO

@onready var player: PlayerController = get_node("../Player")

func _ready() -> void:
	_update_dot_positions()
	get_viewport().size_changed.connect(_update_dot_positions)
	_init_targets()

func _update_dot_positions() -> void:
	var vp = get_viewport().get_visible_rect().size
	left_dot_pos = Vector2(vp.x * 0.18, vp.y * 0.55)
	right_dot_pos = Vector2(vp.x * 0.82, vp.y * 0.65)

func _init_targets() -> void:
	for t in get_tree().get_nodes_in_group("lock_on_targets"):
		if t is Node3D:
			target_stats[t] = {"hp": 1500.0, "max_hp": 1500.0, "posture": 0.0, "max_posture": 300.0, "hit_flash": 0.0}

func is_point_in_right_dot(pos: Vector2) -> bool:
	return pos.distance_to(right_dot_pos) <= (right_dot_expanded_r if is_right_dot_active else 70.0)

func is_point_in_left_dot(pos: Vector2) -> bool:
	return pos.distance_to(left_dot_pos) <= (left_dot_expanded_r if is_left_dot_active else 70.0)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if is_point_in_right_dot(event.position):
				is_right_dot_active = true; right_touch_start = event.position
				right_touch_current = event.position; parry_window_timer = 0.18
				_auto_lock()
			elif is_point_in_left_dot(event.position):
				is_left_dot_active = true; player.is_momentum_coasting = true
		else:
			if is_right_dot_active: _handle_right_release(event.position)
			if is_left_dot_active: is_left_dot_active = false; player.is_momentum_coasting = false

	elif event is InputEventScreenDrag:
		if is_right_dot_active: right_touch_current = event.position

func _auto_lock() -> void:
	var best = null; var min_d = 65.0
	for t in target_stats.keys():
		var d = player.global_position.distance_to(t.global_position)
		if d < min_d: min_d = d; best = t
	combat_lock_to(best)

func combat_lock_to(target: Node3D) -> void:
	if target: player.cam_rot_y = rad_to_deg(atan2(-(target.global_position.x - player.global_position.x), -(target.global_position.z - player.global_position.z)))

func _handle_right_release(pos: Vector2) -> void:
	is_right_dot_active = false
	var dist = pos.distance_to(right_touch_start)
	if dist < 28.0:
		if parry_window_timer > 0.0: _trigger_parry()
		else: _trigger_guard_release()
	elif dist < player.feint_threshold_px: _trigger_feint()
	else: _commit_strike((pos - right_touch_start).normalized())

func _trigger_parry() -> void: pass
func _trigger_guard_release() -> void: pass
func _trigger_feint() -> void: pass

func _commit_strike(dir: Vector2) -> void:
	var move = "STRIKE_RIGHT"
	if dir.y < -0.7: move = "STRIKE_UP"
	elif dir.y > 0.7: move = "STRIKE_DOWN"
	elif dir.x < -0.7: move = "STRIKE_LEFT"
	var best_t = null; var min_d = 4.5
	for t in target_stats.keys():
		var d = player.global_position.distance_to(t.global_position)
		if d < min_d: min_d = d; best_t = t
	if best_t: apply_damage(best_t, action_table[move]["dmg"], action_table[move]["posture"])

func apply_damage(t: Node3D, dmg: float, post_dmg: float) -> void:
	var s = target_stats[t]
	s["hp"] -= dmg; s["posture"] += post_dmg; s["hit_flash"] = 0.12
	if s["hp"] <= 0: impact_flash_timer = 0.055; s["hp"] = s["max_hp"]

func _process(delta: float) -> void:
	if parry_window_timer > 0.0: parry_window_timer -= delta
	if impact_flash_timer > 0.0: impact_flash_timer -= delta
	for t in target_stats.keys():
		if target_stats[t]["hit_flash"] > 0.0: target_stats[t]["hit_flash"] -= delta
