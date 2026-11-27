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
	"01 // FLAME AWAKEN",
	"02 // LOCK-ON",
	"03 // SWITCH TARGET",
	"04 // CAMERA POSE",
	"05 // PVP ROOM",
	"06 // BUILD MODE",
	"07 // REGION",
	"08 // AI MODE",
	"09 // FPS CAP",
	"10 // SAVE LOADOUT",
	"11 // DEV STUDIO",
	"12 // WORLD & CHAR (TAB 6)",
	"13 // STORY & RIVALS (TAB 7)",
	"14 // COMBAT FEEL (TAB 8)",
	"15 // QUALITY TIER",
	"16 // RENDER SCALE",
	"17 // SANDBOX IMMORTAL",
	"18 // REMATCH DUEL",
	"19 // RESUME COMBAT"
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

# --- 3. Direct UDP Port 7778 Custom Room + Password Lock PvP ---
var udp_beacon: PacketPeerUDP = null
var is_p2p_connected: bool = false
var is_p2p_host: bool = false
var is_joining: bool = false
var join_retry_timer: float = 0.0
var join_timeout_timer: float = 0.0
var local_ip: String = "127.0.0.1"
var peer_ip: String = ""
var default_room_code: String = "SZ100"
var active_room_code: String = "SZ100"
var active_room_pass: String = ""
var pending_join_code: String = ""
var pending_join_pass: String = ""
var discovered_rooms: Dictionary = {}
var p2p_status: String = "Enter a Room Code to Create or Join"
var beacon_timer: float = 0.0
var last_sent_swing: bool = false
# State sync is throttled: it used to send a formatted UDP string every rendered
# frame (up to 165/s). 30 Hz is smooth for a background rival and 5x cheaper.
const P2P_SEND_HZ: float = 30.0
const P2P_MAX_PACKETS_PER_FRAME: int = 64
const P2P_MAX_DISCOVERED_ROOMS: int = 16
const P2P_MAX_ROOM_CODE: int = 16
const P2P_MAX_PACKET_CHARS: int = 512
const P2P_MAX_SYNC_COORD: float = 5000.0
var p2p_send_accum: float = 0.0

# --- V7 Task 2: pure, decoupled match state ---------------------------------
# Telemetry and round bookkeeping live here and never touch a fighting
# character: the module feeds ratios/booleans in and reads a HUD dict out.
class PvpMatchState extends RefCounted:
	var active: bool = false
	var room_code: String = ""
	var round_state: String = "IDLE"
	var local_wins: int = 0
	var remote_wins: int = 0
	var local_hp_ratio: float = 1.0
	var remote_hp_ratio: float = 1.0
	var remote_name: String = "CHALLENGER"
	var local_rematch_ready: bool = false
	var remote_rematch_ready: bool = false

	func reset_round() -> void:
		round_state = "ACTIVE" if active else "IDLE"
		local_hp_ratio = 1.0
		remote_hp_ratio = 1.0
		local_rematch_ready = false
		remote_rematch_ready = false

	func reset_match() -> void:
		active = false
		room_code = ""
		round_state = "IDLE"
		local_wins = 0
		remote_wins = 0
		local_hp_ratio = 1.0
		remote_hp_ratio = 1.0
		remote_name = "CHALLENGER"
		local_rematch_ready = false
		remote_rematch_ready = false

	# Idempotent by construction: only an ACTIVE round can be decided, so a
	# repeated or replayed KO packet can never double-count the same round.
	func record_ko(local_won: bool) -> bool:
		if not active or round_state != "ACTIVE":
			return false
		if local_won:
			local_wins += 1
			remote_hp_ratio = 0.0
		else:
			remote_wins += 1
			local_hp_ratio = 0.0
		round_state = "KO"
		return true

	func to_hud_dict() -> Dictionary:
		return {
			"active": active, "room_code": room_code, "round_state": round_state,
			"local_wins": local_wins, "remote_wins": remote_wins,
			"local_hp_ratio": local_hp_ratio, "remote_hp_ratio": remote_hp_ratio,
			"remote_name": remote_name,
			"local_rematch_ready": local_rematch_ready,
			"remote_rematch_ready": remote_rematch_ready,
		}

var match_state: PvpMatchState = PvpMatchState.new()

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
	# Prefer standard Wi-Fi / Hotspot / USB-tether subnets (192.168.x.x or 172.20.10.x) over cellular
	var best_ip: String = "127.0.0.1"
	for a in IP.get_local_addresses():
		var ip_s: String = str(a)
		if ip_s.begins_with("192.168.42.") or ip_s.begins_with("192.168.43.") or ip_s.begins_with("172.20.10."):
			best_ip = ip_s
			break
		elif ip_s.begins_with("192.168."):
			best_ip = ip_s
		elif ip_s.begins_with("10.") and best_ip == "127.0.0.1":
			best_ip = ip_s
	local_ip = best_ip
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
			player_ref.set("eye_awaken_boost", 2.4)
		else:
			player_ref.call("update_cel_shader", float(player_ref.get("cel_cut_threshold")), float(player_ref.get("outline_width")), float(player_ref.get("rim_strength")), Color(0.95, 0.12, 0.18))
			player_ref.set("eye_awaken_boost", 1.0)
		player_ref.call("update_eye_shader")
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

	var code_row: HBoxContainer = HBoxContainer.new()
	vb.add_child(code_row)
	var code_lbl: Label = Label.new()
	code_lbl.text = "Room Code:"
	code_lbl.custom_minimum_size = Vector2(115, 0)
	code_row.add_child(code_lbl)

	room_code_edit = LineEdit.new()
	room_code_edit.text = default_room_code
	room_code_edit.placeholder_text = "Enter Room Code (e.g. SZ148 or KUSH)"
	room_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(room_code_edit)

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
		room_pass_edit.editable = on
		if not on:
			room_pass_edit.text = ""
			room_pass_edit.placeholder_text = "No Password (Open Room)"
		else:
			room_pass_edit.placeholder_text = "Enter Room Password..."
			room_pass_edit.grab_focus()
	)

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
		host_custom_room(r_code, r_pass)
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
		join_custom_room(r_code, r_pass)
	)
	act_row.add_child(b_join)

	var h_bot: HBoxContainer = HBoxContainer.new()
	vb.add_child(h_bot)
	var b_disc: Button = Button.new(); b_disc.text = "[ Disconnect ]"; b_disc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_disc.pressed.connect(disconnect_p2p); h_bot.add_child(b_disc)
	var b_close: Button = Button.new(); b_close.text = "[ Close ]"; b_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_close.pressed.connect(func(): pvp_modal.visible = false); h_bot.add_child(b_close)

func host_custom_room(r_code: String, r_pass: String) -> void:
	disconnect_p2p()
	_detect_local_ip()
	active_room_code = r_code
	active_room_pass = r_pass
	room_code_edit.text = active_room_code
	is_p2p_host = true
	is_joining = false
	is_p2p_connected = false
	var lock_tag: String = " [LOCKED]" if not active_room_pass.is_empty() else " [OPEN]"
	p2p_status = "HOSTING ROOM '%s'%s — Waiting for Challenger..." % [active_room_code, lock_tag]

func join_custom_room(r_code: String, r_pass: String) -> void:
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
		# Subnet Octet Fallback (e.g. SZ148 -> 192.168.0.148)
		var digits: String = ""
		for i in range(clean_code.length()):
			var ch: String = clean_code.substr(i, 1)
			if ch in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
				digits += ch
		var oct_val: int = int(digits) if not digits.is_empty() else -1
		var my_parts: PackedStringArray = local_ip.split(".")
		if oct_val >= 1 and oct_val <= 254 and my_parts.size() == 4:
			target_ip = "%s.%s.%s.%d" % [my_parts[0], my_parts[1], my_parts[2], oct_val]

	is_p2p_host = false
	is_p2p_connected = false
	is_joining = true
	join_retry_timer = 0.0
	join_timeout_timer = 5.0
	pending_join_code = clean_code
	pending_join_pass = r_pass
	peer_ip = target_ip
	active_room_code = clean_code
	p2p_status = "CONNECTING TO ROOM '%s'..." % clean_code
	_send_join_packet()

func _send_join_packet() -> void:
	if not udp_beacon: return
	var pkt: PackedByteArray = ("P2PJOIN:%s:%s" % [pending_join_code, pending_join_pass]).to_utf8_buffer()
	if not peer_ip.is_empty() and peer_ip != "127.0.0.1":
		udp_beacon.set_dest_address(peer_ip, 7778)
		udp_beacon.put_packet(pkt)
	# Also send via broadcast so it reaches the Host even across multi-interface subnets
	udp_beacon.set_dest_address("255.255.255.255", 7778)
	udp_beacon.put_packet(pkt)

func disconnect_p2p() -> void:
	is_p2p_host = false
	is_p2p_connected = false
	is_joining = false
	peer_ip = ""
	match_state.reset_match()
	p2p_status = "SOLO MODE (Disconnected)"

func _on_link_established(remote_ip: String, r_code: String) -> void:
	peer_ip = remote_ip
	active_room_code = r_code
	is_joining = false
	is_p2p_connected = true
	match_state.active = true
	match_state.room_code = active_room_code
	match_state.reset_round()
	p2p_status = "CONNECTED TO ROOM '%s'! LIVE PVP ACTIVE (30Hz SYNC)" % active_room_code
	if player_ref:
		if not bool(player_ref.get("is_locked_on")):
			player_ref.call("toggle_lock_on")
		if player_ref.get("dash_vfx"):
			player_ref.get("dash_vfx").call("play_sfx", "clash")
	if combat_ref:
		combat_ref.set("last_combat_action", "PVP ROOM '%s' LINKED!" % active_room_code)
	# Auto-close modal after 0.6s so both players can fight immediately
	get_tree().create_timer(0.6).timeout.connect(func():
		if is_p2p_connected and pvp_modal:
			pvp_modal.visible = false
	)

# --- V7 Task 2: round / rematch handshake -----------------------------------
# Local tap. The flag rides the next throttled sync packet; the round only
# restarts once both sides ask for it.
func request_rematch() -> bool:
	if not match_state.active or match_state.round_state == "ACTIVE":
		return false
	match_state.local_rematch_ready = true
	if match_state.round_state == "KO":
		match_state.round_state = "REMATCH_READY"
	_try_start_next_round()
	return true

# Solo / offline test helper: stand in for a cooperative peer.
func begin_next_round() -> bool:
	if not match_state.active:
		return false
	match_state.local_rematch_ready = true
	match_state.remote_rematch_ready = true
	return _start_next_round()

func _try_start_next_round() -> void:
	if match_state.round_state == "ACTIVE":
		return
	if match_state.local_rematch_ready and match_state.remote_rematch_ready:
		_start_next_round()

# Both sides agreed: fresh HP, fresh duel, fresh 7.5 m separation.
func _start_next_round() -> bool:
	if not match_state.active:
		return false
	match_state.reset_round()
	if combat_ref and combat_ref.has_method("reset_duel"):
		combat_ref.call("reset_duel")
	if player_ref:
		player_ref.set("hp", float(player_ref.get("max_hp")))
		player_ref.set("hitstun_timer", 0.0)
		if player_ref.get("is_defeated") != null:
			player_ref.set("is_defeated", false)
		var td = combat_ref.call("primary_rival") if combat_ref else null
		if td is Node3D and is_instance_valid(td):
			var fwd: Vector3 = -player_ref.global_transform.basis.z
			var vis: Node3D = player_ref.get("visual_root") as Node3D
			if vis:
				fwd = -vis.global_transform.basis.z
			var rival: Node3D = td
			rival.global_position = player_ref.global_position + Vector3(fwd.x, 0.0, fwd.z).normalized() * 7.5
			rival.global_position.y = 1.0
		if player_ref.get("dash_vfx"):
			player_ref.get("dash_vfx").call("play_sfx", "clash")
	return true

# Join decision, extracted so the password lock can be unit-tested without a socket.
# "IGNORE" = not our room, "DENY" = wrong password, "ACCEPT" = link.
func _join_verdict(req_code: String, req_pass: String) -> String:
	if req_code.to_upper() != active_room_code.to_upper():
		return "IGNORE"
	if not active_room_pass.is_empty() and req_pass != active_room_pass:
		return "DENY"
	return "ACCEPT"

# to_float() on garbage yields 0.0, but nan/inf can survive; reject them explicitly.
func _safe_float(txt: String) -> float:
	var v: float = txt.to_float()
	if is_nan(v) or is_inf(v):
		return 0.0
	return v

# One packet, fully guarded. Malformed, truncated, wrong-room and wrong-password
# datagrams can only fail to do something - they can never throw mid-match.
func _handle_udp_packet(m: String, sender_ip: String) -> void:
	if not udp_beacon:
		return
	if m.is_empty() or m.length() > P2P_MAX_PACKET_CHARS:
		return

	if m.begins_with("P2PROOM:"):
		var sp: PackedStringArray = m.split(":")
		if sp.size() < 4:
			return
		var r_code: String = sp[1].strip_edges()
		if r_code.is_empty() or r_code.length() > P2P_MAX_ROOM_CODE:
			return
		var is_lck: bool = (sp[2] == "1")
		var r_ip: String = sender_ip if not sender_ip.is_empty() else sp[3]
		if r_ip == local_ip or r_ip == "127.0.0.1":
			return
		if is_p2p_host and r_code == active_room_code:
			return
		# A spoofer must not be able to grow this dict without bound.
		if not discovered_rooms.has(r_code) and discovered_rooms.size() >= P2P_MAX_DISCOVERED_ROOMS:
			return
		discovered_rooms[r_code] = {"ip": r_ip, "locked": is_lck}
		if is_joining and r_code.to_upper() == pending_join_code.to_upper():
			peer_ip = r_ip
			_send_join_packet()
		elif not is_p2p_host and not is_p2p_connected and not is_joining:
			if room_code_edit and (room_code_edit.text == default_room_code or room_code_edit.text.is_empty()):
				room_code_edit.text = r_code
			var l_txt: String = " [PASSWORD LOCKED]" if is_lck else " [OPEN]"
			p2p_status = "FOUND ROOM '%s'%s! Tap [ JOIN ]" % [r_code, l_txt]

	elif m.begins_with("P2PJOIN:") and is_p2p_host:
		var sp_j: PackedStringArray = m.split(":")
		if sp_j.size() < 3:
			return
		var req_code: String = sp_j[1].strip_edges()
		var req_pass: String = sp_j[2]
		if req_code.length() > P2P_MAX_ROOM_CODE or req_pass.length() > 64:
			return
		match _join_verdict(req_code, req_pass):
			"ACCEPT":
				udp_beacon.set_dest_address(sender_ip, 7778)
				udp_beacon.put_packet(("P2PACCEPT:" + active_room_code).to_utf8_buffer())
				if not is_p2p_connected:
					_on_link_established(sender_ip, active_room_code)
			"DENY":
				udp_beacon.set_dest_address(sender_ip, 7778)
				udp_beacon.put_packet(("P2PDENY:" + active_room_code + ":ACCESS DENIED — WRONG PASSWORD!").to_utf8_buffer())

	elif m.begins_with("P2PACCEPT:") and (is_joining or not is_p2p_connected) and not is_p2p_host:
		var sp_a: PackedStringArray = m.split(":")
		if sp_a.size() < 2:
			return
		var acc_code: String = sp_a[1]
		if acc_code.to_upper() == pending_join_code.to_upper():
			_on_link_established(sender_ip, acc_code)

	elif m.begins_with("P2PDENY:") and is_joining and not is_p2p_host:
		var sp_d: PackedStringArray = m.split(":")
		if sp_d.size() < 3 or sp_d[1].to_upper() != pending_join_code.to_upper():
			return
		is_joining = false
		is_p2p_connected = false
		p2p_status = sp_d[2].left(96)

	elif m.begins_with("P2PSYNC:") and is_p2p_connected and sender_ip == peer_ip:
		var sp_s: PackedStringArray = m.split(":")
		if sp_s.size() < 7 or not combat_ref:
			return
		# Clamped: a hostile or garbled packet must not teleport the rival to infinity.
		var rx: float = clampf(_safe_float(sp_s[1]), -P2P_MAX_SYNC_COORD, P2P_MAX_SYNC_COORD)
		var ry: float = clampf(_safe_float(sp_s[2]), -P2P_MAX_SYNC_COORD, P2P_MAX_SYNC_COORD)
		var rz: float = clampf(_safe_float(sp_s[3]), -P2P_MAX_SYNC_COORD, P2P_MAX_SYNC_COORD)
		var ryaw: float = _safe_float(sp_s[4])
		var rhp: float = clampf(_safe_float(sp_s[5]), 0.0, 99999.0)
		var ratk: int = 1 if _safe_float(sp_s[6]) >= 0.5 else 0
		# V7 Task 2 trailing fields are optional: an older peer stops at index 6
		# and every extra field is range-clamped before it is trusted.
		var r_ratio: float = 1.0
		var r_ko: bool = false
		var r_rematch: bool = false
		if sp_s.size() > 7:
			r_ratio = clampf(_safe_float(sp_s[7]), 0.0, 1.0)
		if sp_s.size() > 8:
			r_ko = _safe_float(sp_s[8]) >= 0.5
		if sp_s.size() > 9:
			r_rematch = _safe_float(sp_s[9]) >= 0.5
		var ts: Dictionary = combat_ref.get("target_stats")
		if ts.is_empty():
			return
		var td: Node3D = ts.keys()[0] as Node3D
		if not is_instance_valid(td):
			return
		var td_max_hp: float = maxf(1.0, float(ts[td].get("max_hp", 1500.0)))
		td.global_position = td.global_position.lerp(Vector3(rx, ry, rz), 0.65)
		td.rotation.y = ryaw
		# The ratio is authoritative when present; raw HP is the legacy fallback.
		ts[td]["hp"] = r_ratio * td_max_hp if sp_s.size() > 7 else clampf(rhp, 0.0, td_max_hp)
		ts[td]["boss_name"] = "PVP CHALLENGER [%s]" % active_room_code
		match_state.remote_name = str(ts[td]["boss_name"])
		if sp_s.size() > 7:
			match_state.remote_hp_ratio = r_ratio
			if r_ratio <= 0.0:
				match_state.record_ko(true)
			elif r_ko:
				match_state.record_ko(false)
			if r_rematch != match_state.remote_rematch_ready:
				match_state.remote_rematch_ready = r_rematch
				if r_rematch:
					_try_start_next_round()
		if ratk != 1 or not player_ref:
			return
		if player_ref.get("dash_vfx"):
			var fwd: Vector3 = -td.global_transform.basis.z
			player_ref.get("dash_vfx").call("spawn_slash_arc", td.global_position + Vector3(0, 1.1, 0), fwd, 25.0, Color(1.0, 0.25, 0.15))
		if player_ref.global_position.distance_to(td.global_position) <= 5.2 and int(player_ref.get("state")) != 6:
			var lethal: bool = bool(player_ref.call("take_damage", 65.0))
			var knock: Vector3 = (player_ref.global_position - td.global_position).normalized() * 12.0 + Vector3(0, 3.0, 0)
			if lethal:
				player_ref.call("trigger_ragdoll_ko", 1.4, knock * 1.5)
			else:
				player_ref.call("apply_hitstun", 0.28, knock)

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
		# 1. Host broadcasts room availability
		beacon_timer += delta
		if is_p2p_host and not is_p2p_connected and beacon_timer >= 0.40:
			beacon_timer = 0.0
			var lock_flag: String = "1" if not active_room_pass.is_empty() else "0"
			var payload: String = "P2PROOM:%s:%s:%s" % [active_room_code, lock_flag, local_ip]
			udp_beacon.set_dest_address("255.255.255.255", 7778)
			udp_beacon.put_packet(payload.to_utf8_buffer())

		# 2. Client retries join handshake every 0.25s while connecting
		if is_joining and not is_p2p_connected:
			join_retry_timer += delta
			join_timeout_timer -= delta
			if join_retry_timer >= 0.25:
				join_retry_timer = 0.0
				_send_join_packet()
			if join_timeout_timer <= 0.0:
				is_joining = false
				p2p_status = "Connection timed out for Room '%s'. Tap [ JOIN ] to retry." % pending_join_code

		# 3. Poll incoming UDP packets on Port 7778. Bounded per frame: a flood or a
		# burst of retransmits must never stall the frame; leftovers drain next tick.
		var budget: int = P2P_MAX_PACKETS_PER_FRAME
		while budget > 0 and udp_beacon.get_available_packet_count() > 0:
			budget -= 1
			var raw_pkt: PackedByteArray = udp_beacon.get_packet()
			var sender_ip: String = udp_beacon.get_packet_ip()
			_handle_udp_packet(raw_pkt.get_string_from_utf8(), sender_ip)

		# 4. Send throttled 30Hz Direct UDP State + Attack Sync to Connected Challenger
		p2p_send_accum += delta
		if is_p2p_connected and not peer_ip.is_empty() and player_ref and p2p_send_accum >= (1.0 / P2P_SEND_HZ):
			p2p_send_accum = 0.0
			var vis: Node3D = player_ref.get("visual_root") as Node3D
			var yaw: float = vis.rotation.y if vis else 0.0
			var is_swinging: bool = float(player_ref.get("swing_anim_timer")) > 0.15
			var atk_pulse: int = 1 if (is_swinging and not last_sent_swing) else 0
			last_sent_swing = is_swinging
			var pos: Vector3 = player_ref.global_position
			# V7 Task 2: own HP ratio, KO signal and rematch flag ride the packet.
			var l_ratio: float = clampf(float(player_ref.get("hp")) / maxf(1.0, float(player_ref.get("max_hp"))), 0.0, 1.0)
			match_state.local_hp_ratio = l_ratio
			var ko_sig: int = 1 if match_state.round_state in ["KO", "REMATCH_READY"] else 0
			var rm_sig: int = 1 if match_state.local_rematch_ready else 0
			var sync_str: String = "P2PSYNC:%.2f:%.2f:%.2f:%.2f:%.0f:%d:%.3f:%d:%d" % [pos.x, pos.y, pos.z, yaw, float(player_ref.get("hp")), atk_pulse, l_ratio, ko_sig, rm_sig]
			udp_beacon.set_dest_address(peer_ip, 7778)
			udp_beacon.put_packet(sync_str.to_utf8_buffer())

	# --- V7 Task 2: one-shot round KO ---------------------------------------
	# Both fighters' HP are authoritative and record_ko() only fires from
	# ACTIVE, so a burst of repeated packets cannot double-count a round.
	if match_state.active:
		if player_ref:
			match_state.local_hp_ratio = clampf(float(player_ref.get("hp")) / maxf(1.0, float(player_ref.get("max_hp"))), 0.0, 1.0)
		if match_state.round_state == "ACTIVE":
			if match_state.local_hp_ratio <= 0.0:
				match_state.record_ko(false)
			elif match_state.remote_hp_ratio <= 0.0:
				match_state.record_ko(true)

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
