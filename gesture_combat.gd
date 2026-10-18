class_name GestureCombat extends Node

## Zero-Allocation Kinetic Gesture Combat Engine

# --- Mana / Touki Meter ---
@export var max_mana: float = 100.0
@export var mana_regen: float = 12.0
var mana: float = 100.0

# --- Combat States ---
var combat_state: String = "IDLE"
var combo_chain_count: int = 0
var last_action_time: float = 0.0
var input_tape: Array[String] = []

# --- Gesture Tracking ---
var left_press_time: float = -1.0
var right_press_time: float = -1.0
var right_start_pos: Vector2 = Vector2.ZERO
var right_current_pos: Vector2 = Vector2.ZERO
var is_right_dragging: bool = false
var gesture_segments: Array[Vector2] = []
var feint_threshold_px: float = 95.0
var attack_step_force: float = 14.0
var attack_lunge_force: float = 24.0

# --- Zero-Allocation Physics Query Cache ---
var hitbox_shape: BoxShape3D
var hitbox_query: PhysicsShapeQueryParameters3D

@onready var player: PlayerController = get_parent() as PlayerController


func _ready() -> void:
	# Pre-allocate collision shape & query parameters to guarantee 0 GC pressure
	hitbox_shape = BoxShape3D.new()
	hitbox_shape.size = Vector3(2.6, 2.6, 4.2)

	hitbox_query = PhysicsShapeQueryParameters3D.new()
	hitbox_query.shape_rid = hitbox_shape.get_rid()
	hitbox_query.collision_mask = 1
	hitbox_query.collide_with_bodies = true
	hitbox_query.collide_with_areas = true


func _process(delta: float) -> void:
	# Continuous Mana Regeneration
	mana = minf(mana + mana_regen * delta, max_mana)

	# Combo Chain Reset Timer (> 0.45s)
	var now = Time.get_ticks_msec() / 1000.0
	if now - last_action_time > 0.45 and combo_chain_count > 0:
		combo_chain_count = 0


func handle_input(event: InputEvent) -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var half_width = viewport_size.x * 0.5

	# 1. Mobile Screen Touch (Dual-Thumb & Right-Screen Combat)
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < half_width:
				left_press_time = Time.get_ticks_msec() / 1000.0
			else:
				right_press_time = Time.get_ticks_msec() / 1000.0
				_on_right_press(event.position)

			# Dual-Thumb Super Parry / Combo Breaker (< 0.065s window)
			if absf(left_press_time - right_press_time) < 0.065:
				_trigger_super_parry()
		else:
			if event.position.x >= half_width and is_right_dragging:
				_on_right_release(event.position)

	elif event is InputEventScreenDrag and event.position.x >= half_width:
		_on_right_drag(event.position)

	# 2. PC Mouse Combat (Hold Right Click + Drag for Kinetic Swipes)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			right_press_time = Time.get_ticks_msec() / 1000.0
			var start_pt = event.position
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				start_pt = viewport_size * 0.5
			_on_right_press(start_pt)
		else:
			if is_right_dragging:
				_on_right_release(right_current_pos)

	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and is_right_dragging:
		var new_pos = right_current_pos + event.relative
		_on_right_drag(new_pos)


func _on_right_press(pos: Vector2) -> void:
	right_start_pos = pos
	right_current_pos = pos
	is_right_dragging = true
	combat_state = "PARRY"
	gesture_segments.clear()
	gesture_segments.push_back(pos)

	# 0.18s hold stance transition
	get_tree().create_timer(0.18).timeout.connect(func():
		if is_right_dragging and combat_state == "PARRY":
			var d = right_start_pos.distance_to(right_current_pos)
			if d < 30.0:
				combat_state = "HOLD_GUARD"
				_log_input("GUARD STANCE")
	)


func _on_right_drag(current_pos: Vector2) -> void:
	right_current_pos = current_pos
	var dist = right_start_pos.distance_to(current_pos)

	# Zone 1 (30px to feint_threshold_px): Initiation & Stepping Windup
	if dist > 30.0 and (combat_state == "PARRY" or combat_state == "HOLD_GUARD"):
		var is_stance_break = (combat_state == "HOLD_GUARD")
		combat_state = "WINDUP"
		var dir_2d = (current_pos - right_start_pos).normalized()
		var step_mult = 1.8 if is_stance_break else 1.0
		if player:
			player.apply_combat_impulse(_screen_to_world(dir_2d) * (attack_step_force * step_mult))

	# Zone 3 (> feint_threshold_px): Full Commit Strike
	if combat_state == "WINDUP" and dist > feint_threshold_px:
		combat_state = "COMMIT"
		var stroke_dir = (current_pos - right_start_pos).normalized()
		_execute_strike(stroke_dir)

	# Inflection Hook Detection (<, >, V, ^, Z)
	if dist > 50.0 and gesture_segments.size() > 1:
		var cur_step = (current_pos - gesture_segments[-1]).normalized()
		var prev_step = (gesture_segments[-1] - gesture_segments[-2]).normalized()
		if prev_step.dot(cur_step) < 0.35:
			_log_input("HOOK MIX-UP")
			if player:
				player.add_trauma(0.35)

	gesture_segments.push_back(current_pos)


func _on_right_release(release_pos: Vector2) -> void:
	var dist = right_start_pos.distance_to(release_pos)

	# Zone 2: Half-Swipe Feint
	if combat_state == "WINDUP" and dist < feint_threshold_px:
		_trigger_feint()
	elif combat_state == "HOLD_GUARD":
		_log_input("STANCE STRIKE")
		if player:
			player.apply_combat_impulse(-player.global_transform.basis.z * 30.0)
			_perform_hitbox_check()

	combat_state = "IDLE"
	is_right_dragging = false


func _trigger_super_parry() -> void:
	mana = minf(mana + 25.0, max_mana)
	if player:
		player.apply_hitstop(0.12)
		player.add_trauma(1.0)
	_log_input("SUPER PARRY!")


func _trigger_feint() -> void:
	combat_state = "FEINT"
	_log_input("FEINT!")
	if player:
		player.add_trauma(0.12)


func _execute_strike(dir_2d: Vector2) -> void:
	var world_dir = _screen_to_world(dir_2d)
	if player:
		player.apply_combat_impulse(world_dir * attack_lunge_force)
		player.add_trauma(0.4)
	_log_input("STRIKE [%s]" % _classify_8way_direction(dir_2d))
	_perform_hitbox_check()


func _perform_hitbox_check() -> void:
	if not player:
		return

	var space_state = player.get_world_3d().direct_space_state
	# Position pre-allocated shape query 2.5m in front of the player
	hitbox_query.transform = player.global_transform.translated_local(Vector3(0, 1.0, -2.5))

	var results = space_state.intersect_shape(hitbox_query, 8)
	for res in results:
		var collider = res.collider as Node
		if collider and collider.is_in_group("lock_on_targets"):
			_on_hit_target(collider)


func _on_hit_target(_target: Node) -> void:
	combo_chain_count += 1
	last_action_time = Time.get_ticks_msec() / 1000.0
	if player:
		player.apply_hitstop(0.08)
		player.add_trauma(0.5)

	if combo_chain_count >= 3:
		mana = minf(mana + 20.0, max_mana)
		_log_input("COMBO BURST (+20 Mana)")
		if player:
			player.add_trauma(0.8)


func _classify_8way_direction(dir: Vector2) -> String:
	var angle = rad_to_deg(atan2(dir.y, dir.x))
	if angle >= -22.5 and angle < 22.5: return "RIGHT"
	elif angle >= 22.5 and angle < 67.5: return "DOWN-RIGHT"
	elif angle >= 67.5 and angle < 112.5: return "DOWN"
	elif angle >= 112.5 and angle < 157.5: return "DOWN-LEFT"
	elif angle >= -67.5 and angle < -22.5: return "UP-RIGHT"
	elif angle >= -112.5 and angle < -67.5: return "UP"
	elif angle >= -157.5 and angle < -112.5: return "UP-LEFT"
	else: return "LEFT"


func _screen_to_world(dir_2d: Vector2) -> Vector3:
	var cam = get_viewport().get_camera_3d()
	if not cam:
		return -player.global_transform.basis.z if player else Vector3.FORWARD
	var basis = cam.global_transform.basis
	var forward = Vector3(basis.z.x, 0.0, basis.z.z).normalized()
	var right = Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	return (right * dir_2d.x + forward * dir_2d.y).normalized()


func _log_input(msg: String) -> void:
	input_tape.push_front(msg)
	if input_tape.size() > 6:
		input_tape.pop_back()
