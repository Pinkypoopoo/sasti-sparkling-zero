class_name FlameP5PvPModule
extends Node

# --- 1. Pure Flame Awakening + 2-Layer Flame Explosion Dome (No Bones / No Susanoo) ---
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
	"04 // EASY PVP DUEL LOBBY",
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

# --- 3. Idiot-Proof 2-Step Local PvP (UDP 7777 + Auto-Discovery) ---
var enet_peer: ENetMultiplayerPeer = null
var udp_beacon: PacketPeerUDP = null
var is_p2p_connected: bool = false
var is_p2p_host: bool = false
var local_ip: String = "127.0.0.1"
var discovered_host_ip: String = ""
var p2p_status: String = "SOLO MODE (Not Connected)"
var beacon_timer: float = 0.0

var player_ref: Node3D = null
var combat_ref: Node = null
var studio_ref: Control = null
var pvp_modal: PanelContainer = null
var pvp_status_lbl: Label = null
var pvp_ip_edit: LineEdit = null

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
	_build_easy_pvp_modal()

func _detect_local_ip() -> void:
	for a in IP.get_local_addresses():
		var ip_s: String = str(a)
		if ip_s.begins_with("192.168.") or ip_s.begins_with("172.20.10.") or ip_s.begins_with("10."):
			local_ip = ip_s
			if ip_s.begins_with("192.168.42.") or ip_s.begins_with("192.168.43."):
				break

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

func _build_easy_pvp_modal() -> void:
	if not studio_ref: return
	pvp_modal = PanelContainer.new()
	pvp_modal.anchor_left = 0.5; pvp_modal.anchor_top = 0.5; pvp_modal.anchor_right = 0.5; pvp_modal.anchor_bottom = 0.5
	pvp_modal.offset_left = -260; pvp_modal.offset_top = -155; pvp_modal.offset_right = 260; pvp_modal.offset_bottom = 155
	pvp_modal.visible = false
	studio_ref.add_child(pvp_modal)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pvp_modal.add_child(vb)

	var t_lbl: Label = Label.new()
	t_lbl.text = "=== EASY 2-STEP LOCAL PVP DUEL ==="
	t_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	vb.add_child(t_lbl)

	var ip_lbl: Label = Label.new()
	ip_lbl.text = "YOUR DEVICE IP CODE:  " + local_ip
	ip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ip_lbl)

	pvp_status_lbl = Label.new()
	pvp_status_lbl.text = "Status: " + p2p_status
	pvp_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pvp_status_lbl.add_theme_color_override("font_color", Color(0.3, 0.95, 1.0))
	vb.add_child(pvp_status_lbl)

	var b_host: Button = Button.new()
	b_host.text = "1. [ CREATE ROOM (Tap on Device 1) ]"
	b_host.custom_minimum_size = Vector2(0, 40)
	b_host.modulate = Color(0.3, 1.0, 0.5)
	b_host.pressed.connect(func(): host_room(7777))
	vb.add_child(b_host)

	pvp_ip_edit = LineEdit.new()
	pvp_ip_edit.placeholder_text = "Optional: Friend's IP (Leave blank to auto-detect on Wi-Fi/Hotspot)"
	vb.add_child(pvp_ip_edit)

	var b_join: Button = Button.new()
	b_join.text = "2. [ JOIN FRIEND'S ROOM (Tap on Device 2) ]"
	b_join.custom_minimum_size = Vector2(0, 40)
	b_join.modulate = Color(0.4, 0.85, 1.0)
	b_join.pressed.connect(func(): join_room(pvp_ip_edit.text, 7777))
	vb.add_child(b_join)

	var h_bot: HBoxContainer = HBoxContainer.new()
	vb.add_child(h_bot)
	var b_disc: Button = Button.new(); b_disc.text = "[ Disconnect ]"; b_disc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_disc.pressed.connect(disconnect_p2p); h_bot.add_child(b_disc)
	var b_close: Button = Button.new(); b_close.text = "[ Close ]"; b_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_close.pressed.connect(func(): pvp_modal.visible = false); h_bot.add_child(b_close)

func host_room(port: int = 7777) -> void:
	disconnect_p2p()
	_detect_local_ip()
	enet_peer = ENetMultiplayerPeer.new()
	if enet_peer.create_server(port, 2) != OK:
		p2p_status = "ERROR: Port 7777 busy"
		return
	multiplayer.multiplayer_peer = enet_peer
	is_p2p_host = true
	p2p_status = "WAITING FOR FRIEND... (Your IP: %s)" % local_ip
	if not multiplayer.peer_connected.is_connected(_on_peer_conn):
		multiplayer.peer_connected.connect(_on_peer_conn)

func join_room(ip: String, port: int = 7777) -> void:
	var cip: String = ip.strip_edges()
	if cip.is_empty(): cip = discovered_host_ip
	if cip.is_empty() or cip == "127.0.0.1" or cip == local_ip:
		p2p_status = "NO FRIEND FOUND YET! Have friend tap CREATE ROOM first."
		return
	disconnect_p2p()
	enet_peer = ENetMultiplayerPeer.new()
	if enet_peer.create_client(cip, port) != OK:
		p2p_status = "ERROR: Cannot connect to " + cip
		return
	multiplayer.multiplayer_peer = enet_peer
	is_p2p_host = false
	p2p_status = "CONNECTING TO %s..." % cip
	if not multiplayer.peer_connected.is_connected(_on_peer_conn):
		multiplayer.peer_connected.connect(_on_peer_conn)

func disconnect_p2p() -> void:
	if enet_peer: enet_peer.close(); enet_peer = null
	multiplayer.multiplayer_peer = null
	is_p2p_host = false; is_p2p_connected = false
	p2p_status = "SOLO MODE (Disconnected)"

func _on_peer_conn(id: int) -> void:
	if id == 1 and is_p2p_host: return
	is_p2p_connected = true
	p2p_status = "CONNECTED! 120Hz TETHER DUEL ACTIVE"

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
		if is_p2p_host and not is_p2p_connected and beacon_timer >= 0.5:
			beacon_timer = 0.0
			udp_beacon.set_dest_address("255.255.255.255", 7778)
			udp_beacon.put_packet(("P2P:" + local_ip).to_utf8_buffer())
		while udp_beacon.get_available_packet_count() > 0:
			var m: String = udp_beacon.get_packet().get_string_from_utf8()
			if m.begins_with("P2P:"):
				var dip: String = m.split(":")[1]
				if dip != local_ip and dip != "127.0.0.1":
					discovered_host_ip = dip
					if not is_p2p_host and not is_p2p_connected:
						p2p_status = "FOUND FRIEND AT %s! Tap JOIN!" % dip
		if is_p2p_connected and player_ref:
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
	if not combat_ref: return
	var ts: Dictionary = combat_ref.get("target_stats")
	if ts.is_empty(): return
	var td: Node3D = ts.keys()[0] as Node3D
	if is_instance_valid(td):
		td.global_position = td.global_position.lerp(pos, 0.65)
		td.rotation.y = yaw
		ts[td]["boss_name"] = "LIVE PVP FRIEND"
