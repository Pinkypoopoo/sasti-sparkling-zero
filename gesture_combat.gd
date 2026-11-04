class_name GestureCombat
extends Node

enum AIMode { STATIC_BAG, FEINT_TESTER, COMBO_ATTACKER, ADAPTIVE_RIVAL }

var left_dot_ratio: Vector2 = Vector2(0.18, 0.56)
var right_dot_ratio: Vector2 = Vector2(0.82, 0.64)
var left_dot_pos: Vector2 = Vector2.ZERO
var right_dot_pos: Vector2 = Vector2.ZERO
var left_dot_collapsed_r: float = 46.0
var right_dot_collapsed_r: float = 48.0
var left_dot_expanded_r: float = 135.0
var right_dot_expanded_r: float = 145.0

var is_left_dot_active: bool = false
var is_right_dot_active: bool = false
var right_dot_pinned: bool = false
var left_dot_pinned: bool = false
var auto_lock_enabled: bool = true

var right_touch_id: int = -1
var left_weave_touch_id: int = -1
var right_touch_start: Vector2 = Vector2.ZERO
var right_touch_current: Vector2 = Vector2.ZERO
var left_anchor_pos: Vector2 = Vector2.ZERO
var left_weave_current: Vector2 = Vector2.ZERO
var left_press_time: float = -10.0
var right_press_time: float = -10.0

# --- Riptide GP Swipe-Sequence State ---
var current_swipe_chain: Array[String] = []
var swipe_chain_timer: float = 0.0
var active_infusion: String = "READY"
var last_combat_action: String = "READY"

# --- Projectiles Pool ---
var projectiles: Array[Dictionary] = []

var target_stats: Dictionary = {}
var player_habits: Dictionary = {}
var ai_mode: AIMode = AIMode.ADAPTIVE_RIVAL
var ai_reaction_delay: float = 0.16
var ai_adaptation_rate: float = 0.30
var parry_window_timer: float = 0.0
var sonic_sway_timer: float = 0.0
var impact_flash_timer: float = 0.0
var impact_frame_cooldown: float = 0.0
var clash_tension: int = 0

@onready var player: PlayerController = get_node_or_null("../Player") as PlayerController

func _ready() -> void:
	_update_dot_positions()
	get_viewport().size_changed.connect(_update_dot_positions)
	_init_targets()
	_setup_projectile_pool()

func _setup_projectile_pool() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 0.9
	for i in range(6):
		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		mi.top_level = true
		mi.visible = false
		var mat := StandardMaterial3D.new()
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.95, 0.15, 0.2)
		mi.material_override = mat
		add_child(mi)
		projectiles.append({"mesh": mi, "mat": mat, "vel": Vector3.ZERO, "timer": 0.0, "dmg": 150.0, "posture": 60.0})

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
				"hit_flash": 0.0, "ai_state": "IDLE", "whiff_timer": 0.0,
				"vel": Vector3.ZERO, "home_pos": (t as Node3D).global_position
			}

func is_point_in_right_dot(pos: Vector2) -> bool:
	var r := right_dot_expanded_r if (is_right_dot_active or right_dot_pinned) else right_dot_collapsed_r * 1.45
	return pos.distance_to(right_dot_pos) <= r

func is_point_in_left_dot(pos: Vector2) -> bool:
	var r := left_dot_expanded_r if (is_left_dot_active or left_dot_pinned) else left_dot_collapsed_r * 1.45
	return pos.distance_to(left_dot_pos) <= r

func _input(event: InputEvent) -> void:
	_update_dot_positions()

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

func _start_right_orb(pos: Vector2) -> void:
	is_right_dot_active = true
	right_touch_start = pos
	right_touch_current = pos
	parry_window_timer = 0.18
	sonic_sway_timer = 0.35
	last_combat_action = "ATK_ORB"
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
		player.velocity += (cr * d2.x + cf * -d2.y).normalized() * 14.0

func _release_right_orb(pos: Vector2) -> void:
	var dist := pos.distance_to(right_touch_start)
	if dist < 24.0:
		if parry_window_timer > 0.0:
			_trigger_parry()
		else:
			_trigger_sonic_sway()
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

# --- Riptide GP Swipe-Sequence + Physical Step-Weave ---
func _start_left_orb(pos: Vector2) -> void:
	is_left_dot_active = true
	left_anchor_pos = pos
	left_weave_current = pos
	if swipe_chain_timer <= 0.0:
		current_swipe_chain.clear()
	swipe_chain_timer = 0.85
	if auto_lock_enabled and player and not player.is_locked_on:
		player.toggle_lock_on()

func _drag_left_orb(pos: Vector2) -> void:
	left_weave_current = pos
	var delta := pos - left_anchor_pos
	if delta.length() >= 40.0 and current_swipe_chain.size() < 3:
		var dir_str := _vec_to_cardinal(delta.normalized())
		current_swipe_chain.append(dir_str)
		left_anchor_pos = pos
		swipe_chain_timer = 0.85
		active_infusion = ",".join(current_swipe_chain)
		last_combat_action = "WEAVE: " + active_infusion
		_execute_swipe_step(dir_str)

func _vec_to_cardinal(d: Vector2) -> String:
	if absf(d.x) > absf(d.y):
		return "RIGHT" if d.x > 0.0 else "LEFT"
	return "DOWN" if d.y > 0.0 else "UP"

func _execute_swipe_step(dir_str: String) -> void:
	if not player: return
	var cf := -player.camera.global_transform.basis.z; cf.y = 0.0; cf = cf.normalized()
	var cr := player.camera.global_transform.basis.x; cr.y = 0.0; cr = cr.normalized()
	var step_dir := cf
	match dir_str:
		"UP": step_dir = cf
		"DOWN": step_dir = -cf
		"LEFT": step_dir = -cr
		"RIGHT": step_dir = cr
	player.velocity = step_dir * 24.0 + Vector3(0.0, 5.5, 0.0)
	player.trigger_air_hang(0.45)
	if player.dash_vfx:
		player.dash_vfx.spawn_step_sigil(player.global_position, Color(0.95, 0.15, 0.25), 1.25)

func _release_left_orb(pos: Vector2) -> void:
	var delta := pos - left_anchor_pos
	if current_swipe_chain.is_empty() and delta.length() < 24.0:
		left_dot_pinned = not left_dot_pinned
		is_left_dot_active = left_dot_pinned
		return

	if delta.length() >= 32.0 and current_swipe_chain.size() < 3:
		var dir_str := _vec_to_cardinal(delta.normalized())
		current_swipe_chain.append(dir_str)
		_execute_swipe_step(dir_str)

	is_left_dot_active = left_dot_pinned
	if not current_swipe_chain.is_empty():
		_cast_matched_spell(",".join(current_swipe_chain))

func _cast_matched_spell(seq_key: String) -> void:
	if not player or not player.data_store: return
	var spells: Dictionary = player.data_store.spell_slots
	var chosen_key := "Spell_Slot_1"
	for k in spells.keys():
		if str(spells[k].get("sequence", "")).to_upper().replace(" ", "") == seq_key:
			chosen_key = k
			break
	var sp_data: Dictionary = spells[chosen_key]
	var col_arr: Array = sp_data.get("color", [0.95, 0.15, 0.2])
	var col := Color(col_arr[0], col_arr[1], col_arr[2])

	last_combat_action = "%s [%s]" % [chosen_key, seq_key]
	active_infusion = chosen_key
	player.velocity.y = float(sp_data.get("vertical_hop", 5.0))
	player.trigger_air_hang(0.55)
	if player.dash_vfx:
		player.dash_vfx.spawn_step_sigil(player.global_position, col, 1.6)

	_spawn_spell_projectile(col, float(sp_data.get("proj_speed", 48.0)), float(sp_data.get("dmg", 150.0)) * player.base_power, float(sp_data.get("posture", 65.0)))
	current_swipe_chain.clear()

func _spawn_spell_projectile(col: Color, spd: float, dmg: float, post: float) -> void:
	if not player: return
	for p in projectiles:
		if p["timer"] <= 0.0:
			var mi: MeshInstance3D = p["mesh"]
			var mat: StandardMaterial3D = p["mat"]
			mi.global_position = player.global_position + Vector3(0, 1.2, 0)
			var aim_dir := -player.camera.global_transform.basis.z
			if player.is_locked_on and is_instance_valid(player.lock_target):
				aim_dir = ((player.lock_target.global_position + Vector3(0, 1.0, 0)) - mi.global_position).normalized()
			p["vel"] = aim_dir * spd
			p["timer"] = 2.0
			p["dmg"] = dmg
			p["posture"] = post
			mat.albedo_color = col
			mi.visible = true
			break

func _trigger_parry() -> void:
	last_combat_action = "Z-VANISH PARRY!"
	if player:
		player.mana = minf(player.max_mana, player.mana + 18.0)
		if player.dash_vfx:
			player.dash_vfx.spawn_step_sigil(player.global_position + Vector3(0, 1.0, 0), Color(1, 1, 1), 1.8)
	simulate_clash(false)

func _trigger_sonic_sway() -> void:
	last_combat_action = "SONIC SWAY DODGE!"
	if player:
		player.mana = minf(player.max_mana, player.mana + 15.0)
		if player.dash_vfx:
			player.dash_vfx.spawn_step_sigil(player.global_position + Vector3(0, 1.0, 0), Color(0.4, 0.85, 1.0), 1.5)

func _trigger_super_parry() -> void:
	last_combat_action = "SUPER PARRY BREAKER!"
	if player:
		player.state = PlayerController.MoveState.GROUND
		player.mana = minf(player.max_mana, player.mana + 30.0)
	simulate_clash(true)

func _trigger_feint() -> void:
	last_combat_action = "HALF-SWIPE FEINT!"
	for t in target_stats.keys():
		target_stats[t]["ai_state"] = "BAITED_WHIFF!"
		target_stats[t]["whiff_timer"] = 0.9

func _commit_strike(dir: Vector2) -> void:
	if not player or not player.data_store: return
	var slot_key := "Slot_4_Right"
	if dir.y < -0.65: slot_key = "Slot_1_Up"
	elif dir.y > 0.65: slot_key = "Slot_2_Down"
	elif dir.x < -0.65: slot_key = "Slot_3_Left"
	elif dir.x < -0.25 and dir.y < -0.25: slot_key = "Slot_5_Diag_UL"
	elif dir.x > 0.25 and dir.y < -0.25: slot_key = "Slot_6_Diag_UR"
	elif dir.y > 0.25 and absf(dir.x) > 0.25: slot_key = "Slot_7_Burst"

	var moves: Dictionary = player.data_store.move_slots
	if not moves.has(slot_key): slot_key = moves.keys()[0]
	var data: Dictionary = moves[slot_key]
	last_combat_action = slot_key

	var fwd := -player.global_transform.basis.z
	if player.is_locked_on and is_instance_valid(player.lock_target):
		fwd = (player.lock_target.global_position - player.global_position).normalized()
	var lift := float(data.get("vertical_lift", 0.0))
	player.velocity = fwd * float(data.get("lunge_force", 16.0)) + Vector3(0, lift, 0)
	if lift > 4.0 or not player.is_on_floor():
		player.state = PlayerController.MoveState.AIR
		player.trigger_air_hang(0.45)

	player_habits[slot_key] = player_habits.get(slot_key, 0.0) + ai_adaptation_rate
	for k in player_habits.keys():
		if k != slot_key: player_habits[k] = maxf(0.0, player_habits[k] - 0.1)

	for t in target_stats.keys():
		if is_instance_valid(t) and player.global_position.distance_to(t.global_position) <= 7.5:
			var s: Dictionary = target_stats[t]
			if ai_mode == AIMode.ADAPTIVE_RIVAL and player_habits.get(slot_key, 0.0) >= 0.9 and s["whiff_timer"] <= 0.0:
				s["ai_state"] = "Z-VANISH COUNTER!"
				if t is Node3D:
					(t as Node3D).global_position = player.global_position + player.global_transform.basis.z * 2.2
				simulate_clash(false)
				player_habits[slot_key] = 0.0
				return
			var mult := 1.5 if s["whiff_timer"] > 0.0 else 1.0
			apply_damage(t, float(data.get("dmg", 90.0)) * player.physical_strength * mult, float(data.get("posture", 40.0)), fwd * float(data.get("knockback", 6.0)) + Vector3(0, float(data.get("launch_y", 0.0)), 0))

func apply_damage(t: Node3D, dmg: float, post_dmg: float, launch_vec: Vector3 = Vector3.ZERO) -> void:
	if not target_stats.has(t): return
	var s: Dictionary = target_stats[t]
	s["hp"] = maxf(0.0, s["hp"] - dmg)
	s["posture"] = minf(s["max_posture"], s["posture"] + post_dmg)
	s["hit_flash"] = 0.14
	s["vel"] = launch_vec
	if player and player.dash_vfx:
		player.dash_vfx.spawn_step_sigil(t.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.2), 1.3)
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
	if swipe_chain_timer > 0.0:
		swipe_chain_timer -= delta
		if swipe_chain_timer <= 0.0 and not is_left_dot_active:
			current_swipe_chain.clear()

	# Update Spell Projectiles
	for p in projectiles:
		if p["timer"] > 0.0:
			p["timer"] -= delta
			var mi: MeshInstance3D = p["mesh"]
			mi.global_position += p["vel"] * delta
			for t in target_stats.keys():
				if is_instance_valid(t) and mi.global_position.distance_to((t as Node3D).global_position + Vector3(0, 1.0, 0)) <= 2.2:
					apply_damage(t, p["dmg"], p["posture"], p["vel"].normalized() * 8.0 + Vector3(0, 4.0, 0))
					p["timer"] = 0.0
			if p["timer"] <= 0.0:
				mi.visible = false

	# Update Target Dummy Juggle / Knockback Physics
	for t in target_stats.keys():
		if is_instance_valid(t) and t is Node3D:
			var td := t as Node3D
			var s: Dictionary = target_stats[t]
			if s["hit_flash"] > 0.0: s["hit_flash"] -= delta
			if s["whiff_timer"] > 0.0:
				s["whiff_timer"] -= delta
				if s["whiff_timer"] <= 0.0: s["ai_state"] = "IDLE"
			var v: Vector3 = s["vel"]
			if v.length_squared() > 0.1 or td.global_position.y > 1.05:
				td.global_position += v * delta
				v.x = lerpf(v.x, 0.0, 5.0 * delta)
				v.z = lerpf(v.z, 0.0, 5.0 * delta)
				if td.global_position.y > 1.0:
					var g_mult := 0.2 if (player and player.air_hang_timer > 0.0) else 1.0
					v.y -= 24.0 * g_mult * delta
				else:
					td.global_position.y = 1.0
					v.y = 0.0
				s["vel"] = v
