class_name DashVFX
extends Node3D

var afterimages: Array[MeshInstance3D] = []
var afterimage_alphas: Array[float] = [0.0, 0.0, 0.0]
var afterimage_mats: Array[StandardMaterial3D] = []
var afterimage_idx: int = 0
var afterimage_timer: float = 0.0
var echo_color_idx: int = 0

var dash_fx_mesh: MeshInstance3D = null
var dash_fx_mat: StandardMaterial3D = null
var dash_fx_timer: float = 0.0

var sigil_rings: Array[MeshInstance3D] = []
var sigil_mats: Array[StandardMaterial3D] = []
var sigil_timers: Array[float] = [0.0, 0.0, 0.0, 0.0]
var sigil_idx: int = 0

var slash_arcs: Array[Node3D] = []
var slash_core_mats: Array[StandardMaterial3D] = []
var slash_timers: Array[float] = [0.0, 0.0, 0.0, 0.0]
var slash_idx: int = 0

var destructible_pillars: Array[Dictionary] = []
var debris_pool: Array[Dictionary] = []
var crater_pool: Array[MeshInstance3D] = []
var crater_idx: int = 0
var stone_mat: StandardMaterial3D = null
var dark_stone_mat: StandardMaterial3D = null
var flora_mat: ShaderMaterial = null

# --- Minecraft-Style Custom Arena Blocks & MultiMesh Flora ---
var custom_block_nodes: Array[Dictionary] = []

# --- Procedural Synth SFX Engine (Zero External Audio Files Required) ---
var sfx_player: AudioStreamPlayer = null
var sfx_playback: AudioStreamGeneratorPlayback = null
var sfx_phase: float = 0.0
var sfx_freq: float = 0.0
var sfx_end_freq: float = 0.0
var sfx_timer: float = 0.0
var sfx_total_dur: float = 0.1
var sfx_noise_mix: float = 0.0

func _ready() -> void:
	_setup_synth_audio()
	_setup_afterimage_pool()
	_setup_slash_arc_pool()
	_setup_destructible_arena()

func _setup_synth_audio() -> void:
	if DisplayServer.get_name() == "headless": return
	sfx_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.12
	sfx_player.stream = gen
	sfx_player.volume_db = -6.0
	add_child(sfx_player)
	sfx_player.play()
	sfx_playback = sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback

func play_sfx(kind: String) -> void:
	if not sfx_playback: return
	sfx_phase = 0.0
	match kind:
		"slash":
			sfx_freq = 520.0; sfx_end_freq = 110.0; sfx_total_dur = 0.11; sfx_noise_mix = 0.55
		"hit":
			sfx_freq = 190.0; sfx_end_freq = 48.0; sfx_total_dur = 0.14; sfx_noise_mix = 0.35
		"clash":
			sfx_freq = 1480.0; sfx_end_freq = 620.0; sfx_total_dur = 0.22; sfx_noise_mix = 0.25
		"vanish":
			sfx_freq = 320.0; sfx_end_freq = 1280.0; sfx_total_dur = 0.12; sfx_noise_mix = 0.15
		"shatter":
			sfx_freq = 130.0; sfx_end_freq = 38.0; sfx_total_dur = 0.26; sfx_noise_mix = 0.78
		"build":
			sfx_freq = 440.0; sfx_end_freq = 660.0; sfx_total_dur = 0.07; sfx_noise_mix = 0.05
	sfx_timer = sfx_total_dur

func _pump_synth_audio(delta: float) -> void:
	if not sfx_playback or sfx_timer <= 0.0: return
	sfx_timer = maxf(0.0, sfx_timer - delta)
	var frames := mini(sfx_playback.get_frames_available(), 512)
	var prog := 1.0 - (sfx_timer / maxf(0.01, sfx_total_dur))
	var cur_f := lerpf(sfx_freq, sfx_end_freq, prog)
	var env := (1.0 - prog) * 0.45
	for i in range(frames):
		sfx_phase += cur_f / 22050.0
		var tone := sin(sfx_phase * TAU) + 0.35 * sin(sfx_phase * TAU * 2.4)
		var noise := randf_range(-1.0, 1.0)
		var samp := lerpf(tone, noise, sfx_noise_mix) * env
		sfx_playback.push_frame(Vector2(samp, samp))

func _setup_afterimage_pool() -> void:
	var cyl_cap := CapsuleMesh.new()
	cyl_cap.radius = 0.45
	cyl_cap.height = 1.75
	for i in range(3):
		var mi := MeshInstance3D.new()
		mi.mesh = cyl_cap
		mi.top_level = true
		mi.visible = false
		var mat := StandardMaterial3D.new()
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		mat.albedo_color = Color(0.95, 0.12, 0.18, 0.0)
		mi.material_override = mat
		add_child(mi)
		afterimages.append(mi)
		afterimage_mats.append(mat)

	dash_fx_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.4
	cyl.bottom_radius = 0.4
	cyl.height = 2.6
	dash_fx_mesh.mesh = cyl
	dash_fx_mesh.top_level = true
	dash_fx_mesh.visible = false
	dash_fx_mat = StandardMaterial3D.new()
	dash_fx_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	dash_fx_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	dash_fx_mat.albedo_color = Color(0.95, 0.15, 0.2, 0.85)
	dash_fx_mesh.material_override = dash_fx_mat
	add_child(dash_fx_mesh)

	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 1.35
	ring_mesh.bottom_radius = 1.35
	ring_mesh.height = 0.04
	for i in range(4):
		var sm := MeshInstance3D.new()
		sm.mesh = ring_mesh
		sm.top_level = true
		sm.visible = false
		var rmat := StandardMaterial3D.new()
		rmat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		rmat.albedo_color = Color(0.95, 0.15, 0.2, 0.0)
		sm.material_override = rmat
		add_child(sm)
		sigil_rings.append(sm)
		sigil_mats.append(rmat)

func _setup_slash_arc_pool() -> void:
	var outer_mesh := TorusMesh.new()
	outer_mesh.inner_radius = 1.65
	outer_mesh.outer_radius = 2.35
	outer_mesh.rings = 24
	outer_mesh.ring_segments = 8

	var inner_mesh := TorusMesh.new()
	inner_mesh.inner_radius = 1.78
	inner_mesh.outer_radius = 2.22
	inner_mesh.rings = 24
	inner_mesh.ring_segments = 8

	var black_ink_mat := StandardMaterial3D.new()
	black_ink_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	black_ink_mat.albedo_color = Color(0.01, 0.01, 0.02, 1.0)

	for i in range(4):
		var root_arc := Node3D.new()
		root_arc.top_level = true
		root_arc.visible = false

		var outer_mi := MeshInstance3D.new()
		outer_mi.mesh = outer_mesh
		outer_mi.scale = Vector3(1.0, 0.18, 0.55)
		outer_mi.material_override = black_ink_mat
		root_arc.add_child(outer_mi)

		var core_mi := MeshInstance3D.new()
		core_mi.mesh = inner_mesh
		core_mi.scale = Vector3(1.02, 0.26, 0.56)
		var cmat := StandardMaterial3D.new()
		cmat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		cmat.albedo_color = Color(0.98, 0.96, 0.92, 1.0)
		core_mi.material_override = cmat
		root_arc.add_child(core_mi)

		add_child(root_arc)
		slash_arcs.append(root_arc)
		slash_core_mats.append(cmat)

func spawn_slash_arc(origin: Vector3, forward_dir: Vector3, roll_deg: float, core_col: Color = Color(0.98, 0.96, 0.92)) -> void:
	play_sfx("slash")
	var arc := slash_arcs[slash_idx]
	var cmat := slash_core_mats[slash_idx]
	arc.global_position = origin
	var f := forward_dir.normalized()
	if f.length_squared() < 0.01: f = Vector3.FORWARD
	var up_v := Vector3.UP if absf(f.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	arc.look_at(origin + f, up_v)
	arc.rotate_object_local(Vector3.FORWARD, deg_to_rad(roll_deg))
	arc.scale = Vector3(0.75, 0.75, 0.75)
	cmat.albedo_color = core_col
	arc.visible = true
	slash_timers[slash_idx] = 0.18
	slash_idx = (slash_idx + 1) % 4

func _setup_destructible_arena() -> void:
	stone_mat = StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.76, 0.75, 0.73)
	stone_mat.roughness = 0.92
	stone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH

	dark_stone_mat = StandardMaterial3D.new()
	dark_stone_mat.albedo_color = Color(0.12, 0.12, 0.15)
	dark_stone_mat.roughness = 0.95
	dark_stone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH

	flora_mat = ShaderMaterial.new()
	flora_mat.shader = Shader.new()
	flora_mat.shader.code = """
shader_type spatial;
render_mode cull_disabled, unshaded;
uniform vec4 top_col : source_color = vec4(0.25, 0.85, 0.65, 1.0);
uniform vec4 bot_col : source_color = vec4(0.02, 0.05, 0.08, 1.0);
void vertex() {
	float sway = sin(TIME * 3.2 + NODE_POSITION_WORLD.x * 0.8 + VERTEX.x * 2.0) * 0.18;
	VERTEX.x += sway * max(0.0, VERTEX.y);
}
void fragment() {
	ALBEDO = mix(bot_col.rgb, top_col.rgb, clamp(VERTEX.y, 0.0, 1.0));
}
"""

	var pillar_coords: Array[Vector3] = [
		Vector3(-12, 0, -10), Vector3(12, 0, -10),
		Vector3(-16, 0, -24), Vector3(16, 0, -24),
		Vector3(-8, 0, -32), Vector3(8, 0, -32),
		Vector3(-22, 0, -14), Vector3(22, 0, -14)
	]
	for pos in pillar_coords:
		spawn_arena_block("GOTHIC_PILLAR", pos, 0.0, false)

	var chunk_mesh := BoxMesh.new()
	chunk_mesh.size = Vector3(0.75, 0.55, 0.95)
	for i in range(28):
		var d_mi := MeshInstance3D.new()
		d_mi.mesh = chunk_mesh
		d_mi.top_level = true
		d_mi.visible = false
		d_mi.material_override = stone_mat if (i % 2 == 0) else dark_stone_mat
		add_child(d_mi)
		debris_pool.append({
			"mesh": d_mi, "vel": Vector3.ZERO, "rot_vel": Vector3.ZERO, "timer": 0.0
		})

	var crater_mesh := CylinderMesh.new()
	crater_mesh.top_radius = 2.6
	crater_mesh.bottom_radius = 2.8
	crater_mesh.height = 0.08
	crater_mesh.radial_segments = 12
	for i in range(6):
		var c_mi := MeshInstance3D.new()
		c_mi.mesh = crater_mesh
		c_mi.top_level = true
		c_mi.visible = false
		c_mi.material_override = dark_stone_mat
		add_child(c_mi)
		crater_pool.append(c_mi)

# --- Minecraft-Style Modular Block & MultiMesh Flora Spawner ---
func spawn_arena_block(kind: String, pos: Vector3, rot_y_deg: float = 0.0, record_user: bool = true) -> void:
	var snapped := Vector3(snappedf(pos.x, 2.0), maxf(0.0, snappedf(pos.y, 2.0)), snappedf(pos.z, 2.0))
	var b_root := Node3D.new()
	b_root.top_level = true
	add_child(b_root)
	b_root.global_position = snapped
	b_root.rotation_degrees.y = rot_y_deg

	var upper_holder := Node3D.new()
	b_root.add_child(upper_holder)

	match kind:
		"GOTHIC_PILLAR":
			var base_mi := MeshInstance3D.new()
			var bm := BoxMesh.new(); bm.size = Vector3(2.2, 1.6, 2.2)
			base_mi.mesh = bm; base_mi.position = Vector3(0, 0.8, 0); base_mi.material_override = dark_stone_mat
			b_root.add_child(base_mi)

			var shaft_mi := MeshInstance3D.new()
			var sm := CylinderMesh.new(); sm.top_radius = 0.85; sm.bottom_radius = 0.95; sm.height = 14.0; sm.radial_segments = 10
			shaft_mi.mesh = sm; shaft_mi.position = Vector3(0, 8.6, 0); shaft_mi.material_override = stone_mat
			upper_holder.add_child(shaft_mi)

			var spire_mi := MeshInstance3D.new()
			var spm := CylinderMesh.new(); spm.top_radius = 0.05; spm.bottom_radius = 1.25; spm.height = 4.5; spm.radial_segments = 8
			spire_mi.mesh = spm; spire_mi.position = Vector3(0, 17.8, 0); spire_mi.material_override = dark_stone_mat
			upper_holder.add_child(spire_mi)

		"BLAME_MONOLITH":
			var mono_mi := MeshInstance3D.new()
			var mm := BoxMesh.new(); mm.size = Vector3(4.0, 22.0, 4.0)
			mono_mi.mesh = mm; mono_mi.position = Vector3(0, 11.0, 0); mono_mi.material_override = dark_stone_mat
			upper_holder.add_child(mono_mi)

		"RUINED_ARCH":
			for side in [-1.0, 1.0]:
				var col_mi := MeshInstance3D.new()
				var cm := BoxMesh.new(); cm.size = Vector3(1.4, 8.0, 1.4)
				col_mi.mesh = cm; col_mi.position = Vector3(side * 2.6, 4.0, 0); col_mi.material_override = stone_mat
				upper_holder.add_child(col_mi)
			var lintel := MeshInstance3D.new()
			var lm := BoxMesh.new(); lm.size = Vector3(7.2, 1.6, 1.8)
			lintel.mesh = lm; lintel.position = Vector3(0, 8.6, 0); lintel.material_override = dark_stone_mat
			upper_holder.add_child(lintel)

		"ANIME_FLORA_PATCH":
			var mmi := MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			var blade := PrismMesh.new()
			blade.size = Vector3(0.28, 1.45, 0.05)
			mm.mesh = blade
			mm.instance_count = 45
			for i in range(45):
				var t := Transform3D().rotated(Vector3.UP, randf() * TAU)
				t = t.scaled(Vector3.ONE * randf_range(0.65, 1.45))
				t.origin = Vector3(randf_range(-2.2, 2.2), 0.5, randf_range(-2.2, 2.2))
				mm.set_instance_transform(i, t)
			mmi.multimesh = mm
			mmi.material_override = flora_mat
			upper_holder.add_child(mmi)

	var entry := {"kind": kind, "pos": snapped, "rot": rot_y_deg, "root": b_root, "upper": upper_holder, "intact": true, "user_placed": record_user}
	destructible_pillars.append(entry)
	if record_user:
		custom_block_nodes.append(entry)
		play_sfx("build")

func remove_nearest_block(pos: Vector3, max_r: float = 4.5) -> bool:
	var best_idx := -1
	var best_d := max_r
	for i in range(destructible_pillars.size()):
		var p: Dictionary = destructible_pillars[i]
		var d := Vector2(pos.x - p["pos"].x, pos.z - p["pos"].z).length()
		if d < best_d:
			best_d = d
			best_idx = i
	if best_idx != -1:
		var target: Dictionary = destructible_pillars[best_idx]
		if is_instance_valid(target["root"]):
			(target["root"] as Node3D).queue_free()
		destructible_pillars.remove_at(best_idx)
		custom_block_nodes.erase(target)
		play_sfx("shatter")
		return true
	return false

func serialize_user_blocks() -> Array:
	var out: Array = []
	for b in custom_block_nodes:
		if is_instance_valid(b.get("root", null)):
			out.append({"kind": b["kind"], "x": b["pos"].x, "y": b["pos"].y, "z": b["pos"].z, "rot": b["rot"]})
	return out

func load_serialized_blocks(arr: Array) -> void:
	for b in custom_block_nodes:
		if is_instance_valid(b.get("root", null)):
			(b["root"] as Node3D).queue_free()
		destructible_pillars.erase(b)
	custom_block_nodes.clear()
	for item in arr:
		if typeof(item) == TYPE_DICTIONARY:
			spawn_arena_block(str(item.get("kind", "GOTHIC_PILLAR")), Vector3(float(item.get("x", 0.0)), float(item.get("y", 0.0)), float(item.get("z", 0.0))), float(item.get("rot", 0.0)), true)

func check_destruction(impact_pos: Vector3, radius: float, impulse_dir: Vector3, spawn_crater: bool = false) -> void:
	if spawn_crater and impact_pos.y <= 2.2:
		var cm := crater_pool[crater_idx]
		cm.global_position = Vector3(impact_pos.x, 0.54, impact_pos.z)
		cm.rotation.y = randf() * TAU
		cm.visible = true
		crater_idx = (crater_idx + 1) % crater_pool.size()
		_burst_debris(Vector3(impact_pos.x, 1.0, impact_pos.z), Vector3.UP, 6)
		play_sfx("shatter")

	for p in destructible_pillars:
		if p["intact"] and p.get("kind", "") != "ANIME_FLORA_PATCH":
			var p_pos: Vector3 = p["pos"]
			var flat_d := Vector2(impact_pos.x - p_pos.x, impact_pos.z - p_pos.z).length()
			if flat_d <= radius:
				p["intact"] = false
				if is_instance_valid(p["upper"]):
					(p["upper"] as Node3D).visible = false
				_burst_debris(p_pos + Vector3(0, 4.5, 0), impulse_dir, 12)
				spawn_step_sigil(p_pos + Vector3(0, 2.0, 0), Color(0.95, 0.92, 0.88), 2.4)
				play_sfx("shatter")

func _burst_debris(origin: Vector3, dir: Vector3, count: int) -> void:
	var spawned := 0
	var base_d := dir.normalized() if dir.length_squared() > 0.01 else Vector3.UP
	for d in debris_pool:
		if d["timer"] <= 0.0:
			var mi: MeshInstance3D = d["mesh"]
			mi.global_position = origin + Vector3(randf_range(-1.1, 1.1), randf_range(0.0, 3.2), randf_range(-1.1, 1.1))
			mi.scale = Vector3(randf_range(0.6, 1.6), randf_range(0.6, 1.4), randf_range(0.6, 1.6))
			d["vel"] = (base_d + Vector3(randf_range(-0.65, 0.65), randf_range(0.35, 1.1), randf_range(-0.65, 0.65))).normalized() * randf_range(12.0, 26.0)
			d["rot_vel"] = Vector3(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
			d["timer"] = 1.6
			mi.visible = true
			spawned += 1
			if spawned >= count:
				break

func reset_destructibles() -> void:
	for p in destructible_pillars:
		p["intact"] = true
		if is_instance_valid(p.get("upper", null)):
			(p["upper"] as Node3D).visible = true
	for d in debris_pool:
		d["timer"] = 0.0
		(d["mesh"] as MeshInstance3D).visible = false
	for c in crater_pool:
		c.visible = false

func clear_afterimages() -> void:
	for i in range(3):
		afterimage_alphas[i] = 0.0
		afterimages[i].visible = false

func spawn_afterimage(target_xform: Transform3D, col: Color, alpha_val: float = 0.75) -> void:
	var mi := afterimages[afterimage_idx]
	var mat := afterimage_mats[afterimage_idx]
	mi.global_transform = target_xform
	mi.visible = true
	afterimage_alphas[afterimage_idx] = alpha_val
	mat.albedo_color = Color(col.r, col.g, col.b, alpha_val)
	afterimage_idx = (afterimage_idx + 1) % 3

func spawn_step_sigil(pos: Vector3, col: Color, scale_mult: float = 1.0) -> void:
	var sm := sigil_rings[sigil_idx]
	var rmat := sigil_mats[sigil_idx]
	sm.global_position = pos
	sm.scale = Vector3(scale_mult, 1.0, scale_mult)
	sm.visible = true
	rmat.albedo_color = Color(col.r, col.g, col.b, 0.88)
	sigil_timers[sigil_idx] = 0.42
	sigil_idx = (sigil_idx + 1) % 4

func trigger_style_fx(style: int, start_pos: Vector3, end_pos: Vector3, visual_root: Node3D, allow_afterimage: bool) -> void:
	play_sfx("vanish")
	if not allow_afterimage:
		clear_afterimages()
	match style:
		0:
			if visual_root: visual_root.visible = false
			spawn_step_sigil(start_pos + Vector3(0, 0.9, 0), Color(0.95, 0.95, 1.0), 1.4)
		1:
			if allow_afterimage and visual_root:
				spawn_afterimage(visual_root.global_transform, Color(0.01, 0.01, 0.02), 0.95)
			spawn_step_sigil(start_pos + Vector3(0, 0.1, 0), Color(0.02, 0.02, 0.04), 1.2)
		2:
			echo_color_idx = 0
			if allow_afterimage and visual_root:
				spawn_afterimage(visual_root.global_transform, Color(0.95, 0.12, 0.18), 0.85)
		3:
			if visual_root:
				visual_root.rotation.x = deg_to_rad(-42.0)
				visual_root.scale = Vector3(0.8, 0.8, 1.45)
			dash_fx_mesh.global_position = start_pos + Vector3(0, 1.0, 0)
			dash_fx_mesh.scale = Vector3(3.2, 0.06, 3.2)
			dash_fx_mat.albedo_color = Color(0.95, 0.95, 1.0, 0.85)
			dash_fx_mesh.visible = true
			dash_fx_timer = 0.22
		4:
			if visual_root:
				visual_root.scale = Vector3(1.85, 0.04, 1.85)
			spawn_step_sigil(start_pos + Vector3(0, 0.05, 0), Color(0.02, 0.0, 0.04), 1.6)
		5:
			dash_fx_mesh.global_position = start_pos.lerp(end_pos, 0.5) + Vector3(0, 1.0, 0)
			dash_fx_mesh.scale = Vector3(0.55, 2.2, 0.55)
			dash_fx_mat.albedo_color = Color(0.95, 0.12, 0.18, 0.9)
			dash_fx_mesh.visible = true
			dash_fx_timer = 0.25

func update_vfx(delta: float, is_dashing: bool, style: int, visual_root: Node3D, allow_afterimage: bool, cam_pos: Vector3 = Vector3.ZERO, player_pos: Vector3 = Vector3.ZERO) -> void:
	_pump_synth_audio(delta)

	# Camera-to-Player Wall Occlusion Dithering
	if cam_pos.length_squared() > 0.01:
		var cam_to_p := cam_pos.distance_to(player_pos)
		for p in destructible_pillars:
			if p["intact"] and is_instance_valid(p.get("upper", null)):
				var b_pos: Vector3 = p["pos"]
				var d_cam := Vector2(cam_pos.x - b_pos.x, cam_pos.z - b_pos.z).length()
				var d_pl := Vector2(player_pos.x - b_pos.x, player_pos.z - b_pos.z).length()
				var blocking := (d_cam < cam_to_p and d_pl < cam_to_p and (d_cam + d_pl) < cam_to_p + 2.8)
				(p["upper"] as Node3D).scale.y = lerpf((p["upper"] as Node3D).scale.y, 0.22 if blocking else 1.0, 14.0 * delta)

	if dash_fx_timer > 0.0:
		dash_fx_timer -= delta
		if dash_fx_timer <= 0.0:
			dash_fx_mesh.visible = false

	for i in range(4):
		if sigil_timers[i] > 0.0:
			sigil_timers[i] = maxf(0.0, sigil_timers[i] - delta)
			sigil_rings[i].scale += Vector3(delta * 4.5, 0.0, delta * 4.5)
			var sc := sigil_mats[i].albedo_color
			sc.a = (sigil_timers[i] / 0.42) * 0.85
			sigil_mats[i].albedo_color = sc
			if sigil_timers[i] <= 0.0:
				sigil_rings[i].visible = false

		if slash_timers[i] > 0.0:
			slash_timers[i] = maxf(0.0, slash_timers[i] - delta)
			slash_arcs[i].scale += Vector3(delta * 5.2, delta * 5.2, delta * 5.2)
			slash_arcs[i].rotate_object_local(Vector3.UP, delta * 14.0)
			if slash_timers[i] <= 0.0:
				slash_arcs[i].visible = false

	for d in debris_pool:
		if d["timer"] > 0.0:
			d["timer"] -= delta
			var mi: MeshInstance3D = d["mesh"]
			var v: Vector3 = d["vel"]
			var rv: Vector3 = d["rot_vel"]
			mi.global_position += v * delta
			mi.rotation += rv * delta
			v.y -= 28.0 * delta
			if mi.global_position.y <= 0.65:
				mi.global_position.y = 0.65
				v = Vector3.ZERO
				rv = Vector3.ZERO
				d["timer"] = 0.0
			d["vel"] = v
			d["rot_vel"] = rv

	if allow_afterimage and is_dashing and visual_root:
		afterimage_timer -= delta
		if afterimage_timer <= 0.0:
			afterimage_timer = 0.04
			if style == 2:
				var cols: Array[Color] = [Color(0.95, 0.12, 0.18), Color(1.0, 0.82, 0.15), Color(0.92, 0.92, 0.96)]
				spawn_afterimage(visual_root.global_transform, cols[echo_color_idx % 3], 0.82)
				echo_color_idx += 1
			elif style == 1:
				spawn_afterimage(visual_root.global_transform, Color(0.01, 0.01, 0.02), 0.9)
			else:
				spawn_afterimage(visual_root.global_transform, Color(0.95, 0.12, 0.18), 0.65)

	for i in range(3):
		if afterimage_alphas[i] > 0.0:
			afterimage_alphas[i] = maxf(0.0, afterimage_alphas[i] - delta * 4.0)
			var c := afterimage_mats[i].albedo_color
			c.a = afterimage_alphas[i]
			afterimage_mats[i].albedo_color = c
			if afterimage_alphas[i] <= 0.0:
				afterimages[i].visible = false
