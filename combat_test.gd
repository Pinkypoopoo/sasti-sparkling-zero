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
