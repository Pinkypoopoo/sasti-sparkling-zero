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

func _ready() -> void:
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
		0: # DBZ_VANISH_RUSH
			if visual_root: visual_root.visible = false
			spawn_step_sigil(start_pos + Vector3(0, 0.9, 0), Color(0.95, 0.95, 1.0), 1.4)
		1: # BLEACH_SONIDO
			if allow_afterimage and visual_root:
				spawn_afterimage(visual_root.global_transform, Color(0.01, 0.01, 0.02), 0.95)
			spawn_step_sigil(start_pos + Vector3(0, 0.1, 0), Color(0.02, 0.02, 0.04), 1.2)
		2: # SANDEVISTAN_ECHO
			echo_color_idx = 0
			if allow_afterimage and visual_root:
				spawn_afterimage(visual_root.global_transform, Color(0.95, 0.12, 0.18), 0.85)
		3: # MACH_CONE_BURST
			if visual_root:
				visual_root.rotation.x = deg_to_rad(-42.0)
				visual_root.scale = Vector3(0.8, 0.8, 1.45)
			dash_fx_mesh.global_position = start_pos + Vector3(0, 1.0, 0)
			dash_fx_mesh.scale = Vector3(3.2, 0.06, 3.2)
			dash_fx_mat.albedo_color = Color(0.95, 0.95, 1.0, 0.85)
			dash_fx_mesh.visible = true
			dash_fx_timer = 0.22
		4: # SHADOW_ABYSS_SINK
			if visual_root:
				visual_root.scale = Vector3(1.85, 0.04, 1.85)
			spawn_step_sigil(start_pos + Vector3(0, 0.05, 0), Color(0.02, 0.0, 0.04), 1.6)
		5: # TOUKI_HORIZON_FLASH
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
