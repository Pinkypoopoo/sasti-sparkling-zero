class_name PlayerController
extends CharacterBody3D

enum MoveState { GROUND, SPRINT, FLIGHT, STEP, DASH, WINDUP, GUARD, HITSTUN }

# --- Tunables ---
@export var run_speed: float = 16.0
@export var sprint_speed: float = 28.0
@export var flight_speed: float = 32.0
@export var step_speed: float = 34.0
@export var dash_speed: float = 60.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 0.05
@export var jump_velocity: float = 12.0
@export var altitude_burst: float = 18.0
@export var feint_threshold_px: float = 95.0
@export var camera_distance: float = 4.0
@export var base_fov: float = 78.0
@export var dash_fov_kick: float = 100.0
@export var cel_cut_threshold: float = 0.45
@export var outline_width: float = 0.025
@export var rim_strength: float = 0.8
@export var camera_sensitivity: float = 0.0035

# --- Stats ---
var hp: float = 1000.0
var max_hp: float = 1000.0
var mana: float = 100.0
var max_mana: float = 100.0
var mana_regen: float = 12.0
var hp_regen: float = 15.0

# --- State ---
var state: MoveState = MoveState.GROUND
var cam_rot_x: float = 0.0
var cam_rot_y: float = 0.0
var mouse_captured: bool = true
var dash_timer: float = 0.0
var dash_cd_timer: float = 0.0
var dash_leads_to_flight: bool = false
var jump_count: int = 0
var is_momentum_coasting: bool = false

# --- Touch Tracking ---
var left_touch_id: int = -1
var right_look_touch_id: int = -1
var left_touch_start: Vector2 = Vector2.ZERO
var left_touch_current: Vector2 = Vector2.ZERO
var left_touch_start_time: float = 0.0
var is_left_dragging: bool = false

# --- Nodes ---
@onready var visual_root: Node3D = $VisualRoot
@onready var body_mesh: MeshInstance3D = $VisualRoot/Body
@onready var visor_mesh: MeshInstance3D = $VisualRoot/Visor
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var combat: Node = get_node("../CombatManager")

# --- Visuals ---
var anime_mat: ShaderMaterial = null
var outline_mat: ShaderMaterial = null

func _ready() -> void:
	_setup_materials()
	_register_input_actions()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _setup_materials() -> void:
	var base_code = """
shader_type spatial;
render_mode diffuse_toon, specular_toon;
uniform vec4 albedo : source_color = vec4(0.2, 0.25, 0.3, 1.0);
uniform float cel_cut : hint_range(0.0, 1.0) = 0.45;
uniform float rim_str : hint_range(0.0, 2.0) = 0.8;
void fragment() { ALBEDO = albedo.rgb; ROUGHNESS = 0.8; SPECULAR = 0.1; }
void light() {
	float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float cel = step(cel_cut, NdotL);
	float rim = step(0.76, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0));
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * (cel * 0.8 + 0.2) * ATTENUATION;
	DIFFUSE_LIGHT += rim * rim_str * vec3(0.4, 0.7, 1.0) * LIGHT_COLOR * ATTENUATION;
}
"""
	var outline_code = """
shader_type spatial;
render_mode cull_front, unshaded;
uniform float width = 0.025;
void vertex() { VERTEX += NORMAL * width; }
void fragment() { ALBEDO = vec3(0.02, 0.02, 0.03); }
"""
	outline_mat = ShaderMaterial.new(); outline_mat.shader = Shader.new(); outline_mat.shader.code = outline_code
	anime_mat = ShaderMaterial.new(); anime_mat.shader = Shader.new(); anime_mat.shader.code = base_code
	anime_mat.next_pass = outline_mat
	update_cel_shader(cel_cut_threshold, outline_width, rim_strength)
	if body_mesh: body_mesh.set_surface_override_material(0, anime_mat)
	if visor_mesh: visor_mesh.set_surface_override_material(0, anime_mat)

func update_cel_shader(cel: float, out_w: float, rim_s: float) -> void:
	cel_cut_threshold = cel; outline_width = out_w; rim_strength = rim_s
	if anime_mat:
		anime_mat.set_shader_parameter("cel_cut", cel)
		anime_mat.set_shader_parameter("rim_str", rim_s)
	if outline_mat: outline_mat.set_shader_parameter("width", out_w)

func _register_input_actions() -> void:
	var acts = {
		"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
		"jump": [KEY_SPACE], "dash": [KEY_SHIFT], "fly": [KEY_F]
	}
	for a in acts:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev = InputEventKey.new(); ev.physical_keycode = acts[a][0]
			InputMap.action_add_event(a, ev)

func _unhandled_input(event: InputEvent) -> void:
	var is_touch = DisplayServer.is_touchscreen_available()
	var vp_size = get_viewport().get_visible_rect().size

	if event is InputEventMouseMotion and mouse_captured and not is_touch:
		cam_rot_y -= event.relative.x * 0.18
		cam_rot_x = clampf(cam_rot_x - event.relative.y * 0.18, -75, 75)

	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < vp_size.x * 0.5:
				if combat and combat.is_point_in_left_dot(event.position): pass
				elif left_touch_id == -1:
					left_touch_id = event.index; left_touch_start = event.position
					left_touch_current = event.position; left_touch_start_time = Time.get_ticks_msec() / 1000.0
					is_left_dragging = false
			else:
				if combat and combat.is_point_in_right_dot(event.position): pass
				elif right_look_touch_id == -1:
					right_look_touch_id = event.index
		else:
			if event.index == left_touch_id:
				_handle_left_release(event.position)
				left_touch_id = -1; is_left_dragging = false
			elif event.index == right_look_touch_id:
				right_look_touch_id = -1

	elif event is InputEventScreenDrag:
		if event.index == left_touch_id:
			left_touch_current = event.position
			if left_touch_current.distance_to(left_touch_start) > 15.0: is_left_dragging = true
		elif event.index == right_look_touch_id:
			cam_rot_y -= event.relative.x * camera_sensitivity * 57.2958
			cam_rot_x = clampf(cam_rot_x - event.relative.y * camera_sensitivity * 57.2958, -75.0, 75.0)

	if event.is_action_pressed("fly"):
		state = MoveState.FLIGHT if state != MoveState.FLIGHT else MoveState.GROUND

func _handle_left_release(pos: Vector2) -> void:
	var delta = pos - left_touch_start; var dist = delta.length(); var dir = delta.normalized()
	var duration = (Time.get_ticks_msec() / 1000.0) - left_touch_start_time
	
	if left_touch_start.x < 70.0 or (dist > 130.0 and absf(dir.y) > 0.7):
		if dir.y < -0.7: trigger_dash(Vector3.UP, true)
		elif dir.y > 0.7: trigger_dash(Vector3.DOWN, false)
	elif duration <= 0.18 and dist >= 40.0:
		var cf = -camera.global_transform.basis.z; cf.y = 0.0; cf = cf.normalized()
		var cr = camera.global_transform.basis.x; cr.y = 0.0; cr = cr.normalized()
		var w_dir = (cr * dir.x + cf * -dir.y).normalized()
		trigger_dash(w_dir, false)
	elif duration < 0.2 and dist < 25.0:
		_trigger_jump()

func _trigger_jump() -> void:
	jump_count += 1
	if jump_count == 1: velocity.y = jump_velocity
	elif jump_count == 2: velocity.y = jump_velocity * 1.15
	elif jump_count >= 3: state = MoveState.FLIGHT; velocity.y = altitude_burst

func trigger_dash(dir: Vector3, enter_flight: bool = false) -> void:
	if dash_cd_timer > 0.0: return
	state = MoveState.DASH; dash_timer = dash_duration; dash_cd_timer = dash_cooldown
	dash_leads_to_flight = enter_flight
	velocity = dir * dash_speed

func _physics_process(delta: float) -> void:
	hp = minf(max_hp, hp + hp_regen * delta)
	mana = minf(max_mana, mana + mana_regen * delta)
	if dash_cd_timer > 0.0: dash_cd_timer -= delta

	var mv_vec = Vector2.ZERO
	if left_touch_id != -1 and is_left_dragging:
		var d = left_touch_current - left_touch_start
		mv_vec = d.normalized() if d.length() > 20.0 else Vector2.ZERO
	else:
		mv_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	match state:
		MoveState.DASH:
			dash_timer -= delta
			if dash_timer <= 0.0:
				state = MoveState.FLIGHT if (dash_leads_to_flight or state == MoveState.FLIGHT) else MoveState.GROUND
		MoveState.FLIGHT:
			var cf = -camera.global_transform.basis.z
			var cr = camera.global_transform.basis.x
			var t_vel = (cr * mv_vec.x + cf * -mv_vec.y).normalized() * flight_speed
			velocity = velocity.lerp(t_vel, 8.0 * delta) if not is_momentum_coasting else velocity
		MoveState.GROUND, MoveState.SPRINT:
			var cf = -camera.global_transform.basis.z; cf.y = 0.0; cf = cf.normalized()
			var cr = camera.global_transform.basis.x; cr.y = 0.0; cr = cr.normalized()
			var t_dir = (cr * mv_vec.x + cf * -mv_vec.y).normalized()
			var speed = sprint_speed if Input.is_action_pressed("dash") else run_speed
			velocity.x = lerp(velocity.x, t_dir.x * speed, 12.0 * delta)
			velocity.z = lerp(velocity.z, t_dir.z * speed, 12.0 * delta)
			if not is_on_floor(): velocity.y += get_gravity().y * delta
			else: velocity.y = 0.0
			if t_dir.length() > 0.1: visual_root.rotation.y = lerp_angle(visual_root.rotation.y, atan2(-t_dir.x, -t_dir.z), 15 * delta)

	move_and_slide()
	if is_on_floor(): jump_count = 0

func _process(delta: float) -> void:
	camera_pivot.rotation_degrees.y = lerp_angle(deg_to_rad(camera_pivot.rotation_degrees.y), deg_to_rad(cam_rot_y), 24.0 * delta) * 180 / PI
	camera_pivot.rotation_degrees.x = lerp(camera_pivot.rotation_degrees.x, cam_rot_x, 24.0 * delta)
	if spring_arm: spring_arm.spring_length = lerp(spring_arm.spring_length, camera_distance, 10.0 * delta)
	camera.fov = lerp(camera.fov, base_fov + (20.0 if state == MoveState.DASH else 0.0), 12.0 * delta)
