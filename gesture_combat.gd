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

var current_swipe_chain: Array[String] = []
var swipe_chain_timer: float = 0.0
var active_infusion: String = "READY"
var last_combat_action: String = "READY"

var projectiles: Array[Dictionary] = []

var target_stats: Dictionary = {}
var player_habits: Dictionary = {}
var ai_mode: AIMode = AIMode.ADAPTIVE_RIVAL
var ai_telegraph_time: float = 0.46
var ai_attack_cooldown: float = 1.25
var ai_adaptation_rate: float = 0.30
var parry_window_timer: float = 0.0
var sonic_sway_holding: bool = false
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

func _find_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D: return n as MeshInstance3D
	for c in n.get_children():
		var r := _find_mesh_instance(c)
		if r: return r
	return null

func _init_targets() -> void:
	target_stats.clear()
	for t in get_tree().get_nodes_in_group("lock_on_targets"):
		if t is Node3D:
			var td := t as Node3D
			var mi := _find_mesh_instance(td)
			var dmat := StandardMaterial3D.new()
			dmat.albedo_color = Color(0.22, 0.24, 0.30)
			dmat.roughness = 0.8
			if mi:
				mi.material_override = dmat
			target_stats[td] = {
				"hp": 1500.0, "max_hp": 1500.0,
				"posture": 0.0, "max_posture": 300.0,
				"hit_flash": 0.0, "ai_state": "IDLE",
				"state_timer": 1.0, "whiff_timer": 0.0,
				"combo_left": 0, "strike_hit_done": false,
				"vel": Vector3.ZERO, "home_pos": td.global_position,
				"mat": dmat
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
				if absf(right_press_time - left_press_time) <= 0.09:
					_trigger_super_parry()
			elif is_point_in_left_dot(event.position) and left_weave_touch_id == -1:
				left_weave_touch_id = event.index
				left_press_time = Time.get_ticks_msec() / 1000.0
				_start_left_orb(event.position)
				if absf(right_press_time - left_press_time) <= 0.09:
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
	parry_window_timer = 0.24
	sonic_sway_holding = true
	if player and player.state != PlayerController.MoveState.HITSTUN:
		player.state = PlayerController.MoveState.GUARD
	if auto_lock_enabled and player and not player.is_locked_on:
		player.toggle_lock_on()
	# Check immediate Z-Vanish Parry if an enemy is currently telegraphing or swinging!
	_check_active_parry_against_enemies()

func _drag_right_orb(pos: Vector2) -> void:
	right_touch_current = pos
	var dist := right_touch_start.distance_to(pos)
	if dist >= 32.0:
		sonic_sway_holding = false
		if player and player.state != PlayerController.MoveState.WINDUP and player.state != PlayerController.MoveState.HITSTUN:
			player.state = PlayerController.MoveState.WINDUP
			var d2 := (pos - right_touch_start).normalized()
			var cf := -player.camera.global_transform.basis.z; cf.y = 0.0; cf = cf.normalized()
			var cr := player.camera.global_transform.basis.x; cr.y = 0.0; cr = cr.normalized()
			player.velocity += (cr * d2.x + cf * -d2.y).normalized() * 14.0
	else:
		sonic_sway_holding = true

func _release_right_orb(pos: Vector2) -> void:
	sonic_sway_holding = false
	var dist := pos.distance_to(right_touch_start)
	if dist < 26.0:
		if not _check_active_parry_against_enemies():
			if parry_window_timer > 0.0:
				_trigger_parry()
			else:
				_trigger_sonic_sway()
		right_dot_pinned = not right_dot_pinned
		is_right_dot_active = right_dot_pinned
		if player and player.state != PlayerController.MoveState.HITSTUN:
			player.state = PlayerController.MoveState.GROUND
		return

	is_right_dot_active = right_dot_pinned
	var feint_r := player.feint_threshold_px if player else 90.0
	if dist < feint_r:
		_trigger_feint()
	else:
		_commit_strike((pos - right_touch_start).normalized())
	if player and player.state != PlayerController.MoveState.HITSTUN and player.state != PlayerController.MoveState.AIR:
		player.state = PlayerController.MoveState.GROUND

func try_vanish_counter_on_dash() -> bool:
	return _check_active_parry_against_enemies()

func _check_active_parry_against_enemies() -> bool:
	if not player: return false
	for t in target_stats.keys():
		if is_instance_valid(t) and t is Node3D:
			var td := t as Node3D
			var s: Dictionary = target_stats[td]
			var st: String = s["ai_state"]
			if (st == "TELEGRAPH" or st == "STRIKE_ACTIVE") and player.global_position.distance_to(td.global_position) <= 9.0:
				# Execute Sparking Zero Z-Vanish Counter behind enemy!
				player.global_position = td.global_position + td.global_transform.basis.z * 2.2
				player.cam_rot_y += 180.0
				player.whip_lag_timer = player.camera_whip_lag
				player.trigger_air_hang(0.55)
				player.mana = minf(player.max_mana, player.mana + 22.0)
				if player.dash_vfx:
					player.dash_vfx.spawn_step_sigil(player.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.95, 0.3), 1.9)
				s["ai_state"] = "STAGGERED"
				s["state_timer"] = 1.15
				s["combo_left"] = 0
				s["posture"] = minf(s["max_posture"], s["posture"] + 75.0)
				last_combat_action = "Z-VANISH COUNTER!!"
				simulate_clash(true)
				return true
	return false

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
	if not player or player.state == PlayerController.MoveState.HITSTUN: return
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
	last_combat_action = "PARRY STANCE!"
	if player:
		player.mana = minf(player.max_mana, player.mana + 12.0)
		if player.dash_vfx:
			player.dash_vfx.spawn_step_sigil(player.global_position + Vector3(0, 1.0, 0), Color(1, 1, 1), 1.5)

func _trigger_sonic_sway() -> void:
	last_combat_action = "SONIC SWAY DODGE!"
	if player:
		player.trigger_sonic_sway_pose(0.32)
		player.mana = minf(player.max_mana, player.mana + 14.0)
		if player.dash_vfx:
			player.dash_vfx.spawn_step_sigil(player.global_position + Vector3(0, 1.0, 0), Color(0.3, 0.9, 1.0), 1.5)

func _trigger_super_parry() -> void:
	last_combat_action = "SUPER PARRY BREAKER!"
	if player:
		player.hitstun_timer = 0.0
		player.state = PlayerController.MoveState.GROUND
		player.mana = minf(player.max_mana, player.mana + 30.0)
		if player.dash_vfx:
			player.dash_vfx.spawn_step_sigil(player.global_position + Vector3(0, 1.0, 0), Color(0.95, 0.15, 0.25), 2.4)
		for t in target_stats.keys():
			if is_instance_valid(t) and player.global_position.distance_to((t as Node3D).global_position) <= 8.0:
				target_stats[t]["ai_state"] = "STAGGERED"
				target_stats[t]["state_timer"] = 1.2
				target_stats[t]["vel"] = ((t as Node3D).global_position - player.global_position).normalized() * 14.0
	simulate_clash(true)

func _trigger_feint() -> void:
	last_combat_action = "HALF-SWIPE FEINT!"
	for t in target_stats.keys():
		if is_instance_valid(t) and player and player.global_position.distance_to((t as Node3D).global_position) <= 10.0:
			target_stats[t]["ai_state"] = "BAITED_WHIFF!"
			target_stats[t]["whiff_timer"] = 1.1
			target_stats[t]["state_timer"] = 1.1
			target_stats[t]["combo_left"] = 0

func _commit_strike(dir: Vector2) -> void:
	if not player or not player.data_store or player.state == PlayerController.MoveState.HITSTUN: return
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
		if is_instance_valid(t) and player.global_position.distance_to(t.global_position) <= 8.0:
			var td := t as Node3D
			var s: Dictionary = target_stats[td]
			var st: String = s["ai_state"]

			# Check Mid-Air or Ground CLASH if enemy is mid-swing or late telegraph!
			if st == "STRIKE_ACTIVE" or (st == "TELEGRAPH" and s["state_timer"] < ai_telegraph_time * 0.5):
				last_combat_action = "DBZ / ELDEN CLASH!!"
				var push_dir := (player.global_position - td.global_position).normalized()
				player.velocity = push_dir * 12.0 + Vector3(0, 6.5, 0)
				player.trigger_air_hang(0.65)
				s["vel"] = -push_dir * 12.0 + Vector3(0, 6.5, 0)
				s["ai_state"] = "STAGGERED"
				s["state_timer"] = 0.65
				s["combo_left"] = 0
				if player.dash_vfx:
					player.dash_vfx.spawn_step_sigil(player.global_position.lerp(td.global_position, 0.5) + Vector3(0, 1.0, 0), Color(1.0, 0.9, 0.3), 2.2)
				simulate_clash(true)
				return

			if ai_mode == AIMode.ADAPTIVE_RIVAL and player_habits.get(slot_key, 0.0) >= 0.9 and s["whiff_timer"] <= 0.0 and st != "STAGGERED":
				s["ai_state"] = "Z-VANISH COUNTER!"
				td.global_position = player.global_position + player.global_transform.basis.z * 2.2
				s["state_timer"] = 0.35
				s["combo_left"] = 2
				simulate_clash(false)
				player_habits[slot_key] = 0.0
				return

			var mult := 1.5 if (s["whiff_timer"] > 0.0 or st == "STAGGERED") else 1.0
			apply_damage(td, float(data.get("dmg", 90.0)) * player.physical_strength * mult, float(data.get("posture", 40.0)), fwd * float(data.get("knockback", 6.0)) + Vector3(0, float(data.get("launch_y", 0.0)), 0))

func apply_damage(t: Node3D, dmg: float, post_dmg: float, launch_vec: Vector3 = Vector3.ZERO) -> void:
	if not target_stats.has(t): return
	var s: Dictionary = target_stats[t]
	s["hp"] = maxf(0.0, s["hp"] - dmg)
	s["posture"] = minf(s["max_posture"], s["posture"] + post_dmg)
	s["hit_flash"] = 0.16
	s["vel"] = launch_vec
	if launch_vec.y > 6.0 or launch_vec.length() > 14.0:
		s["ai_state"] = "LAUNCHED"
		s["state_timer"] = 0.75
		s["combo_left"] = 0
	if player and player.dash_vfx:
		player.dash_vfx.spawn_step_sigil(t.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.2), 1.3)
	if s["hp"] <= 0.0 or s["posture"] >= s["max_posture"]:
		simulate_clash(true)
		s["hp"] = s["max_hp"]
		s["posture"] = 0.0
		s["ai_state"] = "STAGGERED"
		s["state_timer"] = 1.4

func simulate_clash(is_super: bool) -> void:
	clash_tension += 1
	if is_super or clash_tension >= 3:
		clash_tension = 0
		if impact_frame_cooldown <= 0.0:
			impact_flash_timer = 0.055
			impact_frame_cooldown = 1.5

func _update_enemy_ai(td: Node3D, s: Dictionary, delta: float, is_active_duelist: bool) -> void:
	if not player: return
	var to_p := player.global_position - td.global_position
	var flat_to_p := Vector2(to_p.x, to_p.z)
	var dist := to_p.length()

	if flat_to_p.length_squared() > 0.05:
		td.rotation.y = lerp_angle(td.rotation.y, atan2(-to_p.x, -to_p.z), 12.0 * delta)

	var dmat: StandardMaterial3D = s["mat"]
	if s["hit_flash"] > 0.0:
		dmat.albedo_color = Color(1.0, 1.0, 1.0)
	elif s["ai_state"] == "TELEGRAPH":
		dmat.albedo_color = Color(0.98, 0.12, 0.18)
		td.rotation.x = deg_to_rad(20.0)
	elif s["ai_state"] == "STRIKE_ACTIVE":
		dmat.albedo_color = Color(1.0, 0.88, 0.25)
		td.rotation.x = deg_to_rad(-28.0)
	elif s["ai_state"] == "STAGGERED" or s["ai_state"] == "BAITED_WHIFF!":
		dmat.albedo_color = Color(0.3, 0.85, 1.0)
		td.rotation.x = deg_to_rad(14.0)
	else:
		dmat.albedo_color = Color(0.22, 0.24, 0.30)
		td.rotation.x = 0.0

	if ai_mode == AIMode.STATIC_BAG or not is_active_duelist:
		return

	s["state_timer"] -= delta
	match s["ai_state"]:
		"IDLE", "PURSUIT":
			if dist > 4.2 and dist < 38.0:
				s["ai_state"] = "PURSUIT"
				var move_dir := to_p.normalized()
				var spd := 15.0 if ai_mode == AIMode.ADAPTIVE_RIVAL else 11.0
				td.global_position.x += move_dir.x * spd * delta
				td.global_position.z += move_dir.z * spd * delta
				# Aerial Pursuit if player is high in the air!
				if player.global_position.y - td.global_position.y > 2.0:
					s["vel"].y = 14.0
			elif dist <= 4.5 and s["state_timer"] <= 0.0:
				s["ai_state"] = "TELEGRAPH"
				s["state_timer"] = ai_telegraph_time
				s["combo_left"] = 3 if ai_mode == AIMode.ADAPTIVE_RIVAL else 2
				s["strike_hit_done"] = false
		"TELEGRAPH":
			if s["state_timer"] <= 0.0:
				s["ai_state"] = "STRIKE_ACTIVE"
				s["state_timer"] = 0.20
				s["strike_hit_done"] = false
				var lunge_dir := to_p.normalized()
				s["vel"] = lunge_dir * 22.0
				if player.global_position.y > 1.8:
					s["vel"].y = maxf(s["vel"].y, 4.5)
		"STRIKE_ACTIVE":
			if not s["strike_hit_done"] and dist <= 4.2:
				s["strike_hit_done"] = true
				_resolve_enemy_strike_on_player(td, s)
			if s["state_timer"] <= 0.0:
				s["combo_left"] -= 1
				if s["combo_left"] > 0 and dist <= 6.5:
					s["ai_state"] = "TELEGRAPH"
					s["state_timer"] = maxf(0.22, ai_telegraph_time * 0.65)
				else:
					s["ai_state"] = "IDLE"
					s["state_timer"] = ai_attack_cooldown
		"STAGGERED", "BAITED_WHIFF!", "LAUNCHED", "Z-VANISH COUNTER!":
			if s["state_timer"] <= 0.0:
				if s["ai_state"] == "Z-VANISH COUNTER!":
					s["ai_state"] = "TELEGRAPH"
					s["state_timer"] = 0.26
				else:
					s["ai_state"] = "IDLE"
					s["state_timer"] = ai_attack_cooldown * 0.7

func _resolve_enemy_strike_on_player(td: Node3D, s: Dictionary) -> void:
	if not player: return
	# 1. If Player is holding Sonic Sway (inside Right Orb) -> Auto-Weave Dodge!
	if sonic_sway_holding or player.state == PlayerController.MoveState.GUARD:
		_trigger_sonic_sway()
		s["posture"] = minf(s["max_posture"], s["posture"] + 35.0)
		if s["posture"] >= s["max_posture"]:
			s["ai_state"] = "STAGGERED"
			s["state_timer"] = 1.3
			s["posture"] = 0.0
			last_combat_action = "SWAY POSTURE BREAK!!"
			simulate_clash(true)
		return

	# 2. If Player tapped Parry right before impact -> Z-Vanish Counter!
	if parry_window_timer > 0.0:
		_check_active_parry_against_enemies()
		return

	# 3. If Player is mid-Dash -> I-Frame Evade!
	if player.state == PlayerController.MoveState.DASH:
		last_combat_action = "DASH EVADE!"
		return

	# 4. Unblocked Hit -> Apply Damage & Hitstun to Player
	player.hp = maxf(100.0, player.hp - 55.0)
	var knock := (player.global_position - td.global_position).normalized() * 14.0 + Vector3(0, 3.5, 0)
	player.apply_hitstun(0.36, knock)
	last_combat_action = "HIT BY ENEMY! (TAP BOTH ORBS TO BREAK)"

func _process(delta: float) -> void:
	if parry_window_timer > 0.0: parry_window_timer -= delta
	if impact_flash_timer > 0.0: impact_flash_timer -= delta
	if impact_frame_cooldown > 0.0: impact_frame_cooldown -= delta
	if swipe_chain_timer > 0.0:
		swipe_chain_timer -= delta
		if swipe_chain_timer <= 0.0 and not is_left_dot_active:
			current_swipe_chain.clear()

	if sonic_sway_holding and player:
		player.trigger_sonic_sway_pose(0.15)

	for p in projectiles:
		if p["timer"] > 0.0:
			p["timer"] -= delta
			var mi: MeshInstance3D = p["mesh"]
			mi.global_position += p["vel"] * delta
			for t in target_stats.keys():
				if is_instance_valid(t) and mi.global_position.distance_to((t as Node3D).global_position + Vector3(0, 1.0, 0)) <= 2.4:
					apply_damage(t as Node3D, p["dmg"], p["posture"], p["vel"].normalized() * 8.0 + Vector3(0, 4.0, 0))
					p["timer"] = 0.0
			if p["timer"] <= 0.0:
				mi.visible = false

	var primary_duelist: Node3D = null
	if player and player.is_locked_on and is_instance_valid(player.lock_target):
		primary_duelist = player.lock_target
	elif not target_stats.is_empty():
		primary_duelist = target_stats.keys()[0] as Node3D

	for t in target_stats.keys():
		if is_instance_valid(t) and t is Node3D:
			var td := t as Node3D
			var s: Dictionary = target_stats[td]
			if s["hit_flash"] > 0.0: s["hit_flash"] -= delta
			if s["whiff_timer"] > 0.0: s["whiff_timer"] -= delta

			_update_enemy_ai(td, s, delta, td == primary_duelist)

			var v: Vector3 = s["vel"]
			if v.length_squared() > 0.1 or td.global_position.y > 1.05:
				td.global_position += v * delta
				v.x = lerpf(v.x, 0.0, 6.0 * delta)
				v.z = lerpf(v.z, 0.0, 6.0 * delta)
				if td.global_position.y > 1.0:
					var g_mult := 0.2 if (player and player.air_hang_timer > 0.0) else 1.0
					v.y -= 24.0 * g_mult * delta
				else:
					td.global_position.y = 1.0
					v.y = 0.0
				s["vel"] = v
