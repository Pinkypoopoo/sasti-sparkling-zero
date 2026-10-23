class_name GestureCombat
extends Node

# --- Data-Driven Gesture Action Table ---
var action_table: Dictionary = {
	"STRIKE_UP": {
		"step_force": 12.0, "lunge_force": 14.0, "vertical_lift": 6.0,
		"damage": 85.0, "posture_damage": 35.0, "anim_name": "Slash_Up"
	},
	"STRIKE_DOWN": {
		"step_force": 10.0, "lunge_force": 16.0, "vertical_lift": -8.0,
		"damage": 110.0, "posture_damage": 55.0, "anim_name": "Helm_Splitter"
	},
	"STRIKE_LEFT": {
		"step_force": 15.0, "lunge_force": 12.0, "vertical_lift": 0.0,
		"damage": 75.0, "posture_damage": 30.0, "anim_name": "Horizontal_Left"
	},
	"STRIKE_RIGHT": {
		"step_force": 15.0, "lunge_force": 12.0, "vertical_lift": 0.0,
		"damage": 75.0, "posture_damage": 30.0, "anim_name": "Horizontal_Right"
	},
	"STRIKE_DIAG": {
		"step_force": 14.0, "lunge_force": 15.0, "vertical_lift": 3.0,
		"damage": 95.0, "posture_damage": 40.0, "anim_name": "Diagonal_Slash"
	},
	"HOOK_MIXUP": {
		"step_force": 22.0, "lunge_force": 26.0, "vertical_lift": 2.0,
		"damage": 140.0, "posture_damage": 70.0, "anim_name": "Hook_Feint"
	},
	"STANCE_STRIKE": {
		"step_force": 28.0, "lunge_force": 32.0, "vertical_lift": 1.0,
		"damage": 190.0, "posture_damage": 90.0, "anim_name": "Iaido_Thrust"
	},
	"SUPER_PARRY": {
		"step_force": 0.0, "lunge_force": 8.0, "vertical_lift": 0.0,
		"damage": 220.0, "posture_damage": 140.0, "anim_name": "Mikiri_Counter"
	}
}

# --- 3-Tier Clash Escalation & Impact Stencil ---
var clash_tension: int = 0
var last_parry_time: float = 0.0
var impact_frame_cooldown: float = 0.0
var impact_flash_timer: float = 0.0
var hitstop_timer: float = 0.0

# --- Dedicated Spell Weave System ---
var is_spell_weave_mode: bool = false
var active_infusion: String = "NONE"
var infusion_timer: float = 0.0
var active_element: String = "NONE"
var selected_element_1: int = -1
var selected_element_2: int = -1

const ELEMENTS: Array[String] = ["FIRE", "WIND", "LIGHTNING", "WATER", "EARTH"]
const ELEMENT_COLORS: Array[Color] = [
	Color(1.0, 0.28, 0.12),
	Color(0.2, 0.92, 0.65),
	Color(0.98, 0.88, 0.15),
	Color(0.18, 0.6, 1.0),
	Color(0.85, 0.52, 0.18)
]

# --- Touch & Gesture State (Zero Allocations) ---
var is_right_touch: bool = false
var touch_start: Vector2 = Vector2.ZERO
var touch_current: Vector2 = Vector2.ZERO
var gesture_segments: Array[Vector2] = []
var parry_hold_timer: float = 0.0
var hook_triggered_this_stroke: bool = false
var current_gesture_label: String = "IDLE"

# --- Target Health & Posture System ---
var target_stats: Dictionary = {}
var last_damage_dealt: float = 0.0

# --- Object Pooling ---
var slash_smear_mesh: MeshInstance3D = null
var slash_smear_timer: float = 0.0
var shockwave_rings: Array[MeshInstance3D] = []
var shockwave_timers: Array[float] = [0.0, 0.0, 0.0]
var projectile_pool: Array[MeshInstance3D] = []
var projectile_active: Array[bool] = []
var projectile_velocities: Array[Vector3] = []
var projectile_lifetimes: Array[float] = []
var projectile_damages: Array[float] = []
var projectile_postures: Array[float] = []
var projectile_types: Array[String] = []

@export var player_node_path: NodePath = NodePath("../Player")
@onready var player: PlayerController = get_node_or_null(player_node_path) as PlayerController

func _ready() -> void:
	_init_target_dummies()
	_init_object_pools()

func _init_target_dummies() -> void:
	var dummies := get_tree().get_nodes_in_group("lock_on_targets")
	for d in dummies:
		if d is Node3D:
			target_stats[d] = {
				"hp": 1500.0,
				"max_hp": 1500.0,
				"posture": 0.0,
				"max_posture": 300.0,
				"hit_flash_timer": 0.0,
				"dead_reset_timer": 0.0
			}

func _init_object_pools() -> void:
	var holder := Node3D.new()
	holder.name = "CombatFXPool"
	add_child(holder)

	# Slash Smear
	slash_smear_mesh = MeshInstance3D.new()
	var smear_crescent := BoxMesh.new()
	smear_crescent.size = Vector3(2.6, 0.12, 1.8)
	slash_smear_mesh.mesh = smear_crescent
	slash_smear_mesh.top_level = true
	slash_smear_mesh.visible = false

	var smear_mat := StandardMaterial3D.new()
	smear_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	smear_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smear_mat.albedo_color = Color(1.0, 0.95, 0.6, 0.8)
	smear_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	slash_smear_mesh.material_override = smear_mat
	holder.add_child(slash_smear_mesh)

	# Shockwave Rings
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.1

	for i in range(3):
		var sw := MeshInstance3D.new()
		sw.mesh = torus
		sw.top_level = true
		sw.visible = false

		var sw_mat := StandardMaterial3D.new()
		sw_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		sw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sw_mat.albedo_color = Color(0.2, 0.9, 1.0, 0.8)
		sw.material_override = sw_mat

		holder.add_child(sw)
		shockwave_rings.append(sw)

	# 16 Pooled Projectiles
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.4
	sphere_mesh.height = 0.8

	for i in range(16):
		var p := MeshInstance3D.new()
		p.mesh = sphere_mesh
		p.top_level = true
		p.visible = false

		var p_mat := StandardMaterial3D.new()
		p_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		p_mat.albedo_color = Color(1.0, 0.4, 0.1, 1.0)
		p.material_override = p_mat

		holder.add_child(p)
		projectile_pool.append(p)
		projectile_active.append(false)
		projectile_velocities.append(Vector3.ZERO)
		projectile_lifetimes.append(0.0)
		projectile_damages.append(0.0)
		projectile_postures.append(0.0)
		projectile_types.append("SPEAR")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C or event.keycode == KEY_ALT:
			is_spell_weave_mode = not is_spell_weave_mode
			selected_element_1 = -1
			selected_element_2 = -1
		elif event.keycode == KEY_P:
			simulate_clash(false)

	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			is_spell_weave_mode = not is_spell_weave_mode
			selected_element_1 = -1
			selected_element_2 = -1

	# Touch / Mouse Gesture Handling
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_on_touch_press(event.position)
		else:
			_on_touch_release(event.position)
	elif event is InputEventMouseMotion and is_right_touch:
		_on_touch_drag(event.position)

	if event is InputEventScreenTouch:
		if event.position.x >= get_viewport().get_visible_rect().size.x * 0.45:
			if event.pressed:
				_on_touch_press(event.position)
			else:
				_on_touch_release(event.position)
	elif event is InputEventScreenDrag and is_right_touch:
		_on_touch_drag(event.position)

func _on_touch_press(pos: Vector2) -> void:
	is_right_touch = true
	touch_start = pos
	touch_current = pos
	parry_hold_timer = 0.18
	hook_triggered_this_stroke = false
	current_gesture_label = "PARRY_STANCE"
	gesture_segments.clear()
	gesture_segments.append(pos)

	if is_spell_weave_mode:
		_handle_weave_touch_press(pos)

func _on_touch_drag(pos: Vector2) -> void:
	touch_current = pos
	if gesture_segments.is_empty() or pos.distance_to(gesture_segments[-1]) >= 24.0:
		gesture_segments.append(pos)
		if not is_spell_weave_mode and not hook_triggered_this_stroke and gesture_segments.size() >= 3:
			_check_hook_mixup()

	if is_spell_weave_mode:
		_handle_weave_touch_drag(pos)

func _on_touch_release(pos: Vector2) -> void:
	touch_current = pos
	is_right_touch = false

	if is_spell_weave_mode:
		_handle_weave_touch_release(pos)
		return

	var dist := touch_start.distance_to(pos)
	if dist < 30.0:
		if parry_hold_timer > 0.0:
			trigger_parry()
		else:
			current_gesture_label = "GUARD_RELEASE"
	else:
		_evaluate_strike(touch_start, pos)

func _check_hook_mixup() -> void:
	var n := gesture_segments.size()
	var v1 := (gesture_segments[n - 2] - gesture_segments[n - 3]).normalized()
	var v2 := (gesture_segments[n - 1] - gesture_segments[n - 2]).normalized()
	if v1.dot(v2) < -0.2:
		hook_triggered_this_stroke = true
		_commit_strike("HOOK_MIXUP", (gesture_segments[-1] - gesture_segments[0]).normalized())

func _evaluate_strike(p_start: Vector2, p_end: Vector2) -> void:
	var delta := p_end - p_start
	var dir := delta.normalized()
	var angle := rad_to_deg(atan2(dir.y, dir.x))

	var move_key := "STRIKE_RIGHT"
	if angle >= -135.0 and angle < -45.0:
		move_key = "STRIKE_UP"
	elif angle >= 45.0 and angle < 135.0:
		move_key = "STRIKE_DOWN"
	elif absf(angle) >= 135.0:
		move_key = "STRIKE_LEFT"
	elif absf(angle) < 45.0:
		move_key = "STRIKE_RIGHT"

	if absf(angle + 45.0) < 22.5 or absf(angle - 45.0) < 22.5:
		move_key = "STRIKE_DIAG"

	_commit_strike(move_key, dir)

func _commit_strike(move_key: String, swipe_dir_2d: Vector2) -> void:
	if not action_table.has(move_key):
		return

	var data: Dictionary = action_table[move_key]
	current_gesture_label = move_key

	if player:
		player.apply_hit_shear(swipe_dir_2d, 12.0)
		var forward := -player.global_transform.basis.z
		var lunge: float = data.get("lunge_force", 14.0) * player.race_damage_mult
		player.velocity += forward * lunge + Vector3(0, data.get("vertical_lift", 0.0), 0)

	_spawn_slash_smear(swipe_dir_2d)
	_hitscan_target(data.get("damage", 80.0), data.get("posture_damage", 35.0))

func _spawn_slash_smear(dir_2d: Vector2) -> void:
	if not slash_smear_mesh or not player:
		return
	slash_smear_mesh.global_transform = player.global_transform
	slash_smear_mesh.translate(Vector3(0, 1.2, -1.6))
	slash_smear_mesh.rotation.z = -atan2(dir_2d.y, dir_2d.x)
	slash_smear_mesh.visible = true
	slash_smear_timer = 0.08

func _hitscan_target(dmg: float, posture_dmg: float) -> void:
	if not player:
		return
	var targets := get_tree().get_nodes_in_group("lock_on_targets")
	var hit_target: Node3D = null
	var min_dist: float = 4.5

	if active_infusion == "WIND":
		min_dist += 2.0
	if active_infusion == "FIRE":
		dmg *= 1.35

	for t in targets:
		if t is Node3D and t != player:
			var d := player.global_position.distance_to(t.global_position)
			if d < min_dist:
				min_dist = d
				hit_target = t as Node3D

	if hit_target:
		apply_damage_to_dummy(hit_target, dmg * player.race_damage_mult, posture_dmg)
		if active_infusion == "WATER":
			player.mana = minf(player.max_mana, player.mana + 15.0)

func apply_damage_to_dummy(dummy: Node3D, dmg: float, posture_dmg: float) -> void:
	if not target_stats.has(dummy):
		target_stats[dummy] = {
			"hp": 1500.0, "max_hp": 1500.0,
			"posture": 0.0, "max_posture": 300.0,
			"hit_flash_timer": 0.0, "dead_reset_timer": 0.0
		}

	var stats: Dictionary = target_stats[dummy]
	stats["hp"] = maxf(0.0, stats["hp"] - dmg)
	stats["posture"] = minf(stats["max_posture"], stats["posture"] + posture_dmg)
	stats["hit_flash_timer"] = 0.12
	last_damage_dealt = dmg

	if stats["hp"] <= 0.0 and stats["dead_reset_timer"] <= 0.0:
		stats["dead_reset_timer"] = 1.2
		simulate_clash(true)

func trigger_parry() -> void:
	current_gesture_label = "PERFECT_PARRY"
	simulate_clash(false)

func simulate_clash(is_super: bool) -> void:
	last_parry_time = Time.get_ticks_msec() / 1000.0
	clash_tension += 1

	if player:
		var spark_color := Color(0.2, 0.9, 1.0)
		if clash_tension >= 4:
			spark_color = Color(1.0, 0.85, 0.2)
		if clash_tension >= 5:
			spark_color = Color(1.0, 0.2, 0.25)

		_spawn_shockwave(player.global_position + Vector3(0, 1.2, -1.2), spark_color)
		player.apply_hit_shear(Vector2.ZERO, 10.0 + clash_tension * 2.0)

	if is_super or clash_tension >= 6:
		clash_tension = 0
		if impact_frame_cooldown <= 0.0:
			impact_flash_timer = 0.055
			impact_frame_cooldown = 8.0

func _spawn_shockwave(pos: Vector3, color: Color) -> void:
	for i in range(shockwave_rings.size()):
		if shockwave_timers[i] <= 0.0:
			var sw := shockwave_rings[i]
			sw.global_position = pos
			sw.visible = true
			sw.scale = Vector3.ONE * 0.5
			var mat: StandardMaterial3D = sw.material_override
			if mat:
				mat.albedo_color = color
			shockwave_timers[i] = 0.16
			break

# --- 3-Beat Spell Weave Implementation ---
func _get_pentagon_node_pos(idx: int) -> Vector2:
	var vp_size := get_viewport().get_visible_rect().size
	var center := Vector2(vp_size.x * 0.74, vp_size.y * 0.54)
	var radius: float = minf(vp_size.x, vp_size.y) * 0.20
	var angle := -PI * 0.5 + float(idx) * (TAU / 5.0)
	return center + Vector2(cos(angle), sin(angle)) * radius

func _handle_weave_touch_press(pos: Vector2) -> void:
	for i in range(5):
		if pos.distance_to(_get_pentagon_node_pos(i)) <= 42.0:
			selected_element_1 = i
			selected_element_2 = -1
			return

func _handle_weave_touch_drag(pos: Vector2) -> void:
	if selected_element_1 >= 0 and selected_element_2 < 0:
		for i in range(5):
			if i != selected_element_1 and pos.distance_to(_get_pentagon_node_pos(i)) <= 38.0:
				selected_element_2 = i
				_fuse_elements()
				return

func _handle_weave_touch_release(pos: Vector2) -> void:
	if selected_element_1 >= 0 and selected_element_2 < 0:
		var dist := touch_start.distance_to(pos)
		if dist < 45.0:
			# Beat 1: Single element infusion
			active_infusion = ELEMENTS[selected_element_1]
			infusion_timer = 12.0
			current_gesture_label = "INFUSION: " + active_infusion
			if player:
				player.update_cel_shader(player.cel_cut_threshold, player.outline_width, player.rim_strength, ELEMENT_COLORS[selected_element_1])
			selected_element_1 = -1
			return

	# Beat 3: Delivery Swipe
	var delta := pos - touch_start
	if delta.length() >= 60.0:
		var dir := delta.normalized()
		if dir.y < -0.7:
			_fire_spell_projectile("SPEAR", dir)
		elif absf(dir.x) > 0.7:
			_fire_spell_projectile("CRESCENT", dir)
		elif dir.y > 0.7:
			_fire_spell_projectile("METEOR", dir)
		else:
			_fire_spell_projectile("SWARM", dir)

	selected_element_1 = -1
	selected_element_2 = -1

func _fuse_elements() -> void:
	var a := mini(selected_element_1, selected_element_2)
	var b := maxi(selected_element_1, selected_element_2)

	# 0: FIRE, 1: WIND, 2: LIGHTNING, 3: WATER, 4: EARTH
	if a == 0 and b == 1:
		active_element = "SCORCH (Plasma)"
	elif a == 1 and b == 3:
		active_element = "FROST (Ice)"
	elif a == 0 and b == 4:
		active_element = "MAGMA (Lava)"
	elif a == 2 and b == 3:
		active_element = "STORM (Black Bolt)"
	elif a == 1 and b == 4:
		active_element = "GRAVITY (Void)"
	else:
		active_element = ELEMENTS[a] + "-" + ELEMENTS[b]

func _fire_spell_projectile(type: String, dir_2d: Vector2) -> void:
	if not player:
		return

	for i in range(projectile_pool.size()):
		if not projectile_active[i]:
			projectile_active[i] = true
			var p := projectile_pool[i]
			p.visible = true
			p.global_position = player.global_position + Vector3(0, 1.4, 0)

			var fwd := -player.global_transform.basis.z
			var rgt := player.global_transform.basis.x
			var target_3d := (fwd * -dir_2d.y + rgt * dir_2d.x).normalized()

			if player.is_locked_on and is_instance_valid(player.lock_target):
				target_3d = (player.lock_target.global_position + Vector3(0, 1.2, 0) - p.global_position).normalized()

			projectile_velocities[i] = target_3d * (48.0 if type == "SPEAR" else 26.0)
			projectile_lifetimes[i] = 2.4
			projectile_damages[i] = 180.0
			projectile_postures[i] = 75.0
			projectile_types[i] = type

			var p_mat: StandardMaterial3D = p.material_override
			if p_mat:
				p_mat.albedo_color = ELEMENT_COLORS[selected_element_1] if selected_element_1 >= 0 else Color(1.0, 0.4, 0.1)

			current_gesture_label = "SPELL: " + type
			break

func _process(delta: float) -> void:
	if impact_flash_timer > 0.0:
		impact_flash_timer -= delta
	if impact_frame_cooldown > 0.0:
		impact_frame_cooldown -= delta
	if slash_smear_timer > 0.0:
		slash_smear_timer -= delta
		if slash_smear_timer <= 0.0 and slash_smear_mesh:
			slash_smear_mesh.visible = false

	if infusion_timer > 0.0:
		infusion_timer -= delta
		if infusion_timer <= 0.0:
			active_infusion = "NONE"
			if player:
				player.update_cel_shader(player.cel_cut_threshold, player.outline_width, player.rim_strength, Color(0.3, 0.7, 1.0))

	# Zero-allocation parry hold evaluation
	if is_right_touch and parry_hold_timer > 0.0:
		parry_hold_timer -= delta
		if parry_hold_timer <= 0.0 and touch_current.distance_to(touch_start) < 30.0:
			current_gesture_label = "HOLD_GUARD"
			if player:
				player.state = PlayerController.MoveState.GUARD

	# Shockwaves update
	for i in range(shockwave_rings.size()):
		if shockwave_timers[i] > 0.0:
			shockwave_timers[i] -= delta
			shockwave_rings[i].scale += Vector3.ONE * delta * 24.0
			if shockwave_timers[i] <= 0.0:
				shockwave_rings[i].visible = false

	# Projectiles physics
	for i in range(projectile_pool.size()):
		if projectile_active[i]:
			projectile_lifetimes[i] -= delta
			var p := projectile_pool[i]
			p.global_position += projectile_velocities[i] * delta

			# Hit check against dummies
			for d in target_stats.keys():
				if is_instance_valid(d) and d is Node3D:
					if p.global_position.distance_to(d.global_position + Vector3(0, 1.2, 0)) < 1.6:
						apply_damage_to_dummy(d, projectile_damages[i], projectile_postures[i])
						projectile_active[i] = false
						p.visible = false
						break

			if projectile_lifetimes[i] <= 0.0:
				projectile_active[i] = false
				p.visible = false

	# Target dummy timers & recovery
	for d in target_stats.keys():
		if is_instance_valid(d):
			var s: Dictionary = target_stats[d]
			if s["hit_flash_timer"] > 0.0:
				s["hit_flash_timer"] -= delta
			if s["dead_reset_timer"] > 0.0:
				s["dead_reset_timer"] -= delta
				if s["dead_reset_timer"] <= 0.0:
					s["hp"] = s["max_hp"]
					s["posture"] = 0.0
