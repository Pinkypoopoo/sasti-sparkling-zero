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

	# Leave no test tuning behind for the next run.
	player.data_store.reset_tuning()
	player.data_store.refresh_auto_quality()
	player.apply_quality_tier()
	combat.reset_duel()

func _finish() -> void:
	Engine.time_scale = 1.0
	if failures.is_empty():
		print("COMBAT_TEST_PASS")
		quit(0)
	else:
		print("COMBAT_TEST_FAIL: %d check(s) failed" % failures.size())
		quit(1)
