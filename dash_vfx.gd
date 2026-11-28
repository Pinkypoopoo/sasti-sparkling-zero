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

# One hollow torus, flattened on Y: a solid alpha-hashed disc z-fights and
# stipples against the floor and the raised water plane as it expands.
const SIGIL_FLATTEN: float = 0.08
const SIGIL_FLOOR_CLEARANCE: float = 0.18
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
# Quality tiers shrink this: simultaneous rubble chunks are fill-rate, not logic.
var debris_cap: int = 28
var crater_pool: Array[MeshInstance3D] = []
var crater_idx: int = 0
var stone_mat: StandardMaterial3D = null
var dark_stone_mat: StandardMaterial3D = null
var flora_mat: ShaderMaterial = null

# --- V5 stylized anime water floor + 2-tone cel smoke ----------------------
var water_mesh: MeshInstance3D = null
var water_mat: ShaderMaterial = null
var water_enabled: bool = false
var water_boss_pos: Vector3 = Vector3(9999.0, 0.0, 9999.0)
var _water_height_applied: float = -1.0
var _water_ripple_applied: float = -1.0
var _water_player_applied: Vector3 = Vector3(1e9, 1e9, 1e9)
var _water_boss_applied: Vector3 = Vector3(1e9, 1e9, 1e9)
var cel_smoke_pool: Array[Dictionary] = []
var cel_smoke_idx: int = 0

# --- Screen-space 2D impact slash (CanvasLayer) ----------------------------
# A 0.16 s diagonal ink slash + expanding singularity ring. Drawn with plain 2D
# canvas vectors inside a CanvasLayer: no second viewport, no full-screen
# post-process shader, no 3D fill-rate. Sits above both the 3D world and the HUD.
const SCREEN_SLASH_TIME: float = 0.16
var slash_layer: CanvasLayer = null
var screen_slash: ScreenSlash = null
var slash_enabled: bool = true
var slash_intensity: float = 1.0
var smoke_enabled: bool = true
var smoke_density: float = 1.0
var low_tier: bool = false
# Cap on simultaneous cel-smoke puffs; set from the active 4-tier profile.
var fx_cap: int = 14

class ScreenSlash extends Control:
	var timer: float = 0.0
	var total: float = 0.16
	var angle: float = -0.35
	var strength: float = 1.0
	var centre: Vector2 = Vector2.ZERO
	var reduced: bool = false
	var enabled: bool = true

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		visible = false

	func fire(at: Vector2, tilt: float, power: float) -> void:
		if not enabled:
			return
		centre = at
		angle = tilt
		strength = clampf(power, 0.4, 1.6)
		timer = total
		visible = true
		queue_redraw()

	func _process(delta: float) -> void:
		if timer <= 0.0:
			return
		timer = maxf(0.0, timer - delta)
		queue_redraw()
		if timer <= 0.0:
			visible = false

	func _draw() -> void:
		if timer <= 0.0:
			return
		var vp: Vector2 = get_viewport_rect().size
		var age: float = clampf(1.0 - timer / maxf(0.01, total), 0.0, 1.0)
		var fade: float = 1.0 - age
		var dir := Vector2(cos(angle), sin(angle))
		var reach: float = vp.length() * 1.2
		var a := centre - dir * reach
		var b := centre + dir * reach
		# Sharp diagonal ink slash: two soft under-strokes and a hard core line.
		if age < 0.35:
			draw_line(a, b, Color(0.70, 0.62, 1.0, 0.45 * fade * strength), 22.0 * strength)
			draw_line(a, b, Color(0.92, 0.90, 1.0, 0.65 * fade * strength), 9.0 * strength)
		draw_line(a, b, Color(1, 1, 1, fade * strength), 3.0 * strength)
		if not reduced:
			# Expanding singularity ring, double-walled.
			var ring_r: float = lerpf(10.0, 200.0, minf(1.0, age * 1.15))
			draw_arc(centre, ring_r, 0.0, TAU, 48, Color(1, 1, 1, fade * 0.85), 2.5 * strength)
			draw_arc(centre, ring_r * 0.74, 0.0, TAU, 40, Color(0.72, 0.60, 1.0, fade * 0.6), 1.5 * strength)
			# 4-point star flare on the hit point.
			var perp := Vector2(-dir.y, dir.x)
			var flare: float = lerpf(110.0, 14.0, age) * strength
			for d in [dir, -dir, perp, -perp]:
				draw_line(centre - d * flare, centre + d * flare, Color(1, 1, 1, fade * 0.9), 2.0)
		draw_circle(centre, maxf(2.0, 9.0 * fade * strength), Color(1, 1, 1, fade))

# --- Minecraft-Style Custom Arena Blocks & MultiMesh Flora ---
var custom_block_nodes: Array[Dictionary] = []

# --- Procedural Synth SFX Engine (Zero External Audio Files Required) ---
# V6 Task 5: every cue is pre-baked once into a mono frame buffer with a fixed
# seed, and the render-tick pump streams those frames into the same
# AudioStreamGenerator. One player, no sample files, no per-shot allocation.
const SFX_MIX_RATE: float = 22050.0
const SFX_HISTORY_MAX: int = 8
const SFX_BOSS_AWAKEN: String = "boss_awaken"
const SFX_UNBLOCKABLE_WARN: String = "unblockable_warn"
const SFX_STAGGER_BREAK: String = "stagger_break"
const SFX_STAGGER_FINISHER: String = "stagger_finisher"
const SFX_GATE_TRAVEL: String = "gate_travel"
const SFX_GATE_SEALED: String = "gate_sealed"
const SFX_WALL_KICK: String = "wall_kick"
const SFX_PARRY: String = "parry"

# cue -> [duration_s, [[start_hz, end_hz, gain, noise_mix, partial], ...]]
# V8 Task 1B retune. The bank is now steel, stone and sub-bass instead of arcade
# boings and laser sweeps: transients carry a 0.35-0.65 noise mix over tight
# inharmonic partials (2.76 / 3.41 read as a struck plate, not a sine), decays
# are 0.06-0.16 s, and the heavy cues sit on 42-110 Hz fundamentals. Still one
# table, one baker, one generator.
const SYNTH_CUES: Dictionary = {
	"slash": [0.10, [[1400.0, 620.0, 0.30, 0.55, 2.76], [2600.0, 1400.0, 0.14, 0.45, 3.41]]],
	"hit": [0.12, [[120.0, 58.0, 0.42, 0.40, 2.2], [980.0, 520.0, 0.12, 0.50, 3.41]]],
	"clash": [0.16, [[2760.0, 2410.0, 0.32, 0.55, 2.76], [3410.0, 3180.0, 0.20, 0.45, 3.41], [740.0, 520.0, 0.26, 0.35, 2.05]]],
	SFX_PARRY: [0.13, [[2210.0, 1980.0, 0.30, 0.35, 2.76], [2980.0, 2760.0, 0.18, 0.50, 3.41], [660.0, 640.0, 0.16, 0.35, 2.0]]],
	"vanish": [0.14, [[900.0, 260.0, 0.22, 0.55, 2.76], [1900.0, 900.0, 0.10, 0.45, 3.41]]],
	"shatter": [0.24, [[150.0, 44.0, 0.42, 0.75, 2.2], [1900.0, 760.0, 0.16, 0.60, 3.41]]],
	"build": [0.06, [[320.0, 480.0, 0.30, 0.30, 2.0]]],
	SFX_BOSS_AWAKEN: [0.55, [[42.0, 30.0, 0.62, 0.12, 2.0], [1240.0, 1520.0, 0.14, 0.35, 3.41], [2180.0, 2610.0, 0.08, 0.40, 2.76]]],
	SFX_UNBLOCKABLE_WARN: [0.32, [[196.0, 188.0, 0.32, 0.25, 2.76], [233.0, 222.0, 0.26, 0.35, 3.41], [392.0, 370.0, 0.10, 0.40, 2.76]]],
	SFX_STAGGER_BREAK: [0.16, [[240.0, 74.0, 0.40, 0.65, 2.2], [1980.0, 1180.0, 0.20, 0.50, 2.76], [3020.0, 2400.0, 0.10, 0.45, 3.41]]],
	SFX_STAGGER_FINISHER: [0.30, [[62.0, 34.0, 0.58, 0.30, 2.0], [74.0, 40.0, 0.42, 0.45, 2.2], [640.0, 180.0, 0.18, 0.55, 3.41]]],
	SFX_GATE_TRAVEL: [0.60, [[110.0, 132.0, 0.34, 0.08, 2.0], [165.0, 198.0, 0.20, 0.12, 2.76], [330.0, 396.0, 0.10, 0.10, 3.41]]],
	SFX_GATE_SEALED: [0.22, [[55.0, 36.0, 0.44, 0.50, 2.0], [880.0, 640.0, 0.10, 0.45, 2.76]]],
	SFX_WALL_KICK: [0.12, [[180.0, 92.0, 0.40, 0.65, 2.3], [1760.0, 1320.0, 0.16, 0.50, 3.41]]],
}

var sfx_player: AudioStreamPlayer = null
var sfx_playback: AudioStreamGeneratorPlayback = null
# Baking happens on first use, even headless: the cue buffers are plain data, so
# a device-less run still proves every cue is valid and non-silent.
var synth_frames: Dictionary = {}
var sfx_active_frames: PackedVector2Array = PackedVector2Array()
var sfx_cursor: int = 0
var last_sfx_cue: String = ""
var sfx_play_count: int = 0
var sfx_history: Array[String] = []
var sfx_enabled_flag: bool = true
var sfx_volume_linear: float = 0.75

# Hard cap on player-placed blocks: each one allocates fresh meshes, so an
# unbounded build session could tank a phone.
const MAX_USER_BLOCKS: int = 120

# =============================================================================
#  V6 TASK 2A - CURATED 3-REGION ARENA LAYOUTS
#  Deterministic per-region prop tables, built through spawn_arena_block() so
#  every curated piece stays solid, destructible and painted by stone_mat (the
#  region palette). Spec order is [kind, x, y, z, rot_y_deg]; positions are
#  snapped to the 2 m grid like Tab 6 blocks. Plain data on purpose, so the gate
#  can assert an exact prop count per region.
# =============================================================================
const CURATED_REGION_LAYOUTS: Dictionary = {
	# 0 INK_CATHEDRAL - symmetrical nave: wall-runnable pillars, ruined arches.
	0: [
		["GOTHIC_PILLAR", -12.0, 0.0, -10.0, 0.0],
		["GOTHIC_PILLAR", 12.0, 0.0, -10.0, 0.0],
		["GOTHIC_PILLAR", -22.0, 0.0, -14.0, 0.0],
		["GOTHIC_PILLAR", 22.0, 0.0, -14.0, 0.0],
		["GOTHIC_PILLAR", -16.0, 0.0, -24.0, 0.0],
		["GOTHIC_PILLAR", 16.0, 0.0, -24.0, 0.0],
		["GOTHIC_PILLAR", -8.0, 0.0, -32.0, 0.0],
		["GOTHIC_PILLAR", 8.0, 0.0, -32.0, 0.0],
		["RUINED_ARCH", -32.0, 0.0, -40.0, 90.0],
		["RUINED_ARCH", 32.0, 0.0, -40.0, 90.0],
		["RUINED_ARCH", -32.0, 0.0, 6.0, 90.0],
		["RUINED_ARCH", 32.0, 0.0, 6.0, 90.0],
	],
	# 1 BLAME_MEGASTRUC - staggered monoliths + raised ledges for wall-run kick-offs.
	1: [
		["BLAME_MONOLITH", -24.0, 0.0, -16.0, 0.0],
		["BLAME_MONOLITH", -8.0, 0.0, -32.0, 0.0],
		["BLAME_MONOLITH", 8.0, 4.0, -16.0, 0.0],
		["BLAME_MONOLITH", 24.0, 0.0, -32.0, 0.0],
		["RUINED_ARCH", 0.0, 8.0, -46.0, 0.0],
		["ANIME_FLORA_PATCH", -30.0, 0.0, -6.0, 0.0],
		["ANIME_FLORA_PATCH", 30.0, 0.0, -6.0, 0.0],
	],
	# 2 GOTHIC_ECLIPSE - obsidian ruined-arch sanctum built for the flooded floor.
	2: [
		["RUINED_ARCH", -18.0, 0.0, -22.0, 0.0],
		["RUINED_ARCH", 18.0, 0.0, -22.0, 0.0],
		["RUINED_ARCH", 0.0, 0.0, -6.0, 90.0],
		["GOTHIC_PILLAR", -26.0, 0.0, -4.0, 0.0],
		["GOTHIC_PILLAR", 26.0, 0.0, -4.0, 0.0],
		["ANIME_FLORA_PATCH", -12.0, 0.0, 10.0, 0.0],
		["ANIME_FLORA_PATCH", 12.0, 0.0, 10.0, 0.0],
	],
}

# Curated props live apart from Tab 6's custom_block_nodes: a region switch must
# never eat the player's build, and a saved build must never eat the region.
var curated_region_props: Array[Dictionary] = []
var curated_region_idx: int = 0

# =============================================================================
#  V6 TASK 2B - PHYSICAL SHORTCUT GATES
#  One low-poly arch + emissive beacon per gate, spawned by the same call that
#  builds the region's curated props, so a switch can never strand a gate from
#  the layout that just left. Specs are [target_region, flag, x, z, rot_y_deg];
#  an empty flag is a permanent return gate. Deliberately body-less: a visual
#  marker needs no StaticBody3D, so a region switch cannot leak a Jolt RID.
# =============================================================================
const SHORTCUT_GATE_LAYOUTS: Dictionary = {
	# 0 INK_CATHEDRAL hub: both edge gates are sealed until their rival falls.
	0: [
		[1, "shortcut_blame_unlocked", -36.0, -2.0, 90.0],
		[2, "shortcut_eclipse_unlocked", 36.0, -2.0, 90.0],
	],
	# 1 BLAME_MEGASTRUC: the way back is always open, the eclipse shortcut is not.
	1: [
		[0, "", 0.0, 14.0, 0.0],
		[2, "shortcut_eclipse_unlocked", -36.0, 2.0, 90.0],
	],
	# 2 GOTHIC_ECLIPSE: only the return gate.
	2: [
		[0, "", 0.0, 14.0, 0.0],
	],
}
const SHORTCUT_GATE_LOCKED_COLOR: Color = Color(0.42, 0.05, 0.09)
const SHORTCUT_GATE_OPEN_COLOR: Color = Color(1.0, 0.82, 0.24)

var shortcut_gates: Array[Dictionary] = []

func _ready() -> void:
	_bake_synth_cue_bank()
	_setup_synth_audio()
	_setup_afterimage_pool()
	_setup_slash_arc_pool()
	_setup_cel_smoke_pool()
	_setup_screen_slash()
	_setup_water_floor()
	_setup_destructible_arena()

func _setup_synth_audio() -> void:
	if DisplayServer.get_name() == "headless": return
	sfx_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SFX_MIX_RATE
	gen.buffer_length = 0.12
	sfx_player.stream = gen
	sfx_player.volume_db = linear_to_db(maxf(0.001, sfx_volume_linear))
	add_child(sfx_player)
	sfx_player.play()
	sfx_playback = sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback

func play_sfx(kind: String) -> void:
	# Muted in Tab 8: no sound AND no bookkeeping, so a test can prove silence.
	if not sfx_enabled_flag:
		return
	if not SYNTH_CUES.has(kind):
		return
	last_sfx_cue = kind
	sfx_play_count += 1
	if sfx_history.size() >= SFX_HISTORY_MAX:
		sfx_history.remove_at(0)
	sfx_history.append(kind)
	if not sfx_playback:
		return  # headless / no audio device: the cue is still recorded
	if sfx_player:
		sfx_player.volume_db = synth_volume_db()
	sfx_active_frames = _synth_frames_for(kind)
	sfx_cursor = 0

func _process(delta: float) -> void:
	# Audio is pumped on the render tick, NOT at the end of _physics_process:
	# hitstop early-returns the physics tick, which used to starve the generator
	# and underrun the synth exactly during the impact frames.
	_pump_synth_audio(delta)

func _pump_synth_audio(_delta: float) -> void:
	# Pumped on the render tick (not physics): hitstop early-returns the physics
	# tick and used to starve the generator exactly during impact frames.
	if not sfx_playback or sfx_active_frames.is_empty():
		return
	var room: int = mini(sfx_playback.get_frames_available(), 512)
	if room <= 0:
		return
	var take: int = mini(room, sfx_active_frames.size() - sfx_cursor)
	if take <= 0:
		sfx_cursor = 0
		sfx_active_frames = PackedVector2Array()
		return
	var chunk := PackedVector2Array()
	chunk.resize(take)
	for i in range(take):
		chunk[i] = sfx_active_frames[sfx_cursor + i]
	sfx_playback.push_buffer(chunk)
	sfx_cursor += take
	if sfx_cursor >= sfx_active_frames.size():
		sfx_cursor = 0
		sfx_active_frames = PackedVector2Array()

func set_sfx_tuning(enabled: bool, linear_volume: float) -> void:
	# The player pushes Tab 8 in once per physics tick; the synth never reaches
	# back into combat_data, so there is no cyclic node lookup.
	sfx_enabled_flag = enabled
	sfx_volume_linear = clampf(linear_volume, 0.0, 1.0)
	if sfx_player:
		sfx_player.volume_db = synth_volume_db()

# One dB conversion for both the setter and every shot, clamped so a 0.0 slider
# is silence rather than a -inf volume.
func synth_volume_db() -> float:
	return linear_to_db(maxf(0.001, clampf(sfx_volume_linear, 0.0, 1.0)))

# Bake the whole bank at load: ~3.2 s of mono frames is ~560 KB, far cheaper than
# hitching the frame a boss awakens on.
func _bake_synth_cue_bank() -> void:
	for cue in SYNTH_CUES.keys():
		if not synth_frames.has(cue):
			_bake_synth_cue(str(cue))

func has_synth_cue(cue: String) -> bool:
	return SYNTH_CUES.has(cue)

func synth_frame_count(cue: String) -> int:
	return _synth_frames_for(cue).size()

func synth_peak(cue: String) -> float:
	var peak: float = 0.0
	for fr in _synth_frames_for(cue):
		peak = maxf(peak, absf(fr.x))
	return peak

func _synth_frames_for(cue: String) -> PackedVector2Array:
	if synth_frames.has(cue):
		var cached: PackedVector2Array = synth_frames[cue]
		return cached
	return _bake_synth_cue(cue)

# Bakes one cue at 22.05 kHz. Deterministic (seeded noise) so a headless run and
# a phone hear the same buffer, and so a test can compare peaks across runs.
func _bake_synth_cue(cue: String) -> PackedVector2Array:
	var spec: Array = SYNTH_CUES.get(cue, [])
	if spec.size() < 2:
		return PackedVector2Array()
	var dur: float = maxf(0.02, float(spec[0]))
	var layers: Array = spec[1]
	var frames := PackedVector2Array()
	frames.resize(int(round(dur * SFX_MIX_RATE)))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cue)
	var count: int = frames.size()
	for i in range(count):
		var t: float = float(i) / SFX_MIX_RATE
		var prog: float = clampf(t / dur, 0.0, 1.0)
		# 2 ms attack + exponential decay: percussive, never a click.
		var env: float = minf(1.0, t / 0.002) * pow(1.0 - prog, 1.7)
		var samp: float = 0.0
		for layer in layers:
			var f0: float = float(layer[0])
			var f1: float = float(layer[1])
			var gain: float = float(layer[2])
			var noise: float = float(layer[3])
			var partial: float = float(layer[4])
			# Integrate the sweep so the phase never jumps mid-cue.
			var phase: float = f0 * t + (f1 - f0) * t * prog * 0.5
			var tone: float = sin(phase * TAU) + 0.35 * sin(phase * TAU * partial)
			samp += lerpf(tone, rng.randf_range(-1.0, 1.0), noise) * gain
		samp = clampf(samp * env, -1.0, 1.0)
		frames[i] = Vector2(samp, samp)
	synth_frames[cue] = frames
	return frames

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

	# V8 Task 1A: hollow flattened torus. A solid disc with ALPHA_HASH stippled and
	# flickered against the floor, and it could not read as a ring at all.
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.15
	ring_mesh.outer_radius = 1.38
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 8
	for i in range(4):
		var sm := MeshInstance3D.new()
		sm.mesh = ring_mesh
		sm.top_level = true
		sm.visible = false
		sm.scale = Vector3(1.0, SIGIL_FLATTEN, 1.0)
		var rmat := StandardMaterial3D.new()
		rmat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
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

	# V6 Task 2A: the INK_CATHEDRAL nave moved into CURATED_REGION_LAYOUTS, so boot
	# and the region cycler build the arena through one code path.
	load_curated_region(0)

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

# =============================================================================
#  STYLIZED ANIME WATER FLOOR  (video_3.mp4 — @ITSJUAN.NDS, 00:00–00:13)
#  One subdivided plane, one unshaded 3-band cel shader, two uniforms for the
#  contact ripples. No reflection pass, no screen-space work, zero extra draw
#  calls for the ripples — on a 732G that is the difference between 45 and 30 fps.
# =============================================================================
const WATER_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float wave_height : hint_range(0.0, 0.65) = 0.12;
uniform vec3 player_pos = vec3(0.0);
uniform vec3 boss_pos = vec3(9999.0);
uniform float ripple_str : hint_range(0.0, 2.0) = 1.0;
uniform vec4 trough_col : source_color = vec4(0.03, 0.04, 0.07, 1.0);
uniform vec4 mid_col : source_color = vec4(0.08, 0.13, 0.19, 1.0);
uniform vec4 crest_col : source_color = vec4(0.58, 0.66, 0.72, 1.0);

varying float v_h;
varying vec3 v_wpos;

float contact_ring(vec2 w, vec2 c, float speed, float reach) {
	float d = length(w - c);
	float band = sin(d * 4.6 - TIME * speed * 4.2) * 0.5 + 0.5;
	return step(0.84, band) * smoothstep(reach, 0.0, d);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = sin(w.x * 0.32 + TIME * 1.35) * 0.62
	        + sin(w.z * 0.24 - TIME * 0.95) * 0.38
	        + sin((w.x + w.z) * 0.11 + TIME * 0.55) * 0.22;
	// Clamped troughs: an unclamped sine pulled vertices under the floor at the
	// wave's low points, which is what made the water clip and z-fight.
	VERTEX.y += max(h * wave_height, -0.10);
	v_h = h;
	v_wpos = w;
}

void fragment() {
	float t = clamp(v_h * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = trough_col.rgb;
	if (t >= 0.54) { col = mid_col.rgb; }
	if (t >= 0.82) { col = crest_col.rgb; }
	col += crest_col.rgb * contact_ring(v_wpos.xz, player_pos.xz, 1.0, 2.2) * 0.55 * ripple_str;
	col += crest_col.rgb * contact_ring(v_wpos.xz, boss_pos.xz, 0.7, 2.8) * 0.40 * ripple_str;
	ALBEDO = col;
}
"""

func _setup_water_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(240.0, 240.0)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	water_mesh = MeshInstance3D.new()
	water_mesh.name = "AnimeWaterFloor"
	water_mesh.mesh = plane
	water_mesh.top_level = true
	water_mesh.position = Vector3(0.0, 0.14, 0.0)
	water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_mat = ShaderMaterial.new()
	water_mat.shader = Shader.new()
	water_mat.shader.code = WATER_SHADER
	water_mesh.material_override = water_mat
	water_mesh.visible = false
	add_child(water_mesh)

# Called once per physics tick by the player, so it must be change-driven: a
# blind set_shader_parameter every tick is a RenderingServer dirty-mark per frame.
func set_water_enabled(on: bool, wave_height: float = 0.12, ripple_strength: float = 1.0) -> void:
	if not water_mesh:
		return
	if water_enabled != on:
		water_enabled = on
		water_mesh.visible = on
	var h := clampf(wave_height, 0.0, 0.65)
	if water_mat and not is_equal_approx(h, _water_height_applied):
		_water_height_applied = h
		water_mat.set_shader_parameter("wave_height", h)
	var r := clampf(ripple_strength, 0.0, 2.0)
	if water_mat and not is_equal_approx(r, _water_ripple_applied):
		_water_ripple_applied = r
		water_mat.set_shader_parameter("ripple_str", r)

# Change-driven, like set_water_enabled(): a blind set_shader_parameter every tick
# is a RenderingServer dirty-mark per frame, and these two only move when a
# fighter actually walks or lands.
func _update_water_floor(player_pos: Vector3) -> void:
	if not water_enabled or not water_mat:
		return
	if player_pos.distance_squared_to(_water_player_applied) > 0.0001:
		_water_player_applied = player_pos
		water_mat.set_shader_parameter("player_pos", player_pos)
	if water_boss_pos.distance_squared_to(_water_boss_applied) > 0.0001:
		_water_boss_applied = water_boss_pos
		water_mat.set_shader_parameter("boss_pos", water_boss_pos)

# =============================================================================
#  2-TONE CEL SMOKE  (video_4.mp4 — @NOBI_2D, 00:03–00:05)
#  A camera-facing quad with a hard violet/white boundary: the shadow band is a
#  step, not a gradient, which is the whole look. Pooled, so it allocates nothing.
# =============================================================================
const CEL_SMOKE_SHADER: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 lit_col : source_color = vec4(0.949, 0.941, 1.0, 1.0);
uniform vec4 shadow_col : source_color = vec4(0.431, 0.353, 0.902, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 0.95;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p) + 0.09 * sin(UV.x * 11.0 + UV.y * 8.0) + 0.05 * sin(UV.y * 17.0);
	float body = 1.0 - smoothstep(0.72, 0.98, r);
	if (body <= 0.01) { discard; }
	// Hard 2-band split, no interpolation between them.
	float lit = step(0.0, dot(p, normalize(vec2(-0.62, 0.78))) + 0.12);
	ALBEDO = mix(shadow_col.rgb, lit_col.rgb, lit);
	ALPHA = body * alpha;
}
"""

func _setup_cel_smoke_pool() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	for i in range(14):
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.top_level = true
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new()
		mat.shader = Shader.new()
		mat.shader.code = CEL_SMOKE_SHADER
		mi.material_override = mat
		add_child(mi)
		cel_smoke_pool.append({"mi": mi, "mat": mat, "vel": Vector3.ZERO, "timer": 0.0, "life": 0.8})

func _setup_screen_slash() -> void:
	slash_layer = CanvasLayer.new()
	slash_layer.name = "ImpactSlashLayer"
	slash_layer.layer = 20
	add_child(slash_layer)
	screen_slash = ScreenSlash.new()
	screen_slash.name = "ScreenSlash"
	screen_slash.total = SCREEN_SLASH_TIME
	screen_slash.enabled = slash_enabled
	slash_layer.add_child(screen_slash)

# Project the 3D hit point to the screen and fire the CanvasLayer effect. With no
# camera (headless tests) it still fires at screen centre rather than going silent.
func trigger_screen_slash(world_pos: Vector3, angle_deg: float = -35.0, power: float = 1.0) -> void:
	if not slash_enabled or screen_slash == null:
		return
	var at: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var cam := get_viewport().get_camera_3d()
	if cam != null and not cam.is_position_behind(world_pos):
		at = cam.unproject_position(world_pos)
	screen_slash.enabled = slash_enabled
	screen_slash.reduced = low_tier
	screen_slash.total = SCREEN_SLASH_TIME
	screen_slash.fire(at, deg_to_rad(angle_deg + randf_range(-7.0, 7.0)), power * slash_intensity)

# Everything the 4-tier profile + tab 8 own about VFX, in one setter.
func set_fx_budget(cap: int, low: bool, slash_on: bool, slash_power: float, smoke_on: bool, density: float) -> void:
	fx_cap = clampi(cap, 0, maxi(1, cel_smoke_pool.size()))
	low_tier = low
	slash_enabled = slash_on
	slash_intensity = clampf(slash_power, 0.0, 2.0)
	smoke_enabled = smoke_on
	smoke_density = clampf(density, 0.0, 2.0)
	if screen_slash:
		screen_slash.enabled = slash_on
		screen_slash.reduced = low

func spawn_cel_smoke(pos: Vector3, count: int = 5, dir: Vector3 = Vector3.UP, scale_mult: float = 1.0) -> void:
	if not smoke_enabled or cel_smoke_pool.is_empty() or fx_cap <= 0:
		return
	var active := 0
	for p in cel_smoke_pool:
		if float(p["timer"]) > 0.0:
			active += 1
	var room: int = clampi(fx_cap - active, 0, cel_smoke_pool.size())
	if room <= 0:
		return
	var want: int = clampi(int(round(float(count) * smoke_density)), 1, room)
	var base_dir := dir.normalized() if dir.length_squared() > 0.01 else Vector3.UP
	for i in range(want):
		if cel_smoke_pool.is_empty():
			return
		var p: Dictionary = cel_smoke_pool[cel_smoke_idx]
		cel_smoke_idx = (cel_smoke_idx + 1) % cel_smoke_pool.size()
		var mi: MeshInstance3D = p["mi"]
		var mat: ShaderMaterial = p["mat"]
		var puff := base_dir * 4.0 + Vector3(randf_range(-1.0, 1.0), randf_range(0.1, 0.9), randf_range(-1.0, 1.0)) * 2.4
		p["vel"] = puff.normalized() * randf_range(2.0, 5.2)
		p["life"] = randf_range(0.55, 0.95)
		p["timer"] = float(p["life"])
		mi.global_position = pos + Vector3(randf_range(-0.5, 0.5), randf_range(0.0, 0.6), randf_range(-0.5, 0.5))
		mi.scale = Vector3.ONE * scale_mult * randf_range(0.7, 1.35)
		mi.rotation.z = randf() * TAU
		mat.set_shader_parameter("alpha", 0.95)
		mi.visible = true

func _update_cel_smoke(delta: float) -> void:
	for p in cel_smoke_pool:
		if float(p["timer"]) <= 0.0:
			continue
		p["timer"] = maxf(0.0, float(p["timer"]) - delta)
		var mi: MeshInstance3D = p["mi"]
		var v: Vector3 = p["vel"]
		mi.global_position += v * delta
		v.y += 1.4 * delta
		v.x = lerpf(v.x, 0.0, 2.4 * delta)
		v.z = lerpf(v.z, 0.0, 2.4 * delta)
		p["vel"] = v
		mi.scale += Vector3.ONE * (delta * 1.5)
		var k: float = float(p["timer"]) / maxf(0.01, float(p["life"]))
		(p["mat"] as ShaderMaterial).set_shader_parameter("alpha", clampf(k, 0.0, 1.0) * 0.95)
		if float(p["timer"]) <= 0.0:
			mi.visible = false

# --- V6 Task 2A: curated region arena load / clear ---------------------------
# Builds one region's curated arena and returns the prop count, so callers (and
# the gate) can assert the layout actually landed. Curated entries are flagged
# and never recorded as user blocks.
func load_curated_region(region_idx: int) -> int:
	clear_curated_region()
	curated_region_idx = region_idx
	for spec in CURATED_REGION_LAYOUTS.get(region_idx, []):
		var before: int = destructible_pillars.size()
		var pos := Vector3(float(spec[1]), float(spec[2]), float(spec[3]))
		spawn_arena_block(str(spec[0]), pos, float(spec[4]), false)
		if destructible_pillars.size() > before:
			destructible_pillars[before]["curated"] = true
			curated_region_props.append(destructible_pillars[before])
	_spawn_shortcut_gates(region_idx)
	return curated_region_props.size()

func curated_prop_count() -> int:
	return curated_region_props.size()

# Detach + free() (not queue_free): a deferred free would leave the outgoing
# region's StaticBody3D RIDs alive at headless exit, which the gate reads as a leak.
func clear_curated_region() -> void:
	clear_shortcut_gates()
	for i in range(destructible_pillars.size() - 1, -1, -1):
		if not bool(destructible_pillars[i].get("curated", false)):
			continue
		var root: Node = destructible_pillars[i].get("root", null)
		if is_instance_valid(root) and not root.is_queued_for_deletion():
			if root.get_parent() == self:
				remove_child(root)
			root.free()
		destructible_pillars.remove_at(i)
	curated_region_props.clear()

# --- V6 Task 2B: physical shortcut gates -------------------------------------
func _spawn_shortcut_gates(region_idx: int) -> void:
	for spec in SHORTCUT_GATE_LAYOUTS.get(region_idx, []):
		var flag := str(spec[1])
		var root := Node3D.new()
		root.name = "ShortcutGate"
		root.top_level = true
		add_child(root)
		root.global_position = Vector3(float(spec[2]), 0.0, float(spec[3]))
		root.rotation_degrees.y = float(spec[4])
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color(0.09, 0.09, 0.11)
		stone.roughness = 0.9
		for side in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var pm := BoxMesh.new(); pm.size = Vector3(0.55, 5.6, 0.55)
			post.mesh = pm; post.position = Vector3(side * 1.9, 2.8, 0.0); post.material_override = stone
			root.add_child(post)
		var lintel := MeshInstance3D.new()
		var lm := BoxMesh.new(); lm.size = Vector3(4.4, 0.6, 0.7)
		lintel.mesh = lm; lintel.position = Vector3(0.0, 5.6, 0.0); lintel.material_override = stone
		root.add_child(lintel)
		# Unshaded slab: dim crimson sealed, bright gold open, no post-processing.
		var beacon_mat := StandardMaterial3D.new()
		beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beacon_mat.albedo_color = SHORTCUT_GATE_LOCKED_COLOR
		var beacon := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(3.2, 1.6, 0.18)
		beacon.mesh = bm; beacon.position = Vector3(0.0, 3.2, 0.0); beacon.material_override = beacon_mat
		root.add_child(beacon)
		shortcut_gates.append({
			"target_region": int(spec[0]),
			"required_flag": flag,
			"position": root.global_position,
			"root": root,
			"beacon_mat": beacon_mat,
			"locked": true,
		})
	refresh_shortcut_gate_visuals(false, {})

# Called every physics tick by the player (a colour compare per gate) and
# directly by the story/KO path. Returns how many gates currently read as open.
func refresh_shortcut_gate_visuals(unlock_all: bool, flags: Dictionary) -> int:
	var open_count := 0
	for g in shortcut_gates:
		var flag := str(g.get("required_flag", ""))
		var open: bool = flag.is_empty() or unlock_all or bool(flags.get(flag, false))
		g["locked"] = not open
		if open:
			open_count += 1
		var mat = g.get("beacon_mat", null)
		if mat is StandardMaterial3D:
			var want: Color = SHORTCUT_GATE_OPEN_COLOR if open else SHORTCUT_GATE_LOCKED_COLOR
			if not (mat as StandardMaterial3D).albedo_color.is_equal_approx(want):
				(mat as StandardMaterial3D).albedo_color = want
	return open_count

# Same detach + free() rule as the curated props: a deferred free would leave the
# outgoing gate alive at headless exit (and the gate reads that as an RID leak).
func clear_shortcut_gates() -> void:
	for i in range(shortcut_gates.size() - 1, -1, -1):
		var root: Node = shortcut_gates[i].get("root", null)
		if is_instance_valid(root) and not root.is_queued_for_deletion():
			if root.get_parent() == self:
				remove_child(root)
			root.free()
	shortcut_gates.clear()

# --- Minecraft-Style Modular Block & MultiMesh Flora Spawner ---
func spawn_arena_block(kind: String, pos: Vector3, rot_y_deg: float = 0.0, record_user: bool = true) -> void:
	if record_user and custom_block_nodes.size() >= MAX_USER_BLOCKS:
		return
	var snap_pos := Vector3(snappedf(pos.x, 2.0), maxf(0.0, snappedf(pos.y, 2.0)), snappedf(pos.z, 2.0))
	var b_root := Node3D.new()
	b_root.top_level = true
	add_child(b_root)
	b_root.global_position = snap_pos
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

	# Solid geometry: without a StaticBody the parkour wall-run can never see a
	# pillar (is_on_wall() stays false against a mesh with no collision).
	var solid := StaticBody3D.new()
	solid.name = "SolidBlock"
	var solid_shape := CollisionShape3D.new()
	var has_collision := true
	match kind:
		"GOTHIC_PILLAR":
			var bs := BoxShape3D.new(); bs.size = Vector3(2.2, 16.4, 2.2)
			solid_shape.shape = bs; solid_shape.position = Vector3(0, 8.2, 0)
		"BLAME_MONOLITH":
			var bm := BoxShape3D.new(); bm.size = Vector3(4.0, 22.0, 4.0)
			solid_shape.shape = bm; solid_shape.position = Vector3(0, 11.0, 0)
		"RUINED_ARCH":
			var ba := BoxShape3D.new(); ba.size = Vector3(7.2, 8.8, 1.8)
			solid_shape.shape = ba; solid_shape.position = Vector3(0, 4.4, 0)
		_:
			has_collision = false
	if has_collision:
		solid.add_child(solid_shape)
		b_root.add_child(solid)
	else:
		# Never parented, so nothing else would ever free them: a flora patch used
		# to leak one StaticBody3D + shape per spawn at exit.
		solid.free()
		solid_shape.free()

	var entry := {"kind": kind, "pos": snap_pos, "rot": rot_y_deg, "root": b_root, "upper": upper_holder, "intact": true, "user_placed": record_user, "solid": solid if has_collision else null, "solid_shape": solid_shape if has_collision else null}
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
	if spawn_crater:
		spawn_cel_smoke(impact_pos + Vector3(0, 0.3, 0), 5, impulse_dir if impulse_dir.length_squared() > 0.01 else Vector3.UP, 0.9)
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
				if is_instance_valid(p.get("upper", null)):
					(p["upper"] as Node3D).visible = false
				# A shattered pillar must not stay an invisible wall you can climb.
				if is_instance_valid(p.get("solid_shape", null)):
					(p["solid_shape"] as CollisionShape3D).set_deferred("disabled", true)
				_burst_debris(p_pos + Vector3(0, 4.5, 0), impulse_dir, 12)
				spawn_step_sigil(p_pos + Vector3(0, 2.0, 0), Color(0.95, 0.92, 0.88), 2.4)
				play_sfx("shatter")

func _burst_debris(origin: Vector3, dir: Vector3, count: int) -> void:
	var spawned := 0
	var active := 0
	for d in debris_pool:
		if d["timer"] > 0.0:
			active += 1
	var room: int = clampi(debris_cap - active, 0, debris_pool.size())
	if room <= 0:
		return
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
			if spawned >= count or spawned >= room:
				break

func reset_destructibles() -> void:
	for p in destructible_pillars:
		p["intact"] = true
		if is_instance_valid(p.get("upper", null)):
			(p["upper"] as Node3D).visible = true
		if is_instance_valid(p.get("solid_shape", null)):
			(p["solid_shape"] as CollisionShape3D).set_deferred("disabled", false)
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
	# Never on the floor plane: 0.18 m clears both the arena floor and the raised
	# water sheet, so the two alpha surfaces cannot z-fight while the ring expands.
	sm.global_position = Vector3(pos.x, maxf(pos.y, SIGIL_FLOOR_CLEARANCE), pos.z)
	sm.scale = Vector3(scale_mult, SIGIL_FLATTEN, scale_mult)
	sm.visible = true
	rmat.albedo_color = Color(col.r, col.g, col.b, 0.88)
	sigil_timers[sigil_idx] = 0.42
	sigil_idx = (sigil_idx + 1) % 4

func trigger_style_fx(style: int, start_pos: Vector3, end_pos: Vector3, visual_root: Node3D, allow_afterimage: bool) -> void:
	play_sfx("vanish")
	spawn_cel_smoke(start_pos + Vector3(0, 0.8, 0), 4, -Vector3(end_pos - start_pos).normalized(), 0.6)
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

func update_vfx(delta: float, is_dashing: bool, style: int, visual_root: Node3D, allow_afterimage: bool, cam_pos: Vector3 = Vector3.ZERO, player_pos: Vector3 = Vector3.ZERO, boss_pos: Vector3 = Vector3.ZERO) -> void:
	water_boss_pos = boss_pos if boss_pos.length_squared() > 0.01 else water_boss_pos
	_update_water_floor(player_pos)
	_update_cel_smoke(delta)
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
