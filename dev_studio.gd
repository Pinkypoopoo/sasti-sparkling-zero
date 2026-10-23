class_name DevStudio
extends Control

@export var player_node_path: NodePath = NodePath("../Player")
@export var combat_node_path: NodePath = NodePath("../CombatManager")

@onready var player: PlayerController = get_node_or_null(player_node_path) as PlayerController
@onready var combat: GestureCombat = get_node_or_null(combat_node_path) as GestureCombat

# --- UI Containers ---
var telemetry_label: Label = null
var top_action_bar: HBoxContainer = null
var dev_panel: PanelContainer = null
var tab_container: TabContainer = null
var is_panel_open: bool = false

# --- Hardware GPU Telemetry ---
var gpu_ms: float = 0.0
var cpu_ms: float = 0.0
var phys_ms: float = 0.0
var fps: int = 0
var vsync_mode_idx: int = 0

func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_build_ui_layout()
	_load_profile()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			toggle_dev_panel()

func toggle_dev_panel() -> void:
	is_panel_open = not is_panel_open
	if dev_panel:
		dev_panel.visible = is_panel_open
	if is_panel_open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _process(delta: float) -> void:
	gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	cpu_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	phys_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	fps = Engine.get_frames_per_second()

	if telemetry_label:
		telemetry_label.text = "FPS: %d | GPU: %.2f ms | CPU: %.2f ms | PHYS: %.2f ms" % [fps, gpu_ms, cpu_ms, phys_ms]

	queue_redraw()

func _build_ui_layout() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0

	# Top-Left Telemetry Label
	telemetry_label = Label.new()
	telemetry_label.position = Vector2(16, 12)
	telemetry_label.add_theme_color_override("font_color", Color(0.2, 0.95, 0.7))
	add_child(telemetry_label)

	# Top-Right Quick Action Bar
	top_action_bar = HBoxContainer.new()
	top_action_bar.anchor_left = 1.0
	top_action_bar.anchor_right = 1.0
	top_action_bar.offset_left = -660.0
	top_action_bar.offset_top = 10.0
	top_action_bar.offset_right = -16.0
	top_action_bar.offset_bottom = 44.0
	top_action_bar.alignment = BoxContainer.ALIGNMENT_END
	add_child(top_action_bar)

	_add_quick_btn("CAST WEAVE (C)", func():
		if combat:
			combat.is_spell_weave_mode = not combat.is_spell_weave_mode
	)
	_add_quick_btn("SIM CLASH (P)", func():
		if combat:
			combat.simulate_clash(false)
	)
	_add_quick_btn("FPS: VSYNC", func():
		_cycle_vsync()
	)
	_add_quick_btn("LOCK (Q)", func():
		if player:
			player.toggle_lock_on()
	)
	_add_quick_btn("FLY (F)", func():
		if player:
			player.state = PlayerController.MoveState.FLIGHT if player.state != PlayerController.MoveState.FLIGHT else PlayerController.MoveState.GROUND
	)
	_add_quick_btn("DEV (Tab)", func():
		toggle_dev_panel()
	)

	# Main 4-Tab Dev Studio Panel
	dev_panel = PanelContainer.new()
	dev_panel.anchor_left = 0.5
	dev_panel.anchor_top = 0.5
	dev_panel.anchor_right = 0.5
	dev_panel.anchor_bottom = 0.5
	dev_panel.offset_left = -380.0
	dev_panel.offset_top = -240.0
	dev_panel.offset_right = 380.0
	dev_panel.offset_bottom = 260.0
	dev_panel.visible = false
	add_child(dev_panel)

	var panel_vbox := VBoxContainer.new()
	dev_panel.add_child(panel_vbox)

	var title_bar := HBoxContainer.new()
	var title_lbl := Label.new()
	title_lbl.text = "  AEGIS LABYRINTH - DEV STUDIO"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = " X "
	close_btn.pressed.connect(func(): toggle_dev_panel())
	title_bar.add_child(close_btn)
	panel_vbox.add_child(title_bar)

	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_vbox.add_child(tab_container)

	_build_tab_physics()
	_build_tab_gestures()
	_build_tab_importer()
	_build_tab_visuals()

	# Bottom Profile Actions Bar
	var bot_bar := HBoxContainer.new()
	panel_vbox.add_child(bot_bar)

	var save_btn := Button.new()
	save_btn.text = " Save Profile & Copy JSON "
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(func(): _save_profile())
	bot_bar.add_child(save_btn)

	var reset_btn := Button.new()
	reset_btn.text = " Reset Defaults "
	reset_btn.pressed.connect(func(): _reset_defaults())
	bot_bar.add_child(reset_btn)

func _add_quick_btn(label: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(callback)
	top_action_bar.add_child(btn)

func _cycle_vsync() -> void:
	vsync_mode_idx = (vsync_mode_idx + 1) % 4
	match vsync_mode_idx:
		0: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		1: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		2: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		3: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)

# --- Direct HSlider + SpinBox Synchronization ---
func _add_tuner_row(parent: Control, label_text: String, min_v: float, max_v: float, step_v: float, default_v: float, callback: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(170, 0)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = default_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step_v
	spin.value = default_v
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.custom_minimum_size = Vector2(90, 0)
	row.add_child(spin)

	var is_updating: Array[bool] = [false]
	slider.value_changed.connect(func(v: float):
		if is_updating[0]: return
		is_updating[0] = true
		spin.value = v
		callback.call(v)
		is_updating[0] = false
	)
	spin.value_changed.connect(func(v: float):
		if is_updating[0]: return
		is_updating[0] = true
		slider.value = v
		callback.call(v)
		is_updating[0] = false
	)

	parent.add_child(row)
	return row

func _build_tab_physics() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Physics & Race"
	tab_container.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Race Selection
	var race_row := HBoxContainer.new()
	var race_lbl := Label.new()
	race_lbl.text = "Player Race:"
	race_lbl.custom_minimum_size = Vector2(170, 0)
	race_row.add_child(race_lbl)

	var race_opt := OptionButton.new()
	race_opt.add_item("Human Touki", PlayerController.Race.HUMAN_TOUKI)
	race_opt.add_item("Demon Fiend", PlayerController.Race.DEMON_FIEND)
	race_opt.add_item("Beastkin Vanguard", PlayerController.Race.BEASTKIN_VANGUARD)
	race_opt.add_item("Elf Caster", PlayerController.Race.ELF_CASTER)
	race_opt.selected = player.current_race if player else 0
	race_opt.item_selected.connect(func(idx: int):
		if player:
			player.apply_race_stats(idx as PlayerController.Race)
	)
	race_row.add_child(race_opt)
	vbox.add_child(race_row)

	_add_tuner_row(vbox, "Run Speed", 4.0, 40.0, 0.5, player.run_speed if player else 16.0, func(v): if player: player.run_speed = v)
	_add_tuner_row(vbox, "Sprint Speed", 10.0, 60.0, 0.5, player.sprint_speed if player else 28.0, func(v): if player: player.sprint_speed = v)
	_add_tuner_row(vbox, "Flight Speed", 10.0, 80.0, 0.5, player.flight_speed if player else 32.0, func(v): if player: player.flight_speed = v)
	_add_tuner_row(vbox, "Step Speed", 10.0, 70.0, 0.5, player.step_speed if player else 34.0, func(v): if player: player.step_speed = v)
	_add_tuner_row(vbox, "Dash Speed", 20.0, 100.0, 1.0, player.dash_speed if player else 54.0, func(v): if player: player.dash_speed = v)
	_add_tuner_row(vbox, "Dash Duration", 0.08, 0.6, 0.01, player.dash_duration if player else 0.22, func(v): if player: player.dash_duration = v)
	_add_tuner_row(vbox, "Dash Cooldown", 0.0, 0.4, 0.01, player.dash_cooldown if player else 0.04, func(v): if player: player.dash_cooldown = v)
	_add_tuner_row(vbox, "Jump Velocity", 4.0, 30.0, 0.5, player.jump_velocity if player else 12.0, func(v): if player: player.jump_velocity = v)
	_add_tuner_row(vbox, "Altitude Burst", 6.0, 40.0, 0.5, player.altitude_burst if player else 18.0, func(v): if player: player.altitude_burst = v)
	_add_tuner_row(vbox, "Camera Distance", 1.5, 12.0, 0.2, player.camera_distance if player else 4.0, func(v): if player: player.camera_distance = v)
	_add_tuner_row(vbox, "Base FOV", 50.0, 110.0, 1.0, player.base_fov if player else 78.0, func(v): if player: player.base_fov = v)
	_add_tuner_row(vbox, "Dash FOV Kick", 60.0, 125.0, 1.0, player.dash_fov_kick if player else 98.0, func(v): if player: player.dash_fov_kick = v)
	_add_tuner_row(vbox, "Shake Intensity", 0.0, 3.0, 0.1, player.shake_intensity if player else 1.0, func(v): if player: player.shake_intensity = v)

func _build_tab_gestures() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Gesture & Moves"
	tab_container.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var move_opt := OptionButton.new()
	if combat:
		for k in combat.action_table.keys():
			move_opt.add_item(k)
	vbox.add_child(move_opt)

	var dynamic_rows := VBoxContainer.new()
	vbox.add_child(dynamic_rows)

	var refresh_move_fields := func(move_name: String):
		for c in dynamic_rows.get_children():
			c.queue_free()
		if not combat or not combat.action_table.has(move_name):
			return
		var d: Dictionary = combat.action_table[move_name]
		_add_tuner_row(dynamic_rows, "Step Force", 0.0, 50.0, 1.0, d.get("step_force", 12.0), func(v): d["step_force"] = v)
		_add_tuner_row(dynamic_rows, "Lunge Force", 0.0, 60.0, 1.0, d.get("lunge_force", 14.0), func(v): d["lunge_force"] = v)
		_add_tuner_row(dynamic_rows, "Vertical Lift", -20.0, 20.0, 1.0, d.get("vertical_lift", 0.0), func(v): d["vertical_lift"] = v)
		_add_tuner_row(dynamic_rows, "Damage", 10.0, 500.0, 5.0, d.get("damage", 85.0), func(v): d["damage"] = v)
		_add_tuner_row(dynamic_rows, "Posture Damage", 5.0, 250.0, 5.0, d.get("posture_damage", 35.0), func(v): d["posture_damage"] = v)

	move_opt.item_selected.connect(func(idx: int):
		refresh_move_fields.call(move_opt.get_item_text(idx))
	)
	if move_opt.item_count > 0:
		refresh_move_fields.call(move_opt.get_item_text(0))

func _build_tab_importer() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "3D Model Importer"
	tab_container.add_child(vbox)

	var scan_row := HBoxContainer.new()
	var scan_btn := Button.new()
	scan_btn.text = "Scan Models (.glb/.gltf)"
	scan_row.add_child(scan_btn)

	var models_opt := OptionButton.new()
	models_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scan_row.add_child(models_opt)
	vbox.add_child(scan_row)

	var path_row := HBoxContainer.new()
	var path_edit := LineEdit.new()
	path_edit.placeholder_text = "res://models/character.glb or user://..."
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_child(path_edit)

	var load_btn := Button.new()
	load_btn.text = " Load 3D Model "
	load_btn.pressed.connect(func():
		if player:
			player.swap_custom_model(path_edit.text)
	)
	path_row.add_child(load_btn)
	vbox.add_child(path_row)

	_add_tuner_row(vbox, "Model Scale", 0.1, 5.0, 0.05, player.model_scale if player else 1.0, func(v):
		if player:
			player.model_scale = v
			if player.custom_model_root:
				player.custom_model_root.scale = Vector3.ONE * v
	)
	_add_tuner_row(vbox, "Model Rot Offset", -180.0, 180.0, 5.0, player.model_rot_offset if player else 0.0, func(v):
		if player:
			player.model_rot_offset = v
			if player.custom_model_root:
				player.custom_model_root.rotation.y = deg_to_rad(v)
	)

func _build_tab_visuals() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "Anime Visuals & Clash"
	tab_container.add_child(vbox)

	_add_tuner_row(vbox, "Cel Cut Threshold", 0.1, 0.9, 0.02, player.cel_cut_threshold if player else 0.45, func(v):
		if player:
			player.update_cel_shader(v, player.outline_width, player.rim_strength)
	)
	_add_tuner_row(vbox, "Outline Width", 0.005, 0.1, 0.002, player.outline_width if player else 0.025, func(v):
		if player:
			player.update_cel_shader(player.cel_cut_threshold, v, player.rim_strength)
	)
	_add_tuner_row(vbox, "Rim Strength", 0.0, 2.5, 0.05, player.rim_strength if player else 0.8, func(v):
		if player:
			player.update_cel_shader(player.cel_cut_threshold, player.outline_width, v)
	)
	_add_tuner_row(vbox, "Feint Threshold Px", 40.0, 200.0, 5.0, player.feint_threshold_px if player else 95.0, func(v):
		if player:
			player.feint_threshold_px = v
	)
	_add_tuner_row(vbox, "Impact Frame CD", 1.0, 20.0, 0.5, 8.0, func(v):
		if combat:
			combat.impact_frame_cooldown = v
	)

	var reset_dummies_btn := Button.new()
	reset_dummies_btn.text = " Reset Target Dummies (HP & Posture) "
	reset_dummies_btn.pressed.connect(func():
		if combat:
			combat._init_target_dummies()
	)
	vbox.add_child(reset_dummies_btn)

func _draw() -> void:
	_draw_impact_stencil()
	_draw_spell_weave_pentagon()
	_draw_player_hud()
	_draw_enemy_hud()

func _draw_impact_stencil() -> void:
	if combat and combat.impact_flash_timer > 0.0:
		var rect := get_viewport_rect()
		# Stark 2-frame Black & White High Contrast Impact Stencil
		draw_rect(rect, Color(0.02, 0.02, 0.03, 0.96))
		var center := rect.size * 0.5
		for i in range(16):
			var a := float(i) * (TAU / 16.0)
			var p1 := center + Vector2(cos(a), sin(a)) * 60.0
			var p2 := center + Vector2(cos(a), sin(a)) * rect.size.x
			draw_line(p1, p2, Color(1.0, 1.0, 1.0, 0.85), 3.0)

func _draw_spell_weave_pentagon() -> void:
	if not combat or not combat.is_spell_weave_mode:
		return

	var vp_size := get_viewport_rect().size
	var center := Vector2(vp_size.x * 0.74, vp_size.y * 0.54)
	var radius: float = minf(vp_size.x, vp_size.y) * 0.20

	# Background darkened rune circle
	draw_circle(center, radius * 1.35, Color(0.04, 0.05, 0.08, 0.75))
	draw_arc(center, radius, 0.0, TAU, 32, Color(0.4, 0.5, 0.7, 0.4), 2.0)

	var node_positions: Array[Vector2] = []
	for i in range(5):
		var a := -PI * 0.5 + float(i) * (TAU / 5.0)
		var p := center + Vector2(cos(a), sin(a)) * radius
		node_positions.append(p)

	# Pentagon and Star connectors
	for i in range(5):
		var next_idx := (i + 1) % 5
		var star_idx := (i + 2) % 5
		draw_line(node_positions[i], node_positions[next_idx], Color(0.3, 0.4, 0.6, 0.35), 1.5)
		draw_line(node_positions[i], node_positions[star_idx], Color(0.2, 0.3, 0.5, 0.2), 1.0)

	# Fused link line if two elements selected
	if combat.selected_element_1 >= 0 and combat.selected_element_2 >= 0:
		var p1: Vector2 = node_positions[combat.selected_element_1]
		var p2: Vector2 = node_positions[combat.selected_element_2]
		draw_line(p1, p2, Color(1.0, 0.95, 0.4, 0.9), 4.0)

	# Drag line if currently holding
	if combat.is_right_touch and combat.selected_element_1 >= 0:
		var p1: Vector2 = node_positions[combat.selected_element_1]
		draw_line(p1, combat.touch_current, Color(0.3, 0.9, 1.0, 0.8), 2.5)

	# Draw nodes
	for i in range(5):
		var p: Vector2 = node_positions[i]
		var col: Color = GestureCombat.ELEMENT_COLORS[i]
		var is_sel: bool = (i == combat.selected_element_1 or i == combat.selected_element_2)
		draw_circle(p, 28.0 if is_sel else 22.0, col if is_sel else col.darkened(0.3))
		draw_arc(p, 28.0 if is_sel else 22.0, 0.0, TAU, 24, Color.WHITE if is_sel else col, 2.5)
		draw_string(ThemeDB.fallback_font, p + Vector2(-16, 5), GestureCombat.ELEMENTS[i].substr(0, 3), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)

	# Display Active Fusion Element Banner
	if not combat.active_element.is_empty() and combat.active_element != "NONE":
		draw_string(ThemeDB.fallback_font, center + Vector2(-90, radius * 1.25), "FUSION: " + combat.active_element, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(1.0, 0.85, 0.3))

func _draw_player_hud() -> void:
	if not player:
		return

	var base_pos := Vector2(24, get_viewport_rect().size.y - 64)
	# HP Bar
	var hp_ratio := clampf(player.hp / player.max_hp, 0.0, 1.0)
	draw_rect(Rect2(base_pos, Vector2(220, 18)), Color(0.08, 0.09, 0.12, 0.9))
	draw_rect(Rect2(base_pos + Vector2(2, 2), Vector2(216 * hp_ratio, 14)), Color(0.18, 0.78, 0.42))
	draw_string(ThemeDB.fallback_font, base_pos + Vector2(6, 13), "HP %d / %d" % [int(player.hp), int(player.max_hp)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

	# Touki / Mana Bar
	var mana_pos := base_pos + Vector2(0, 22)
	var mana_ratio := clampf(player.mana / player.max_mana, 0.0, 1.0)
	draw_rect(Rect2(mana_pos, Vector2(180, 12)), Color(0.08, 0.09, 0.12, 0.9))
	draw_rect(Rect2(mana_pos + Vector2(2, 2), Vector2(176 * mana_ratio, 8)), Color(0.2, 0.6, 0.98))
	draw_string(ThemeDB.fallback_font, mana_pos + Vector2(6, 9), "TOUKI %d / %d" % [int(player.mana), int(player.max_mana)], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)

	# Race & Infusion Badge
	var badge_str := "%s | INFUSION: %s" % [PlayerController.Race.keys()[player.current_race], combat.active_infusion if combat else "NONE"]
	draw_string(ThemeDB.fallback_font, base_pos + Vector2(0, -8), badge_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.9, 1.0))

func _draw_enemy_hud() -> void:
	if not combat or not player or not player.camera:
		return

	var cam := player.camera
	for dummy in combat.target_stats.keys():
		if is_instance_valid(dummy) and dummy is Node3D:
			if cam.is_position_behind(dummy.global_position):
				continue

			var screen_pos := cam.unproject_position(dummy.global_position + Vector3(0, 2.1, 0))
			if get_viewport_rect().has_point(screen_pos):
				var s: Dictionary = combat.target_stats[dummy]
				var hp_ratio := clampf(s["hp"] / s["max_hp"], 0.0, 1.0)
				var post_ratio := clampf(s["posture"] / s["max_posture"], 0.0, 1.0)

				# Mini Floating Bar
				var bar_w := 70.0
				var p := screen_pos - Vector2(bar_w * 0.5, 0)
				draw_rect(Rect2(p, Vector2(bar_w, 7)), Color(0.05, 0.05, 0.07, 0.85))
				draw_rect(Rect2(p + Vector2(1, 1), Vector2((bar_w - 2.0) * hp_ratio, 5)), Color(0.85, 0.22, 0.22))

				var post_p := p + Vector2(0, 8)
				draw_rect(Rect2(post_p, Vector2(bar_w, 4)), Color(0.05, 0.05, 0.07, 0.85))
				draw_rect(Rect2(post_p + Vector2(1, 1), Vector2((bar_w - 2.0) * post_ratio, 2)), Color(0.95, 0.75, 0.18))

	# Prominent Boss Bar if Locked On
	if player.is_locked_on and is_instance_valid(player.lock_target) and combat.target_stats.has(player.lock_target):
		var bs: Dictionary = combat.target_stats[player.lock_target]
		var boss_w := 460.0
		var boss_pos := Vector2((get_viewport_rect().size.x - boss_w) * 0.5, 48.0)
		var b_hp_r := clampf(bs["hp"] / bs["max_hp"], 0.0, 1.0)
		var b_post_r := clampf(bs["posture"] / bs["max_posture"], 0.0, 1.0)

		draw_string(ThemeDB.fallback_font, boss_pos + Vector2(0, -6), "ABYSSAL TRAINING SENTINEL", HORIZONTAL_ALIGNMENT_CENTER, int(boss_w), 13, Color(1.0, 0.9, 0.9))
		draw_rect(Rect2(boss_pos, Vector2(boss_w, 16)), Color(0.06, 0.06, 0.08, 0.95))
		draw_rect(Rect2(boss_pos + Vector2(2, 2), Vector2((boss_w - 4.0) * b_hp_r, 12)), Color(0.85, 0.18, 0.22))

		var boss_post_p := boss_pos + Vector2(0, 18)
		draw_rect(Rect2(boss_post_p, Vector2(boss_w, 6)), Color(0.06, 0.06, 0.08, 0.95))
		draw_rect(Rect2(boss_post_p + Vector2(2, 1), Vector2((boss_w - 4.0) * b_post_r, 4)), Color(0.98, 0.8, 0.2))

# --- Profile Persistence ---
func _save_profile() -> void:
	if not player or not combat:
		return
	var data := {
		"race": player.current_race,
		"run_speed": player.run_speed,
		"sprint_speed": player.sprint_speed,
		"flight_speed": player.flight_speed,
		"step_speed": player.step_speed,
		"dash_speed": player.dash_speed,
		"jump_velocity": player.jump_velocity,
		"base_fov": player.base_fov,
		"dash_fov_kick": player.dash_fov_kick,
		"cel_cut_threshold": player.cel_cut_threshold,
		"outline_width": player.outline_width,
		"rim_strength": player.rim_strength,
		"action_table": combat.action_table
	}
	var json_str := JSON.stringify(data, "  ")
	var f := FileAccess.open("user://dev_profile.json", FileAccess.WRITE)
	if f:
		f.store_string(json_str)
		f.close()
	var f_res := FileAccess.open("res://dev_profile.json", FileAccess.WRITE)
	if f_res:
		f_res.store_string(json_str)
		f_res.close()
	DisplayServer.clipboard_set(json_str)

func _load_profile() -> void:
	var path := "user://dev_profile.json"
	if not FileAccess.file_exists(path):
		path = "res://dev_profile.json"
	if not FileAccess.file_exists(path):
		return

	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return
	var json_str := f.get_as_text()
	f.close()

	var json := JSON.new()
	if json.parse(json_str) == OK and json.data is Dictionary:
		var d: Dictionary = json.data
		if player:
			if d.has("race"): player.apply_race_stats(d["race"] as PlayerController.Race)
			if d.has("run_speed"): player.run_speed = d["run_speed"]
			if d.has("sprint_speed"): player.sprint_speed = d["sprint_speed"]
			if d.has("flight_speed"): player.flight_speed = d["flight_speed"]
			if d.has("step_speed"): player.step_speed = d["step_speed"]
			if d.has("dash_speed"): player.dash_speed = d["dash_speed"]
			if d.has("jump_velocity"): player.jump_velocity = d["jump_velocity"]
			if d.has("base_fov"): player.base_fov = d["base_fov"]
			if d.has("dash_fov_kick"): player.dash_fov_kick = d["dash_fov_kick"]
			if d.has("cel_cut_threshold"): player.cel_cut_threshold = d["cel_cut_threshold"]
			if d.has("outline_width"): player.outline_width = d["outline_width"]
			if d.has("rim_strength"): player.rim_strength = d["rim_strength"]
			player.update_cel_shader(player.cel_cut_threshold, player.outline_width, player.rim_strength)
		if combat and d.has("action_table") and d["action_table"] is Dictionary:
			combat.action_table = d["action_table"]

func _reset_defaults() -> void:
	if player:
		player.run_speed = 16.0
		player.sprint_speed = 28.0
		player.flight_speed = 32.0
		player.step_speed = 34.0
		player.dash_speed = 54.0
		player.base_fov = 78.0
		player.dash_fov_kick = 98.0
		player.cel_cut_threshold = 0.45
		player.outline_width = 0.025
		player.rim_strength = 0.8
		player.apply_race_stats(PlayerController.Race.HUMAN_TOUKI)
		player.update_cel_shader(0.45, 0.025, 0.8)
