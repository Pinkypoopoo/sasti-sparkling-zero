extends CharacterBody3D

class_name PlayerController

## High-Speed Hybrid Ground + 3D Flight Controller

enum MoveState { NORMAL, SPRINT, STEP, DASH, FLIGHT }

# --- Tunables ---
@export_group("Locomotion")
@export var run_speed: float = 16.0
@export var sprint_speed: float = 28.0
@export var flight_speed: float = 32.0
@export var step_speed: float = 34.0
@export var dash_speed: float = 54.0
@export var dash_duration: float = 0.22
@export var dash_cooldown: float = 0.04
@export var jump_velocity: float = 12.0
@export var altitude_burst: float = 18.0

@export_group("Combat & Juicing")
@export var feint_threshold_px: float = 95.0
@export var attack_step_force: float = 14.0
@export var base_fov: float = 78.0
@export var dash_fov_kick: float = 98.0
@export var shake_intensity: float = 1.0

# --- State ---
var current_state: MoveState = MoveState.NORMAL
var jump_count: int = 0
var state_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var hitstop_timer: float = 0.0
var trauma: float = 0.0
var impulse_vector: Vector3 = Vector3.ZERO

# --- Camera & Look ---
var camera_rot_x: float = 0.0
var camera_rot_y: float = 0.0
var mouse_sensitivity: float = 0.0022
var controller_sensitivity: float = 2.4
var bob_time: float = 0.0

# --- Lock-On Target ---
var is_locked_on: bool = false
var lock_target: Node3D = null

# --- Mobile Left-Screen Touch ---
var touch_left_id: int = -1
var touch_left_start: Vector2 = Vector2.ZERO
var touch_left_current: Vector2 = Vector2.ZERO
var touch_left_time: float = 0.0
var is_left_dragging: bool = false
var last_flick_time: float = -10.0
var last_flick_dir: Vector2 = Vector2.ZERO

# --- Node References ---
@onready var visual_root: Node3D = $VisualRoot
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var combat: GestureCombat = $GestureCombat

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	spring_arm.add_excluded_object(get_rid())
	_register_input_actions()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


func _register_input_actions() -> void:
	var actions = {
		"move_forward": [KEY_W, JOY_AXIS_LEFT_Y, -1.0],
		"move_backward": [KEY_S, JOY_AXIS_LEFT_Y, 1.0],
		"move_left": [KEY_A, JOY_AXIS_LEFT_X, -1.0],
		"move_right": [KEY_D, JOY_AXIS_LEFT_X, 1.0],
		"jump": [KEY_SPACE, JOY_BUTTON_A],
		"dash": [KEY_SHIFT, JOY_BUTTON_B],
		"lock_on": [KEY_Q, JOY_BUTTON_RIGHT_STICK],
		"dev_tab": [KEY_TAB, -1]
	}

	for act in actions:
		if not InputMap.has_action(act):
			InputMap.add_action(act)
			var data = actions[act]
			if data[0] is int and data[0] != -1:
				var key_ev = InputEventKey.new()
				key_ev.keycode = data[0]
				InputMap.action_add_event(act, key_ev)
			if data.size() > 1 and data[1] != -1:
				if act.begins_with("move"):
					var joy_motion = InputEventJoypadMotion.new()
					joy_motion.axis = data[1]
					joy_motion.axis_value = data[2]
					InputMap.action_add_event(act, joy_motion)
				else:
					var joy_btn = InputEventJoypadButton.new()
					joy_btn.button_index = data[1]
					InputMap.action_add_event(act, joy_btn)


func _physics_process(delta: float) -> void:
	# 1. Hitstop Freeze with micro-vibration
	if hitstop_timer > 0.0:
		hitstop_timer -= delta
		visual_root.position = Vector3(
			randf_range(-0.06, 0.06),
			randf_range(-0.06, 0.06),
			randf_range(-0.06, 0.06)
		)
		if hitstop_timer <= 0.0:
			visual_root.position = Vector3.ZERO
		return
	elif visual_root.position != Vector3.ZERO:
		visual_root.position = Vector3.ZERO

	# 2. Timers
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta

	# 3. Grounding & 3-Stage Vertical Escalation
	if is_on_floor():
		jump_count = 0
		if current_state == MoveState.FLIGHT:
			current_state = MoveState.NORMAL

	# 4. Lock-On Orientation
	_process_lock_on(delta)

	# 5. Controller Right Stick Camera Look
	if not is_locked_on:
		var joy_x = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
		var joy_y = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
		if Vector2(joy_x, joy_y).length() > 0.15:
			_rotate_camera(-joy_x * controller_sensitivity * delta, -joy_y * controller_sensitivity * delta)

	# 6. Movement State Machine
	_process_locomotion(delta)

	# 7. Physics execution
	move_and_slide()

	# 8. Procedural Camera & Visual Juice
	_process_juice(delta)


func _process_lock_on(delta: float) -> void:
	if not is_locked_on:
		return

	if not is_instance_valid(lock_target) or not lock_target.is_inside_tree():
		toggle_lock()
		return

	var to_target = lock_target.global_position - camera_pivot.global_position
	var dist = to_target.length()
	if dist > 85.0:
		toggle_lock()
		return

	# Smoothly orient body yaw & camera pitch toward target
	var target_yaw = atan2(-to_target.x, -to_target.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 14.0 * delta)
	camera_rot_y = rotation.y

	var flat_dist = Vector2(to_target.x, to_target.z).length()
	var target_pitch = clampf(atan2(to_target.y, flat_dist), -1.15, 1.15)
	camera_rot_x = lerpf(camera_rot_x, target_pitch, 14.0 * delta)
	camera_pivot.rotation.x = camera_rot_x
	visual_root.rotation.y = 0.0


func _process_locomotion(delta: float) -> void:
	# Gravity in normal locomotion
	if not is_on_floor() and current_state != MoveState.FLIGHT:
		velocity.y -= gravity * delta

	# Gather input direction (Keyboard / Controller / Touch)
	var move_dir = _get_composite_input_direction()

	match current_state:
		MoveState.NORMAL, MoveState.SPRINT:
			var is_sprinting = Input.is_action_pressed("dash") or (is_left_dragging and (touch_left_current - touch_left_start).length() > 70.0)
			current_state = MoveState.SPRINT if is_sprinting else MoveState.NORMAL
			var target_speed = sprint_speed if current_state == MoveState.SPRINT else run_speed

			if move_dir != Vector3.ZERO:
				velocity.x = lerp(velocity.x, move_dir.x * target_speed, 16.0 * delta)
				velocity.z = lerp(velocity.z, move_dir.z * target_speed, 16.0 * delta)
				if not is_locked_on:
					var target_yaw = atan2(-move_dir.x, -move_dir.z)
					visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw - rotation.y, 16.0 * delta)
			else:
				velocity.x = lerp(velocity.x, 0.0, 12.0 * delta)
				velocity.z = lerp(velocity.z, 0.0, 12.0 * delta)

		MoveState.FLIGHT:
			_process_flight_movement(delta, move_dir)

		MoveState.STEP:
			velocity.x = impulse_vector.x * step_speed
			velocity.z = impulse_vector.z * step_speed
			state_timer -= delta
			if state_timer <= 0.0:
				current_state = MoveState.NORMAL

		MoveState.DASH:
			velocity = impulse_vector * dash_speed
			state_timer -= delta
			if state_timer <= 0.0:
				dash_cooldown_timer = dash_cooldown
				# Seamless Hold-to-Sprint or Hold-to-Fly transition!
				var has_active_input = move_dir != Vector3.ZERO or is_left_dragging
				if has_active_input:
					current_state = MoveState.FLIGHT if not is_on_floor() else MoveState.SPRINT
				else:
					current_state = MoveState.NORMAL


func _process_flight_movement(delta: float, move_dir: Vector3) -> void:
	# Gravity is bypassed in 3D Flight
	velocity.y = lerp(velocity.y, 0.0, 6.0 * delta)

	if is_locked_on and is_instance_valid(lock_target):
		# Orbiting & closing distance on horizontal plane
		if move_dir != Vector3.ZERO:
			velocity.x = lerp(velocity.x, move_dir.x * flight_speed, 14.0 * delta)
			velocity.z = lerp(velocity.z, move_dir.z * flight_speed, 14.0 * delta)
		else:
			velocity.x = lerp(velocity.x, 0.0, 10.0 * delta)
			velocity.z = lerp(velocity.z, 0.0, 10.0 * delta)
	else:
		# Free 3D flight along camera pitch & yaw vectors
		var input_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		if is_left_dragging:
			var diff = (touch_left_current - touch_left_start).normalized()
			input_vec = Vector2(diff.x, diff.y)

		if input_vec != Vector2.ZERO:
			var cam_basis = camera.global_transform.basis
			var flight_vector = (cam_basis.x * input_vec.x + cam_basis.z * input_vec.y).normalized()
			velocity = lerp(velocity, flight_vector * flight_speed, 14.0 * delta)
			var target_yaw = atan2(-velocity.x, -velocity.z)
			visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw - rotation.y, 14.0 * delta)
		else:
			velocity = lerp(velocity, Vector3.ZERO, 8.0 * delta)


func _get_composite_input_direction() -> Vector3:
	var input_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	# Mobile Left-Screen Floating Analog overlay
	if is_left_dragging:
		var diff = touch_left_current - touch_left_start
		if diff.length() > 25.0:
			var norm = diff.normalized()
			input_vec = Vector2(norm.x, norm.y)

	if input_vec == Vector2.ZERO:
		return Vector3.ZERO

	var forward = -transform.basis.z
	var right = transform.basis.x
	return (right * input_vec.x + forward * (-input_vec.y)).normalized()


func _screen_dir_to_world(dir_2d: Vector2) -> Vector3:
	var forward = -transform.basis.z
	var right = transform.basis.x
	return (right * dir_2d.x + forward * (-dir_2d.y)).normalized()


func _unhandled_input(event: InputEvent) -> void:
	# Forward to combat engine
	if combat:
		combat.handle_input(event)

	# Mouse Look (Captured Mode)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not is_locked_on:
		_rotate_camera(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)

	# Jump Action
	if event.is_action_pressed("jump"):
		_on_jump()

	# Dash Action
	if event.is_action_pressed("dash"):
		_on_dash()

	# Lock-On Toggle Action
	if event.is_action_pressed("lock_on"):
		toggle_lock()

	# Mobile Left-Screen Touch Handling
	var half_width = get_viewport().get_visible_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		if event.pressed and event.position.x < half_width and touch_left_id == -1:
			touch_left_id = event.index
			touch_left_start = event.position
			touch_left_current = event.position
			touch_left_time = Time.get_ticks_msec() / 1000.0
			is_left_dragging = false
		elif not event.pressed and event.index == touch_left_id:
			_evaluate_left_touch_release(event.position)
			touch_left_id = -1
			is_left_dragging = false

	elif event is InputEventScreenDrag and event.index == touch_left_id:
		touch_left_current = event.position
		if touch_left_start.distance_to(touch_left_current) > 25.0:
			is_left_dragging = true


func _evaluate_left_touch_release(release_pos: Vector2) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	var duration = now - touch_left_time
	var swipe = release_pos - touch_left_start
	var dist = swipe.length()

	# Quick Flick (< 0.22s, > 55px)
	if duration <= 0.22 and dist >= 55.0:
		var dir = swipe.normalized()
		# Flick Up -> High Jump / Leap / Ascend
		if dir.y < -0.65:
			_on_jump()
			return

		var world_dir = _screen_dir_to_world(dir)
		var is_double = (now - last_flick_time) <= 0.35 and dir.dot(last_flick_dir) > 0.4
		if is_double:
			_start_dash(world_dir)
			last_flick_time = -10.0
		else:
			_start_step(world_dir)
			last_flick_dir = dir
			last_flick_time = now


func _on_jump() -> void:
	if current_state == MoveState.FLIGHT:
		# Altitude shift in flight
		velocity.y = altitude_burst
		add_trauma(0.2)
		return

	jump_count += 1
	if jump_count == 1:
		velocity.y = jump_velocity
	elif jump_count == 2:
		velocity.y = jump_velocity * 1.15
		add_trauma(0.25)
	elif jump_count >= 3:
		current_state = MoveState.FLIGHT
		velocity.y = altitude_burst * 0.75
		add_trauma(0.4)


func _on_dash() -> void:
	if dash_cooldown_timer > 0.0 or current_state == MoveState.DASH:
		return

	var dir = _get_composite_input_direction()

	# Lock-on homing dash if no directional input
	if dir == Vector3.ZERO:
		if is_locked_on and is_instance_valid(lock_target):
			dir = (lock_target.global_position - global_position).normalized()
		else:
			dir = -transform.basis.z

	_start_dash(dir)


func _start_dash(direction: Vector3) -> void:
	current_state = MoveState.DASH
	state_timer = dash_duration
	impulse_vector = direction.normalized()
	add_trauma(0.5)

	# If airborne, dashing activates 3D Flight seamlessly
	if not is_on_floor() and jump_count >= 1:
		jump_count = 3


func _start_step(direction: Vector3) -> void:
	current_state = MoveState.STEP
	state_timer = 0.16
	impulse_vector = direction.normalized()
	add_trauma(0.15)


func toggle_lock() -> void:
	if is_locked_on:
		is_locked_on = false
		lock_target = null
		return

	# Query nearest target in "lock_on_targets" group
	var targets = get_tree().get_nodes_in_group("lock_on_targets")
	var best_dist = 99999.0
	var best_target: Node3D = null

	for t in targets:
		if t is Node3D and t != self:
			var d = global_position.distance_to(t.global_position)
			if d < best_dist and d < 65.0:
				best_dist = d
				best_target = t

	if best_target:
		is_locked_on = true
		lock_target = best_target
		add_trauma(0.2)


func _rotate_camera(dx: float, dy: float) -> void:
	camera_rot_y += dx
	camera_rot_x = clampf(camera_rot_x + dy, -1.25, 1.25)
	rotation.y = camera_rot_y
	camera_pivot.rotation.x = camera_rot_x


func _process_juice(delta: float) -> void:
	# 1. Sine-wave Head Bobbing
	if is_on_floor() and velocity.length() > 0.5 and current_state != MoveState.DASH:
		bob_time += delta * velocity.length() * 2.2
		var bob_y = abs(sin(bob_time)) * 0.07
		camera.position.y = lerpf(camera.position.y, bob_y, 12.0 * delta)
	else:
		bob_time = 0.0
		camera.position.y = lerpf(camera.position.y, 0.0, 10.0 * delta)

	# 2. Camera Tilt / Roll on strafe & flight
	var side_input = Input.get_axis("move_left", "move_right")
	if is_left_dragging:
		side_input = (touch_left_current - touch_left_start).normalized().x
	var target_roll = -side_input * 0.04
	camera.rotation.z = lerpf(camera.rotation.z, target_roll, 6.0 * delta)
	visual_root.rotation.z = lerpf(visual_root.rotation.z, -side_input * 0.08, 8.0 * delta)

	# 3. Dynamic FOV Kick
	var target_fov = base_fov
	if current_state == MoveState.DASH:
		target_fov = dash_fov_kick
	elif current_state == MoveState.SPRINT or current_state == MoveState.FLIGHT:
		target_fov = base_fov + 8.0
	camera.fov = lerpf(camera.fov, target_fov, 10.0 * delta)

	# 4. Trauma-based Camera Shake Decay
	if trauma > 0.0:
		trauma = maxf(trauma - delta * 1.6, 0.0)
		var shake = trauma * trauma * shake_intensity
		camera.h_offset = randf_range(-shake, shake) * 0.45
		camera.v_offset = randf_range(-shake, shake) * 0.45
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func apply_combat_impulse(impulse: Vector3) -> void:
	velocity += impulse


func apply_hitstop(duration: float) -> void:
	hitstop_timer = duration


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount * shake_intensity, 0.0, 1.0)
