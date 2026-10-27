class_name DevStudio
extends Control

@onready var player: PlayerController = get_node_or_null("../Player") as PlayerController
@onready var combat: GestureCombat = get_node_or_null("../CombatManager") as GestureCombat

var telemetry: Label
var action_bar: HBoxContainer
var dev_panel: PanelContainer
var tab_container: TabContainer
var fps_mode_idx: int = 0
var btn_fps: Button
var btn_lock: Button
var btn_ai: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_build_ui()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle_dev_panel()
		elif event.keycode == KEY_ESCAPE:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			elif not DisplayServer.is_touchscreen_available():
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _toggle_dev_panel() -> void:
	dev_panel.visible = not dev_panel.visible
	if dev_panel.visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif not DisplayServer.is_touchscreen_available():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _build_ui() -> void:
	telemetry = Label.new()
	telemetry.position = Vector2(16, 12)
	telemetry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	telemetry.add_theme_color_override("font_color", Color(0.25, 0.98, 0.75))
	telemetry.add_theme_color_override("font_outline_color", Color.BLACK)
	telemetry.add_theme_constant_override("outline_size", 4)
	add_child(telemetry)

	action_bar = HBoxContainer.new()
	action_bar.anchor_left = 1.0
	action_bar.anchor_right = 1.0
	action_bar.offset_left = -740
	action_bar.offset_top = 12
	action_bar.offset_right = -16
	action_bar.offset_bottom = 52
	action_bar.alignment = BoxContainer.ALIGNMENT_END
	action_bar.add_theme_constant_override("separation", 6)
	add_child(action_bar)

	btn_lock = _add_quick_btn("[ LOCK (Q) ]", func(): if player: player.toggle_lock_on())
	_add_quick_btn("[ SWITCH ]", func(): if player: player.cycle_lock_target())
	_add_quick_btn("[ FLY (F) ]", func():
		if player:
			player.state = PlayerController.MoveState.FLIGHT if player.state != PlayerController.MoveState.FLIGHT else PlayerController.MoveState.GROUND
	)
	btn_ai = _add_quick_btn("[ AI: RIVAL ]", func():
		if combat:
			combat.ai_mode = ((combat.ai_mode + 1) % 4) as GestureCombat.AIMode
			btn_ai.text = "[ AI: %s ]" % GestureCombat.AIMode.keys()[combat.ai_mode]
	)
	btn_fps = _add_quick_btn("[ FPS: VSYNC ]", _cycle_fps)
	_add_quick_btn("[ DEV STUDIO (Tab) ]", _toggle_dev_panel)

	dev_panel = PanelContainer.new()
	dev_panel.visible = false
	dev_panel.anchor_left = 0.5
	dev_panel.anchor_top = 0.5
	dev_panel.anchor_right = 0.5
	dev_panel.anchor_bottom = 0.5
	dev_panel.offset_left = -360
	dev_panel.offset_top = -230
	dev_panel.offset_right = 360
	dev_panel.offset_bottom = 230
	add_child(dev_panel)

	var root_vbox := VBoxContainer.new()
	dev_panel.add_child(root_vbox)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "  SASTI SPARKLING ZERO — DEV STUDIO"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_b := Button.new()
	close_b.text = " [ X ] "
	close_b.pressed.connect(_toggle_dev_panel)
	header.add_child(close_b)
	root_vbox.add_child(header)

	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(tab_container)

	_build_tab_physics()
	_build_tab_races()
	_build_tab_gestures()
	_build_tab_models()
	_build_tab_visuals()

func _add_quick_btn(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 36)
	b.pressed.connect(cb)
	action_bar.add_child(b)
	return b

func _cycle_fps() -> void:
	fps_mode_idx = (fps_mode_idx + 1) % 4
	match fps_mode_idx:
		0:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			Engine.max_fps = 0
			Engine.physics_ticks_per_second = 60
			btn_fps.text = "[ FPS: VSYNC ]"
		1:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
			Engine.physics_ticks_per_second = 144
			btn_fps.text = "[ FPS: UNLIMITED ]"
		2:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 144
			Engine.physics_ticks_per_second = 144
			btn_fps.text = "[ FPS: 144Hz ]"
		3:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 165
			Engine.physics_ticks_per_second = 165
			btn_fps.text = "[ FPS: 165Hz ]"

func _make_scroll_tab(tab_name: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = tab_name
	tab_container.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	return vb

func _add_row(parent: Control, obj: Object, prop: String, min_v: float, max_v: float, step_v: float = 0.5) -> void:
	if not obj: return
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := Label.new()
	l.text = prop
	l.custom_minimum_size = Vector2(175, 0)
	h.add_child(l)

	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step_v
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var sp := SpinBox.new()
	sp.min_value = min_v
	sp.max_value = max_v
	sp.step = step_v
	sp.allow_greater = true
	sp.allow_lesser = true
	sp.custom_minimum_size = Vector2(95, 0)

	var init_val: float = float(obj.get(prop)) if obj.get(prop) != null else 0.0
	s.value = init_val
	sp.value = init_val

	var guard: Array[bool] = [false]
	s.value_changed.connect(func(v: float):
		if guard[0]: return
		guard[0] = true
		sp.value = v
		obj.set(prop, v)
		guard[0] = false
	)
	sp.value_changed.connect(func(v: float):
		if guard[0]: return
		guard[0] = true
		s.value = v
		obj.set(prop, v)
		guard[0] = false
	)
	h.add_child(s)
	h.add_child(sp)

func _build_tab_physics() -> void:
	var vb := _make_scroll_tab("1. Physics & Orbs")
	var p_defs := [
		["run_speed", 4.0, 45.0, 0.5], ["sprint_speed", 10.0, 70.0, 0.5],
		["flight_speed", 10.0, 80.0, 0.5], ["dash_speed", 20.0, 120.0, 1.0],
		["dash_duration", 0.05, 0.6, 0.01], ["dash_cooldown", 0.0, 0.5, 0.01],
		["jump_velocity", 5.0, 35.0, 0.5], ["altitude_burst", 5.0, 45.0, 0.5],
		["camera_distance", 1.5, 14.0, 0.2], ["base_fov", 50.0, 115.0, 1.0],
		["camera_sensitivity", 0.05, 1.0, 0.01], ["feint_threshold_px", 40.0, 180.0, 2.0]
	]
	for d in p_defs:
		_add_row(vb, player, d[0], d[1], d[2], d[3])
	_add_row(vb, combat, "right_dot_collapsed_r", 24.0, 90.0, 2.0)
	_add_row(vb, combat, "right_dot_expanded_r", 80.0, 240.0, 5.0)
	_add_row(vb, combat, "left_dot_collapsed_r", 24.0, 90.0, 2.0)
	_add_row(vb, combat, "left_dot_expanded_r", 80.0, 240.0, 5.0)

func _build_tab_races() -> void:
	var vb := _make_scroll_tab("2. Race & Dash Builder")
	var top := HBoxContainer.new()
	vb.add_child(top)
	var r_opt := OptionButton.new()
	r_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if player:
		for k in player.custom_races.keys(): r_opt.add_item(k)
	top.add_child(r_opt)

	var new_name := LineEdit.new()
	new_name.placeholder_text = "New Race Name..."
	new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(new_name)

	var btn_add := Button.new()
	btn_add.text = " + Create/Save Race "
	top.add_child(btn_add)

	var style_row := HBoxContainer.new()
	var s_lbl := Label.new(); s_lbl.text = "Dash Visual Style:"; s_lbl.custom_minimum_size = Vector2(175, 0)
	style_row.add_child(s_lbl)
	var style_opt := OptionButton.new()
	for st in PlayerController.DashStyle.keys(): style_opt.add_item(st)
	style_opt.item_selected.connect(func(idx: int):
		if player:
			player.dash_style = idx as PlayerController.DashStyle
			player.custom_races[player.active_race_name]["dash_style"] = idx
	)
	style_row.add_child(style_opt)
	vb.add_child(style_row)

	r_opt.item_selected.connect(func(idx: int):
		if player:
			player.apply_race_by_name(r_opt.get_item_text(idx))
			style_opt.selected = player.dash_style
	)
	btn_add.pressed.connect(func():
		if not player or new_name.text.strip_edges().is_empty(): return
		var rn := new_name.text.strip_edges()
		player.custom_races[rn] = {
			"max_hp": player.max_hp, "hp_regen": player.hp_regen,
			"max_mana": player.max_mana, "mana_regen": player.mana_regen,
			"physical_strength": player.physical_strength, "base_power": player.base_power,
			"step_mult": player.step_mult, "flight_mult": player.flight_mult,
			"dash_style": player.dash_style, "aura_color": Color(0.4, 0.8, 1.0), "model_path": ""
		}
		r_opt.add_item(rn)
		r_opt.selected = r_opt.item_count - 1
		player.apply_race_by_name(rn)
	)

	var r_defs := [
		["max_hp", 200.0, 5000.0, 50.0], ["hp_regen", 0.0, 100.0, 1.0],
		["max_mana", 20.0, 500.0, 10.0], ["mana_regen", 0.0, 50.0, 1.0],
		["physical_strength", 0.2, 5.0, 0.05], ["base_power", 0.2, 5.0, 0.05],
		["step_mult", 0.5, 3.0, 0.05], ["flight_mult", 0.5, 3.0, 0.05],
		["vanish_strobe_hz", 4.0, 40.0, 1.0]
	]
	for d in r_defs:
		_add_row(vb, player, d[0], d[1], d[2], d[3])

func _build_tab_gestures() -> void:
	var vb := _make_scroll_tab("3. Gesture & VFX Maker")
	var m_opt := OptionButton.new()
	if combat:
		for k in combat.action_table.keys(): m_opt.add_item(k)
	vb.add_child(m_opt)

	var dyn := VBoxContainer.new()
	vb.add_child(dyn)

	var rebuild := func(m_key: String):
		for c in dyn.get_children(): c.queue_free()
		if not combat or not combat.action_table.has(m_key): return
		var entry: Dictionary = combat.action_table[m_key]
		for f in [["step_force", 0.0, 50.0], ["lunge_force", 0.0, 60.0], ["vertical_lift", -30.0, 30.0], ["dmg", 10.0, 600.0], ["posture", 5.0, 300.0]]:
			var row := HBoxContainer.new(); dyn.add_child(row)
			var l := Label.new(); l.text = f[0]; l.custom_minimum_size = Vector2(160, 0); row.add_child(l)
			var sp := SpinBox.new(); sp.min_value = f[1]; sp.max_value = f[2]; sp.step = 1.0; sp.allow_greater = true
			sp.value = entry.get(f[0], 10.0)
			var key_name: String = f[0]
			sp.value_changed.connect(func(v: float): entry[key_name] = v)
			row.add_child(sp)
	m_opt.item_selected.connect(func(i: int): rebuild.call(m_opt.get_item_text(i)))
	if m_opt.item_count > 0: rebuild.call(m_opt.get_item_text(0))

func _build_tab_models() -> void:
	var vb := _make_scroll_tab("4. 3D Model & Jiggle")
	var row := HBoxContainer.new(); vb.add_child(row)
	var p_edit := LineEdit.new()
	p_edit.placeholder_text = "res://models/hero.glb or user://models/hero.glb"
	p_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(p_edit)
	var b_load := Button.new(); b_load.text = " Load .GLB "
	b_load.pressed.connect(func(): if player: player.swap_custom_model(p_edit.text))
	row.add_child(b_load)

	_add_row(vb, player, "model_scale", 0.05, 10.0, 0.05)
	_add_row(vb, player, "model_rot_offset", -180.0, 180.0, 5.0)
	_add_row(vb, player, "jiggle_stiffness", 1.0, 50.0, 0.5)
	_add_row(vb, player, "jiggle_damping", 0.5, 20.0, 0.2)
	_add_row(vb, player, "jiggle_gravity", 0.0, 5.0, 0.1)

func _build_tab_visuals() -> void:
	var vb := _make_scroll_tab("5. Shaders & AI Lab")
	_add_row(vb, player, "cel_cut_threshold", 0.05, 0.95, 0.02)
	_add_row(vb, player, "outline_width", 0.0, 0.08, 0.002)
	_add_row(vb, player, "rim_strength", 0.0, 2.5, 0.05)
	_add_row(vb, combat, "ai_reaction_delay", 0.02, 0.8, 0.02)
	_add_row(vb, combat, "ai_adaptation_rate", 0.05, 1.0, 0.05)
	var rst := Button.new()
	rst.text = " [ Reset Target Dummies & Clear AI Memory ] "
	rst.pressed.connect(func():
		if combat:
			combat._init_targets()
			combat.player_habits.clear()
	)
	vb.add_child(rst)

func _process(_delta: float) -> void:
	if not player or not combat: return
	var fps := Engine.get_frames_per_second()
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	var cpu_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var st_name: String = PlayerController.MoveState.keys()[player.state]
	telemetry.text = "FPS: %d | GPU: %.2f ms | CPU: %.2f ms\nRace: %s | State: %s | Action: %s" % [
		fps, gpu_ms, cpu_ms, player.active_race_name, st_name, combat.last_combat_action
	]
	btn_lock.modulate = Color(0.3, 1.0, 0.5) if player.is_locked_on else Color.WHITE
	queue_redraw()

func _draw() -> void:
	if not player or not combat: return

	# 1. Left Spell Weave Hover Dot & 5-Node Runic Pentagon
	var l_pos := combat.left_dot_pos
	draw_circle(l_pos, combat.left_dot_collapsed_r, Color(0.15, 0.55, 1.0, 0.45))
	draw_arc(l_pos, combat.left_dot_collapsed_r, 0.0, TAU, 32, Color(0.5, 0.85, 1.0, 0.9), 2.5)
	draw_string(ThemeDB.fallback_font, l_pos + Vector2(-18, 5), "SPELL", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)
	if combat.is_left_dot_active:
		draw_circle(l_pos, combat.left_dot_expanded_r, Color(0.05, 0.08, 0.14, 0.78))
		draw_arc(l_pos, combat.left_dot_expanded_r, 0.0, TAU, 48, Color(0.3, 0.8, 1.0, 0.85), 2.5)
		for i in range(5):
			var np := combat.get_pentagon_node_pos(i)
			var is_sel := (i == combat.selected_element_1 or i == combat.selected_element_2)
			draw_circle(np, 24.0 if is_sel else 18.0, GestureCombat.ELEMENT_COLORS[i])
			draw_string(ThemeDB.fallback_font, np + Vector2(-14, 5), GestureCombat.ELEMENTS[i].substr(0, 3), HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color.WHITE)

	# 2. Right Physical Combat Hover Dot & 3-Zone Feint Ring
	var r_pos := combat.right_dot_pos
	var r_open := combat.is_right_dot_active or combat.right_dot_pinned
	draw_circle(r_pos, combat.right_dot_collapsed_r, Color(0.95, 0.22, 0.28, 0.5))
	draw_arc(r_pos, combat.right_dot_collapsed_r, 0.0, TAU, 32, Color(1.0, 0.75, 0.75, 0.95), 2.5)
	draw_string(ThemeDB.fallback_font, r_pos + Vector2(-14, 5), "ATK", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)
	if r_open:
		var center := combat.right_touch_start if combat.is_right_dot_active else r_pos
		draw_circle(center, combat.right_dot_expanded_r, Color(0.08, 0.04, 0.06, 0.55))
		draw_arc(center, 28.0, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 1.5)
		draw_arc(center, player.feint_threshold_px, 0.0, TAU, 48, Color(1.0, 0.85, 0.15, 0.85), 2.5)
		draw_arc(center, combat.right_dot_expanded_r, 0.0, TAU, 48, Color(1.0, 0.3, 0.35, 0.85), 2.5)

	# 3. Bottom-Left Player HP & Touki Bars
	var hud_p := Vector2(20, get_viewport_rect().size.y - 68)
	var hp_r := clampf(player.hp / maxf(1.0, player.max_hp), 0.0, 1.0)
	var mp_r := clampf(player.mana / maxf(1.0, player.max_mana), 0.0, 1.0)
	draw_rect(Rect2(hud_p, Vector2(240, 18)), Color(0.06, 0.07, 0.1, 0.9))
	draw_rect(Rect2(hud_p + Vector2(2, 2), Vector2(236 * hp_r, 14)), Color(0.2, 0.85, 0.45))
	draw_string(ThemeDB.fallback_font, hud_p + Vector2(8, 14), "HP: %d / %d" % [int(player.hp), int(player.max_hp)], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

	var mp_p := hud_p + Vector2(0, 22)
	draw_rect(Rect2(mp_p, Vector2(200, 14)), Color(0.06, 0.07, 0.1, 0.9))
	draw_rect(Rect2(mp_p + Vector2(2, 2), Vector2(196 * mp_r, 10)), Color(0.2, 0.65, 1.0))
	draw_string(ThemeDB.fallback_font, mp_p + Vector2(8, 11), "TOUKI: %d / %d (%s)" % [int(player.mana), int(player.max_mana), combat.active_infusion], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

	# 4. Target Dummy Floating HP + Posture Bars
	for t in combat.target_stats.keys():
		if is_instance_valid(t) and t is Node3D and not player.camera.is_position_behind(t.global_position):
			var sp := player.camera.unproject_position(t.global_position + Vector3(0, 2.2, 0))
			var s: Dictionary = combat.target_stats[t]
			var thp := clampf(s["hp"] / s["max_hp"], 0.0, 1.0)
			var tpo := clampf(s["posture"] / s["max_posture"], 0.0, 1.0)
			draw_rect(Rect2(sp - Vector2(45, 0), Vector2(90, 8)), Color(0.05, 0.05, 0.07, 0.9))
			draw_rect(Rect2(sp - Vector2(44, -1), Vector2(88 * thp, 6)), Color(0.9, 0.2, 0.22))
			draw_rect(Rect2(sp - Vector2(45, -10), Vector2(90, 5)), Color(0.05, 0.05, 0.07, 0.9))
			draw_rect(Rect2(sp - Vector2(44, -9), Vector2(88 * tpo, 3)), Color(1.0, 0.82, 0.15))
			draw_string(ThemeDB.fallback_font, sp + Vector2(-45, -14), str(s["ai_state"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.9, 0.4))

	# 5. 2-Frame B&W Impact Flash
	if combat.impact_flash_timer > 0.0:
		draw_rect(get_viewport_rect(), Color(1, 1, 1, 0.92))
