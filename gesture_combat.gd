class_name GestureCombat
extends Node

enum AIMode { STATIC_BAG, FEINT_TESTER, COMBO_ATTACKER, ADAPTIVE_RIVAL }

# --- AssistiveTouch Dots ---
var left_dot_pos: Vector2 = Vector2.ZERO
var right_dot_pos: Vector2 = Vector2.ZERO
var left_dot_expanded_r: float = 125.0
var right_dot_expanded_r: float = 145.0
var is_left_dot_active: bool = false
var is_right_dot_active: bool = false
var right_dot_pinned: bool = false
var auto_lock_enabled: bool = true

# --- Combat Engine ---
var action_table: Dictionary = {
	"STRIKE_UP": { "step_force": 12.0, "lunge_force": 14.0, "dmg": 85, "anim": "Slash_Up" },
	"STRIKE_DOWN": { "step_force": 10.0, "lunge_force": 16.0, "dmg": 110, "anim": "Slash_Down" },
	"SUPER_PARRY": { "step_force": 0.0, "lunge_force": 8.0, "dmg": 220, "anim": "Counter" }
}
var vfx_table: Dictionary = {}
var vfx_pool: Array[Node3D] = []

# --- AI & Habit Memory ---
var ai_mode: AIMode = AIMode.ADAPTIVE_RIVAL
var player_habits: Dictionary = {}
var ai_reaction_delay: float = 0.16
var ai_adaptation_rate: float = 0.30

# --- State ---
var touch_start: Vector2 = Vector2.ZERO
var gesture_segments: Array[Vector2] = []
var lock_target: Node3D = null
var impact_flash_timer: float = 0.0

@onready var player: PlayerController = get_node("../Player")

func _ready() -> void:
	var vp = get_viewport().size
	left_dot_pos = Vector2(vp.x * 0.18, vp.y * 0.42)
	right_dot_pos = Vector2(vp.x * 0.82, vp.y * 0.68)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.distance_to(right_dot_pos) < 34.0:
				is_right_dot_active = true; touch_start = event.position
				if auto_lock_enabled: _try_auto_lock()
			elif event.position.distance_to(left_dot_pos) < 32.0:
				is_left_dot_active = true; player.is_momentum_coasting = true
		else:
			if is_right_dot_active: _evaluate_right_release(event.position)
			if is_left_dot_active: is_left_dot_active = false; player.is_momentum_coasting = false
	elif event is InputEventScreenDrag:
		if is_right_dot_active:
			if gesture_segments.is_empty() or event.position.distance_to(gesture_segments[-1]) > 24.0:
				gesture_segments.append(event.position)

func _try_auto_lock() -> void:
	var targets = get_tree().get_nodes_in_group("lock_on_targets")
	var best = null; var min_d = 65.0
	for t in targets:
		var d = player.global_position.distance_to(t.global_position)
		if d < min_d: min_d = d; best = t
	lock_target = best

func _evaluate_right_release(pos: Vector2) -> void:
	is_right_dot_active = false
	var dist = pos.distance_to(touch_start)
	if dist < 30.0: _commit_strike("PERFECT_PARRY")
	elif dist < player.feint_threshold_px: _trigger_feint()
	else: _evaluate_swipe(pos - touch_start)
	gesture_segments.clear()

func _evaluate_swipe(delta: Vector2) -> void:
	var dir = delta.normalized(); var mk = "STRIKE_RIGHT"
	if dir.y < -0.7: mk = "STRIKE_UP"
	elif dir.y > 0.7: mk = "STRIKE_DOWN"
	_commit_strike(mk)

func _commit_strike(key: String) -> void:
	if not action_table.has(key): return
	var data = action_table[key]
	if player: player.velocity += (-player.global_transform.basis.z * data["lunge_force"])
	_record_habit(key)

func _trigger_feint() -> void: pass 

func _record_habit(key: String) -> void:
	player_habits[key] = player_habits.get(key, 0.0) + ai_adaptation_rate
	if player_habits[key] > 0.75: _ai_counter_vanish()

func _ai_counter_vanish() -> void: pass 

func simulate_clash(is_super: bool) -> void:
	if is_super: impact_flash_timer = 0.055

func _process(delta: float) -> void:
	if impact_flash_timer > 0: impact_flash_timer -= delta
