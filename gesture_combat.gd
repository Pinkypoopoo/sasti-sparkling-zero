class_name GestureCombat
extends Node

enum AIMode { STATIC_BAG, FEINT_TESTER, COMBO_ATTACKER, ADAPTIVE_RIVAL }

const ELEMENTS: Array[String] = ["FIRE", "WIND", "LIGHTNING", "WATER", "EARTH"]
const ELEMENT_COLORS: Array[Color] = [
	Color(1.0, 0.28, 0.12), Color(0.2, 0.92, 0.65), Color(0.98, 0.88, 0.15),
	Color(0.18, 0.6, 1.0), Color(0.85, 0.52, 0.18)
]

var left_dot_ratio: Vector2 = Vector2(0.18, 0.56)
var right_dot_ratio: Vector2 = Vector2(0.82, 0.64)
var left_dot_pos: Vector2 = Vector2.ZERO
var right_dot_pos: Vector2 = Vector2.ZERO
var left_dot_collapsed_r: float = 44.0
var right_dot_collapsed_r: float = 48.0
var left_dot_expanded_r: float = 135.0
var right_dot_expanded_r: float = 145.0

var is_left_dot_active: bool = false
var is_right_dot_active: bool = false
var right_dot_pinned: bool = false
var auto_lock_enabled: bool = true

var right_touch_id: int = -1
var left_weave_touch_id: int = -1
var right_touch_start: Vector2 = Vector2.ZERO
var right_touch_current: Vector2 = Vector2.ZERO
var left_weave_start: Vector2 = Vector2.ZERO
var left_weave_current: Vector2 = Vector2.ZERO
var left_press_time: float = -10.0
var right_press_time: float = -10.0

var selected_element_1: int = -1
var selected_element_2: int = -1
var active_infusion: String = "NONE"
var active_element: String = "NONE"
var infusion_timer: float = 0.0
var last_combat_action: String = "READY"

var action_table: Dictionary = {
	"STRIKE_UP": {"step_force": 12.0, "lunge_force": 16.0, "vertical_lift": 6.0, "dmg": 95.0, "posture": 40.0, "anim": "Slash_Up", "vfx": "NONE"},
	"STRIKE_DOWN": {"step_force": 10.0, "lunge_force": 18.0, "vertical_lift": -8.0, "dmg": 125.0, "posture": 60.0, "anim": "Helm_Splitter", "vfx": "NONE"},
	"STRIKE_LEFT": {"step_force": 14.0, "lunge_force": 15.0, "vertical_lift": 0.0, "dmg": 85.0, "posture": 35.0, "anim": "Slash_Left", "vfx": "NONE"},
	"STRIKE_RIGHT": {"step_force": 14.0, "lunge_force": 15.0, "vertical_lift": 0.0, "dmg": 85.0, "posture": 35.0, "anim": "Slash_Right", "vfx": "NONE"},
	"STRIKE_DIAG": {"step_force": 14.0, "lunge_force": 16.0, "vertical_lift": 3.0, "dmg": 100.0, "posture": 45.0, "anim": "Diag_Slash", "vfx": "NONE"},
	"SUPER_PARRY": {"step_force": 0.0, "lunge_force": 10.0, "vertical_lift": 0.0, "dmg": 220.0, "posture": 140.0, "anim": "Counter", "vfx": "NONE"}
}

var target_stats: Dictionary = {}
var player_habits: Dictionary = {}
var ai_mode: AIMode = AIMode.ADAPTIVE_RIVAL
var ai_reaction_delay: float = 0.16
var ai_adaptation_rate: float = 0.30
var parry_window_timer: float = 0.0
var impact_flash_timer: float = 0.0
var impact_frame_cooldown: float = 0.0
var clash_tension: int = 0

@onready var player: PlayerController = get_node_or_null("../Player") as PlayerController

func _ready() -> void:
	_update_dot_positions()
	get_viewport().size_changed.connect(_update_dot_positions)
	_init_targets()

func _update_dot_positions() -> void:
	var vp := get_viewport().get_visible_rect().size
	left_dot_pos = Vector2(vp.x * left_dot_ratio.x, vp.y * left_dot_ratio.y)
	right_dot_pos = Vector2(vp.x * right_dot_ratio.x, vp.y * right_dot_ratio.y)

func _init_targets() -> void:
	target_stats.clear()
	for t in get_tree().get_nodes_in_group("lock_on_targets"):
		if t is Node3D:
			target_stats[t] = {
				"hp": 1500.0, "max_hp": 1500.0,
				"posture": 0.0, "max_posture": 300.0,
				"hit_flash": 0.0, "ai_state": "IDLE", "whiff_timer": 0.0
			}

func is_point_in_right_dot(pos: Vector2) -> bool:
	var r := right_dot_expanded_r if (is_right_dot_active or right_dot_pinned) else right_dot_collapsed_r * 1.45
	return pos.distance_to(right_dot_pos) <= r

func is_point_in_left_dot(pos: Vector2) -> bool:
	var r := left_dot_expanded_r if is_left_dot_active else left_dot_collapsed_r * 1.45
	return pos.distance_to(left_dot_pos) <= r

func _input(event: InputEvent) -> void:
	_update_dot_positions()

	# Mobile Touchscreen Support
	if event is InputEventScreenTouch:
		if event.pressed:
			if is_point_in_right_dot(event.position) and right_touch_id == -1:
				right_touch_id = event.index
				right_press_time = Time.get_ticks_msec() / 1000.0
				_start_right_orb(event.position)
				if absf(right_press_time - left_press_time) <= 0.08:
					_trigger_super_parry()
			elif is_point_in_left_dot(event.position) and left_weave_touch_id == -1:
				left_weave_touch_id = event.index
				left_press_time = Time.get_ticks_msec() / 1000.0
				_start_left_orb(event.position)
				if absf(right_press_time - left_press_time) <= 0.08:
					_trigger_super_parry()
		else:
			if event.index == right_touch_id:
				_release_right_orb(event.position)
				right_touch_id = -1
			elif event.index == left_weave_touch_id:
				_release_left_orb(event.position)
				left_weave_touch_id = -1

	elif event is InputEventScreenDrag:
		if event.index == right_touch_id:
			_drag_right_orb(event.position)
		elif event.index == left_weave_touch_id:
			_drag_left_orb(event.position)

	# PC Mouse Support for testing orbs directly on laptop
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		var m_pos: Vector2 = event.position
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			m_pos = right_dot_pos
		if event.pressed:
			_start_right_orb(m_pos)
		else:
			_release_right_orb(right_touch_current)
	elif event is InputEventMouseMotion and is_right_dot_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_drag_right_orb(right_touch_current + event.relative)

func _start_right_orb(pos: Vector2) -> void:
	is_right_dot_active = true
	right_touch_start = pos
	right_touch_current = pos
	parry_window_timer = 0.18
	last_combat_action = "ORB_OPEN"
	if auto_lock_enabled and player and not player.is_locked_on:
		player.toggle_lock_on()

func _drag_right_orb(pos: Vector2) -> void:
	right_touch_current = pos
	var dist := right_touch_start.distance_to(pos)
	if dist >= 30.0 and player and player.state != PlayerController.MoveState.WINDUP:
		player.state = PlayerController.MoveState.WINDUP
		var d2 := (pos - right_touch_start).normalized()
		var cf := -player.camera.global_transform.basis.z; cf.y = 0.0; cf = cf.normalized()
		var cr := player.camera.global_transform.basis.x; cr.y = 0.0; cr = cr.normalized()
		player.velocity += (cr * d2.x + cf * -d2.y).normalized() * 12.0

func _release_right_orb(pos: Vector2) -> void:
	var dist := pos.distance_to(right_touch_start)
	# Tap on dot: toggle stays open so user can inspect or swipe next!
	if dist < 24.0:
		if parry_window_timer > 0.0:
			_trigger_parry()
		right_dot_pinned = not right_dot_pinned
		is_right_dot_active = right_dot_pinned
		if player: player.state = PlayerController.MoveState.GROUND
		return

	is_right_dot_active = right_dot_pinned
	var feint_r := player.feint_threshold_px if player else 90.0
	if dist < feint_r:
		_trigger_feint()
	else:
		_commit_strike((pos - right_touch_start).normalized())
	if player: player.state = PlayerController.MoveState.GROUND

func _start_left_orb(pos: Vector2) -> void:
	is_left_dot_active = true
	left_weave_start = pos
	left_weave_current = pos
	if player: player.is_momentum_coasting = true
	_check_pentagon_node(pos)

func _drag_left_orb(pos: Vector2) -> void:
	left_weave_current = pos
	_check_pentagon_node(pos)

func _release_left_orb(pos: Vector2) -> void:
	var dist := pos.distance_to(left_weave_start)
	if selected_element_1 >= 0:
		active_infusion = ELEMENTS[selected_element_1] if selected_element_2 < 0 else active_element
		infusion_timer = 12.0
		last_combat_action = "WEAVE: " + active_infusion
		if player:
			player.update_cel_shader(player.cel_cut_threshold, player.outline_width, player.rim_strength, ELEMENT_COLORS[selected_element_1])
		if dist > 60.0 and player and player.is_locked_on and is_instance_valid(player.lock_target):
			apply_damage(player.lock_target, 160.0 * player.base_power, 65.0)
	selected_element_1 = -1
	selected_element_2 = -1
	is_left_dot_active = false
	if player: player.is_momentum_coasting = false

func get_pentagon_node_pos(idx: int) -> Vector2:
	var a := -PI * 0.5 + float(idx) * (TAU / 5.0)
	return left_dot_pos + Vector2(cos(a), sin(a)) * (left_dot_expanded_r * 0.72)

func _check_pentagon_node(pos: Vector2) -> void:
	for i in range(5):
		if pos.distance_to(get_pentagon_node_pos(i)) <= 42.0:
			if selected_element_1 == -1:
				selected_element_1 = i
			elif selected_element_2 == -1 and i != selected_element_1:
				selected_element_2 = i
				active_element = ELEMENTS[selected_element_1] + "+" + ELEMENTS[selected_element_2]

func _trigger_parry() -> void:
	last_combat_action = "PERFECT PARRY"
	simulate_clash(false)

func _trigger_super_parry() -> void:
	last_combat_action = "SUPER PARRY!"
	if player:
		player.state = PlayerController.MoveState.GROUND
		player.mana = minf(player.max_mana, player.mana + 25.0)
	simulate_clash(true)

func _trigger_feint() -> void:
	last_combat_action = "HALF-SWIPE FEINT!"
	for t in target_stats.keys():
		target_stats[t]["ai_state"] = "BAITED_WHIFF!"
		target_stats[t]["whiff_timer"] = 0.85

func _commit_strike(dir: Vector2) -> void:
	var move := "STRIKE_RIGHT"
	if dir.y < -0.65: move = "STRIKE_UP"
	elif dir.y > 0.65: move = "STRIKE_DOWN"
	elif dir.x < -0.65: move = "STRIKE_LEFT"
	elif absf(dir.x) > 0.35 and absf(dir.y) > 0.35: move = "STRIKE_DIAG"

	if not action_table.has(move): move = "STRIKE_RIGHT"
	var data: Dictionary = action_table[move]
	last_combat_action = move

	if player:
		var fwd := -player.global_transform.basis.z
		if player.is_locked_on and is_instance_valid(player.lock_target):
			fwd = (player.lock_target.global_position - player.global_position).normalized()
		player.velocity = fwd * data.get("lunge_force", 15.0) + Vector3(0, data.get("vertical_lift", 0.0), 0)

	# Record habit for Adaptive AI
	player_habits[move] = player_habits.get(move, 0.0) + ai_adaptation_rate
	for k in player_habits.keys():
		if k != move: player_habits[k] = maxf(0.0, player_habits[k] - 0.1)

	for t in target_stats.keys():
		if is_instance_valid(t) and player and player.global_position.distance_to(t.global_position) <= 6.5:
			var s: Dictionary = target_stats[t]
			# Adaptive AI spam punish
			if ai_mode == AIMode.ADAPTIVE_RIVAL and player_habits.get(move, 0.0) >= 0.9 and s["whiff_timer"] <= 0.0:
				s["ai_state"] = "AI_PARRY_COUNTER!"
				simulate_clash(false)
				player_habits[move] = 0.0
				return
			var mult := 1.5 if s["whiff_timer"] > 0.0 else 1.0
			apply_damage(t, data.get("dmg", 90.0) * player.physical_strength * mult, data.get("posture", 40.0))

func apply_damage(t: Node3D, dmg: float, post_dmg: float) -> void:
	if not target_stats.has(t): return
	var s: Dictionary = target_stats[t]
	s["hp"] = maxf(0.0, s["hp"] - dmg)
	s["posture"] = minf(s["max_posture"], s["posture"] + post_dmg)
	s["hit_flash"] = 0.14
	if s["hp"] <= 0.0 or s["posture"] >= s["max_posture"]:
		simulate_clash(true)
		s["hp"] = s["max_hp"]
		s["posture"] = 0.0

func simulate_clash(is_super: bool) -> void:
	clash_tension += 1
	if is_super or clash_tension >= 4:
		clash_tension = 0
		if impact_frame_cooldown <= 0.0:
			impact_flash_timer = 0.055
			impact_frame_cooldown = 4.0

func _process(delta: float) -> void:
	if parry_window_timer > 0.0: parry_window_timer -= delta
	if impact_flash_timer > 0.0: impact_flash_timer -= delta
	if impact_frame_cooldown > 0.0: impact_frame_cooldown -= delta
	if infusion_timer > 0.0:
		infusion_timer -= delta
		if infusion_timer <= 0.0: active_infusion = "NONE"
	for t in target_stats.keys():
		if is_instance_valid(t):
			var s: Dictionary = target_stats[t]
			if s["hit_flash"] > 0.0: s["hit_flash"] -= delta
			if s["whiff_timer"] > 0.0:
				s["whiff_timer"] -= delta
				if s["whiff_timer"] <= 0.0: s["ai_state"] = "IDLE"
