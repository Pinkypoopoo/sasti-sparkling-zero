class_name PlayerController
extends CharacterBody3D

enum MoveState {
	GROUND,
	SPRINT,
	FLIGHT,
	STEP,
	DASH,
	WINDUP,
	ATTACK_RECOVERY,
	GUARD
}

enum Race {
	HUMAN_TOUKI,
	DEMON_FIEND,
	BEASTKIN_VANGUARD,
	ELF_CASTER
}

# --- Player Stats & Races ---
@export var current_race: Race = Race.HUMAN_TOUKI
@export var max_hp: float = 1000.0
@export var hp: float = 1000.0
@export var hp_regen: float = 15.0

@export var max_mana: float = 100.0
@export var mana: float = 100.0
@export var mana_regen: float = 10.0

var race_damage_mult: float = 1.0
var race_step_mult: float = 1.0
var race_flight_mult: float = 1.0
var race_hyper_armor: bool = false
var race_feint_recovery_mult: float = 1.0

# --- Movement & Combat Tunables (DevStudio SpinBox + HSlider) ---
@export var run_speed: float = 16.0
@export var sprint_speed: float = 28.0
@export var flight_speed: float = 32.0
@export var step_speed: float = 34.0
@export var dash_speed: float = 54.0
@export var dash_duration: float = 0.22
@export var dash_cooldown: float = 0.04
@export var jump_velocity: float = 12.0
@export var altitude_burst: float = 18.0
@export var feint_threshold_px: float = 95.0
@export var attack_step_force: float = 14.0
@export var base_fov: float = 78.0
@export var dash_fov_kick: float = 98.0
@export var shake_intensity: float = 1.0
@export var camera_distance: float = 4.0
@export var cel_cut_threshold: float = 0.45
@export var outline_width: float = 0.025
@export var rim_strength: float = 0.8
@export var model_scale: float = 1.0
@export var model_rot_offset: float = 0.0

# --- State & Timers ---
var state: MoveState = MoveState.GROUND
var move_direction: Vector3 = Vector3.ZERO
var dash_direction: Vector3 = Vector3.FORWARD
var dash_timer: float = 0.0
var dash_cd_timer: float = 0.0
var step_timer: float = 0.0

# --- Camera & Juice ---
var hit_shear_angle: float = 0.0
var fov_punch: float = 0.0
var shake_trauma: float = 0.0
var cam_rot_x: float = -12.0
var cam_rot_y: float = 0.0
var mouse_captured: bool = true

# --- Lock-On System ---
var is_locked_on: bool = false
var lock_target: Node3D = null

# --- Nodes ---
@onready var visual_root: Node3D = $VisualRoot
@onready var body_mesh: MeshInstance3D = $VisualRoot/Body
@onready var visor_mesh: MeshInstance3D = $VisualRoot/Visor
@onready var col_shape: CollisionShape3D = $CollisionShape3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

# --- Shaders & Afterimages ---
var anime_mat: ShaderMaterial = null
var outline_mat: ShaderMaterial = null
var afterimages: Array[MeshInstance3D] = []
var afterimage_alphas: Array[float] = [0.0, 0.0, 0.0]
var afterimage_mats: Array[StandardMaterial3D] = []
var afterimage_idx: int = 0
var afterimage_timer: float = 0.0

# --- Model Importer & Animations ---
var custom_model_root: Node3D = null
var active_anim_player: AnimationPlayer = null

func _ready() -> void:
	_register_input_actions()
	_setup_anime_materials()
	_setup_afterimages()
	apply_race_stats(current_race)

	if spring_arm:
		spring_arm.spring_length = camera_distance

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _setup_anime_materials() -> void:
	var base_shader := Shader.new()
	base_shader.code = """
shader_type spatial;
render_mode diffuse_toon, specular_toon;
uniform vec4 albedo_color : source_color = vec4(0.18, 0.22, 0.28, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.04, 0.05, 0.09, 1.0);
uniform vec4 rim_color : source_color = vec4(0.3, 0.7, 1.0, 1.0);
uniform float cel_cut_threshold : hint_range(0.0, 1.0) = 0.45;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.8;

void fragment() {
	ALBEDO = albedo_color.rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.1;
}

void light() {
	float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float cel = step(cel_cut_threshold, NdotL);
	vec3 diff = mix(shadow_tint.rgb, ALBEDO * LIGHT_COLOR, cel);
	float rim = step(0.76, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0));
	vec3 rim_contrib = rim * rim_color.rgb * rim_strength * (cel * 0.5 + 0.5);
	DIFFUSE_LIGHT += (diff + rim_contrib) * ATTENUATION;
}
"""
	var hull_shader := Shader.new()
	hull_shader.code = """
shader_type spatial;
render_mode cull_front, unshaded;
uniform float outline_width = 0.025;
uniform vec4 outline_color : source_color = vec4(0.02, 0.02, 0.03, 1.0);

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
"""
	outline_mat = ShaderMaterial.new()
	outline_mat.shader = hull_shader
	outline_mat.set_shader_parameter("outline_width", outline_width)
	outline_mat.set_shader_parameter("outline_color", Color(0.02, 0.02, 0.03, 1.0))

	anime_mat = ShaderMaterial.new()
	anime_mat.shader = base_shader
	anime_mat.next_pass = outline_mat
	anime_mat.set_shader_parameter("cel_cut_threshold", cel_cut_threshold)
	anime_mat.set_shader_parameter("rim_strength", rim_strength)
	anime_mat.set_shader_parameter("albedo_color", Color(0.2, 0.24, 0.32, 1.0))
	anime_mat.set_shader_parameter("shadow_tint", Color(0.04, 0.05, 0.09, 1.0))
	anime_mat.set_shader_parameter("rim_color", Color(0.3, 0.7, 1.0, 1.0))

	if body_mesh:
		body_mesh.set_surface_override_material(0, anime_mat)

func update_cel_shader(cel_cut: float, out_w: float, rim_str: float, rim_c: Color = Color(0.3, 0.7, 1.0)) -> void:
	cel_cut_threshold = cel_cut
	outline_width = out_w
	rim_strength = rim_str
	if anime_mat:
		anime_mat.set_shader_parameter("cel_cut_threshold", cel_cut_threshold)
		anime_mat.set_shader_parameter("rim_strength", rim_strength)
		anime_mat.set_shader_parameter("rim_color", rim_c)
	if outline_mat:
		outline_mat.set_shader_parameter("outline_width", outline_width)

func _setup_afterimages() -> void:
	var ghosts_holder := Node3D.new()
	ghosts_holder.name = "AfterimageGhosts"
	add_child(ghosts_holder)

	var ghost_mesh := CapsuleMesh.new()
	ghost_mesh.radius = 0.45
	ghost_mesh.height = 1.75

	for i in range(3):
		var mi := MeshInstance3D.new()
		mi.mesh = ghost_mesh
		mi.top_level = true
		mi.visible = false

		var mat := StandardMaterial3D.new()
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.3, 0.8, 1.0, 0.0)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat

		ghosts_holder.add_child(mi)
		afterimages.append(mi)
		afterimage_mats.append(mat)

func spawn_afterimage(color: Color = Color(0.3, 0.8, 1.0)) -> void:
	if afterimages.is_empty():
		return
	var mi := afterimages[afterimage_idx]
	var mat := afterimage_mats[afterimage_idx]
	mi.global_transform = visual_root.global_transform if visual_root else global_transform
	mi.visible = true
	afterimage_alphas[afterimage_idx] = 0.65
	mat.albedo_color = Color(color.r, color.g, color.b, 0.65)
	afterimage_idx = (afterimage_idx + 1) % 3

func apply_race_stats(race: Race) -> void:
	current_race = race
	match race:
		Race.HUMAN_TOUKI:
			max_hp = 1000.0
			hp = minf(hp, max_hp)
			hp_regen = 15.0
			max_mana = 100.0
			mana = minf(mana, max_mana)
			mana_regen = 10.0
			race_damage_mult = 1.0
			race_step_mult = 1.15
			race_flight_mult = 1.0
			race_hyper_armor = false
			race_feint_recovery_mult = 0.75
		Race.DEMON_FIEND:
			max_hp = 1400.0
			hp = 1400.0
			hp_regen = 20.0
			max_mana = 80.0
			mana = minf(mana, max_mana)
			mana_regen = 8.0
			race_damage_mult = 1.3
			race_step_mult = 0.95
			race_flight_mult = 0.95
			race_hyper_armor = true
			race_feint_recovery_mult = 1.1
		Race.BEASTKIN_VANGUARD:
			max_hp = 1100.0
			hp = minf(hp, max_hp)
			hp_regen = 18.0
			max_mana = 90.0
			mana = minf(mana, max_mana)
			mana_regen = 9.0
			race_damage_mult = 1.15
			race_step_mult = 1.4
			race_flight_mult = 1.05
			race_hyper_armor = false
			race_feint_recovery_mult = 0.9
		Race.ELF_CASTER:
			max_hp = 850.0
			hp = minf(hp, max_hp)
			hp_regen = 12.0
			max_mana = 150.0
			mana = 150.0
			mana_regen = 15.0
			race_damage_mult = 1.0
			race_step_mult = 1.0
			race_flight_mult = 1.25
			race_hyper_armor = false
			race_feint_recovery_mult = 1.0

func _register_input_actions() -> void:
	var actions: Dictionary = {
		"move_forward": [KEY_W, -1],
		"move_back": [KEY_S, -1],
		"move_left": [KEY_A, -1],
		"move_right": [KEY_D, -1],
		"jump": [KEY_SPACE, -1],
		"dash": [KEY_SHIFT, -1],
		"toggle_fly": [KEY_F, -1],
		"toggle_lock": [KEY_Q, JOY_BUTTON_RIGHT_STICK],
		"fly_up": [KEY_SPACE, -1],
		"fly_down": [KEY_CTRL, -1]
	}
	for act in actions.keys():
		if not InputMap.has_action(act):
			InputMap.add_action(act)
			var key_code: int = actions[act][0]
			var joy_btn: int = actions[act][1]
			if key_code > 0:
				var ev := InputEventKey.new()
				ev.physical_keycode = key_code as Key
				InputMap.action_add_event(act, ev)
			if joy_btn >= 0:
				var jev := InputEventJoypadButton.new()
				jev.button_index = joy_btn as JoyButton
				InputMap.action_add_event(act, jev)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		cam_rot_y -= event.relative.x * 0.18
		cam_rot_x -= event.relative.y * 0.18
		cam_rot_x = clampf(cam_rot_x, -75.0, 75.0)

	if event.is_action_pressed("toggle_fly"):
		if state == MoveState.FLIGHT:
			state = MoveState.GROUND
		else:
			state = MoveState.FLIGHT
			velocity.y = altitude_burst * 0.5

	if event.is_action_pressed("toggle_lock"):
		toggle_lock_on()

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			mouse_captured = not mouse_captured
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if mouse_captured else Input.MOUSE_MODE_VISIBLE)

func toggle_lock_on() -> void:
	if is_locked_on:
		is_locked_on = false
		lock_target = null
		return

	var targets := get_tree().get_nodes_in_group("lock_on_targets")
	var best_target: Node3D = null
	var best_dist: float = 120.0

	for t in targets:
		if t is Node3D and t != self:
			var d := global_position.distance_to(t.global_position)
			if d < best_dist:
				best_dist = d
				best_target = t as Node3D

	if best_target:
		is_locked_on = true
		lock_target = best_target
	else:
		is_locked_on = false
		lock_target = null

func apply_hit_shear(dir_2d: Vector2, fov_kick: float) -> void:
	hit_shear_angle = -dir_2d.x * 0.12
	fov_punch = fov_kick
	shake_trauma = minf(shake_trauma + 0.4, 1.0)

func trigger_dash(dir: Vector3) -> void:
	if dash_cd_timer > 0.0:
		return
	state = MoveState.DASH
	dash_direction = dir.normalized() if dir.length_squared() > 0.01 else -global_transform.basis.z
	dash_timer = dash_duration
	dash_cd_timer = dash_cooldown
	spawn_afterimage(Color(0.2, 0.9, 1.0))
	fov_punch = dash_fov_kick - base_fov

func trigger_step(dir: Vector3) -> void:
	state = MoveState.STEP
	dash_direction = dir.normalized() if dir.length_squared() > 0.01 else -global_transform.basis.z
	step_timer = 0.14
	spawn_afterimage(Color(0.9, 0.8, 0.2))

func _physics_process(delta: float) -> void:
	hp = minf(max_hp, hp + hp_regen * delta)
	mana = minf(max_mana, mana + mana_regen * delta)

	if dash_cd_timer > 0.0:
		dash_cd_timer -= delta

	var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := Vector3.ZERO
	var right := Vector3.ZERO

	if camera:
		var cam_basis := camera.global_transform.basis
		forward = -cam_basis.z
		right = cam_basis.x

	match state:
		MoveState.FLIGHT:
			_process_flight(delta, input_vec, forward, right)
		MoveState.DASH:
			_process_dash(delta)
		MoveState.STEP:
			_process_step(delta)
		MoveState.GROUND, MoveState.SPRINT, MoveState.WINDUP, MoveState.ATTACK_RECOVERY, MoveState.GUARD:
			_process_ground(delta, input_vec, forward, right)

	move_and_slide()
	_update_afterimages(delta)

func _process_ground(delta: float, input_vec: Vector2, forward: Vector3, right: Vector3) -> void:
	var fwd_planar := Vector3(forward.x, 0.0, forward.z).normalized()
	var right_planar := Vector3(right.x, 0.0, right.z).normalized()
	move_direction = (right_planar * input_vec.x + fwd_planar * -input_vec.y).normalized()

	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity * (1.4 if current_race == Race.BEASTKIN_VANGUARD else 1.0)
		else:
			velocity.y = 0.0

	var is_sprint := Input.is_action_pressed("dash")
	var target_speed := (sprint_speed if is_sprint else run_speed)

	if state == MoveState.GUARD:
		target_speed *= 0.35
	elif state == MoveState.WINDUP:
		target_speed *= 0.2

	var target_vel := move_direction * target_speed
	velocity.x = lerpf(velocity.x, target_vel.x, 14.0 * delta)
	velocity.z = lerpf(velocity.z, target_vel.z, 14.0 * delta)

	if move_direction.length_squared() > 0.01 and visual_root:
		var target_rot_y := atan2(-move_direction.x, -move_direction.z)
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_rot_y, 16.0 * delta)

	if Input.is_action_just_pressed("dash") and move_direction.length_squared() > 0.01:
		trigger_dash(move_direction)

func _process_flight(delta: float, input_vec: Vector2, forward: Vector3, right: Vector3) -> void:
	var up_axis := Vector3.UP
	var fly_dir := (right * input_vec.x + forward * -input_vec.y)

	if Input.is_action_pressed("fly_up"):
		fly_dir += up_axis
	elif Input.is_action_pressed("fly_down"):
		fly_dir -= up_axis

	fly_dir = fly_dir.normalized()
	var current_flight_speed := flight_speed * race_flight_mult
	if Input.is_action_pressed("dash"):
		current_flight_speed *= 1.45

	var target_vel := fly_dir * current_flight_speed
	velocity = velocity.lerp(target_vel, 8.0 * delta)

	if fly_dir.length_squared() > 0.01 and visual_root:
		var target_rot_y := atan2(-fly_dir.x, -fly_dir.z)
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_rot_y, 14.0 * delta)

	if Input.is_action_just_pressed("jump"):
		velocity.y += altitude_burst

func _process_dash(delta: float) -> void:
	dash_timer -= delta
	velocity = dash_direction * dash_speed * race_step_mult
	if visual_root and dash_direction.length_squared() > 0.01:
		visual_root.rotation.y = atan2(-dash_direction.x, -dash_direction.z)
	if dash_timer <= 0.0:
		state = MoveState.FLIGHT if not is_on_floor() and velocity.y > 0.0 else MoveState.GROUND

func _process_step(delta: float) -> void:
	step_timer -= delta
	velocity = dash_direction * step_speed * race_step_mult
	if step_timer <= 0.0:
		state = MoveState.GROUND

func _update_afterimages(delta: float) -> void:
	var is_high_speed := velocity.length_squared() > (24.0 * 24.0)
	if (state == MoveState.DASH or state == MoveState.STEP or is_high_speed):
		afterimage_timer -= delta
		if afterimage_timer <= 0.0:
			afterimage_timer = 0.045
			spawn_afterimage(Color(0.2, 0.85, 1.0) if state == MoveState.DASH else Color(0.85, 0.7, 0.2))

	for i in range(3):
		if afterimage_alphas[i] > 0.0:
			afterimage_alphas[i] = maxf(0.0, afterimage_alphas[i] - delta * 4.2)
			var c: Color = afterimage_mats[i].albedo_color
			c.a = afterimage_alphas[i]
			afterimage_mats[i].albedo_color = c
			if afterimage_alphas[i] <= 0.0:
				afterimages[i].visible = false

func _process(delta: float) -> void:
	_update_camera(delta)

func _update_camera(delta: float) -> void:
	if not camera_pivot or not camera:
		return

	if is_locked_on and is_instance_valid(lock_target):
		var target_pos := lock_target.global_position + Vector3(0, 1.4, 0)
		var diff := target_pos - global_position
		var flat_diff := Vector2(diff.x, diff.z)
		cam_rot_y = rad_to_deg(atan2(-flat_diff.x, -flat_diff.y))
		cam_rot_x = clampf(rad_to_deg(atan2(diff.y, flat_diff.length())), -45.0, 45.0)

	camera_pivot.rotation_degrees.y = lerp_angle(deg_to_rad(camera_pivot.rotation_degrees.y), deg_to_rad(cam_rot_y), 24.0 * delta) * 180.0 / PI
	camera_pivot.rotation_degrees.x = lerpf(camera_pivot.rotation_degrees.x, cam_rot_x, 24.0 * delta)

	hit_shear_angle = lerpf(hit_shear_angle, 0.0, 14.0 * delta)
	camera.rotation.z = hit_shear_angle

	fov_punch = lerpf(fov_punch, 0.0, 12.0 * delta)
	var target_fov := base_fov + fov_punch
	if state == MoveState.DASH:
		target_fov = maxf(target_fov, dash_fov_kick)
	camera.fov = lerpf(camera.fov, target_fov, 16.0 * delta)

	if spring_arm:
		spring_arm.spring_length = lerpf(spring_arm.spring_length, camera_distance, 10.0 * delta)

	if shake_trauma > 0.0:
		shake_trauma = maxf(0.0, shake_trauma - delta * 1.5)
		var shake := shake_trauma * shake_trauma * shake_intensity * 0.12
		camera.h_offset = randf_range(-shake, shake)
		camera.v_offset = randf_range(-shake, shake)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0

func swap_custom_model(path: String) -> bool:
	if path.is_empty():
		return false

	var new_node: Node3D = null
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is PackedScene:
			new_node = res.instantiate() as Node3D
	elif FileAccess.file_exists(path):
		var gltf := GLTFDocument.new()
		var state_obj := GLTFState.new()
		var err := gltf.append_from_file(path, state_obj)
		if err == OK:
			new_node = gltf.generate_scene(state_obj) as Node3D

	if not new_node:
		return false

	if custom_model_root and is_instance_valid(custom_model_root):
		custom_model_root.queue_free()

	custom_model_root = new_node
	visual_root.add_child(custom_model_root)
	custom_model_root.scale = Vector3.ONE * model_scale
	custom_model_root.rotation.y = deg_to_rad(model_rot_offset)

	if body_mesh:
		body_mesh.visible = false
	if visor_mesh:
		visor_mesh.visible = false

	active_anim_player = _find_anim_player(custom_model_root)
	return true

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var res := _find_anim_player(child)
		if res:
			return res
	return null
