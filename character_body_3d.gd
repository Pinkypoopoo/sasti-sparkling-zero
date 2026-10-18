# PlayerMovement.gd
# Attach this script to your Player (CharacterBody3D) node.
# Handles left-screen mobile gestures:
# - Drag / Hold: Run / Sprint
# - Quick Flick: Step / Micro-hop
# - Double Flick: Burst Dash
# - Flick Up: High Jump / Leap (works while running or stationary)

extends CharacterBody3D

# --- Movement Parameters ---
@export_group("Locomotion")
@export var run_speed: float = 7.5
@export var acceleration: float = 14.0
@export var rotation_speed: float = 12.0
@export var jump_velocity: float = 7.5

@export_group("Evasion & Dashes")
@export var step_speed: float = 14.0
@export var step_duration: float = 0.16
@export var dash_speed: float = 22.0
@export var dash_duration: float = 0.28

@export_group("Gesture Thresholds")
@export var drag_deadzone: float = 35.0          # Distance in px before registering continuous run
@export var flick_min_distance: float = 60.0     # Minimum px for a flick / swipe
@export var flick_max_duration: float = 0.22     # Max seconds a touch can last to count as a flick
@export var double_flick_window: float = 0.35    # Time window between flicks to trigger a Burst Dash

@export_group("References")
@export var camera: Camera3D                     # Optional: Assign your main Camera3D for relative steering

# --- Internal State ---
enum MoveState { NORMAL, STEP, DASH }
var current_state: MoveState = MoveState.NORMAL
var state_timer: float = 0.0
var impulse_direction: Vector3 = Vector3.ZERO

# Touch Tracking (Left-Screen Half Only)
var active_touch_id: int = -1
var touch_start_pos: Vector2 = Vector2.ZERO
var touch_current_pos: Vector2 = Vector2.ZERO
var touch_start_time: float = 0.0
var is_dragging: bool = false

# Double-Flick Buffer
var last_flick_dir: Vector2 = Vector2.ZERO
var last_flick_time: float = -10.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _unhandled_input(event: InputEvent) -> void:
	var screen_width = get_viewport().get_visible_rect().size.x

	# 1. Touch Press
	if event is InputEventScreenTouch:
		if event.pressed:
			# Only capture touches originating on the LEFT half of the display
			if event.position.x <= screen_width * 0.5 and active_touch_id == -1:
				active_touch_id = event.index
				touch_start_pos = event.position
				touch_current_pos = event.position
				touch_start_time = Time.get_ticks_msec() / 1000.0
				is_dragging = false
		else:
			# Touch Release on the tracked finger
			if event.index == active_touch_id:
				_evaluate_gesture(event.position)
				_reset_touch()

	# 2. Touch Drag
	elif event is InputEventScreenDrag:
		if event.index == active_touch_id:
			touch_current_pos = event.position
			var drag_dist = touch_start_pos.distance_to(touch_current_pos)
			if drag_dist > drag_deadzone:
				is_dragging = true


func _evaluate_gesture(release_pos: Vector2) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	var touch_duration = current_time - touch_start_time
	var swipe_vector = release_pos - touch_start_pos
	var swipe_dist = swipe_vector.length()

	# Fast swipe gesture detection
	if touch_duration <= flick_max_duration and swipe_dist >= flick_min_distance:
		var normalized_swipe = swipe_vector.normalized()

		# Check for Swipe UP -> High Jump / Leap (Up on screen is -Y)
		if normalized_swipe.y < -0.7:
			_perform_jump()
			return

		# Check for Double Flick (Burst Dash)
		var is_double_flick = (current_time - last_flick_time) <= double_flick_window
		var is_same_direction = normalized_swipe.dot(last_flick_dir) > 0.5

		var world_dir = _screen_vector_to_world(normalized_swipe)

		if is_double_flick and is_same_direction:
			_start_evasion(MoveState.DASH, world_dir, dash_duration)
			last_flick_time = -10.0
		else:
			_start_evasion(MoveState.STEP, world_dir, step_duration)
			last_flick_dir = normalized_swipe
			last_flick_time = current_time


func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Process evasion impulse vs normal running
	match current_state:
		MoveState.STEP:
			velocity.x = impulse_direction.x * step_speed
			velocity.z = impulse_direction.z * step_speed
			_update_state_timer(delta)

		MoveState.DASH:
			velocity.x = impulse_direction.x * dash_speed
			velocity.z = impulse_direction.z * dash_speed
			_update_state_timer(delta)

		MoveState.NORMAL:
			_handle_continuous_movement(delta)

	move_and_slide()


func _handle_continuous_movement(delta: float) -> void:
	var target_vel = Vector3.ZERO

	if is_dragging and active_touch_id != -1:
		var drag_offset = touch_current_pos - touch_start_pos
		var drag_dist = drag_offset.length()

		if drag_dist > drag_deadzone:
			var normalized_drag = drag_offset.normalized()
			var move_dir = _screen_vector_to_world(normalized_drag)

			# Speed scales slightly based on drag extension, capped at run_speed
			var speed_factor = clampf((drag_dist - drag_deadzone) / 80.0, 0.4, 1.0)
			target_vel = move_dir * (run_speed * speed_factor)

			# Face movement direction smoothly
			var target_rot_y = atan2(-move_dir.x, -move_dir.z)
			rotation.y = lerp_angle(rotation.y, target_rot_y, rotation_speed * delta)

	# Horizontal acceleration / deceleration
	velocity.x = lerp(velocity.x, target_vel.x, acceleration * delta)
	velocity.z = lerp(velocity.z, target_vel.z, acceleration * delta)


func _perform_jump() -> void:
	if is_on_floor() and current_state == MoveState.NORMAL:
		velocity.y = jump_velocity


func _start_evasion(state: MoveState, direction: Vector3, duration: float) -> void:
	current_state = state
	state_timer = duration
	impulse_direction = direction

	# Face the evasion direction instantly
	if direction != Vector3.ZERO:
		rotation.y = atan2(-direction.x, -direction.z)


func _update_state_timer(delta: float) -> void:
	state_timer -= delta
	if state_timer <= 0.0:
		current_state = MoveState.NORMAL


func _screen_vector_to_world(screen_vec: Vector2) -> Vector3:
	# Converts 2D screen coordinates (+X right, +Y down) to 3D world space relative to Camera or Body
	var forward: Vector3
	var right: Vector3

	if camera:
		var cam_basis = camera.global_transform.basis
		forward = -cam_basis.z
		right = cam_basis.x
	else:
		forward = -global_transform.basis.z
		right = global_transform.basis.x

	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()

	# Note: On touch screens, pulling down (+Y) moves backward (-forward)
	return (right * screen_vec.x + forward * (-screen_vec.y)).normalized()


func _reset_touch() -> void:
	active_touch_id = -1
	is_dragging = false
	touch_start_pos = Vector2.ZERO
	touch_current_pos = Vector2.ZERO
