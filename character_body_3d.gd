class_name PlayerController
extends CharacterBody3D

enum MoveState { GROUND, SPRINT, FLIGHT, STEP, DASH, WINDUP, ATTACK_RECOVERY, GUARD, HITSTUN }
enum DashStyle { DBZ_VANISH_RUSH, BLEACH_SONIDO, SANDEVISTAN_ECHO, MACH_CONE_BURST, SHADOW_ABYSS_SINK, TOUKI_HORIZON_FLASH }

# --- Custom Race Database ---
var custom_races: Dictionary = {
	"Human_Touki": {
		"max_hp": 1000.0, "hp_regen": 15.0, "max_mana": 100.0, "mana_regen": 10.0,
		"physical_strength": 1.0, "base_power": 1.0, "step_mult": 1.15, "flight_mult": 1.0,
		"hyper_armor": false, "dash_style": DashStyle.DBZ_VANISH_RUSH, "aura_color": Color(0.3, 0.7, 1.0),
		"model_path": "", "model_scale": 1.0, "model_rot_offset": 0.0
	},
	"Demon_Fiend": {
		"max_hp": 1400.0, "hp_regen": 20.0, "max_mana": 80.0, "mana_regen": 8.0,
		"physical_strength": 1.35, "base_power": 0.9, "step_mult": 0.9, "flight_mult": 0.85,
		"hyper_armor": true, "dash_style": DashStyle.SHADOW_ABYSS_SINK, "aura_color": Color(0.8, 0.1, 0.2),
		"model_path": "", "model_scale": 1.1, "model_rot_offset": 0.0
	}
}
var active_race_name: String = "Human_Touki"

# --- Tunables (DevStudio Sync) ---
@export var run_speed: float = 16.0
@export var sprint_speed: float = 28.0
@export var flight_speed: float = 32.0
@export var step_speed: float = 34.0
@export var dash_speed: float = 64.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 0.05
@export var jump_velocity: float = 12.0
@export var altitude_burst: float = 18.0
@export var feint_threshold_px: float = 95.0
@export var camera_distance: float = 4.0
@export var base_fov: float = 78.0
@export var dash_fov_kick: float = 102.0
@export var camera_whip_lag: float = 0.055
@export var combat_shoulder_offset: float = 0.55
@export var vanish_strobe_hz: float = 18.0
@export var letterbox_amount: float = 0.0
@export var cel_cut_threshold: float = 0.45
@export var outline_width: float = 0.025
@export var rim_strength: float = 0.8

# --- State ---
var state: MoveState = MoveState.GROUND
var input_frame: Dictionary = { "move_vec": Vector2.ZERO, "fly_vertical": 0.0, "jump_just_pressed": false, "sprint_held": false }
var dash_timer: float = 0.0
var dash_cd_timer: float = 0.0
var dash_style: DashStyle = DashStyle.DBZ_VANISH_RUSH
var whip_lag_timer: float = 0.0
var is_momentum_coasting: bool = false
var coasting_timer: float = 0.0
var coasting_velocity: Vector3 = Vector3.ZERO
var jump_count: int = 0
var hp: float = 1000.0
var mana: float = 100.0

# --- Mobile Touch ---
var left_touch_id: int = -1
var left_touch_start: Vector2 = Vector2.ZERO
var left_touch_current: Vector2 = Vector2.ZERO
var left_touch_start_time: float = 0.0
var is_left_dragging: bool = false

# --- Jiggle Physics ---
var jiggle_enabled: bool = true
var jiggle_stiffness: float = 18.0
var jiggle_damping: float = 4.5
var jiggle_gravity: float = 0.6
var jiggle_bone_names: Array[String] = []
var jiggle_bones: Array[Dictionary] = [] 

# --- Camera ---
var cam_rot_x: float = -12.0
var cam_rot_y: float = 0.0
var mouse_captured: bool = true

# --- Nodes ---
@onready var visual_root: Node3D = $VisualRoot
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var combat: Node = get_node("../CombatManager")

var custom_model_root: Node3D = null
var active_skeleton: Skeleton3D = null
var active_anim_player: AnimationPlayer = null

func _ready() -> void:
	_register_input_actions()
	DirAccess.make_dir_recursive_absolute("user://models")
	DirAccess.make_dir_recursive_absolute("user://vfx")
	apply_race_by_name(active_race_name)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _register_input_actions() -> void:
	var acts = {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"jump": KEY_SPACE, "dash": KEY_SHIFT, "toggle_fly": KEY_F
	}
	for a in acts:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev = InputEventKey.new(); ev.physical_keycode = acts[a]
			InputMap.action_add_event(a, ev)

func apply_race_by_name(race_name: String) -> void:
	if not custom_races.has(race_name): return
	active_race_name = race_name
	var r: Dictionary = custom_races[race_name]
	hp = r["max_hp"]
	mana = r["max_mana"]
	dash_style = r["dash_style"] as DashStyle
	if r["model_path"] != "": swap_custom_model(r["model_path"])

func swap_custom_model(path: String) -> void:
	var new_node: Node3D = null
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is PackedScene: new_node = res.instantiate()
	elif FileAccess.file_exists(path):
		var gltf := GLTFDocument.new(); var state_obj := GLTFState.new()
		if gltf.append_from_file(path, state_obj) == OK: new_node = gltf.generate_scene(state_obj)
	if not new_node: return
	if custom_model_root: custom_model_root.queue_free()
	custom_model_root = new_node; visual_root.add_child(custom_model_root)
	active_skeleton = _find_skeleton(custom_model_root)
	active_anim_player = _find_anim_player(custom_model_root)
	_setup_jiggle_bones()

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for c in node.get_children():
		var res = _find_skeleton(c); if res: return res
	return null

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for c in node.get_children():
		var res = _find_anim_player(c); if res: return res
	return null

func _setup_jiggle_bones() -> void:
	jiggle_bones.clear()
	if not active_skeleton: return
	for b_name in jiggle_bone_names:
		var idx = active_skeleton.find_bone(b_name)
		if idx != -1: jiggle_bones.append({"idx": idx, "vel": Vector3.ZERO, "rot": Quaternion.IDENTITY})

func _unhandled_input(event: InputEvent) -> void:
	var is_touch := DisplayServer.is_touchscreen_available()
	if event is InputEventMouseMotion and mouse_captured and not is_touch:
		cam_rot_y -= event.relative.x * 0.18
		cam_rot_x -= event.relative.y * 0.18; cam_rot_x = clamp(cam_rot_x, -75, 75)

	if event is InputEventScreenTouch:
		if event.position.x < get_viewport().size.x * 0.5:
			if combat and event.position.distance_to(combat.left_dot_pos) < combat.left_dot_expanded_r and combat.is_left_dot_active: pass
			elif event.pressed:
				left_touch_id = event.index; left_touch_start = event.position
				left_touch_current = event.position; left_touch_start_time = Time.get_ticks_msec() / 1000.0
				is_left_dragging = false
			elif event.index == left_touch_id: _handle_left_touch_release(event.position); left_touch_id = -1
	elif event is InputEventScreenDrag and event.index == left_touch_id:
		left_touch_current = event.position; is_left_dragging = true

func _handle_left_touch_release(pos: Vector2) -> void:
	var duration = (Time.get_ticks_msec() / 1000.0) - left_touch_start_time
	var delta = pos - left_touch_start; var dist = delta.length(); var dir = delta.normalized()
	if left_touch_start.x < 70.0 or (dist > 135.0 and abs(dir.y) > 0.72):
		if dir.y < -0.72: trigger_dash(Vector3.UP); state = MoveState.FLIGHT
		elif dir.y > 0.72: trigger_dash(Vector3.DOWN)
	elif duration <= 0.16 and dist >= 45.0:
		var cf = -camera.global_transform.basis.z; cf.y = 0; cf = cf.normalized()
		var cr = camera.global_transform.basis.x; cr.y = 0; cr = cr.normalized()
		trigger_dash((cr * dir.x + cf * dir.y).normalized())
	elif duration < 0.16 and dist < 20.0: _trigger_jump()

func _trigger_jump() -> void:
	jump_count += 1
	if jump_count == 1: velocity.y = jump_velocity
	elif jump_count == 2: velocity.y = jump_velocity * 1.15
	elif jump_count >= 3: state = MoveState.FLIGHT; velocity.y = altitude_burst

func trigger_dash(dir: Vector3) -> void:
	if dash_cd_timer > 0: return
	state = MoveState.DASH; dash_timer = dash_duration; dash_cd_timer = dash_cooldown
	if is_locked_on() and dir.dot(-camera.global_transform.basis.z) > 0.7 and global_position.distance_to(combat.lock_target.global_position) < 7.5:
		global_position = combat.lock_target.global_position + combat.lock_target.global_transform.basis.z * 2.2
		cam_rot_y += 180.0; whip_lag_timer = camera_whip_lag
	else: velocity = dir * dash_speed

func is_locked_on() -> bool: return combat and combat.lock_target != null

func _physics_process(delta: float) -> void:
	if dash_cd_timer > 0: dash_cd_timer -= delta
	if whip_lag_timer > 0: whip_lag_timer -= delta
	_update_input_frame()
	match state:
		MoveState.GROUND: _process_ground(delta)
		MoveState.FLIGHT: _process_flight(delta)
		MoveState.DASH: _process_dash(delta)
	move_and_slide()
	if is_on_floor(): jump_count = 0
	_process_jiggle(delta)

func _update_input_frame() -> void:
	if left_touch_id != -1 and is_left_dragging:
		var delta = left_touch_current - left_touch_start
		input_frame["move_vec"] = delta.normalized() if delta.length() > 20 else Vector2.ZERO
		input_frame["sprint_held"] = delta.length() > 75.0
	else:
		input_frame["move_vec"] = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		input_frame["sprint_held"] = Input.is_action_pressed("dash")

func _process_ground(delta: float) -> void:
	var cf = -camera.global_transform.basis.z; cf.y = 0; cf = cf.normalized()
	var cr = camera.global_transform.basis.x; cr.y = 0; cr = cr.normalized()
	var move_dir = (cr * input_frame["move_vec"].x + cf * -input_frame["move_vec"].y).normalized()
	var ts = sprint_speed if input_frame["sprint_held"] else run_speed
	velocity.x = lerp(velocity.x, move_dir.x * ts, 12.0 * delta)
	velocity.z = lerp(velocity.z, move_dir.z * ts, 12.0 * delta)
	velocity.y += get_gravity().y * delta
	if move_dir.length() > 0.1: visual_root.rotation.y = lerp_angle(visual_root.rotation.y, atan2(-move_dir.x, -move_dir.z), 15 * delta)

func _process_flight(delta: float) -> void:
	var cb = camera.global_transform.basis
	var fd = (cb.x * input_frame["move_vec"].x + cb.y * -input_frame["move_vec"].y).normalized()
	velocity = velocity.lerp(fd * flight_speed, 8 * delta) if not is_momentum_coasting else velocity.lerp(coasting_velocity, 2 * delta)

func _process_dash(delta: float) -> void:
	dash_timer -= delta; if dash_timer <= 0: state = MoveState.GROUND

func _process_jiggle(_delta: float) -> void: pass

func _process(delta: float) -> void: _update_camera(delta)

func _update_camera(delta: float) -> void:
	var ls = 36.0 if whip_lag_timer <= 0 else 5.0
	camera_pivot.rotation_degrees.y = lerp_angle(deg_to_rad(camera_pivot.rotation_degrees.y), deg_to_rad(cam_rot_y), ls * delta) * 180 / PI
	camera_pivot.rotation_degrees.x = lerp(camera_pivot.rotation_degrees.x, cam_rot_x, ls * delta)
	if is_locked_on():
		var tp = combat.lock_target.global_position + Vector3(0, 1.4, 0)
		var tr = camera.global_transform.looking_at(tp, Vector3.UP).basis.get_euler()
		cam_rot_y = rad_to_deg(tr.y); cam_rot_x = rad_to_deg(tr.x)
