class_name FlameP5PvPModule
extends Node

# --- 1. Pure Flame Awakening + 2-Layer Flame Explosion Dome ---
var is_flame_awakened: bool = false
var flame_aura_mesh: MeshInstance3D = null
var flame_embers: Array[MeshInstance3D] = []
var dome_outer: MeshInstance3D = null
var dome_inner: MeshInstance3D = null
var shock_ring: MeshInstance3D = null
var dome_timer: float = 0.0

# --- 2. Anchored 1-Tap Persona 5 Pause Menu ---
var p5_pause_active: bool = false
var p5_selected_idx: int = 0
var p5_pose_idx: int = 0
var p5_anim_t: float = 0.0

const MENU_ITEMS: Array[String] = [
	"01 // FLAME AWAKEN (IGNITE)",
	"02 // WORLD & CHAR MAKER (TAB 6)",
	"03 // STORY & RIVALS (TAB 7)",
	"04 // CUSTOM ROOM PVP LOBBY",
	"05 // SWITCH CAMERA POSE",
	"06 // RESUME COMBAT"
]
const POSE_NAMES: Array[String] = [
	"CRIMSON IGNITION", "RITUAL BLADE POINT", "OVER-SHOULDER ECLIPSE", "SOVEREIGN LEAN", "ASH VANGUARD"
]
const POSE_PRESETS: Array = [
	[2.4, -0.55, 1.45, -6.0, 155.0, -8.0],
	[2.6, -0.65, 1.50, -4.0, 135.0, 9.0],
	[2.2, -0.50, 1.55, -10.0, 165.0, -6.0],
	[2.7, -0.60, 1.38, 2.0, 145.0, 10.0],
	[2.3, -0.58, 1.48, -8.0, 172.0, -9.0]
]

# --- 3. Custom Room Code + Optional Password Lock PvP ---
var enet_peer: ENetMultiplayerPeer = null
var udp_beacon: PacketPeerUDP = null
var is_p2p_connected: bool = false
var is_p2p_host: bool = false
var is_authenticated: bool = false
var local_ip: String = "127.0.0.1"
var default_room_code: String = "SZ100"
var active_room_code: String = "SZ100"
var active_room_pass: String = ""
var room_use_password: bool = false
var pending_join_code: String = ""
var pending_join_pass: String = ""
var discovered_rooms: Dictionary = {}
var p2p_status: String = "Enter a Room Code to Create or Join"
var beacon_timer: float = 0.0

var player_ref: Node3D = null
var combat_ref: Node = null
var studio_ref: Control = null
var pvp_modal: PanelContainer = null
var pvp_status_lbl: Label = null
var room_code_edit: LineEdit = null
var pass_lock_chk: CheckBox = null
var room_pass_edit: LineEdit = null

func setup_module(p: Node3D, c: Node, s: Control) -> void:
	player_ref = p
	combat_ref = c
	studio_ref = s
	_detect_local_ip()
	if DisplayServer.get_name() != "headless":
		udp_beacon = PacketPeerUDP.new()
		udp_beacon.set_broadcast_enabled(true)
		udp_beacon.bind(7778)
	_build_flame_and_explosion_nodes()
	_build_custom_room_pvp_modal()

func _detect_local_ip() -> void:
	for a in IP.get_local_addresses():
		var ip_s: String = str(a)
		if ip_s.begins_with("192.168.") or ip_s.begins_with("172.20.10.") or ip_s.begins_with("10."):
			local_ip = ip_s
			if ip_s.begins_with("192.168.42.") or ip_s.begins_with("192.168.43."):
				break
	var parts: PackedStringArray = local_ip.split(".")
	if parts.size() == 4:
		default_room_code = "SZ" + parts[3]
		active_room_code = default_room_code

func _build_flame_and_explosion_nodes() -> void:
	if not player_ref: return
	var vis: Node3D = player_ref.get("visual_root") as Node3D
	if not vis: return

	flame_aura_mesh = MeshInstance3D.new()
	var fcyl: CylinderMesh = CylinderMesh.new()
	fcyl.top_radius = 0.18; fcyl.bottom_radius = 0.78; fcyl.height = 2.5; fcyl.rings = 12; fcyl.radial_segments = 16
	flame_aura_mesh.mesh = fcyl
	flame_aura_mesh.position = Vector3(0.0, 1.0, 0.0)
	flame_aura_mesh.visible = false

	var fmat: ShaderMaterial = ShaderMaterial.new()
	fmat.shader = Shader.new()
	fmat.shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;
void vertex() {
	float w1 = sin(TIME * 16.0 - VERTEX.y * 6.0 + VERTEX.x * 8.0) * 0.18;
	float w2 = cos(TIME * 22.0 - VERTEX.y * 9.0 + VERTEX.z * 8.0) * 0.14;
	VERTEX.xz += vec2(w1, w2) * clamp(VERTEX.y + 1.25, 0.1, 2.3);
}
void fragment() {
	float h = clamp((VERTEX.y + 1.25) / 2.5, 0.0, 1.0);
	float flk = sin(TIME * 28.0 - UV.y * 18.0 + UV.x * 12.0) * 0.5 + 0.5;
	float m = (1.0 - h) * smoothstep(0.15, 0.65, flk + (1.0 - h) * 0.4);
	vec3 col = mix(vec3(1.0, 0.14, 0.02), vec3(1.0, 0.86, 0.18), (1.0 - h) * 0.7 + flk * 0.3);
	ALBEDO = col * m * 2.2;
	ALPHA = clamp(m * 0.85, 0.0, 1.0);
}
"""
	flame_aura_mesh.material_override = fmat
	vis.add_child(flame_aura_mesh)

	var emat: StandardMaterial3D = StandardMaterial3D.new()
	emat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	emat.albedo_color = Color(1.0, 0.68, 0.12)
	var ebox: BoxMesh = BoxMesh.new(); ebox.size = Vector3(0.07, 0.22, 0.07)
	for i in range(8):
		var em: MeshInstance3D = MeshInstance3D.new()
		em.mesh = ebox; em.visible = false; em.material_override = emat
		vis.add_child(em)
		flame_embers.append(em)

	var mat_outer: StandardMaterial3D = StandardMaterial3D.new()
	mat_outer.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_outer.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat_outer.albedo_color = Color(1.0, 0.32, 0.02, 0.88)

	var mat_inner: StandardMaterial3D = StandardMaterial3D.new()
	mat_inner.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_inner.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat_inner.albedo_color = Color(1.0, 0.92, 0.45, 0.95)

	dome_outer = MeshInstance3D.new()
	var s1: SphereMesh = SphereMesh.new(); s1.radius = 1.0; s1.height = 1.0; s1.is_hemisphere = true
	dome_outer.mesh = s1; dome_outer.top_level = true; dome_outer.visible = false; dome_outer.material_override = mat_outer
	player_ref.add_child(dome_outer)

	dome_inner = MeshInstance3D.new()
	var s2: SphereMesh = SphereMesh.new(); s2.radius = 0.68; s2.height = 0.68; s2.is_hemisphere = true
	dome_inner.mesh = s2; dome_inner.top_level = true; dome_inner.visible = false; dome_inner.material_override = mat_inner
	player_ref.add_child(dome_inner)

	shock_ring = MeshInstance3D.new()
	var ring_mesh: TorusMesh = TorusMesh.new(); ring_mesh.inner_radius = 1.1; ring_mesh.outer_radius = 1.35
	shock_ring.mesh = ring_mesh; shock_ring.top_level = true; shock_ring.visible = false; shock_ring.material_override = mat_inner
	player_ref.add_child(shock_ring)

func toggle_flame_awakening() -> void:
	is_flame_awakened = not is_flame_awakened
	if flame_aura_mesh: flame_aura_mesh.visible = is_flame_awakened
	for em in flame_embers: em.visible = is_flame_awakened
	if player_ref:
		player_ref.call("trigger_hitstop", 0.05, 0.65)
		if is_flame_awakened:
			trigger_flame_explosion(player_ref.global_position)
			player_ref.call("update_cel_shader", float(player_ref.get("cel_cut_threshold")), float(player_ref.get("outline_width")), 1.6, Color(1.0, 0.42, 0.05))
		else:
			player_ref.call("update_cel_shader", float(player_ref.get("cel_cut_threshold")), float(player_ref.get("outline_width")), float(player_ref.get("rim_strength")), Color(0.95, 0.12, 0.18))
	if combat_ref:
		combat_ref.set("last_combat_action", "FLAME AWAKENING IGNITED!!" if is_flame_awakened else "BASE FORM")

func trigger_flame_explosion(pos: Vector3) -> void:
	var g_pos: Vector3 = Vector3(pos.x, 0.5, pos.z)
	dome_outer.global_position = g_pos; dome_outer.scale = Vector3.ONE * 1.2; dome_outer.visible = true
	dome_inner.global_position = g_pos; dome_inner.scale = Vector3.ONE * 1.0; dome_inner.visible = true
	shock_ring.global_position = g_pos + Vector3(0.0, 0.15, 0.0); shock_ring.scale = Vector3(1.4, 0.2, 1.4); shock_ring.visible = true
	dome_timer = 0.48
	if player_ref and player_ref.get("dash_vfx"):
		player_ref.get("dash_vfx").call("play_sfx", "shatter")
		player_ref.get("dash_vfx").call("check_destruction", g_pos, 6.0, Vector3.UP, true)

func toggle_p5_pause() -> bool:
	p5_pause_active = not p5_pause_active
	if pvp_modal: pvp_modal.visible = false
	if player_ref:
		player_ref.set("p5_camera_override", p5_pause_active)
	if p5_pause_active:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		roll_next_pose()
	else:
		if player_ref:
			if player_ref.get("camera"):
				(player_ref.get("camera") as Camera3D).rotation_degrees.z = 0.0
			player_ref.call("play_character_anim", "idle")
		if not DisplayServer.is_touchscreen_available():
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	return p5_pause_active

func roll_next_pose() -> void:
	p5_pose_idx = (p5_pose_idx + 1) % POSE_PRESETS.size()
	p5_anim_t = 0.0
	if player_ref:
		var anims: Array[String] = ["guard_sway", "slash_side", "slash_up", "idle", "slash_down"]
		player_ref.call("play_character_anim", anims[p5_pose_idx % anims.size()])
		if player_ref.get("dash_vfx"):
			player_ref.get("dash_vfx").call("play_sfx", "slash")

func _build_custom_room_pvp_modal() -> void:
	if not studio_ref: return
	pvp_modal = PanelContainer.new()
	pvp_modal.anchor_left = 0.5; pvp_modal.anchor_top = 0.5; pvp_modal.anchor_right = 0.5; pvp_modal.anchor_bottom = 0.5
	pvp_modal.offset_left = -270; pvp_modal.offset_top = -165; pvp_modal.offset_right = 270; pvp_modal.offset_bottom = 165
	pvp_modal.visible = false

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.07, 0.97)
	sb.border_color = Color(0.95, 0.15, 0.22, 0.95)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(14)
	pvp_modal.add_theme_stylebox_override("panel", sb)
	studio_ref.add_child(pvp_modal)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pvp_modal.add_child(vb)

	var t_lbl: Label = Label.new()
	t_lbl.text = "=== CUSTOM ROOM PVP LOBBY ==="
	t_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	vb.add_child(t_lbl)

	pvp_status_lbl = Label.new()
	pvp_status_lbl.text = "Status: " + p2p_status
	pvp_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pvp_status_lbl.add_theme_color_override("font_color", Color(0.3, 0.95, 1.0))
	vb.add_child(pvp_status_lbl)

	# Row 1: Room Code Input
	var code_row: HBoxContainer = HBoxContainer.new()
	vb.add_child(code_row)
	var code_lbl: Label = Label.new()
	code_lbl.text = "Room Code:"
	code_lbl.custom_minimum_size = Vector2(115, 0)
	code_row.add_child(code_lbl)

	room_code_edit = LineEdit.new()
	room_code_edit.text = default_room_code
	room_code_edit.placeholder_text = "Enter Room Code (e.g. SZ224 or KUSH)"
	room_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(room_code_edit)

	# Row 2: Optional Password Lock Checkbox + Password Field
	var pass_row: HBoxContainer = HBoxContainer.new()
	vb.add_child(pass_row)
	pass_lock_chk = CheckBox.new()
	pass_lock_chk.text = "Password Lock"
	pass_lock_chk.button_pressed = false
	pass_row.add_child(pass_lock_chk)

	room_pass_edit = LineEdit.new()
	room_pass_edit.placeholder_text = "No Password (Open Room)"
	room_pass_edit.secret = true
	room_pass_edit.editable = false
	room_pass_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pass_row.add_child(room_pass_edit)

	pass_lock_chk.toggled.connect(func(on: bool):
		room_use_password = on
		room_pass_edit.editable = on
		if not on:
			room_pass_edit.text = ""
			room_pass_edit.placeholder_text = "No Password (Open Room)"
		else:
			room_pass_edit.placeholder_text = "Enter Room Password..."
			room_pass_edit.grab_focus()
	)

	# Row 3: [ CREATE ROOM ] and [ JOIN ] Side-by-Side
	var act_row: HBoxContainer = HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 10)
	vb.add_child(act_row)

	var b_host: Button = Button.new()
	b_host.text = "[ CREATE ROOM ]"
	b_host.custom_minimum_size = Vector2(0, 44)
	b_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_host.modulate = Color(0.3, 1.0, 0.5)
	b_host.pressed.connect(func():
		var r_code: String = room_code_edit.text.strip_edges().to_upper()
		if r_code.is_empty(): r_code = default_room_code
		var r_pass: String = room_pass_edit.text.strip_edges() if pass_lock_chk.button_pressed else ""
		host_custom_room(r_code, r_pass, 7777)
	)
	act_row.add_child(b_host)

	var b_join: Button = Button.new()
	b_join.text = "[ JOIN ]"
	b_join.custom_minimum_size = Vector2(0, 44)
	b_join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_join.modulate = Color(0.35, 0.88, 1.0)
	b_join.pressed.connect(func():
		var r_code: String = room_code_edit.text.strip_edges().to_upper()
		var r_pass: String = room_pass_edit.text.strip_edges() if pass_lock_chk.button_pressed else ""
		join_custom_room(r_code, r_pass, 7777)
	)
	act_row.add_child(b_join)

	# Row 4: Disconnect & Close
	var h_bot: HBoxContainer = HBoxContainer.new()
	vb.add_child(h_bot)
	var b_disc: Button = Button.new(); b_disc.text = "[ Disconnect ]"; b_disc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_disc.pressed.connect(disconnect_p2p); h_bot.add_child(b_disc)
	var b_close: Button = Button.new(); b_close.text = "[ Close ]"; b_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_close.pressed.connect(func(): pvp_modal.visible = false); h_bot.add_child(b_close)

func host_custom_room(r_code: String, r_pass: String, port: int = 7777) -> void:
	disconnect_p2p()
	_detect_local_ip()
	active_room_code = r_code
	active_room_pass = r_pass
	room_code_edit.text = active_room_code

	enet_peer = ENetMultiplayerPeer.new()
	if enet_peer.create_server(port, 2) != OK:
		p2p_status = "ERROR: Could not open room port"
		return
	multiplayer.multiplayer_peer = enet_peer
	is_p2p_host = true
	is_authenticated = true
	var lock_tag: String = " [LOCKED]" if not active_room_pass.is_empty() else " [OPEN]"
	p2p_status = "HOSTING ROOM '%s'%s — Waiting for Challenger..." % [active_room_code, lock_tag]
	if not multiplayer.peer_connected.is_connected(_on_peer_conn):
		multiplayer.peer_connected.connect(_on_peer_conn)

func join_custom_room(r_code: String, r_pass: String, port: int = 7777) -> void:
	var clean_code: String = r_code.strip_edges().to_upper()
	if clean_code.is_empty() and not discovered_rooms.is_empty():
		clean_code = str(discovered_rooms.keys()[0])
		if room_code_edit: room_code_edit.text = clean_code

	if clean_code.is_empty():
		p2p_status = "Please enter a Room Code first!"
		return

	var target_ip: String = ""
	if discovered_rooms.has(clean_code):
		var info: Dictionary = discovered_rooms[clean_code]
		target_ip = str(info.get("ip", ""))
		var needs_pass: bool = bool(info.get("locked", false))
		if needs_pass and r_pass.is_empty():
			if pass_lock_chk and not pass_lock_chk.button_pressed:
				pass_lock_chk.button_pressed = true
			p2p_status = "Room '%s' is Password Locked! Enter password & tap [ JOIN ]." % clean_code
			return
	else:
		# Smart Subnet Octet Fallback (e.g. SZ224 -> 192.168.0.224) if router blocks UDP broadcast
		var digits: String = ""
		for i in range(clean_code.length()):
			var ch: String = clean_code.substr(i, 1)
			if ch in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
				digits += ch
		var oct_val: int = int(digits) if not digits.is_empty() else -1
		var my_parts: PackedStringArray = local_ip.split(".")
		if oct_val >= 1 and oct_val <= 254 and my_parts.size() == 4:
			target_ip = "%s.%s.%s.%d" % [my_parts[0], my_parts[1], my_parts[2], oct_val]

	if target_ip.is_empty() or target_ip == local_ip or target_ip == "127.0.0.1":
		p2p_status = "Room '%s' not found on Wi-Fi/Hotspot yet!" % clean_code
		return

	disconnect_p2p()
	pending_join_code = clean_code
	pending_join_pass = r_pass
	enet_peer = ENetMultiplayerPeer.new()
	if enet_peer.create_client(target_ip, port) != OK:
		p2p_status = "ERROR: Could not join Room " + clean_code
		return
	multiplayer.multiplayer_peer = enet_peer
	is_p2p_host = false
	is_authenticated = false
	p2p_status = "JOINING ROOM '%s'..." % clean_code
	if not multiplayer.peer_connected.is_connected(_on_peer_conn):
		multiplayer.peer_connected.connect(_on_peer_conn)

func disconnect_p2p() -> void:
	if enet_peer: enet_peer.close(); enet_peer = null
	multiplayer.multiplayer_peer = null
	is_p2p_host = false; is_p2p_connected = false; is_authenticated = false
	p2p_status = "SOLO MODE (Disconnected)"

func _on_peer_conn(id: int) -> void:
	if id == 1 and not is_p2p_host:
		# Client connected to Host -> send Room Code & Password handshake
		rpc_id(1, "_rpc_verify_room_join", pending_join_code, pending_join_pass)

@rpc("any_peer", "reliable")
func _rpc_verify_room_join(c_code: String, c_pass: String) -> void:
	if not is_p2p_host: return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if c_code.to_upper() != active_room_code.to_upper():
		rpc_id(sender_id, "_rpc_join_result", false, "WRONG ROOM CODE!")
		return
	if not active_room_pass.is_empty() and c_pass != active_room_pass:
		rpc_id(sender_id, "_rpc_join_result", false, "ACCESS DENIED: WRONG PASSWORD!")
		return
	is_p2p_connected = true
	is_authenticated = true
	p2p_status = "ROOM '%s' CONNECTED! 120Hz PVP DUEL ACTIVE" % active_room_code
	rpc_id(sender_id, "_rpc_join_result", true, "ROOM '%s' CONNECTED! 120Hz PVP DUEL ACTIVE" % active_room_code)

@rpc("any_peer", "reliable")
func _rpc_join_result(ok: bool, msg: String) -> void:
	p2p_status = msg
	if ok:
		is_p2p_connected = true
		is_authenticated = true
	else:
		if enet_peer: enet_peer.close(); enet_peer = null
		multiplayer.multiplayer_peer = null
		is_p2p_connected = false
		is_authenticated = false

func _process(delta: float) -> void:
	if pvp_status_lbl: pvp_status_lbl.text = "Status: " + p2p_status
	if dome_timer > 0.0:
		dome_timer -= delta
		dome_outer.scale += Vector3.ONE * (delta * 26.0)
		dome_inner.scale += Vector3.ONE * (delta * 20.0)
		shock_ring.scale += Vector3(delta * 38.0, 0.0, delta * 38.0)
		if dome_timer <= 0.0:
			dome_outer.visible = false; dome_inner.visible = false; shock_ring.visible = false

	if is_flame_awakened:
		var t_sec: float = Time.get_ticks_msec() * 0.004
		for i in range(flame_embers.size()):
			var ang: float = t_sec * 2.2 + float(i) * (TAU / 8.0)
			var y_c: float = fmod(t_sec * 1.8 + float(i) * 0.35, 2.2)
			var rad: float = 0.55 + sin(t_sec + float(i)) * 0.2
			flame_embers[i].position = Vector3(cos(ang) * rad, y_c, sin(ang) * rad)

	if udp_beacon:
		beacon_timer += delta
		if is_p2p_host and not is_p2p_connected and beacon_timer >= 0.45:
			beacon_timer = 0.0
			var lock_flag: String = "1" if not active_room_pass.is_empty() else "0"
			var payload: String = "P2PROOM:%s:%s:%s" % [active_room_code, lock_flag, local_ip]
			udp_beacon.set_dest_address("255.255.255.255", 7778)
			udp_beacon.put_packet(payload.to_utf8_buffer())

		while udp_beacon.get_available_packet_count() > 0:
			var m: String = udp_beacon.get_packet().get_string_from_utf8()
			if m.begins_with("P2PROOM:"):
				var sp: PackedStringArray = m.split(":")
				if sp.size() >= 4:
					var r_code: String = sp[1]
					var is_lck: bool = (sp[2] == "1")
					var r_ip: String = sp[3]
					if r_ip != local_ip and r_ip != "127.0.0.1":
						discovered_rooms[r_code] = {"ip": r_ip, "locked": is_lck}
						if not is_p2p_host and not is_p2p_connected:
							if room_code_edit and (room_code_edit.text == default_room_code or room_code_edit.text.is_empty()):
								room_code_edit.text = r_code
							var l_txt: String = " [PASSWORD LOCKED]" if is_lck else " [OPEN]"
							p2p_status = "FOUND ROOM '%s'%s! Tap [ JOIN ]" % [r_code, l_txt]

		if is_p2p_connected and is_authenticated and player_ref:
			var vis: Node3D = player_ref.get("visual_root") as Node3D
			rpc("_sync_p2p", player_ref.global_position, vis.rotation.y if vis else 0.0)

	if p5_pause_active and player_ref:
		p5_anim_t += delta
		var pr: Array = POSE_PRESETS[p5_pose_idx]
		var vis: Node3D = player_ref.get("visual_root") as Node3D
		var cp: Node3D = player_ref.get("camera_pivot") as Node3D
		var sa: SpringArm3D = player_ref.get("spring_arm") as SpringArm3D
		var cm: Camera3D = player_ref.get("camera") as Camera3D
		if cp and sa and cm:
			var base_yaw: float = rad_to_deg(vis.rotation.y) if vis else 0.0
			var dy: float = base_yaw + float(pr[4]) + sin(p5_anim_t * 2.0) * 2.0
			cp.position = cp.position.lerp(Vector3(0.0, float(pr[2]) * float(player_ref.get("char_height")), 0.0), 14.0 * delta)
			sa.position = sa.position.lerp(Vector3(float(pr[1]), 0.0, 0.0), 14.0 * delta)
			sa.spring_length = lerpf(sa.spring_length, float(pr[0]), 14.0 * delta)
			cp.rotation_degrees.y = lerp_angle(deg_to_rad(cp.rotation_degrees.y), deg_to_rad(dy), 14.0 * delta) * 180.0 / PI
			cp.rotation_degrees.x = lerpf(cp.rotation_degrees.x, float(pr[3]), 14.0 * delta)
			cm.rotation_degrees.z = lerpf(cm.rotation_degrees.z, float(pr[5]), 14.0 * delta)
			cm.fov = lerpf(cm.fov, 60.0, 14.0 * delta)

@rpc("any_peer", "unreliable_ordered")
func _sync_p2p(pos: Vector3, yaw: float) -> void:
	if not combat_ref or not is_authenticated: return
	var ts: Dictionary = combat_ref.get("target_stats")
	if ts.is_empty(): return
	var td: Node3D = ts.keys()[0] as Node3D
	if is_instance_valid(td):
		td.global_position = td.global_position.lerp(pos, 0.65)
		td.rotation.y = yaw
		ts[td]["boss_name"] = "CHALLENGER [%s]" % active_room_code
