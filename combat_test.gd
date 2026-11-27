extends SceneTree

# Headless regression test for the V3 combat layer.
# Drives: damage -> combo + damage numbers, KO -> VICTORY, RETRY -> reset,
# Sandbox Immortal, lethal damage -> DEFEAT, tuning save/load order,
# and the generated Combat Feel tab + the in-game menu row layout.
# Run: godot --headless --path . --script res://combat_test.gd

var frames := 0
var scene_node: Node = null
var player: Node = null
var combat: Node = null
var studio: Node = null
var failures: Array[String] = []

func _initialize() -> void:
	var packed = load("res://character_movement_test.tscn")
	if packed == null:
		print("COMBAT_TEST_FAIL: scene missing")
		quit(1)
		return
	scene_node = packed.instantiate()
	root.add_child(scene_node)
	player = scene_node.get_node_or_null("Player")
	combat = scene_node.get_node_or_null("CombatManager")
	studio = scene_node.get_node_or_null("DevStudio")

func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   " + label)
	else:
		print("  FAIL " + label)
		failures.append(label)

func _process(_delta: float) -> bool:
	frames += 1
	# Let _ready / @onready settle before touching anything.
	if frames == 3:
		_run()
		return false
	# Give the engine a few frames to flush any deferred free / material errors.
	if frames >= 20:
		_finish()
		return true
	return false

func _run() -> void:
	if player == null or combat == null or studio == null:
		print("COMBAT_TEST_FAIL: Player / CombatManager / DevStudio not found")
		failures.append("scene nodes")
		return

	# Hermetic: a previous run may have left a user:// save with test tuning in it.
	# (The fact that this mattered is proof the tuning really does persist.)
	player.data_store.reset_tuning()
	combat.reset_duel()

	check(not combat.target_stats.is_empty(), "enemies registered on boot")
	var td: Node3D = combat.target_stats.keys()[0] as Node3D
	var s: Dictionary = combat.target_stats[td]

	# --- 1. One real hit: damage, combo counter, floating number -------------
	var hp_before: float = float(s["hp"])
	combat.apply_damage(td, 250.0, 40.0, Vector3(0, 0, 6.0))
	check(float(s["hp"]) < hp_before, "apply_damage reduces rival HP")
	check(combat.combo_hits >= 1, "combo counter increments")
	var live_numbers := 0
	for d in combat.dmg_numbers:
		if float(d["timer"]) > 0.0:
			live_numbers += 1
	check(live_numbers >= 1, "floating damage number spawned")

	# --- 2. KO -> real victory, no silent full heal --------------------------
	combat.apply_damage(td, 9999.0, 0.0, Vector3(0, 8.0, 12.0))
	check(float(s["hp"]) <= 0.0, "rival HP stays at 0 after a lethal hit")
	check(int(s["ai_state"]) == combat.AIState.DEAD, "rival enters DEAD state")
	check(str(combat.result_state) == "VICTORY", "result_state == VICTORY")
	Engine.time_scale = 1.0

	# --- 3. Rematch resets everything ---------------------------------------
	combat.reset_duel()
	check(str(combat.result_state) == "", "reset_duel clears the result")
	check(is_equal_approx(float(s["hp"]), float(s["max_hp"])), "reset_duel restores rival HP")
	check(int(s["ai_state"]) == combat.AIState.IDLE, "reset_duel puts rival back to IDLE")
	check(not bool(player.is_defeated), "reset_duel revives the player")

	# --- 4. Sandbox Immortal ------------------------------------------------
	player.data_store.tuning["immortal_mode"] = true
	for i in range(12):
		player.take_damage(400.0)
	check(not bool(player.is_defeated), "immortal mode survives 12 lethal hits")
	check(float(player.hp) >= 1.0, "immortal mode clamps at 1 HP")

	# --- 5. Mortal again -> DEFEAT ------------------------------------------
	player.data_store.tuning["immortal_mode"] = false
	player.data_store.tuning["ko_slowmo_time"] = 0.0
	var lethal: bool = bool(player.take_damage(99999.0))
	check(lethal, "lethal damage reports a kill")
	check(bool(player.is_defeated), "player enters defeated state")
	check(float(player.hp) <= 0.0, "player HP reaches 0")
	combat.result_state = "DEFEAT"
	Engine.time_scale = 1.0
	combat.reset_duel()

	# --- 6. Tuning save/load order -----------------------------------------
	player.data_store.tuning["enemy_damage"] = 123.0
	player.data_store.save_to_disk(player, combat)
	player.data_store.reset_tuning()
	check(is_equal_approx(player.data_store.tuning_get("enemy_damage", 0.0), 55.0), "reset_tuning restores defaults")
	# apply_race_by_name must NOT be able to wipe loaded values (the old load-order bug).
	player.apply_race_by_name("Profile_2")
	player.data_store.load_from_disk(player, combat)
	check(is_equal_approx(player.data_store.tuning_get("enemy_damage", 0.0), 123.0), "saved tuning survives a load after a profile switch")
	player.apply_race_by_name("Profile_1")
	player.data_store.reset_tuning()

	# --- 7. Hitstop is tunable in one place ---------------------------------
	player.data_store.tuning["hitstop_scale"] = 0.0
	player.hitstop_timer = 0.0
	player.trigger_hitstop(0.1, 0.4)
	check(is_equal_approx(player.hitstop_timer, 0.0), "hitstop_scale 0 disables hitstop")
	player.data_store.tuning["hitstop_scale"] = 1.0
	player.trigger_hitstop(0.1, 0.0)
	check(player.hitstop_timer > 0.09, "hitstop_scale 1 restores hitstop")

	# --- 8. Generated Combat Feel tab + menu layout ------------------------
	check(int(studio.tab_container.get_tab_count()) == 8, "Dev Studio has 8 tabs (Combat Feel added)")
	check(studio.combat_feel_vb != null and studio.combat_feel_vb.get_child_count() >= 12, "Combat Feel tab generated its rows")
	var rows: int = int(studio._p5_row_count())
	check(rows == 19, "in-game menu has 19 rows")
	var vp: Vector2 = studio.get_viewport_rect().size
	check(studio._p5_row_rect(rows - 1).end.y <= vp.y, "last menu row fits on screen")

	# --- 9. Boss plays a real attack animation -----------------------------
	combat._boss_anim(s, "slash_up")
	check(true, "_boss_anim is safe to call")

	# --- 10. Quality tiers drive the live viewport -------------------------
	player.data_store.tuning["auto_quality"] = false
	player.data_store.tuning["quality_tier"] = 0
	player.data_store.tuning["render_scale"] = 0.65
	player.apply_quality_tier()
	check(is_equal_approx(player.get_viewport().scaling_3d_scale, 0.65), "LOW tier applies 0.65 render scale")
	check(int(player.get_viewport().msaa_3d) == Viewport.MSAA_DISABLED, "LOW tier disables MSAA")
	check(int(player.dash_vfx.debris_cap) == 8, "LOW tier caps debris at 8")
	player.data_store.tuning["quality_tier"] = 3
	player.data_store.tuning["render_scale"] = 1.0
	player.apply_quality_tier()
	check(is_equal_approx(player.get_viewport().scaling_3d_scale, 1.0), "ULTRA tier applies full render scale")
	check(player.anime_mat.next_pass != null, "ULTRA tier keeps the ink outline pass")
	check(not player.face_sdf_active, "masked characters stay off the SDF face path")
	# The detector must never claim ULTRA for a potato GPU name.
	check(player.data_store.tier_label(0) == "LOW" and player.data_store.tier_label(3) == "ULTRA", "tier labels resolve")

	# --- 11. One tap = one menu action -------------------------------------
	var fp = studio.fp_mod
	fp.set("p5_pause_active", true)
	studio.fps_mode_idx = 0
	var target_row: int = 8
	var row_rect: Rect2 = studio._p5_row_rect(target_row)
	studio._handle_p5_blade_tap(row_rect.get_center())
	check(studio.fps_mode_idx == 1, "a single tap executes the tapped row once")
	check(int(fp.get("p5_selected_idx")) == target_row, "the tapped row is selected")
	var after_one_tap: int = studio.fps_mode_idx
	var vpx: float = studio.get_viewport_rect().size.x
	studio._handle_p5_blade_tap(Vector2(vpx - 2.0, row_rect.get_center().y))
	check(studio.fps_mode_idx == after_one_tap, "tapping outside a row fires nothing")
	fp.set("p5_pause_active", false)
	studio.fps_mode_idx = 0
	studio._apply_display_mode()

	# --- 12. V5 Task 0: a pre-V5 profile must never abort _ready() -------------
	# This is the exact phone crash: load_from_disk() read parsed["tuning"] on a
	# profile written before the key existed, so PlayerController._ready() died
	# half-way and the camera stayed inside the character mesh.
	var legacy_f := FileAccess.open(player.data_store.SAVE_PATH, FileAccess.WRITE)
	if legacy_f:
		# player_tunables is applied at the END of load_from_disk(), so it only lands
		# if the function ran to completion. That is what proves the abort is gone.
		legacy_f.store_string(JSON.stringify({"run_speed": 18.0, "player_tunables": {"run_speed": 18.0}}))
		legacy_f.close()
	player.data_store.tuning = {}
	player.run_speed = 16.0
	player.data_store.load_from_disk(player, combat)
	check(player.data_store.tuning.has("quality_tier") and player.data_store.tuning.has("water_floor_enabled"), "legacy profile without 'tuning' loads a complete default dict")
	check(is_equal_approx(player.data_store.tuning_get("wall_run_speed", 0.0), 26.0), "legacy profile falls back to the default wall-run speed")
	check(is_equal_approx(player.run_speed, 18.0), "legacy profile reaches the end of load_from_disk() (no mid-function abort)")
	player.run_speed = 16.0
	player.data_store.tuning["quality_tier"] = {"bad": 1}
	check(player.data_store.quality_tier_index() == 2, "a non-numeric quality_tier degrades to MID instead of erroring")
	var profiles_ok: bool = typeof(player.data_store.profiles) == TYPE_DICTIONARY and player.data_store.profiles.has("Profile_1")
	check(profiles_ok, "profile table survives a legacy load")
	player.data_store.ensure_tuning({"wall_run_speed": "fast", "unrelated": 1})
	check(is_equal_approx(player.data_store.tuning_get("wall_run_speed", 0.0), 26.0), "a wrong-typed saved value is discarded, not applied")
	DirAccess.remove_absolute(player.data_store.SAVE_PATH)

	# --- 13. V5 Task 1: parkour wall-run gate + solid pillars ------------------
	player.data_store.reset_tuning()
	check(CombatData.TUNING_DEFAULTS.has("wall_run_enabled") and bool(CombatData.TUNING_DEFAULTS["wall_run_enabled"]), "wall_run_enabled exists in tuning defaults, default on")
	check(is_equal_approx(player.WALL_RUN_MIN_SPEED, 11.0), "wall-run speed gate is 11.0")
	check(player.wall_run_gate(true, 0.0, true, 4.0, false), "wall-run: sprinting into a vertical wall engages")
	check(player.wall_run_gate(true, 0.0, false, 14.0, false), "wall-run: fast airborne contact engages without sprint")
	check(not player.wall_run_gate(true, 0.0, false, 3.0, false), "wall-run: slow contact is refused")
	check(not player.wall_run_gate(true, 0.0, true, 20.0, true), "wall-run: attacking / dashing / hitstun is refused")
	check(not player.wall_run_gate(false, 0.0, true, 20.0, false), "wall-run: needs an actual wall")
	check(not player.wall_run_gate(true, 0.95, true, 20.0, false), "wall-run: a floor-like normal (|ny| >= 0.35) is refused")
	player.data_store.tuning["wall_run_enabled"] = false
	check(not player.wall_run_gate(true, 0.0, true, 20.0, false), "wall-run: the tab-8 toggle disables it entirely")
	player.data_store.tuning["wall_run_enabled"] = true
	check(player.data_store.tuning_bool("wall_run_enabled", false), "wall_run_enabled toggles back on cleanly")
	check(is_equal_approx(player.data_store.tuning_get("wall_kick_force", 0.0), 18.0), "wall kick-off force is a saved knob")
	check(is_equal_approx(player.data_store.tuning_get("wall_run_gravity_scale", 0.0), 0.15), "wall-run gravity scale is a saved knob")

	var pillars_before: int = player.dash_vfx.destructible_pillars.size()
	player.dash_vfx.spawn_arena_block("GOTHIC_PILLAR", Vector3(60, 0, 60), 0.0, true)
	var solid_ok := false
	if player.dash_vfx.destructible_pillars.size() > pillars_before:
		var entry: Dictionary = player.dash_vfx.destructible_pillars[pillars_before]
		solid_ok = entry.get("solid", null) != null and entry.get("solid_shape", null) != null
	check(solid_ok, "arena pillars carry a StaticBody so is_on_wall() can see them")
	player.dash_vfx.remove_nearest_block(Vector3(60, 0, 60), 4.5)

	# --- 14. V5 Task 2: anime water floor + celestial constellation eye -------
	player.data_store.tuning["water_floor_enabled"] = true
	player.data_store.tuning["water_wave_height"] = 0.3
	player.apply_quality_tier()
	check(player.dash_vfx.water_enabled and player.dash_vfx.water_mesh.visible, "water floor switches on from tab 8")
	check(is_equal_approx(float(player.dash_vfx.water_mat.get_shader_parameter("wave_height")), 0.3), "water wave height reaches the shader")
	player.dash_vfx.update_vfx(0.016, false, 0, player.visual_root, false, Vector3.ZERO, Vector3(2, 0, 0), Vector3(9, 0, 9))
	var ripple_p = player.dash_vfx.water_mat.get_shader_parameter("player_pos")
	check(typeof(ripple_p) == TYPE_VECTOR3 and (ripple_p as Vector3).is_equal_approx(Vector3(2, 0, 0)), "foot contact ripple origin is fed every physics tick")
	player.data_store.tuning["water_floor_enabled"] = false
	player.apply_quality_tier()
	check(not player.dash_vfx.water_mesh.visible, "water floor switches back off")

	player.eye_shape = 4
	player.update_eye_shader()
	check(int(player.eye_mat.get_shader_parameter("eye_shape")) == 4, "eye_shape 4 (celestial constellation) reaches the eye shader")
	check(is_equal_approx(float(player.eye_mat.get_shader_parameter("awaken")), 1.0), "eye emission starts at base form")
	player.eye_awaken_boost = 2.4
	player.update_eye_shader()
	check(is_equal_approx(float(player.eye_mat.get_shader_parameter("awaken")), 2.4), "flame awakening multiplies eye emission 2.4x")
	player.eye_awaken_boost = 1.0
	player.eye_shape = 0
	player.update_eye_shader()

	# --- 15. V5 Task 3: impact slash + 2-tone cel smoke -----------------------
	combat.impact_slash_timer = 0.0
	combat.trigger_impact_slash(Vector3(0, 2, -4), -30.0, 1.2)
	check(combat.impact_slash_timer > 0.15, "crit / parry / KO records the 0.16s impact slash")
	check(is_equal_approx(combat.impact_flash_scale, 1.2), "impact flash scale is recorded")
	check(absf(rad_to_deg(combat.impact_slash_angle) + 30.0) <= 8.0, "impact slash angle jitters around the requested angle")
	combat._process(0.3)
	check(combat.impact_slash_timer <= 0.0, "impact slash expires")

	var smoke_before := 0
	for p in player.dash_vfx.cel_smoke_pool:
		if float(p["timer"]) > 0.0:
			smoke_before += 1
	player.dash_vfx.spawn_cel_smoke(Vector3(0, 1, -2), 4, Vector3.UP, 1.0)
	var smoke_after := 0
	for p in player.dash_vfx.cel_smoke_pool:
		if float(p["timer"]) > 0.0:
			smoke_after += 1
	check(player.dash_vfx.cel_smoke_pool.size() == 14, "cel-smoke pool is preallocated")
	check(smoke_after >= smoke_before + 1, "cel-smoke pool emits 2-tone puffs")

	# --- 15. V5 Task 2: screen-space impact slash + 2-tone cel smoke ----------
	player.data_store.reset_tuning()
	check(CombatData.TUNING_DEFAULTS.has("impact_slash_enabled") and bool(CombatData.TUNING_DEFAULTS["impact_slash_enabled"]), "impact_slash_enabled exists in tuning defaults")
	check(CombatData.TUNING_SPEC.has("impact_slash_intensity"), "impact slash intensity is a tab-8 slider")
	check(CombatData.TUNING_BOOLS.has("cel_smoke_enabled"), "cel_smoke_enabled is a tab-8 checkbox")
	check(CombatData.TUNING_SPEC.has("cel_smoke_density"), "cel smoke density is a tab-8 slider")
	player._push_fx_budget()
	check(player.dash_vfx.screen_slash != null and player.dash_vfx.slash_layer is CanvasLayer, "impact slash lives on a CanvasLayer")
	player.dash_vfx.screen_slash.timer = 0.0
	combat.trigger_impact_slash(Vector3(0, 2, -4), -30.0, 1.2)
	check(player.dash_vfx.screen_slash.timer > 0.0, "a crit / Z-Vanish / KO slash fires the CanvasLayer effect")
	check(player.dash_vfx.screen_slash.visible, "the fired slash is visible so it redraws every frame")
	player.dash_vfx.screen_slash._process(0.5)
	check(player.dash_vfx.screen_slash.timer == 0.0 and not player.dash_vfx.screen_slash.visible, "the idle slash hides and stops redrawing")
	player.data_store.tuning["impact_slash_enabled"] = false
	player._push_fx_budget()
	player.dash_vfx.screen_slash.timer = 0.0
	combat.trigger_impact_slash(Vector3(0, 2, -4), -30.0, 1.2)
	check(player.dash_vfx.screen_slash.timer == 0.0, "the tab-8 toggle disables the screen slash")
	player.data_store.tuning["impact_slash_enabled"] = true
	player.data_store.tuning["cel_smoke_enabled"] = false
	player._push_fx_budget()
	for p in player.dash_vfx.cel_smoke_pool:
		p["timer"] = 0.0
	player.dash_vfx.spawn_cel_smoke(Vector3(0, 1, -2), 6, Vector3.UP, 1.0)
	var smoke_off := 0
	for p in player.dash_vfx.cel_smoke_pool:
		if float(p["timer"]) > 0.0: smoke_off += 1
	check(smoke_off == 0, "cel smoke never spawns while its tab-8 toggle is off")
	player.data_store.tuning["cel_smoke_enabled"] = true
	player._push_fx_budget()
	for p in player.dash_vfx.cel_smoke_pool:
		p["timer"] = 0.0
	player.dash_vfx.set_fx_budget(2, true, true, 1.0, true, 1.0)
	player.dash_vfx.spawn_cel_smoke(Vector3(0, 1, -2), 8, Vector3.UP, 1.0)
	var smoke_capped := 0
	for p in player.dash_vfx.cel_smoke_pool:
		if float(p["timer"]) > 0.0: smoke_capped += 1
	check(smoke_capped > 0 and smoke_capped <= 2, "the tier cap bounds simultaneous cel-smoke puffs")
	for p in player.dash_vfx.cel_smoke_pool:
		p["timer"] = 0.0
	player.data_store.reset_tuning()
	player._push_fx_budget()

	# --- 16. V5 Task 3: 3-band water floor + ledge floor confirmation ---------
	player.data_store.reset_tuning()
	check(CombatData.TUNING_BOOLS.has("water_floor_enabled"), "water floor toggle is a tab-8 checkbox")
	check(CombatData.QUALITY_TIERS.size() == 4, "quality tiers still resolve for water gating")
	check(is_equal_approx(float(CombatData.TUNING_DEFAULTS.get("water_ripple_strength", -1.0)), 1.0), "water ripple strength exists in tuning defaults")
	check(CombatData.TUNING_SPEC.has("water_wave_height") and CombatData.TUNING_SPEC.has("water_ripple_strength"), "water wave + ripple are tab-8 sliders")
	player.data_store.tuning["auto_quality"] = false
	player.data_store.tuning["quality_tier"] = 1
	player.data_store.tuning["water_floor_enabled"] = true
	player.apply_quality_tier()
	check(player.dash_vfx.water_enabled and player.dash_vfx.water_mesh.visible, "MID tier renders the water floor when the toggle is on")
	player.dash_vfx._update_water_floor(Vector3(3.0, 0.0, -7.0))
	var pp = player.dash_vfx.water_mat.get_shader_parameter("player_pos")
	check(pp is Vector3 and (pp as Vector3).distance_to(Vector3(3.0, 0.0, -7.0)) < 0.001, "player_pos reaches the water shader")
	player.dash_vfx.water_boss_pos = Vector3(-4.0, 0.0, 9.0)
	player.dash_vfx._update_water_floor(Vector3(3.0, 0.0, -7.0))
	var bp = player.dash_vfx.water_mat.get_shader_parameter("boss_pos")
	check(bp is Vector3 and (bp as Vector3).distance_to(Vector3(-4.0, 0.0, 9.0)) < 0.001, "boss_pos reaches the water shader")
	player.data_store.tuning["quality_tier"] = 0
	player.apply_quality_tier()
	check(not player.dash_vfx.water_enabled and not player.dash_vfx.water_mesh.visible, "LOW tier disables the water floor entirely")
	player.data_store.reset_tuning()
	player.apply_quality_tier()

	# Ledge floor confirmation: open air must refuse, a real surface must accept.
	check(not player._has_floor_below(Vector3(300.0, 80.0, 300.0), 2.4), "no floor is found below open air")
	check(player._has_floor_below(Vector3(0.0, 1.2, 0.0), 2.4), "the arena floor counts as a landing surface")
	var restore_pos: Vector3 = player.global_position
	var restore_fwd: Vector3 = player.wall_run_forward
	player.wall_run_forward = Vector3.RIGHT
	player.global_position = Vector3(300.0, 80.0, 300.0)
	check(not player._ledge_vault_clear(), "running past a pillar side edge into open air refuses the vault")
	player.global_position = restore_pos
	player.wall_run_forward = restore_fwd

	# --- 17. V5 Task 4: 4-channel vertex colour + SDF face head basis ---------
	check(player.anime_mat != null and player.anime_mat.shader != null, "the character NPR shader is built on the rigged hero")
	var code: String = player.anime_mat.shader.code if player.anime_mat and player.anime_mat.shader else ""
	check(code.contains("varying vec4 v_col") and code.contains("v_col = COLOR"), "COLOR reaches light() through a varying")
	var light_at := code.find("void light()")
	var light_src: String = code.substr(light_at) if light_at != -1 else ""
	check(light_at != -1 and not light_src.contains("return"), "no early return inside the light() processor")
	check(code.contains("v_col.r") and code.contains("v_col.b") and code.contains("v_col.a > 0.5"), "R bias, B spec mask and A face switch are all read")
	check(code.contains("varying vec2 v_uv") and code.contains("sdf_face_tex"), "the SDF face path samples UV through a varying")
	check(player.body_mesh == null or player.body_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "character self-shadowing stays off")
	check(player.anime_mat.next_pass != null, "the outline rides next_pass instead of a second mesh")

	# head_forward / head_right: live, change-driven, idle-silent.
	player.face_sdf_active = true
	player._push_head_basis()
	var hb: Basis = player.visual_root.global_basis
	var hf = player.anime_mat.get_shader_parameter("head_forward")
	check(hf is Vector3 and (hf as Vector3).distance_to(-hb.z) < 0.001, "head_forward follows the head basis")
	var hr = player.anime_mat.get_shader_parameter("head_right")
	check(hr is Vector3 and (hr as Vector3).distance_to(hb.x) < 0.001, "head_right follows the head basis")
	player.anime_mat.set_shader_parameter("head_forward", Vector3.ZERO)
	player._push_head_basis()
	var idle_hf = player.anime_mat.get_shader_parameter("head_forward")
	check(idle_hf is Vector3 and (idle_hf as Vector3).length() < 0.001, "an idle head basis is not re-pushed (epsilon cache)")
	player.visual_root.rotate_y(0.35)
	player._push_head_basis()
	var turn_hf = player.anime_mat.get_shader_parameter("head_forward")
	check(turn_hf is Vector3 and (turn_hf as Vector3).distance_to(-(player.visual_root.global_basis.z)) < 0.001, "a turning head repushes the basis")
	player.visual_root.rotate_y(-0.35)
	player.face_sdf_active = false

	# --- 18. V5 Task 5: merged saves, single-tap menu, UDP hardening ----------
	var t5_save: String = player.data_store.SAVE_PATH
	var t5_had := FileAccess.file_exists(t5_save)
	var t5_backup := FileAccess.get_file_as_string(t5_save) if t5_had else ""
	var t5_seed := FileAccess.open(t5_save, FileAccess.WRITE)
	if t5_seed:
		t5_seed.store_string(JSON.stringify({
			"story_state": {"schema_version": 1, "active_origin_id": "Profile_3",
				"current_node_id": "node_megastructure_descent",
				"story_flags": {"fought_inquisitor": true},
				"completed_nodes": ["node_start_sanctuary"]},
			"hand_written_key": 7}))
		t5_seed.close()
	player.data_store.save_to_disk(player, combat)
	var t5_after_combat = JSON.parse_string(FileAccess.get_file_as_string(t5_save))
	var t5_acd: Dictionary = t5_after_combat if typeof(t5_after_combat) == TYPE_DICTIONARY else {}
	check(t5_acd.has("tuning") and t5_acd.has("story_state"), "a combat save keeps story_state and writes tuning")
	var t5_raw_state = t5_acd.get("story_state", {})
	var t5_acstate: Dictionary = t5_raw_state if typeof(t5_raw_state) == TYPE_DICTIONARY else {}
	check(bool((t5_acstate.get("story_flags", {}) as Dictionary).get("fought_inquisitor", false)), "story flags survive a combat save")
	check(int(t5_acd.get("hand_written_key", 0)) == 7, "unknown profile keys survive a combat save")

	var t5_ws = load("res://world_story.gd").new()
	t5_ws.load_story_data()
	t5_ws.load_state()
	check(bool(t5_ws.get("schema_ok")) and bool(t5_ws.story_flags.get("fought_inquisitor", false)), "the story loader reads story_state back")
	t5_ws.story_flags["after_playtest"] = true
	t5_ws.save_state()
	var t5_after_story = JSON.parse_string(FileAccess.get_file_as_string(t5_save))
	var t5_asd: Dictionary = t5_after_story if typeof(t5_after_story) == TYPE_DICTIONARY else {}
	check(t5_asd.has("tuning") and t5_asd.has("story_state"), "a story save keeps tuning and story_state")
	check(not t5_asd.has("story"), "the legacy 'story' key is no longer written")
	t5_ws.free()

	# Single-tap P5 menu: the tap is consumed before the row runs.
	var t5_menu = studio.fp_mod if studio else null
	check(t5_menu != null, "the P5 module is attached to the Dev Studio")
	if t5_menu:
		t5_menu.set("p5_pause_active", true)
		var t5_vp := studio.get_viewport()
		var t5_lock_before: bool = player.is_locked_on
		var t5_row1: Rect2 = studio._p5_row_rect(1)
		studio._handle_p5_blade_tap(t5_row1.get_center())
		check(player.is_locked_on != t5_lock_before, "one tap on a menu row runs its action")
		check(t5_vp.is_input_handled(), "the tap is consumed before the row action executes")
		t5_menu.set("p5_pause_active", false)

		# UDP 7778: 30 Hz throttle, password lock, hostile datagrams.
		check(is_equal_approx(float(t5_menu.get("P2P_SEND_HZ")), 30.0), "PvP state sync is throttled to 30 Hz")
		check(absf(1.0 / float(t5_menu.get("P2P_SEND_HZ")) - 0.0333) < 0.001, "the 30 Hz accumulator step is 0.033 s")
		t5_menu.set("active_room_code", "SZ100")
		t5_menu.set("active_room_pass", "secret")
		check(t5_menu._join_verdict("sz100", "secret") == "ACCEPT", "a correct room code + password links")
		check(t5_menu._join_verdict("sz100", "nope") == "DENY", "a wrong password is denied")
		check(t5_menu._join_verdict("SZ999", "secret") == "IGNORE", "a wrong room code is ignored")
		check(not bool(t5_menu.get("is_p2p_connected")), "no link is opened by a verdict alone")
		t5_menu.call("_handle_udp_packet", "", "1.2.3.4")
		t5_menu.call("_handle_udp_packet", "P2PSYNC", "1.2.3.4")
		t5_menu.call("_handle_udp_packet", "P2PSYNC:nan:inf:1e30:0:0:0", "9.9.9.9")
		t5_menu.call("_handle_udp_packet", "P2PJOIN:", "1.2.3.4")
		t5_menu.call("_handle_udp_packet", "P2PROOM:" + "X".repeat(400), "1.2.3.4")
		t5_menu.call("_handle_udp_packet", "P2PDENY:", "1.2.3.4")
		check(not bool(t5_menu.get("is_p2p_connected")) and str(t5_menu.get("peer_ip")) == "", "malformed packets never open a match")

	if t5_had:
		var t5_restore := FileAccess.open(t5_save, FileAccess.WRITE)
		if t5_restore:
			t5_restore.store_string(t5_backup)
			t5_restore.close()

	# --- 19. V6 Task 1: touch-first Dev Studio + 4.7.2 editor warnings ---------
	check(studio.tab_container.tabs_visible == false, "the tiny native tab bar is hidden")
	check(studio.tab_pills.size() == 8, "the mobile category grid exposes all 8 sections")
	check(studio.dev_panel.theme != null, "the dev panel carries the mobile touch theme")
	var t6_tabs_ok := true
	for i in range(8):
		studio._select_tab(i)
		if int(studio.tab_container.current_tab) != i:
			t6_tabs_ok = false
		if not (studio.tab_pills[i] as Button).button_pressed:
			t6_tabs_ok = false
	check(t6_tabs_ok, "one tap on any category pill reaches its tab (no arrow scrolling)")
	studio._select_tab(7)
	(studio.tab_pills[0] as Button).pressed.emit()
	check(int(studio.tab_container.current_tab) == 0, "pressing a category pill switches the tab")
	studio._select_tab(7)

	var t6_sliders_ok := true
	var t6_slider_count := 0
	for row in studio.combat_feel_vb.get_children():
		for c in row.get_children():
			if c is HSlider:
				t6_slider_count += 1
				if (c as HSlider).custom_minimum_size.y < 44.0:
					t6_sliders_ok = false
			elif c is CheckBox and (c as CheckBox).custom_minimum_size.y < 44.0:
				t6_sliders_ok = false
	check(t6_slider_count > 0 and t6_sliders_ok, "auto-generated tab-8 sliders are thumb-sized (>= 44 px)")

	check(studio.process_mode == Node.PROCESS_MODE_ALWAYS, "the Dev Studio keeps ticking while the tree is paused")
	studio._set_paused(true)
	check(studio.get_tree().paused, "PAUSE freezes gameplay")
	check(studio.pause_badge.visible and studio.pause_button.text.contains("RESUME"), "the PAUSED badge and the RESUME label are shown")
	studio._toggle_pause()
	check(not studio.get_tree().paused and not studio.pause_badge.visible, "tapping the pill again resumes gameplay")

	studio._set_sandbox_immortal(true)
	check(player.data_store.tuning_bool("immortal_mode", false) and studio.god_button.button_pressed, "GOD MODE drives sandbox immortal")
	studio._toggle_sandbox_immortal()
	check(not player.data_store.tuning_bool("immortal_mode", true) and not studio.god_button.button_pressed, "GOD MODE toggles sandbox immortal back off")

	player.data_store.tuning["enemy_damage"] = 77.0
	studio.toast_label.text = ""
	var t6_export: String = studio._export_all_values()
	check(t6_export.contains("enemy_damage = 77") and t6_export.contains("immortal_mode ="), "COPY ALL formats every live tuning value")
	check(t6_export.contains("[profile]") and t6_export.contains("[player]"), "COPY ALL includes the profile and player sections")
	check(FileAccess.file_exists(studio.BALANCE_PATH), "COPY ALL writes user://balance_values.txt")
	check(FileAccess.get_file_as_string(studio.BALANCE_PATH).contains("enemy_damage = 77"), "the exported file holds the live values")
	check(studio.toast_label.text.contains("balance_values.txt"), "COPY ALL shows an on-panel confirmation")
	DirAccess.remove_absolute(studio.BALANCE_PATH)
	player.data_store.reset_tuning()

	# 4.7.2 editor-debugger warnings: no `var scale` shadow, no bare enum int,
	# no unused ragdoll arg, no interpolated Camera3D written from _process().
	check(player.camera.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "the Camera3D opts out of physics interpolation (no render-tick warning)")
	check(player.camera_pivot.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF and player.spring_arm.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "the whole camera rig opts out, so the follow stays smooth")
	player.data_store.tuning["quality_tier"] = 2
	player.apply_quality_tier()
	check(int(player.get_viewport().msaa_3d) == int(CombatData.QUALITY_TIERS[2]["msaa"]), "the MSAA enum cast still applies the tier value")

	# --- 20. V6 Task 2A: curated 3-region arena layouts ----------------------
	player.data_store.reset_tuning()
	var t7_layouts: Dictionary = player.dash_vfx.CURATED_REGION_LAYOUTS
	check(t7_layouts.size() == 3 and t7_layouts.has(0) and t7_layouts.has(1) and t7_layouts.has(2), "all three regions own a curated prop layout")
	player.dash_vfx.load_curated_region(0)
	var t7_kids0 := 0
	for c in player.dash_vfx.get_children():
		if not c.is_queued_for_deletion():
			t7_kids0 += 1
	studio.region_idx = 2
	var t7_counts: Array[int] = []
	var t7_paint: Array[Color] = []
	var t7_bad := 0
	var t7_prev: Color = player.dash_vfx.stone_mat.albedo_color
	for pass_i in range(2):
		for want in range(3):
			studio._cycle_region()
			var props: int = player.dash_vfx.curated_prop_count()
			if int(studio.region_idx) != want or props != (t7_layouts[want] as Array).size():
				t7_bad += 1
			var live := 0
			for p in player.dash_vfx.curated_region_props:
				if is_instance_valid(p.get("root", null)):
					live += 1
			if live != props:
				t7_bad += 1
			if pass_i == 0:
				if t7_paint.size() > 0 and player.dash_vfx.stone_mat.albedo_color.is_equal_approx(t7_prev):
					t7_bad += 1
				t7_prev = player.dash_vfx.stone_mat.albedo_color
				t7_paint.append(t7_prev)
				t7_counts.append(props)
	check(t7_bad == 0, "regions 0/1/2 spawn exactly their curated props, live, in cycle order")
	check(t7_paint.size() == 3 and not t7_paint[0].is_equal_approx(t7_paint[1]) and not t7_paint[1].is_equal_approx(t7_paint[2]), "each curated region swaps the arena palette")
	check(t7_counts[0] > t7_counts[1] and t7_counts[1] > 0 and t7_counts[2] > 0, "the three layouts are distinct prop sets")
	studio.region_idx = 2
	studio._cycle_region()
	var t7_kids1 := 0
	for c in player.dash_vfx.get_children():
		if not c.is_queued_for_deletion():
			t7_kids1 += 1
	check(t7_kids1 == t7_kids0, "repeated region switches free every curated prop (no orphan nodes)")
	# GOTHIC_ECLIPSE floods through the existing plane; the LOW-tier gate is untouched.
	studio.region_idx = 1
	studio._cycle_region()
	player.data_store.tuning["auto_quality"] = false
	player.data_store.tuning["quality_tier"] = 0
	player.apply_quality_tier()
	check(not player.dash_vfx.water_enabled and not player.dash_vfx.water_mesh.visible, "GOTHIC_ECLIPSE on LOW keeps the water floor hidden")
	player.data_store.tuning["quality_tier"] = 2
	player.apply_quality_tier()
	check(player.dash_vfx.water_enabled and player.dash_vfx.water_mesh.visible, "GOTHIC_ECLIPSE on MID+ floods the sanctum")
	var t7_before: int = player.dash_vfx.destructible_pillars.size()
	player.dash_vfx.spawn_arena_block("BLAME_MONOLITH", Vector3(-60, 0, 60), 0.0, true)
	check(player.dash_vfx.destructible_pillars.size() == t7_before + 1, "Tab 6 blocks still place on top of a curated region")
	check(player.dash_vfx.curated_prop_count() == (t7_layouts[2] as Array).size(), "a Tab 6 block is never counted as curated")
	player.dash_vfx.remove_nearest_block(Vector3(-60, 0, 60), 4.5)
	check(player.dash_vfx.curated_prop_count() == (t7_layouts[2] as Array).size(), "removing a Tab 6 block leaves the curated sanctum intact")
	player.dash_vfx.clear_curated_region()
	check(player.dash_vfx.curated_prop_count() == 0, "clear_curated_region() leaves no curated props behind")
	player.dash_vfx.load_curated_region(0)

	# --- 21. V6 Task 2B: physical shortcut gates + flag-gated travel --------
	player.data_store.reset_tuning()
	check(CombatData.TUNING_BOOLS.has("unlock_all_shortcuts") and CombatData.TUNING_DEFAULTS.has("unlock_all_shortcuts") and not bool(CombatData.TUNING_DEFAULTS["unlock_all_shortcuts"]), "unlock_all_shortcuts is an auto-generated Tab 8 bool, default off")
	player.data_store.tuning["unlock_all_shortcuts"] = true
	check(player.data_store.tuning_bool("unlock_all_shortcuts", false), "the sandbox gate override toggles on")
	player.data_store.tuning["unlock_all_shortcuts"] = false
	player.data_store.tuning["auto_quality"] = false

	var t8_story = studio.story_mgr
	t8_story.story_flags.erase("shortcut_blame_unlocked")
	t8_story.story_flags.erase("shortcut_eclipse_unlocked")
	studio.travel_to_region(0)
	var t8_kids0 := 0
	for c in player.dash_vfx.get_children():
		if not c.is_queued_for_deletion():
			t8_kids0 += 1
	var t8_counts: Array[int] = []
	var t8_locked := 0
	var t8_bad := 0
	for want in [0, 1, 2]:
		studio.travel_to_region(want)
		t8_counts.append(player.dash_vfx.shortcut_gates.size())
		for g in player.dash_vfx.shortcut_gates:
			if int(g["target_region"]) == want:
				t8_bad += 1
			if bool(g["locked"]):
				t8_locked += 1
	check(t8_counts == [2, 2, 1], "each curated region spawns its expected shortcut gates (hub 2, megastruc 2, eclipse 1)")
	check(t8_bad == 0, "no gate ever targets the region it stands in")
	check(t8_locked == 3 and not t8_story.has_flag("shortcut_blame_unlocked") and not t8_story.has_flag("shortcut_eclipse_unlocked"), "with both flags absent the progression gates start sealed")
	studio.travel_to_region(0)
	var t8_kids1 := 0
	for c in player.dash_vfx.get_children():
		if not c.is_queued_for_deletion():
			t8_kids1 += 1
	check(t8_kids1 == t8_kids0, "repeated region switches free every shortcut gate (no orphan nodes)")

	# Sealed gate: standing in it must not travel and must report why.
	player.shortcut_arrival_cd = 0.0
	player.shortcut_dwell = 0.0
	player.global_position = Vector3(-36.0, 1.6, -2.0)
	player._tick_shortcut_gates(1.0)
	check(int(studio.region_idx) == 0 and player.shortcut_status.begins_with("SEALED"), "a sealed gate refuses travel and reports it without blocking input")
	check(is_equal_approx(player.shortcut_dwell, 0.0), "a sealed gate never accumulates a dwell timer")

	# Rival KO in Region 0 is the real unlock path, and it persists.
	player.data_store.tuning["enemy_damage"] = 91.0
	player.data_store.save_to_disk(player, combat)
	combat.reset_duel()
	var t8_rival: Node3D = combat.target_stats.keys()[0] as Node3D
	combat.apply_damage(t8_rival, 99999.0, 0.0, Vector3(0.0, 8.0, 12.0))
	Engine.time_scale = 1.0
	check(bool(t8_story.story_flags.get("shortcut_blame_unlocked", false)), "a rival KO in region 0 grants shortcut_blame_unlocked")
	check(not bool(t8_story.story_flags.get("shortcut_eclipse_unlocked", false)), "that KO leaves the eclipse shortcut sealed")
	var t8_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://dev_profile.json"))
	var t8_state: Dictionary = t8_profile.get("story_state", {})
	var t8_saved_flags: Dictionary = t8_state.get("story_flags", {})
	var t8_saved_tuning: Dictionary = t8_profile.get("tuning", {})
	check(t8_saved_flags.has("shortcut_blame_unlocked") and is_equal_approx(float(t8_saved_tuning.get("enemy_damage", 0.0)), 91.0), "the shortcut flag persists in story_state without erasing tuning")
	check(player.dash_vfx.refresh_shortcut_gate_visuals(false, t8_story.story_flags) >= 1, "the unlocked hub gate repaints to its bright-gold beacon")

	# Partial dwell must not travel; a full hold on the physics tick must.
	studio.travel_to_region(0)
	player.shortcut_arrival_cd = 0.0
	player.shortcut_dwell = 0.0
	player.global_position = Vector3(-36.0, 1.6, -2.0)
	player._tick_shortcut_gates(0.4)
	check(int(studio.region_idx) == 0, "a dwell shorter than 0.85 s does not travel")
	player._tick_shortcut_gates(0.5)
	check(int(studio.region_idx) == 1 and player.shortcut_banner == "BLAME! MEGASTRUCTURE", "a full dwell travels through the unlocked gate to region 1")
	check(player.shortcut_arrival_cd > 0.0 and is_equal_approx(player.shortcut_dwell, 0.0), "arriving starts the 2 s cooldown so a return gate cannot re-fire")

	# The Tab 8 sandbox override opens a gate the story has not unlocked yet.
	studio.travel_to_region(0)
	player.data_store.tuning["unlock_all_shortcuts"] = true
	player.shortcut_arrival_cd = 0.0
	player.shortcut_dwell = 0.0
	player.global_position = Vector3(36.0, 1.6, -2.0)
	player._tick_shortcut_gates(1.0)
	check(int(studio.region_idx) == 2 and player.shortcut_banner == "GOTHIC ECLIPSE", "unlock_all_shortcuts opens the eclipse gate in sandbox")
	player.data_store.tuning["unlock_all_shortcuts"] = false
	player.global_position = Vector3(0.0, 1.6, 0.0)
	player.shortcut_status = ""
	player.shortcut_banner = ""
	player.shortcut_dwell = 0.0
	player.shortcut_arrival_cd = 0.0
	studio.travel_to_region(0)
	t8_story.story_flags.erase("shortcut_blame_unlocked")
	t8_story.story_flags.erase("shortcut_eclipse_unlocked")
	t8_story.save_state()
	combat.reset_duel()

	# --- 22. V6 Task 3: 2-phase boss, regional telegraphs, stagger finisher --
	player.data_store.reset_tuning()
	player.data_store.tuning["auto_quality"] = false
	combat.sonic_sway_holding = false
	combat.parry_window_timer = 0.0
	check(CombatData.TUNING_BOOLS.has("boss_phase2_enabled") and CombatData.TUNING_DEFAULTS.has("boss_phase2_enabled") and bool(CombatData.TUNING_DEFAULTS["boss_phase2_enabled"]), "boss_phase2_enabled is an auto-generated Tab 8 bool, default on")
	var t9_spec: Array = CombatData.TUNING_SPEC.get("boss_phase2_speed_mult", [])
	check(t9_spec.size() >= 4 and is_equal_approx(float(t9_spec[0]), 1.0) and is_equal_approx(float(t9_spec[1]), 1.6) and is_equal_approx(float(CombatData.TUNING_DEFAULTS.get("boss_phase2_speed_mult", 0.0)), 1.22), "boss_phase2_speed_mult is a 1.0-1.6 Tab 8 slider defaulting to 1.22")
	player.data_store.tuning["boss_phase2_speed_mult"] = 1.4
	check(is_equal_approx(combat.tune("boss_phase2_speed_mult", 0.0), 1.4), "the phase 2 speed multiplier updates live")
	player.data_store.tuning["boss_phase2_speed_mult"] = 1.22

	# 50% HP awakening, exactly once, and clean on retry.
	studio.travel_to_region(0)
	combat.reset_duel()
	var t9_rival: Node3D = combat.target_stats.keys()[0] as Node3D
	var t9_s: Dictionary = combat.target_stats[t9_rival]
	t9_s["hp"] = float(t9_s["max_hp"]) * 0.62
	combat.apply_damage(t9_rival, float(t9_s["max_hp"]) * 0.15, 0.0, Vector3.ZERO)
	check(int(t9_s["boss_phase"]) == 2 and combat.boss_phase == 2, "dropping the rival below 50% HP awakens phase 2")
	check(combat.phase2_awakenings == 1, "phase 2 awakens exactly once")
	combat.apply_damage(t9_rival, 60.0, 0.0, Vector3.ZERO)
	check(combat.phase2_awakenings == 1 and int(t9_s["boss_phase"]) == 2, "further damage never re-triggers the awakening")
	combat.reset_duel()
	check(int(t9_s["boss_phase"]) == 1 and combat.boss_phase == 1 and combat.phase2_awakenings == 0, "a duel retry resets the boss to phase 1")
	player.data_store.tuning["boss_phase2_enabled"] = false
	combat.reset_duel()
	t9_s["hp"] = float(t9_s["max_hp"]) * 0.62
	combat.apply_damage(t9_rival, float(t9_s["max_hp"]) * 0.2, 0.0, Vector3.ZERO)
	check(int(t9_s["boss_phase"]) == 1 and combat.phase2_awakenings == 0, "boss_phase2_enabled = false keeps the rival in phase 1")
	player.data_store.tuning["boss_phase2_enabled"] = true
	combat.reset_duel()

	# Regional archetypes ride the same switch as the curated arena.
	var t9_arch: Array[String] = []
	for want in [0, 1, 2]:
		studio.travel_to_region(want)
		t9_arch.append(combat.region_archetype)
	check(t9_arch[0] != t9_arch[1] and t9_arch[1] != t9_arch[2] and t9_arch[0] != t9_arch[2], "each curated region assigns a distinct boss archetype")
	check(t9_arch == ["INK_DUELIST", "BLAME_RUSHDOWN", "GOTHIC_SANCTUM"], "the archetypes are the authored INK / BLAME / GOTHIC profiles")
	check(combat.region_archetype_for(2) == "GOTHIC_SANCTUM" and str(combat.boss_profile_for_region(2).get("phase2_attack", "")) == "SLAM", "region 2's guardian owns the phase 2 slam")

	# A shortcut re-seats both fighters apart and starts a clean phase 1.
	var t9_story = studio.story_mgr
	t9_story.story_flags["shortcut_blame_unlocked"] = true
	studio.travel_to_region(0)
	combat.reset_duel()
	t9_s["boss_phase"] = 2
	t9_s["ai_state"] = combat.AIState.STAGGERED
	player._refresh_shortcut_visuals()
	player.shortcut_arrival_cd = 0.0
	player.shortcut_dwell = 0.0
	player.global_position = Vector3(-36.0, 1.6, -2.0)
	player._tick_shortcut_gates(1.0)
	var t9_gap: float = player.global_position.distance_to(t9_rival.global_position)
	check(int(studio.region_idx) == 1 and t9_gap >= 6.0, "region travel keeps the player and rival at least 6 m apart")
	check(int(t9_s["boss_phase"]) == 1 and int(t9_s["ai_state"]) != combat.AIState.STAGGERED, "region travel resets boss_phase to 1 and clears the stagger window")

	# UNBLOCKABLE bypasses a guard; PARRIABLE, dash and Sonic Sway still beat it.
	player.lock_target = t9_rival
	player.is_locked_on = true
	player.global_position = t9_rival.global_position + Vector3(0.0, 0.0, 3.0)
	player.velocity = Vector3.ZERO
	player.hp = player.max_hp
	player.state = PlayerController.MoveState.GUARD
	t9_s["telegraph_kind"] = combat.BOSS_TELEGRAPH_UNBLOCKABLE
	t9_s["ai_state"] = combat.AIState.STRIKE_ACTIVE
	combat._resolve_enemy_strike_on_player(t9_rival, t9_s)
	check(player.hp < player.max_hp, "an UNBLOCKABLE slam breaks a raised guard")
	player.hp = player.max_hp
	player.state = PlayerController.MoveState.GUARD
	t9_s["telegraph_kind"] = combat.BOSS_TELEGRAPH_PARRIABLE
	combat._resolve_enemy_strike_on_player(t9_rival, t9_s)
	check(is_equal_approx(player.hp, player.max_hp), "a PARRIABLE wind-up is still negated by guard / Sonic Sway")
	player.hp = player.max_hp
	player.sway_timer = 0.0
	player.state = PlayerController.MoveState.DASH
	t9_s["telegraph_kind"] = combat.BOSS_TELEGRAPH_UNBLOCKABLE
	combat._resolve_enemy_strike_on_player(t9_rival, t9_s)
	check(is_equal_approx(player.hp, player.max_hp), "dash evasion still beats the UNBLOCKABLE slam")
	player.hp = player.max_hp
	player.state = PlayerController.MoveState.GROUND
	player.trigger_sonic_sway_pose(0.4)
	combat._resolve_enemy_strike_on_player(t9_rival, t9_s)
	check(is_equal_approx(player.hp, player.max_hp) and player.sway_timer > 0.0, "a timed Sonic Sway still evades the UNBLOCKABLE slam")
	player.sway_timer = 0.0

	# Posture break -> 2 s STAGGERED -> one finisher consumes the window.
	combat.reset_duel()
	player.lock_target = t9_rival
	player.is_locked_on = true
	player.global_position = t9_rival.global_position + Vector3(0.0, 0.0, 2.6)
	player.velocity = Vector3.ZERO
	player.state = PlayerController.MoveState.GROUND
	combat.player_habits.clear()
	var t9_base_hp: float = float(t9_s["hp"])
	combat._commit_strike(Vector2(0.0, 1.0))
	var t9_base_dmg: float = t9_base_hp - float(t9_s["hp"])
	t9_s["posture"] = float(t9_s["max_posture"]) - 1.0
	combat.apply_damage(t9_rival, 5.0, 40.0, Vector3.ZERO)
	check(int(t9_s["ai_state"]) == combat.AIState.STAGGERED and is_equal_approx(float(t9_s["state_timer"]), GestureCombat.STAGGER_TIME), "breaking posture opens a 2 s STAGGERED window")
	check(is_equal_approx(float(t9_s["posture"]), 0.0) and str(t9_s["telegraph_kind"]) == "NONE", "the posture break empties the bar and drops the telegraph")
	var t9_fin_hp: float = float(t9_s["hp"])
	combat._commit_strike(Vector2(0.0, 1.0))
	var t9_fin_dmg: float = t9_fin_hp - float(t9_s["hp"])
	check(t9_base_dmg > 0.0 and t9_fin_dmg >= t9_base_dmg * 1.9, "a strike on a STAGGERED rival deals finisher bonus damage")
	check(int(t9_s["ai_state"]) != combat.AIState.STAGGERED, "the stagger finisher consumes the STAGGERED window")
	check(is_equal_approx(float(t9_s["posture"]), 0.0) and float(t9_s["stagger_immunity"]) > 0.0, "the finisher refills the rival posture and blocks a chain-stagger")

	# Leave no V6 Task 3 state behind.
	player.sway_timer = 0.0
	player.state = PlayerController.MoveState.GROUND
	player.is_locked_on = false
	player.lock_target = null
	player.shortcut_arrival_cd = 0.0
	player.shortcut_dwell = 0.0
	player.global_position = Vector3(0.0, 1.6, 0.0)
	t9_story.story_flags.erase("shortcut_blame_unlocked")
	t9_story.save_state()
	combat.player_habits.clear()
	combat.reset_duel()
	player.data_store.tuning["boss_phase2_enabled"] = true
	player.data_store.tuning["boss_phase2_speed_mult"] = 1.22

	# --- 23. V6 Task 4: Dark Seinen HUD snapshot ----------------------------
	player.data_store.reset_tuning()
	check(CombatData.TUNING_BOOLS.has("seinen_hud_enabled") and CombatData.TUNING_DEFAULTS.has("seinen_hud_enabled") and bool(CombatData.TUNING_DEFAULTS["seinen_hud_enabled"]), "seinen_hud_enabled is an auto-generated Tab 8 bool, default on")
	studio.dev_panel.visible = false
	studio.dev_backdrop.visible = false
	studio.fp_mod.set("p5_pause_active", false)
	studio.travel_to_region(0)
	combat.reset_duel()
	player.hp = player.max_hp
	player.hitstun_timer = 0.0
	var t10_hud: Dictionary = studio.get_hud_snapshot()
	check(bool(t10_hud["visible"]), "the Seinen HUD is visible with the studio and pause menu closed")

	# Player cluster numbers.
	player.hp = player.max_hp * 0.5
	check(is_equal_approx(float(studio.get_hud_snapshot()["player"]["hp_ratio"]), 0.5), "the snapshot reports the player HP ratio")
	player.hitstun_timer = 0.18
	var t10_guard: float = float(studio.get_hud_snapshot()["player"]["posture_ratio"])
	check(t10_guard > 0.0 and t10_guard < 1.0, "the player guard ratio dips while reeling from a hit")
	player.hitstun_timer = 0.0
	player.hp = player.max_hp
	combat.combo_hits = 4
	check(int(studio.get_hud_snapshot()["player"]["combo"]) == 4, "the snapshot carries the combo count")

	# Boss cluster numbers, phase and telegraph.
	var t10_rival: Node3D = combat.target_stats.keys()[0] as Node3D
	var t10_s: Dictionary = combat.target_stats[t10_rival]
	t10_s["hp"] = float(t10_s["max_hp"]) * 0.5
	t10_s["posture"] = float(t10_s["max_posture"]) * 0.25
	var t10_boss: Dictionary = studio.get_hud_snapshot()["boss"]
	check(bool(t10_boss["present"]) and is_equal_approx(float(t10_boss["hp_ratio"]), 0.5) and is_equal_approx(float(t10_boss["posture_ratio"]), 0.25), "the snapshot reports boss HP and posture ratios")
	check(str(t10_boss["archetype"]) == "INK_DUELIST" and str(t10_boss["name"]).begins_with("KATANA"), "the snapshot carries the regional archetype and rival name")
	combat.apply_damage(t10_rival, 10.0, 0.0, Vector3.ZERO)
	check(int(studio.get_hud_snapshot()["boss"]["phase"]) == 2, "crossing 50% HP shows PHASE II in the HUD snapshot")
	t10_s["telegraph_kind"] = "PARRIABLE"
	check(str(studio.get_hud_snapshot()["boss"]["telegraph_kind"]) == "PARRIABLE", "the snapshot forwards a PARRIABLE wind-up")
	t10_s["telegraph_kind"] = "UNBLOCKABLE"
	check(str(studio.get_hud_snapshot()["boss"]["telegraph_kind"]) == "UNBLOCKABLE", "the snapshot forwards an UNBLOCKABLE slam")
	t10_s["posture"] = float(t10_s["max_posture"]) - 1.0
	combat.apply_damage(t10_rival, 5.0, 60.0, Vector3.ZERO)
	var t10_stag: Dictionary = studio.get_hud_snapshot()["boss"]
	check(bool(t10_stag["staggered"]) and str(t10_stag["telegraph_kind"]) == "NONE" and is_equal_approx(float(t10_stag["posture_ratio"]), 0.0), "a posture break reports staggered with an empty posture bar")

	# World band: region title, gate status and a live dwell ratio.
	var t10_story = studio.story_mgr
	t10_story.story_flags["shortcut_blame_unlocked"] = true
	studio.travel_to_region(0)
	combat.reset_duel()
	player._refresh_shortcut_visuals()
	player.shortcut_arrival_cd = 0.0
	player.shortcut_dwell = 0.0
	player.global_position = Vector3(-36.0, 1.6, -2.0)
	player._tick_shortcut_gates(0.4)
	var t10_world: Dictionary = studio.get_hud_snapshot()["world"]
	check(float(t10_world["gate_dwell_ratio"]) > 0.0 and float(t10_world["gate_dwell_ratio"]) < 1.0, "dwelling in an open gate reports a partial travel bar")
	check(str(t10_world["gate_status"]).begins_with("SHORTCUT OPEN"), "the snapshot forwards the gate status string")
	check(str(t10_world["region_title"]) == "INK CATHEDRAL", "the snapshot carries the readable region title")

	# Visibility rules: the bool, the studio panel and the P5 menu all hide it.
	player.data_store.tuning["seinen_hud_enabled"] = false
	check(not bool(studio.get_hud_snapshot()["visible"]), "seinen_hud_enabled = false hides the HUD")
	player.data_store.tuning["seinen_hud_enabled"] = true
	check(bool(studio.get_hud_snapshot()["visible"]), "re-enabling the bool brings the HUD back")
	studio.dev_panel.visible = true
	check(not bool(studio.get_hud_snapshot()["visible"]), "the full-bleed Dev Studio panel hides the HUD")
	studio.dev_panel.visible = false
	studio.fp_mod.set("p5_pause_active", true)
	check(not bool(studio.get_hud_snapshot()["visible"]), "the P5 pause menu hides the HUD")
	studio.fp_mod.set("p5_pause_active", false)
	check(bool(studio.get_hud_snapshot()["visible"]), "closing both overlays restores the HUD")

	# Leave no V6 Task 4 state behind.
	player.data_store.tuning["seinen_hud_enabled"] = true
	player.shortcut_arrival_cd = 0.0
	player.shortcut_dwell = 0.0
	player.shortcut_status = ""
	player.global_position = Vector3(0.0, 1.6, 0.0)
	player.hp = player.max_hp
	player.hitstun_timer = 0.0
	combat.combo_hits = 0
	combat.combo_timer = 0.0
	studio.dev_panel.visible = false
	studio.dev_backdrop.visible = false
	studio.fp_mod.set("p5_pause_active", false)
	t10_story.story_flags.erase("shortcut_blame_unlocked")
	t10_story.save_state()
	studio.travel_to_region(0)
	combat.reset_duel()

	# --- 24. V6 Task 5: procedural Seinen synth cues ------------------------
	player.data_store.reset_tuning()
	check(CombatData.TUNING_BOOLS.has("sfx_enabled") and bool(CombatData.TUNING_DEFAULTS["sfx_enabled"]), "sfx_enabled is an auto-generated Tab 8 bool, default on")
	var t11_vol_spec: Array = CombatData.TUNING_SPEC.get("sfx_volume", [])
	check(t11_vol_spec.size() >= 4 and is_equal_approx(float(t11_vol_spec[0]), 0.0) and is_equal_approx(float(t11_vol_spec[1]), 1.0) and is_equal_approx(float(CombatData.TUNING_DEFAULTS.get("sfx_volume", 0.0)), 0.75), "sfx_volume is a 0.0-1.0 Tab 8 slider defaulting to 0.75")
	player._push_fx_budget()
	var t11_vfx = player.dash_vfx
	check(bool(t11_vfx.sfx_enabled_flag) and is_equal_approx(float(t11_vfx.sfx_volume_linear), 0.75), "the player pushes the Tab 8 SFX state into the synth host")

	# Every V6 cue bakes a real buffer with no audio device present.
	var t11_cues: Array[String] = ["boss_awaken", "unblockable_warn", "stagger_break", "stagger_finisher", "gate_travel", "gate_sealed", "wall_kick"]
	var t11_buffer_bad := 0
	for c in t11_cues:
		if not t11_vfx.has_synth_cue(c) or t11_vfx.synth_frame_count(c) < 256 or t11_vfx.synth_peak(c) <= 0.01:
			t11_buffer_bad += 1
	check(t11_buffer_bad == 0, "every V6 cue bakes a valid, non-silent frame buffer (headless, no audio device)")

	# Bookkeeping + mute switch + dB volume.
	var t11_before: int = t11_vfx.sfx_play_count
	t11_vfx.play_sfx(t11_vfx.SFX_BOSS_AWAKEN)
	check(t11_vfx.sfx_play_count == t11_before + 1 and t11_vfx.last_sfx_cue == "boss_awaken" and t11_vfx.sfx_history.has("boss_awaken"), "a played cue records its name, play count and history")
	player.data_store.tuning["sfx_enabled"] = false
	player._push_fx_budget()
	t11_vfx.sfx_history.clear()
	t11_vfx.play_sfx(t11_vfx.SFX_STAGGER_BREAK)
	check(t11_vfx.sfx_play_count == t11_before + 1 and t11_vfx.last_sfx_cue == "boss_awaken" and t11_vfx.sfx_history.is_empty(), "sfx_enabled = false plays nothing and never increments the count")
	player.data_store.tuning["sfx_enabled"] = true
	player.data_store.tuning["sfx_volume"] = 0.5
	player._push_fx_budget()
	check(is_equal_approx(float(t11_vfx.sfx_volume_linear), 0.5) and is_equal_approx(t11_vfx.synth_volume_db(), linear_to_db(0.5)), "sfx_volume reaches the host and converts to dB with linear_to_db")
	player.data_store.tuning["sfx_volume"] = 0.75
	player._push_fx_budget()

	# Phase 2 awakening: BOSS_AWAKEN + a camera kick with no hitstop freeze.
	studio.travel_to_region(0)
	combat.reset_duel()
	var t11_rival: Node3D = combat.target_stats.keys()[0] as Node3D
	var t11_s: Dictionary = combat.target_stats[t11_rival]
	t11_vfx.sfx_history.clear()
	t11_s["hp"] = float(t11_s["max_hp"]) * 0.52
	combat.apply_damage(t11_rival, float(t11_s["max_hp"]) * 0.1, 0.0, Vector3.ZERO)
	check(t11_vfx.sfx_history.has("boss_awaken") and int(t11_s["boss_phase"]) == 2, "the phase 2 awakening fires BOSS_AWAKEN")
	player.cam_shake_trauma = 0.0
	player.hitstop_timer = 0.0
	t11_vfx.sfx_history.clear()
	combat._awaken_phase_two(t11_rival, t11_s)
	check(t11_vfx.sfx_history.has("boss_awaken") and float(player.cam_shake_trauma) > 0.0 and is_equal_approx(float(player.hitstop_timer), 0.0), "the awakening kicks the camera without freezing the boss mid-transition")

	# Telegraph sting: only the unblockable wind-up warns.
	t11_s["boss_phase"] = 2
	t11_s["phase2_attack"] = "SLAM"
	t11_s["telegraph_seq"] = 1
	t11_vfx.sfx_history.clear()
	combat._begin_telegraph(t11_s, t11_rival)
	check(str(t11_s["telegraph_kind"]) == "UNBLOCKABLE" and t11_vfx.sfx_history.has("unblockable_warn"), "an UNBLOCKABLE wind-up fires UNBLOCKABLE_WARN")
	t11_s["telegraph_seq"] = 2
	t11_vfx.sfx_history.clear()
	combat._begin_telegraph(t11_s, t11_rival)
	check(str(t11_s["telegraph_kind"]) == "PARRIABLE" and t11_vfx.sfx_history.is_empty(), "a PARRIABLE wind-up stays silent")

	# Posture break crack, then the finisher's heavier cue.
	t11_s["ai_state"] = combat.AIState.IDLE
	t11_s["posture"] = float(t11_s["max_posture"]) - 1.0
	t11_vfx.sfx_history.clear()
	combat.apply_damage(t11_rival, 1.0, 40.0, Vector3.ZERO)
	check(int(t11_s["ai_state"]) == combat.AIState.STAGGERED and t11_vfx.sfx_history.has("stagger_break"), "a posture break fires STAGGER_BREAK")
	player.lock_target = t11_rival
	player.is_locked_on = true
	player.global_position = t11_rival.global_position + Vector3(0.0, 0.0, 2.6)
	player.velocity = Vector3.ZERO
	player.state = PlayerController.MoveState.GROUND
	player.cam_shake_trauma = 0.0
	player.hitstop_timer = 0.0
	t11_vfx.sfx_history.clear()
	combat._commit_strike(Vector2(0.0, 1.0))
	check(t11_vfx.sfx_history.has("stagger_finisher") and float(player.cam_shake_trauma) > 0.0 and float(player.hitstop_timer) > 0.0, "the stagger finisher fires STAGGER_FINISHER with hitstop and a camera kick")

	# Sealed gate: one thud, then the 1.2 s cooldown, then allowed again.
	var t11_story = studio.story_mgr
	t11_story.story_flags.erase("shortcut_blame_unlocked")
	studio.travel_to_region(0)
	combat.reset_duel()
	player._refresh_shortcut_visuals()
	player.shortcut_sealed_sfx_cd = 0.0
	player.shortcut_arrival_cd = 0.0
	player.shortcut_dwell = 0.0
	player.global_position = Vector3(-36.0, 1.6, -2.0)
	var t11_sealed: int = t11_vfx.sfx_play_count
	player._tick_shortcut_gates(1.0 / 60.0)
	check(t11_vfx.sfx_play_count == t11_sealed + 1 and t11_vfx.last_sfx_cue == "gate_sealed", "bumping a sealed gate fires GATE_SEALED once")
	for i in range(6):
		player._tick_shortcut_gates(1.0 / 60.0)
	check(t11_vfx.sfx_play_count == t11_sealed + 1, "... and the 1.2 s cooldown silences every later physics tick")
	player._tick_shortcut_gates(1.3)
	check(t11_vfx.sfx_play_count == t11_sealed + 2, "... while the thud is allowed again after 1.2 s")

	# Open gate travel chime.
	t11_story.story_flags["shortcut_blame_unlocked"] = true
	player._refresh_shortcut_visuals()
	player.shortcut_arrival_cd = 0.0
	player.shortcut_dwell = 0.0
	player.global_position = Vector3(-36.0, 1.6, -2.0)
	t11_vfx.sfx_history.clear()
	player._tick_shortcut_gates(1.0)
	check(int(studio.region_idx) == 1 and t11_vfx.sfx_history.has("gate_travel"), "completing open gate travel fires GATE_TRAVEL")

	# Wall kick-off and auto ledge-vault.
	combat.reset_duel()
	player.is_wall_running = true
	player.wall_run_normal = Vector3(1.0, 0.0, 0.0)
	player.state = PlayerController.MoveState.AIR
	t11_vfx.sfx_history.clear()
	player._trigger_jump()
	check(not player.is_wall_running and t11_vfx.sfx_history.has("wall_kick"), "a wall-run jump kick-off fires WALL_KICK")
	player.wall_run_normal = Vector3(1.0, 0.0, 0.0)
	player.wall_run_forward = Vector3(1.0, 0.0, 0.0)
	t11_vfx.sfx_history.clear()
	player._vault_onto_ledge()
	check(t11_vfx.sfx_history.has("wall_kick"), "an auto ledge-vault fires the same WALL_KICK burst")

	# Leave no V6 Task 5 state behind.
	player.wall_run_normal = Vector3.ZERO
	player.wall_run_forward = Vector3.ZERO
	player.is_wall_running = false
	player.state = PlayerController.MoveState.GROUND
	player.is_locked_on = false
	player.lock_target = null
	player.cam_shake_trauma = 0.0
	player.hitstop_timer = 0.0
	player.shortcut_sealed_sfx_cd = 0.0
	player.shortcut_arrival_cd = 0.0
	player.shortcut_dwell = 0.0
	player.global_position = Vector3(0.0, 1.6, 0.0)
	t11_story.story_flags.erase("shortcut_blame_unlocked")
	t11_story.save_state()
	player.data_store.tuning["sfx_enabled"] = true
	player.data_store.tuning["sfx_volume"] = 0.75
	player._push_fx_budget()
	t11_vfx.sfx_history.clear()
	studio.travel_to_region(0)
	combat.reset_duel()

	# Leave no test tuning behind for the next run.
	player.data_store.reset_tuning()
	player.data_store.refresh_auto_quality()
	player.apply_quality_tier()
	player.data_store.save_to_disk(player, combat)
	combat.reset_duel()

func _finish() -> void:
	Engine.time_scale = 1.0
	if failures.is_empty():
		print("COMBAT_TEST_PASS")
		quit(0)
	else:
		print("COMBAT_TEST_FAIL: %d check(s) failed" % failures.size())
		quit(1)
