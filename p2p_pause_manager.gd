extends Node

# --- Progression Ability Flag: "Crimson Mind's Eye" (Persona 5 Dynamic Pause) ---
var unlocked_p5_pause: bool = false
var p5_pause_active: bool = false
var p5_selected_idx: int = 0
var p5_pose_idx: int = 0
var p5_shatter_flash: float = 0.0
var p5_anim_t: float = 0.0
var locked_warning_timer: float = 0.0

const MENU_ITEMS: Array[String] = [
	"01 // SKILL & MOVES",
	"02 // EQUIP & SLOTS",
	"03 // ORIGIN & EYES",
	"04 // TETHER P2P DUEL",
	"05 // SYSTEM & UNLOCKS",
	"06 // RESUME COMBAT"
]

const POSE_NAMES: Array[String] = [
	"PHANTOM HAND VEIL",
	"RITUAL BLADE POINT",
	"OVER-SHOULDER ECLIPSE",
	"SOVEREIGN LEAN",
	"SHATTERED CROSS"
]

# Each pose defines: [cam_dist, cam_off_x, cam_off_y, cam_pitch, cam_yaw_add, cam_roll, spine_rot, head_rot, arm_r_rot, arm_l_rot]
const POSE_PRESETS: Array = [
	[1.95, -0.65, 1.55, -4.0, 155.0, -11.0, Vector3(6, -15, 4), Vector3(-8, 22, -6), Vector3(-25, 15, -18), Vector3(-75, 45, 35)],
	[2.20, 0.78, 1.48, -6.0, 135.0, 13.0, Vector3(-8, 28, -5), Vector3(4, -25, 8), Vector3(-88, -20, 15), Vector3(18, 0, 22)],
	[1.75, -0.55, 1.68, -12.0, 32.0, -9.0, Vector3(10, 35, 0), Vector3(-12, 48, 5), Vector3(-40, 25, -45), Vector3(-20, -15, 25)],
	[2.35, 0.72, 1.38, 4.0, 168.0, 14.0, Vector3(-14, -18, 8), Vector3(12, 18, -10), Vector3(-115, 10, -25), Vector3(-55, -30, 40)],
	[2.05, -0.70, 1.52, -8.0, 195.0, -15.0, Vector3(12, 12, -8), Vector3(-14, -18, 6), Vector3(-65, 55, -60), Vector3(-65, -55, 60)]
]

# --- Zero-Lag Tethered P2P Multiplayer (ENet UDP + Auto-Beacon) ---
var enet_peer: ENetMultiplayerPeer = null
var udp_beacon: PacketPeerUDP = null
var is_p2p_connected: bool = false
var is_p2p_host: bool = false
var local_tether_ip: String = "127.0.0.1"
var remote_peer_ip: String = ""
var p2p_status: String = "OFFLINE (Tether Ready)"
var p2p_ping_ms: float = 0.0
var beacon_timer: float = 0.0
var last_ping_sent: float = 0.0

var player_ref: Node3D = null
var combat_ref: Node = null

func _ready() -> void:
	_detect_local_tether_ip()
	if DisplayServer.get_name() != "headless":
		_init_udp_beacon()

func _detect_local_tether_ip() -> void:
	var addrs: PackedStringArray = IP.get_local_addresses()
	for a in addrs:
		var ip_str: String = str(a)
		# Prioritize USB Tethering (192.168.42.x), Hotspot (192.168.43.x / 172.20.10.x), or LAN (192.168.x.x / 10.x.x.x)
		if ip_str.begins_with("192.168.42.") or ip_str.begins_with("192.168.43.") or ip_str.begins_with("172.20.10."):
			local_tether_ip = ip_str
			return
		elif ip_str.begins_with("192.168.") or ip_str.begins_with("10."):
			local_tether_ip = ip_str

func _init_udp_beacon() -> void:
	udp_beacon = PacketPeerUDP.new()
	udp_beacon.set_broadcast_enabled(true)
	udp_beacon.bind(7778)

func acquire_p5_pause_ability() -> void:
	unlocked_p5_pause = true
	if combat_ref:
		combat_ref.set("last_combat_action", "ABILITY ACQUIRED: CRIMSON MIND'S EYE PAUSE!")

func toggle_p5_pause() -> bool:
	if not unlocked_p5_pause:
		locked_warning_timer = 2.2
		if combat_ref:
			combat_ref.set("last_combat_action", "LOCKED! Acquire 'Mind's Eye Pause' in Tab 7 or Top Bar!")
		if player_ref and player_ref.get("dash_vfx"):
			player_ref.get("dash_vfx").play_sfx("hit")
		return false

	p5_pause_active = not p5_pause_active
	if p5_pause_active:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_roll_new_pose_and_camera()
	else:
		if player_ref:
			player_ref.call("play_character_anim", "idle")
			if player_ref.get("camera"):
				(player_ref.get("camera") as Camera3D).rotation_degrees.z = 0.0
		if not DisplayServer.is_touchscreen_available():
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	return p5_pause_active

func select_p5_menu_item(idx: int) -> void:
	p5_selected_idx = (idx + MENU_ITEMS.size()) % MENU_ITEMS.size()
	_roll_new_pose_and_camera()

func _roll_new_pose_and_camera() -> void:
	p5_pose_idx = (p5_pose_idx + randi_range(1, POSE_PRESETS.size() - 1)) % POSE_PRESETS.size()
	p5_shatter_flash = 0.18
	p5_anim_t = 0.0
	if player_ref and player_ref.get("dash_vfx"):
		player_ref.get("dash_vfx").play_sfx("slash")
	_apply_pose_to_skeleton()

func _apply_pose_to_skeleton() -> void:
	if not player_ref: return
	var skel: Skeleton3D = player_ref.get("active_skeleton") as Skeleton3D
	if not skel: return
	var preset: Array = POSE_PRESETS[p5_pose_idx]
	var bone_pairs: Array = [
		["Spine", preset[6]],
		["Head", preset[7]],
		["Arm_R", preset[8]],
		["Arm_L", preset[9]]
	]
	for bp in bone_pairs:
		var b_name: String = str(bp[0])
		var rot_deg: Vector3 = bp[1]
		var b_idx: int = skel.find_bone(b_name)
		if b_idx != -1:
			var q := Quaternion.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
			skel.set_bone_pose_rotation(b_idx, q)

func update_p5_camera(delta: float) -> void:
	if locked_warning_timer > 0.0:
		locked_warning_timer = maxf(0.0, locked_warning_timer - delta)
	if p5_shatter_flash > 0.0:
		p5_shatter_flash = maxf(0.0, p5_shatter_flash - delta)
	p5_anim_t += delta
	_poll_p2p_network(delta)

	if not p5_pause_active or not player_ref: return
	_apply_pose_to_skeleton()

	var preset: Array = POSE_PRESETS[p5_pose_idx]
	var target_dist: float = float(preset[0])
	var target_ox: float = float(preset[1])
	var target_oy: float = float(preset[2]) * float(player_ref.get("char_height"))
	var target_pitch: float = float(preset[3])
	var yaw_offset: float = float(preset[4])
	var target_roll: float = float(preset[5])

	var vis_root: Node3D = player_ref.get("visual_root") as Node3D
	var cam_piv: Node3D = player_ref.get("camera_pivot") as Node3D
	var sp_arm: SpringArm3D = player_ref.get("spring_arm") as SpringArm3D
	var cam: Camera3D = player_ref.get("camera") as Camera3D
	if not cam_piv or not sp_arm or not cam: return

	var char_yaw_deg: float = rad_to_deg(vis_root.rotation.y) if vis_root else 0.0
	var desired_yaw: float = char_yaw_deg + yaw_offset + sin(p5_anim_t * 1.8) * 2.5

	cam_piv.position = cam_piv.position.lerp(Vector3(0.0, target_oy, 0.0), 16.0 * delta)
	sp_arm.position = sp_arm.position.lerp(Vector3(target_ox, 0.0, 0.0), 16.0 * delta)
	sp_arm.spring_length = lerpf(sp_arm.spring_length, target_dist, 16.0 * delta)
	cam_piv.rotation_degrees.y = lerp_angle(deg_to_rad(cam_piv.rotation_degrees.y), deg_to_rad(desired_yaw), 16.0 * delta) * 180.0 / PI
	cam_piv.rotation_degrees.x = lerpf(cam_piv.rotation_degrees.x, target_pitch, 16.0 * delta)
	cam.rotation_degrees.z = lerpf(cam.rotation_degrees.z, target_roll, 16.0 * delta)
	cam.fov = lerpf(cam.fov, 62.0, 14.0 * delta)

# =========================================================================
# ZERO-LAG TETHERED & LOCAL P2P MULTIPLAYER (USB TETHER / HOTSPOT / WI-FI)
# =========================================================================
func host_tethered_duel(port: int = 7777) -> void:
	_detect_local_tether_ip()
	enet_peer = ENetMultiplayerPeer.new()
	var err: int = enet_peer.create_server(port, 2)
	if err != OK:
		p2p_status = "HOST ERROR (%d)" % err
		return
	multiplayer.multiplayer_peer = enet_peer
	is_p2p_host = true
	is_p2p_connected = false
	p2p_status = "HOSTING ON TETHER IP %s:%d (Waiting...)" % [local_tether_ip, port]
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func join_tethered_duel(ip: String, port: int = 7777) -> void:
	var clean_ip: String = ip.strip_edges()
	if clean_ip.is_empty(): clean_ip = "127.0.0.1"
	enet_peer = ENetMultiplayerPeer.new()
	var err: int = enet_peer.create_client(clean_ip, port)
	if err != OK:
		p2p_status = "JOIN ERROR (%d)" % err
		return
	multiplayer.multiplayer_peer = enet_peer
	is_p2p_host = false
	remote_peer_ip = clean_ip
	p2p_status = "CONNECTING TO %s:%d..." % [clean_ip, port]
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_connected(id: int) -> void:
	if id == 1 and is_p2p_host: return
	is_p2p_connected = true
	p2p_status = "TETHER LINKED (Peer %d) — ZERO-LAG 120Hz SYNC" % id
	if player_ref and player_ref.get("dash_vfx"):
		player_ref.get("dash_vfx").play_sfx("clash")
	if combat_ref:
		combat_ref.set("last_combat_action", "TETHER P2P DUEL LINKED!")

func _on_peer_disconnected(_id: int) -> void:
	is_p2p_connected = false
	p2p_status = "PEER DISCONNECTED"

func _poll_p2p_network(delta: float) -> void:
	if not udp_beacon: return
	beacon_timer += delta
	# 1. Host broadcasts beacon on USB-tether / Hotspot / LAN subnet every 0.45s
	if is_p2p_host and not is_p2p_connected and beacon_timer >= 0.45:
		beacon_timer = 0.0
		var pkt: PackedByteArray = ("SASTI_P2P_HOST:" + local_tether_ip).to_utf8_buffer()
		udp_beacon.set_dest_address("255.255.255.255", 7778)
		udp_beacon.put_packet(pkt)

	# 2. Client listens for Host beacon to auto-fill IP
	while udp_beacon.get_available_packet_count() > 0:
		var raw: PackedByteArray = udp_beacon.get_packet()
		var msg: String = raw.get_string_from_utf8()
		if msg.begins_with("SASTI_P2P_HOST:"):
			var discovered_ip: String = msg.split(":")[1]
			if discovered_ip != local_tether_ip and remote_peer_ip != discovered_ip:
				remote_peer_ip = discovered_ip
				if not is_p2p_connected and not is_p2p_host:
					p2p_status = "FOUND TETHER HOST AT " + discovered_ip

	# 3. 120Hz Unreliable-Ordered State Sync over Tethered UDP
	if is_p2p_connected and player_ref:
		var vis: Node3D = player_ref.get("visual_root") as Node3D
		var yaw: float = vis.rotation.y if vis else 0.0
		rpc("_rpc_sync_fighter", player_ref.global_position, yaw, float(player_ref.get("hp")), int(player_ref.get("state")))
		if Time.get_ticks_msec() / 1000.0 - last_ping_sent >= 0.5:
			last_ping_sent = Time.get_ticks_msec() / 1000.0
			rpc("_rpc_ping", last_ping_sent)

@rpc("any_peer", "unreliable_ordered")
func _rpc_sync_fighter(pos: Vector3, yaw: float, remote_hp: float, _remote_state: int) -> void:
	if not combat_ref: return
	var t_stats: Dictionary = combat_ref.get("target_stats")
	if t_stats.is_empty(): return
	var rival_td: Node3D = t_stats.keys()[0] as Node3D
	if is_instance_valid(rival_td):
		rival_td.global_position = rival_td.global_position.lerp(pos, 0.65)
		rival_td.rotation.y = yaw
		var s: Dictionary = t_stats[rival_td]
		s["hp"] = remote_hp
		s["boss_name"] = "TETHER P2P CHALLENGER (%.1fms)" % p2p_ping_ms

@rpc("any_peer", "unreliable")
func _rpc_ping(sent_t: float) -> void:
	rpc_id(multiplayer.get_remote_sender_id(), "_rpc_pong", sent_t)

@rpc("any_peer", "unreliable")
func _rpc_pong(sent_t: float) -> void:
	p2p_ping_ms = maxf(0.4, ((Time.get_ticks_msec() / 1000.0) - sent_t) * 1000.0 * 0.5)

func broadcast_remote_strike(roll_deg: float, dmg: float, posture_dmg: float, knock_vec: Vector3) -> void:
	if is_p2p_connected:
		rpc("_rpc_remote_strike", roll_deg, dmg, posture_dmg, knock_vec)

@rpc("any_peer", "reliable")
func _rpc_remote_strike(roll_deg: float, dmg: float, _posture_dmg: float, knock_vec: Vector3) -> void:
	if not player_ref: return
	if player_ref.get("dash_vfx"):
		var fwd := -player_ref.global_transform.basis.z
		player_ref.get("dash_vfx").spawn_slash_arc(player_ref.global_position + Vector3(0, 1.2, 0), fwd, roll_deg, Color(1.0, 0.15, 0.25))
	if int(player_ref.get("state")) != 6: # Not GUARD
		player_ref.set("hp", maxf(100.0, float(player_ref.get("hp")) - dmg * 0.35))
		player_ref.call("apply_hitstun", 0.32, knock_vec * 0.6)
