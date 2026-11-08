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

# --- Dual-Tone Crescent Slash Arcs (Visible in Bright & Dark Regions) ---
var slash_arcs: Array[Node3D] = []
var slash_core_mats: Array[StandardMaterial3D] = []
var slash_timers: Array[float] = [0.0, 0.0, 0.0, 0.0]
var slash_idx: int = 0

# --- Destructible Gothic Pillars, Rubble & Craters ---
var destructible_pillars: Array[Dictionary] = []
var debris_pool: Array[Dictionary] = []
var crater_pool: Array[MeshInstance3D] = []
var crater_idx: int = 0
var stone_mat: StandardMaterial3D = null
var dark_stone_mat: StandardMaterial3D = null

func _ready() -> void:
	_setup_afterimage_pool()
	_setup_slash_arc_pool()
	_setup_destructible_arena()

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
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
	dash_fx_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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

	dark_stone_mat = StandardMaterial3D.new()
	dark_stone_mat.albedo_color = Color(0.12, 0.12, 0.15)
	dark_stone_mat.roughness = 0.95

	var pillar_coords: Array[Vector3] = [
		Vector3(-12, 0, -10), Vector3(12, 0, -10),
		Vector3(-16, 0, -24), Vector3(16, 0, -24),
		Vector3(-8, 0, -32), Vector3(8, 0, -32),
		Vector3(-22, 0, -14), Vector3(22, 0, -14)
	]

	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(2.2, 1.6, 2.2)

	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.85
	shaft_mesh.bottom_radius = 0.95
	shaft_mesh.height = 14.0
	shaft_mesh.radial_segments = 10

	var spire_mesh := CylinderMesh.new()
	spire_mesh.top_radius = 0.05
	spire_mesh.bottom_radius = 1.25
	spire_mesh.height = 4.5
	spire_mesh.radial_segments = 8

	for pos in pillar_coords:
		var p_root := Node3D.new()
		p_root.top_level = true
		add_child(p_root)
		p_root.global_position = pos

		var base_mi := MeshInstance3D.new()
		base_mi.mesh = base_mesh
		base_mi.position = Vector3(0, 0.8, 0)
		base_mi.material_override = dark_stone_mat
		p_root.add_child(base_mi)

		var upper_holder := Node3D.new()
		p_root.add_child(upper_holder)

		var shaft_mi := MeshInstance3D.new()
		shaft_mi.mesh = shaft_mesh
		shaft_mi.position = Vector3(0, 8.6, 0)
		shaft_mi.material_override = stone_mat
		upper_holder.add_child(shaft_mi)

		var spire_mi := MeshInstance3D.new()
		spire_mi.mesh = spire_mesh
		spire_mi.position = Vector3(0, 17.8, 0)
		spire_mi.material_override = dark_stone_mat
		upper_holder.add_child(spire_mi)

		destructible_pillars.append({
			"pos": pos, "upper": upper_holder, "intact": true
		})

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

func check_destruction(impact_pos: Vector3, radius: float, impulse_dir: Vector3, spawn_crater: bool = false) -> void:
	if spawn_crater and impact_pos.y <= 2.2:
		var cm := crater_pool[crater_idx]
		cm.global_position = Vector3(impact_pos.x, 0.54, impact_pos.z)
		cm.rotation.y = randf() * TAU
		cm.visible = true
		crater_idx = (crater_idx + 1) % crater_pool.size()
		_burst_debris(Vector3(impact_pos.x, 1.0, impact_pos.z), Vector3.UP, 6)

	for p in destructible_pillars:
		if p["intact"]:
			var p_pos: Vector3 = p["pos"]
			var flat_d := Vector2(impact_pos.x - p_pos.x, impact_pos.z - p_pos.z).length()
			if flat_d <= radius:
				p["intact"] = false
				(p["upper"] as Node3D).visible = false
				_burst_debris(p_pos + Vector3(0, 4.5, 0), impulse_dir, 12)
				spawn_step_sigil(p_pos + Vector3(0, 2.0, 0), Color(0.95, 0.92, 0.88), 2.4)

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

func update_vfx(delta: float, is_dashing: bool, style: int, visual_root: Node3D, allow_afterimage: bool) -> void:
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
				d["timer"] = 0.0 # Freeze rubble on floor permanently at 0 CPU cost
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
