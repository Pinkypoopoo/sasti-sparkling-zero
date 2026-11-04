class_name PlayerController
extends CharacterBody3D

enum MoveState { GROUND, SPRINT, FLIGHT, STEP, DASH, WINDUP, GUARD, HITSTUN }
enum DashStyle { DBZ_VANISH_RUSH, BLEACH_SONIDO, SANDEVISTAN_ECHO, MACH_CONE_BURST, SHADOW_ABYSS_SINK, TOUKI_HORIZON_FLASH }

var custom_races: Dictionary = {
	"Human_Touki": {
		"max_hp": 1000.0, "hp_regen": 15.0, "max_mana": 100.0, "mana_regen": 12.0,
		"physical_strength": 1.0, "base_power": 1.0, "step_mult": 1.15, "flight_mult": 1.0,
		"dash_style": DashStyle.DBZ_VANISH_RUSH, "aura_color": Color(0.95, 0.12, 0.18), "model_path": ""
	},
	"Demon_Fiend": {
		"max_hp": 1400.0, "hp_regen": 20.0, "max_mana": 85.0, "mana_regen": 8.0,
		"physical_strength": 1.35, "base_power": 1.1, "step_mult": 0.95, "flight_mult": 0.9,
		"dash_style": DashStyle.SHADOW_ABYSS_SINK, "aura_color": Color(0.9, 0.1, 0.2), "model_path": ""
	},
	"Beastkin_Vanguard": {
		"max_hp": 1150.0, "hp_regen": 18.0, "max_mana": 90.0, "mana_regen": 10.0,
		"physical_strength": 1.25, "base_power": 0.9, "step_mult": 1.4, "flight_mult": 1.05,
		"dash_style": DashStyle.MACH_CONE_BURST, "aura_color": Color(1.0, 0.78, 0.15), "model_path": ""
	},
	"Elf_Caster": {
		"max_hp": 850.0, "hp_regen": 12.0, "max_mana": 160.0, "mana_regen": 18.0,
		"physical_strength": 0.9, "base_power": 1.45, "step_mult": 1.1, "flight_mult": 1.3,
		"dash_style": DashStyle.TOUKI_HORIZON_FLASH, "aura_color": Color(0.2, 0.95, 0.7), "model_path": ""
	}
}
var active_race_name: String = "Human_Touki"

@export var run_speed: float = 16.0
@export var sprint_speed: float = 28.0
@export var flight_speed: float = 32.0
@export var step_speed: float = 34.0
@export var dash_speed: float = 60.0
@export var dash_duration: float = 0.22
@export var dash_cooldown: float = 0.04
@export var jump_velocity: float = 12.0
@export var altitude_burst: float = 18.0
@export var feint_threshold_px: float = 90.0
@export var camera_distance: float = 4.0
@export var base_fov: float = 78.0
@export var dash_fov_kick: float = 100.0
@export var camera_whip_lag: float = 0.055
@export var vanish_strobe_hz: float = 18.0
@export var letterbox_amount: float = 0.0
@export var cel_cut_threshold: float = 0.45
@export var hatch_width: float = 0.08
@export var outline_width: float = 0.024
@export var rim_strength: float = 0.9
@export var anim_step_fps: float = 12.0
@export var camera_sensitivity: float = 0.22
@export var model_scale: float = 1.0
@export var model_rot_offset: float = 0.0

var jiggle_enabled: bool = true
var jiggle_stiffness: float = 18.0
var jiggle_damping: float = 4.5
var jiggle_gravity: float = 0.6

var hp: float = 1000.0
var max_hp: float = 1000.0
var mana: float = 100.0
var max_mana: float = 100.0
var mana_regen: float = 12.0
var hp_regen: float = 15.0
var physical_strength: float = 1.0
var base_power: float = 1.0
var step_mult: float = 1.15
var flight_mult: float = 1.0
var dash_style: DashStyle = DashStyle.DBZ_VANISH_RUSH

var state: MoveState = MoveState.GROUND
var cam_rot_x: float = -8.0
var cam_rot_y: float = 0.0
var dash_timer: float = 0.0
var dash_cd_timer: float = 0.0
var dash_dir: Vector3 = Vector3.FORWARD
var dash_start_pos: Vector3 = Vector3.ZERO
var dash_leads_to_flight: bool = false
var whip_lag_timer: float = 0.0
var hitstun_timer: float = 0.0
var jump_count: int = 0
var is_momentum_coasting: bool = false
var coasting_velocity: Vector3 = Vector3.ZERO
var is_locked_on: bool = false
var lock_target: Node3D = null

var anim_step_accum: float = 0.0
var stepped_time: float = 0.0
var echo_color_idx: int = 0

var left_touch_id: int = -1
var right_look_touch_id: int = -1
var left_touch_start: Vector2 = Vector2.ZERO
var left_touch_current: Vector2 = Vector2.ZERO
var left_touch_start_time: float = 0.0
var is_left_dragging: bool = false

@onready var visual_root: Node3D = $VisualRoot
@onready var body_mesh: MeshInstance3D = $VisualRoot/Body
@onready var visor_mesh: MeshInstance3D = $VisualRoot/Visor
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var combat: Node = get_node_or_null("../CombatManager")

var anime_mat: ShaderMaterial = null
var outline_mat: ShaderMaterial = null
var afterimages: Array[MeshInstance3D] = []
var afterimage_alphas: Array[float] = [0.0, 0.0, 0.0]
var afterimage_mats: Array[StandardMaterial3D] = []
var afterimage_idx: int = 0
var afterimage_timer: float = 0.0
var dash_fx_mesh: MeshInstance3D = null
var dash_fx_mat: StandardMaterial3D = null
var dash_fx_timer: float = 0.0

var custom_model_root: Node3D = null
var active_anim_player: AnimationPlayer = null
var active_skeleton: Skeleton3D = null

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://models")
	DirAccess.make_dir_recursive_absolute("user://vfx")
	_setup_materials()
	_setup_afterimages()
	_register_input_actions()
	apply_race_by_name(active_race_name)
	if not DisplayServer.is_touchscreen_available():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _setup_materials() -> void:
	var base_code := """
shader_type spatial;
render_mode diffuse_toon, specular_toon, ambient_light_disabled;
uniform vec4 albedo : source_color = vec4(0.18, 0.20, 0.26, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.015, 0.01, 0.02, 1.0);
uniform vec4 rim_color : source_color = vec4(0.95, 0.12, 0.18, 1.0);
uniform float cel_cut : hint_range(0.0, 1.0) = 0.45;
uniform float hatch_width : hint_range(0.0, 0.3) = 0.08;
uniform float rim_str : hint_range(0.0, 2.5) = 0.9;

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.1;
}

void light() {
	float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 H = normalize(LIGHT + VIEW);
	float spec = step(0.88, pow(max(dot(NORMAL, H), 0.0), 16.0));
	float rim = step(0.78, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0));

	float hatch_pattern = step(0.0, sin((FRAGCOORD.x + FRAGCOORD.y) * 0.95));
	vec3 ink_lit = ALBEDO * LIGHT_COLOR * ATTENUATION;
	vec3 ink_hatch = mix(shadow_color.rgb, ink_lit, hatch_pattern * 0.65);

	vec3 band_color = shadow_color.rgb;
	if (NdotL >= cel_cut + hatch_width) {
		band_color = ink_lit;
	} else if (NdotL >= cel_cut) {
		band_color = ink_hatch;
	}

	DIFFUSE_LIGHT += band_color + (spec * vec3(0.95, 0.92, 0.88) * ATTENUATION) + (rim * rim_str * rim_color.rgb);
}
"""
	var outline_code := """
shader_type spatial;
render_mode cull_front, unshaded;
uniform float width = 0.024;
void vertex() { VERTEX += NORMAL * width; }
void fragment() { ALBEDO = vec3(0.015, 0.0, 0.015); }
"""
	outline_mat = ShaderMaterial.new()
	outline_mat.shader = Shader.new()
	outline_mat.shader.code = outline_code
	anime_mat = ShaderMaterial.new()
	anime_mat.shader = Shader.new()
	anime_mat.shader.code = base_code
	anime_mat.next_pass = outline_mat
	update_cel_shader(cel_cut_threshold, outline_width, rim_strength)
	if body_mesh: body_mesh.set_surface_override_material(0, anime_mat)
	if visor_mesh: visor_mesh.set_surface_override_material(0, anime_mat)

func update_cel_shader(cel: float, out_w: float, rim_s: float, rim_col: Color = Color(0.95, 0.12, 0.18)) -> void:
	cel_cut_threshold = cel
	outline_width = out_w
	rim_strength = rim_s
	if anime_mat:
		anime_mat.set_shader_parameter("cel_cut", cel)
		anime_mat.set_shader_parameter("hatch_width", hatch_width)
		anime_mat.set_shader_parameter("rim_str", rim_s)
		anime_mat.set_shader_parameter("rim_color", rim_col)
	if outline_mat:
		outline_mat.set_shader_parameter("width", out_w)

func _setup_afterimages() -> void:
	var holder := Node3D.new()
	holder.name = "AfterimagePool"
	add_child(holder)
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.45
	mesh.height = 1.75
	for i in range(3):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.top_level = true
		mi.visible = false
		var mat := StandardMaterial3D.new()
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.95, 0.12, 0.18, 0.0)
		mi.material_override = mat
		holder.add_child(mi)
		afterimages.append(mi)
		afterimage_mats.append(mat)

	dash_fx_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	cyl.height = 3.0
	dash_fx_mesh.mesh = cyl
	dash_fx_mesh.top_level = true
	dash_fx_mesh.visible = false
	dash_fx_mat = StandardMaterial3D.new()
	dash_fx_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	dash_fx_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dash_fx_mat.albedo_color = Color(0.95, 0.15, 0.2, 0.85)
	dash_fx_mesh.material_override = dash_fx_mat
	holder.add_child(dash_fx_mesh)

func spawn_afterimage(col: Color, alpha_val: float = 0.75) -> void:
	if afterimages.is_empty(): return
	var mi := afterimages[afterimage_idx]
	var mat := afterimage_mats[afterimage_idx]
	mi.global_transform = visual_root.global_transform if visual_root else global_transform
	mi.visible = true
	afterimage_alphas[afterimage_idx] = alpha_val
	mat.albedo_color = Color(col.r, col.g, col.b, alpha_val)
	afterimage_idx = (afterimage_idx + 1) % 3

func _reset_dash_visuals() -> void:
	if visual_root:
		visual_root.visible = true
		visual_root.scale = Vector3.ONE
		visual_root.rotation.x = 0.0
		visual_root.rotation.z = 0.0
		visual_root.position.y = 0.0

func apply_race_by_name(r_name: String) -> void:
	if not custom_races.has(r_name): return
	active_race_name = r_name
	var r: Dictionary = custom_races[r_name]
	max_hp = r.get("max_hp", 1000.0)
	hp = max_hp
	hp_regen = r.get("hp_regen", 15.0)
	max_mana = r.get("max_mana", 100.0)
	mana = max_mana
	mana_regen = r.get("mana_regen", 12.0)
	physical_strength = r.get("physical_strength", 1.0)
	base_power = r.get("base_power", 1.0)
	step_mult = r.get("step_mult", 1.15)
	flight_mult = r.get("flight_mult", 1.0)
	dash_style = r.get("dash_style", DashStyle.DBZ_VANISH_RUSH) as DashStyle
	var col: Color = r.get("aura_color", Color(0.95, 0.12, 0.18))
	update_cel_shader(cel_cut_threshold, outline_width, rim_strength, col)
	var m_path: String = r.get("model_path", "")
	if not m_path.is_empty():
		swap_custom_model(m_path)

func swap_custom_model(path: String) -> bool:
	if path.is_empty(): return false
	var new_node: Node3D = null
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is PackedScene: new_node = res.instantiate() as Node3D
	elif FileAccess.file_exists(path):
		var gltf := GLTFDocument.new()
		var state_obj := GLTFState.new()
		if gltf.append_from_file(path, state_obj) == OK:
			new_node = gltf.generate_scene(state_obj) as Node3D
	if not new_node: return false
	if custom_model_root and is_instance_valid(custom_model_root):
		custom_model_root.queue_free()
	custom_model_root = new_node
	visual_root.add_child(custom_model_root)
	custom_model_root.scale = Vector3.ONE * model_scale
	custom_model_root.rotation.y = deg_to_rad(model_rot_offset)
	if body_mesh: body_mesh.visible = false
	if visor_mesh: visor_mesh.visible = false
	active_anim_player = _find_anim_player(custom_model_root)
	active_skeleton = _find_skeleton(custom_model_root)
	return true

func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r: return r
	return null

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r: return r
	return null

func _register_input_actions() -> void:
	var acts := {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"jump": KEY_SPACE, "dash": KEY_SHIFT, "fly": KEY_F, "lock_on": KEY_Q
	}
	for a in acts.keys():
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev := InputEventKey.new()
			ev.physical_keycode = acts[a] as Key
			InputMap.action_add_event(a, ev)

func toggle_lock_on() -> void:
	if is_locked_on:
		is_locked_on = false
		lock_target = null
		return
	cycle_lock_target()

func cycle_lock_target() -> void:
	var targets := get_tree().get_nodes_in_group("lock_on_targets")
	if targets.is_empty():
		is_locked_on = false
		lock_target = null
		return
	var valid_targets: Array[Node3D] = []
	for t in targets:
		if t is Node3D and t != self:
			valid_targets.append(t as Node3D)
	if valid_targets.is_empty(): return
	if not is_locked_on or not is_instance_valid(lock_target):
		lock_target = valid_targets[0]
		is_locked_on = true
	else:
		var idx := valid_targets.find(lock_target)
		lock_target = valid_targets[(idx + 1) % valid_targets.size()]
		is_locked_on = true

func _unhandled_input(event: InputEvent) -> void:
	var vp_size := get_viewport().get_visible_rect().size

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		cam_rot_y -= event.relative.x * 0.18
		cam_rot_x = clampf(cam_rot_x - event.relative.y * 0.18, -75.0, 75.0)

	if event is InputEventScreenTouch:
		if event.pressed:
			if combat and (combat.is_point_in_right_dot(event.position) or combat.is_point_in_left_dot(event.position)):
				return
			if event.position.x < vp_size.x * 0.5:
				if left_touch_id == -1:
					left_touch_id = event.index
					left_touch_start = event.position
					left_touch_current = event.position
					left_touch_start_time = Time.get_ticks_msec() / 1000.0
					is_left_dragging = false
			else:
				if right_look_touch_id == -1:
					right_look_touch_id = event.index
		else:
			if event.index == left_touch_id:
				_handle_left_release(event.position)
				left_touch_id = -1
				is_left_dragging = false
			elif event.index == right_look_touch_id:
				right_look_touch_id = -1

	elif event is InputEventScreenDrag:
		if event.index == left_touch_id:
			left_touch_current = event.position
			if left_touch_current.distance_to(left_touch_start) > 16.0:
				is_left_dragging = true
		elif event.index == right_look_touch_id:
			cam_rot_y -= event.relative.x * camera_sensitivity
			cam_rot_x = clampf(cam_rot_x - event.relative.y * camera_sensitivity, -75.0, 75.0)

	if event.is_action_pressed("fly"):
		state = MoveState.FLIGHT if state != MoveState.FLIGHT else MoveState.GROUND
	if event.is_action_pressed("lock_on"):
		toggle_lock_on()
	if event.is_action_pressed("jump") and not DisplayServer.is_touchscreen_available():
		_trigger_jump()
	if event.is_action_pressed("dash") and not DisplayServer.is_touchscreen_available():
		var in_v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var cf := -camera.global_transform.basis.z; cf.y = 0.0; cf = cf.normalized()
		var cr := camera.global_transform.basis.x; cr.y = 0.0; cr = cr.normalized()
		var d := (cr * in_v.x + cf * -in_v.y).normalized()
		if d.length_squared() < 0.01: d = cf
		trigger_dash(d, state == MoveState.FLIGHT)

func _handle_left_release(pos: Vector2) -> void:
	var delta := pos - left_touch_start
	var dist := delta.length()
	var dir := delta.normalized()
	var duration := (Time.get_ticks_msec() / 1000.0) - left_touch_start_time

	if left_touch_start.x < 75.0 or (dist > 130.0 and absf(dir.y) > 0.7):
		if dir.y < -0.7:
			trigger_dash(Vector3.UP, true)
		elif dir.y > 0.7:
			trigger_dash(Vector3.DOWN, false)
	elif duration <= 0.22 and dist >= 38.0:
		var cf := -camera.global_transform.basis.z; cf.y = 0.0; cf = cf.normalized()
		var cr := camera.global_transform.basis.x; cr.y = 0.0; cr = cr.normalized()
		var w_dir := (cr * dir.x + cf * -dir.y).normalized()
		trigger_dash(w_dir, state == MoveState.FLIGHT)
	elif duration < 0.22 and dist < 28.0:
		_trigger_jump()

func _trigger_jump() -> void:
	if state == MoveState.FLIGHT:
		velocity.y = altitude_burst
		return
	jump_count += 1
	if jump_count == 1:
		velocity.y = jump_velocity
	elif jump_count == 2:
		velocity.y = jump_velocity * 1.15
	elif jump_count >= 3:
		state = MoveState.FLIGHT
		velocity.y = altitude_burst

func trigger_dash(dir: Vector3, keep_flight: bool = false) -> void:
	if dash_cd_timer > 0.0: return
	_reset_dash_visuals()
	state = MoveState.DASH
	dash_timer = dash_duration
	dash_cd_timer = dash_cooldown
	dash_leads_to_flight = keep_flight
	dash_start_pos = global_position
	dash_dir = dir.normalized() if dir.length_squared() > 0.01 else -global_transform.basis.z
	whip_lag_timer = camera_whip_lag

	if is_locked_on and is_instance_valid(lock_target) and global_position.distance_to(lock_target.global_position) < 8.0 and dir.y > -0.5:
		global_position = lock_target.global_position + lock_target.global_transform.basis.z * 2.2
		cam_rot_y += 180.0
	else:
		velocity = dash_dir * dash_speed * step_mult

	match dash_style:
		DashStyle.DBZ_VANISH_RUSH:
			if visual_root: visual_root.visible = false
			camera.fov = dash_fov_kick + 14.0
			spawn_afterimage(Color(0.95, 0.95, 1.0), 0.85)
		DashStyle.BLEACH_SONIDO:
			spawn_afterimage(Color(0.01, 0.01, 0.02), 0.96)
			velocity *= 1.35
		DashStyle.SANDEVISTAN_ECHO:
			echo_color_idx = 0
			spawn_afterimage(Color(0.95, 0.12, 0.18), 0.85)
		DashStyle.MACH_CONE_BURST:
			if visual_root:
				visual_root.rotation.x = deg_to_rad(-42.0)
				visual_root.scale = Vector3(0.8, 0.8, 1.45)
			if dash_fx_mesh:
				dash_fx_mesh.global_position = dash_start_pos + Vector3(0, 1.0, 0)
				dash_fx_mesh.scale = Vector3(3.5, 0.08, 3.5)
				dash_fx_mat.albedo_color = Color(0.95, 0.95, 1.0, 0.85)
				dash_fx_mesh.visible = true
				dash_fx_timer = 0.22
		DashStyle.SHADOW_ABYSS_SINK:
			if visual_root:
				visual_root.scale = Vector3(1.85, 0.04, 1.85)
			spawn_afterimage(Color(0.02, 0.0, 0.04), 0.92)
		DashStyle.TOUKI_HORIZON_FLASH:
			if dash_fx_mesh:
				dash_fx_mesh.global_position = dash_start_pos + Vector3(0, 1.0, 0)
				dash_fx_mesh.scale = Vector3(0.6, 2.5, 0.6)
				dash_fx_mat.albedo_color = Color(0.95, 0.12, 0.18, 0.9)
				dash_fx_mesh.visible = true
				dash_fx_timer = 0.25

func _physics_process(delta: float) -> void:
	hp = minf(max_hp, hp + hp_regen * delta)
	mana = minf(max_mana, mana + mana_regen * delta)
	if dash_cd_timer > 0.0: dash_cd_timer -= delta
	if whip_lag_timer > 0.0: whip_lag_timer -= delta

	var mv_vec := Vector2.ZERO
	var is_sprint_drag := false
	if left_touch_id != -1 and is_left_dragging:
		var d := left_touch_current - left_touch_start
		if d.length() > 18.0:
			mv_vec = d.normalized()
			is_sprint_drag = d.length() > 75.0
	else:
		mv_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		is_sprint_drag = Input.is_action_pressed("dash")

	match state:
		MoveState.DASH:
			dash_timer -= delta
			var spd_mult := 1.35 if dash_style == DashStyle.BLEACH_SONIDO else 1.0
			velocity = dash_dir * dash_speed * step_mult * spd_mult
			if dash_style == DashStyle.DBZ_VANISH_RUSH and visual_root:
				visual_root.visible = dash_timer < (dash_duration * 0.2)
			elif dash_style == DashStyle.SHADOW_ABYSS_SINK and visual_root:
				visual_root.scale = Vector3(1.85, 0.04, 1.85)
			elif dash_style == DashStyle.MACH_CONE_BURST and visual_root:
				visual_root.rotation.x = deg_to_rad(-42.0)
				visual_root.scale = Vector3(0.8, 0.8, 1.45)
			if dash_timer <= 0.0:
				_reset_dash_visuals()
				state = MoveState.FLIGHT if (dash_leads_to_flight or not is_on_floor()) else MoveState.GROUND
		MoveState.FLIGHT:
			var cf := -camera.global_transform.basis.z
			var cr := camera.global_transform.basis.x
			var t_vel := (cr * mv_vec.x + cf * -mv_vec.y).normalized() * flight_speed * flight_mult
			if is_momentum_coasting:
				velocity = velocity.lerp(coasting_velocity, 4.0 * delta)
			else:
				velocity = velocity.lerp(t_vel, 10.0 * delta)
				coasting_velocity = velocity
			if mv_vec.length_squared() > 0.01:
				visual_root.rotation.y = lerp_angle(visual_root.rotation.y, atan2(-velocity.x, -velocity.z), 14.0 * delta)
		MoveState.GROUND, MoveState.SPRINT, MoveState.WINDUP, MoveState.GUARD, MoveState.HITSTUN:
			var cf := -camera.global_transform.basis.z; cf.y = 0.0; cf = cf.normalized()
			var cr := camera.global_transform.basis.x; cr.y = 0.0; cr = cr.normalized()
			var t_dir := (cr * mv_vec.x + cf * -mv_vec.y).normalized()
			var spd := (sprint_speed if is_sprint_drag else run_speed)
			if is_momentum_coasting:
				velocity.x = lerpf(velocity.x, coasting_velocity.x, 4.0 * delta)
				velocity.z = lerpf(velocity.z, coasting_velocity.z, 4.0 * delta)
			else:
				velocity.x = lerpf(velocity.x, t_dir.x * spd, 14.0 * delta)
				velocity.z = lerpf(velocity.z, t_dir.z * spd, 14.0 * delta)
				coasting_velocity = velocity
			if not is_on_floor():
				velocity.y += get_gravity().y * delta
			elif velocity.y < 0.0:
				velocity.y = 0.0
			if t_dir.length_squared() > 0.01:
				visual_root.rotation.y = lerp_angle(visual_root.rotation.y, atan2(-t_dir.x, -t_dir.z), 15.0 * delta)

	move_and_slide()
	if is_on_floor():
		jump_count = 0
		if state == MoveState.FLIGHT and velocity.y <= 0.0:
			state = MoveState.GROUND

	_update_afterimages(delta)
	_update_stepped_animation(delta)

func _update_stepped_animation(delta: float) -> void:
	var step_interval: float = 1.0 / maxf(1.0, anim_step_fps)
	anim_step_accum += delta
	if anim_step_accum >= step_interval:
		var steps: int = int(anim_step_accum / step_interval)
		var advance_time: float = float(steps) * step_interval
		anim_step_accum -= advance_time
		stepped_time += advance_time
		if active_anim_player:
			active_anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			active_anim_player.advance(advance_time)
		elif state != MoveState.DASH and visual_root:
			var h_speed: float = Vector2(velocity.x, velocity.z).length()
			if h_speed > 1.5 and is_on_floor():
				visual_root.position.y = absf(sin(stepped_time * 11.0)) * 0.14
				visual_root.rotation.x = deg_to_rad(-8.0)
			else:
				visual_root.position.y = sin(stepped_time * 3.5) * 0.04
				visual_root.rotation.x = 0.0

func _update_afterimages(delta: float) -> void:
	if dash_fx_timer > 0.0:
		dash_fx_timer -= delta
		if dash_fx_timer <= 0.0 and dash_fx_mesh:
			dash_fx_mesh.visible = false

	if state == MoveState.DASH or velocity.length_squared() > 700.0:
		afterimage_timer -= delta
		if afterimage_timer <= 0.0:
			afterimage_timer = 0.035 if dash_style == DashStyle.SANDEVISTAN_ECHO else 0.05
			if dash_style == DashStyle.SANDEVISTAN_ECHO:
				var echo_cols: Array[Color] = [Color(0.95, 0.12, 0.18), Color(1.0, 0.82, 0.15), Color(0.92, 0.92, 0.96)]
				spawn_afterimage(echo_cols[echo_color_idx % 3], 0.85)
				echo_color_idx += 1
			elif dash_style == DashStyle.BLEACH_SONIDO:
				spawn_afterimage(Color(0.01, 0.01, 0.02), 0.9)
			else:
				spawn_afterimage(Color(0.95, 0.12, 0.18), 0.65)

	for i in range(3):
		if afterimage_alphas[i] > 0.0:
			afterimage_alphas[i] = maxf(0.0, afterimage_alphas[i] - delta * 3.5)
			var c := afterimage_mats[i].albedo_color
			c.a = afterimage_alphas[i]
			afterimage_mats[i].albedo_color = c
			if afterimage_alphas[i] <= 0.0:
				afterimages[i].visible = false

func _process(delta: float) -> void:
	if is_locked_on and is_instance_valid(lock_target):
		var diff := (lock_target.global_position + Vector3(0, 1.2, 0)) - global_position
		var flat := Vector2(diff.x, diff.z)
		cam_rot_y = rad_to_deg(atan2(-flat.x, -flat.y))
		cam_rot_x = clampf(rad_to_deg(atan2(diff.y, flat.length())), -55.0, 55.0)

	var cam_lerp := 6.0 if whip_lag_timer > 0.0 else 24.0
	camera_pivot.rotation_degrees.y = lerp_angle(deg_to_rad(camera_pivot.rotation_degrees.y), deg_to_rad(cam_rot_y), cam_lerp * delta) * 180.0 / PI
	camera_pivot.rotation_degrees.x = lerpf(camera_pivot.rotation_degrees.x, cam_rot_x, cam_lerp * delta)
	if spring_arm:
		spring_arm.spring_length = lerpf(spring_arm.spring_length, camera_distance, 10.0 * delta)
	var target_fov := dash_fov_kick if state == MoveState.DASH else base_fov
	camera.fov = lerpf(camera.fov, target_fov, 12.0 * delta)
