class_name DevStudio
extends Control

@onready var player: PlayerController = get_node_or_null("../Player") as PlayerController
@onready var combat: GestureCombat = get_node_or_null("../CombatManager") as GestureCombat
@onready var world_env: WorldEnvironment = get_node_or_null("../WorldEnvironment") as WorldEnvironment
@onready var floor_mesh: MeshInstance3D = get_node_or_null("../Floor/MeshInstance3D") as MeshInstance3D

var telemetry: Label
var action_bar: HBoxContainer
var dev_panel: PanelContainer
var tab_container: TabContainer
var fps_mode_idx: int = 0
var region_idx: int = 0
var btn_fps: Button
var btn_lock: Button
var btn_ai: Button
var btn_region: Button
var btn_build: Button

const REGION_NAMES: Array[String] = ["INK_CATHEDRAL", "BLAME_MEGASTRUC", "GOTHIC_ECLIPSE"]

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
	action_bar.offset_left = -980
	action_bar.offset_top = 12
	action_bar.offset_right = -16
	action_bar.offset_bottom = 52
	action_bar.alignment = BoxContainer.ALIGNMENT_END
	action_bar.add_theme_constant_override("separation", 4)
	add_child(action_bar)

	btn_lock = _add_quick_btn("[ LOCK (Q) ]", func(): if player: player.toggle_lock_on())
	_add_quick_btn("[ SWITCH ]", func(): if player: player.cycle_lock_target())
	btn_build = _add_quick_btn("[ BUILD: OFF ]", func():
		if combat:
			combat.build_mode_active = not combat.build_mode_active
			btn_build.text = "[ BUILD: ON ]" if combat.build_mode_active else "[ BUILD: OFF ]"
			btn_build.modulate = Color(1.0, 0.85, 0.25) if combat.build_mode_active else Color.WHITE
	)
	btn_region = _add_quick_btn("[ REG: INK_CATHEDRAL ]", _cycle_region)
	btn_ai = _add_quick_btn("[ AI: ADAPTIVE_RIVAL ]", func():
		if combat:
			combat.ai_mode = ((combat.ai_mode + 1) % 4) as GestureCombat.AIMode
			btn_ai.text = "[ AI: %s ]" % GestureCombat.AIMode.keys()[combat.ai_mode]
	)
	btn_fps = _add_quick_btn("[ FPS: NATIVE ]", _cycle_fps)
	_add_quick_btn("[ SAVE JSON ]", func():
		if player and player.data_store:
			if player.dash_vfx:
				player.data_store.placed_blocks = player.dash_vfx.serialize_user_blocks()
			player.data_store.save_to_disk(player)
			if combat: combat.last_combat_action = "SAVED TO JSON!"
	)
	_add_quick_btn("[ DEV STUDIO (Tab) ]", _toggle_dev_panel)

	dev_panel = PanelContainer.new()
	dev_panel.visible = false
	dev_panel.anchor_left = 0.5
	dev_panel.anchor_top = 0.5
	dev_panel.anchor_right = 0.5
	dev_panel.anchor_bottom = 0.5
	dev_panel.offset_left = -410
	dev_panel.offset_top = -250
	dev_panel.offset_right = 410
	dev_panel.offset_bottom = 250
	add_child(dev_panel)

	var root_vbox := VBoxContainer.new()
	dev_panel.add_child(root_vbox)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "  SASTI SPARKLING ZERO — MODULAR DEV STUDIO"
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
	_build_tab_moves()
	_build_tab_spells()
	_build_tab_visuals()
	_build_tab_world_and_char()

func _add_quick_btn(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 36)
	b.pressed.connect(cb)
	action_bar.add_child(b)
	return b

func _cycle_region() -> void:
	region_idx = (region_idx + 1) % 3
	btn_region.text = "[ REG: %s ]" % REGION_NAMES[region_idx]
	var env := world_env.environment if world_env else null
	var fmat := StandardMaterial3D.new()
	fmat.roughness = 0.92
	match region_idx:
		0:
			if env:
				env.background_color = Color(0.06, 0.06, 0.08)
				env.fog_light_color = Color(0.12, 0.12, 0.14)
			fmat.albedo_color = Color(0.78, 0.77, 0.75)
			if player and player.dash_vfx and player.dash_vfx.stone_mat:
				player.dash_vfx.stone_mat.albedo_color = Color(0.76, 0.75, 0.73)
		1:
			if env:
				env.background_color = Color(0.02, 0.05, 0.09)
				env.fog_light_color = Color(0.05, 0.16, 0.25)
			fmat.albedo_color = Color(0.14, 0.18, 0.24)
			if player and player.dash_vfx and player.dash_vfx.stone_mat:
				player.dash_vfx.stone_mat.albedo_color = Color(0.22, 0.28, 0.36)
		2:
			if env:
				env.background_color = Color(0.18, 0.05, 0.06)
				env.fog_light_color = Color(0.35, 0.12, 0.10)
			fmat.albedo_color = Color(0.38, 0.32, 0.26)
			if player and player.dash_vfx and player.dash_vfx.stone_mat:
				player.dash_vfx.stone_mat.albedo_color = Color(0.52, 0.44, 0.36)
	if floor_mesh:
		floor_mesh.material_override = fmat

func _cycle_fps() -> void:
	fps_mode_idx = (fps_mode_idx + 1) % 3
	var is_android := DisplayServer.get_name() == "Android"
	match fps_mode_idx:
		0:
			if not is_android: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			Engine.max_fps = 0
			Engine.physics_ticks_per_second = 120
			btn_fps.text = "[ FPS: NATIVE ]"
		1:
			if not is_android: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 144
			Engine.physics_ticks_per_second = 144
			btn_fps.text = "[ FPS: 144Hz ]"
		2:
			if not is_android: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
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
	l.custom_minimum_size = Vector2(180, 0)
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
	var apply_fn := func(v: float):
		obj.set(prop, v)
		if prop in ["cel_cut_threshold", "outline_width", "rim_strength", "hatch_width"] and player:
			player.update_cel_shader(player.cel_cut_threshold, player.outline_width, player.rim_strength)
		elif prop in ["char_height", "char_width", "weapon_scale", "model_scale"] and player:
			player.apply_character_proportions()
		elif prop in ["eye_hue", "eye_pupil_scale", "eye_glow_strength"] and player:
			player.update_eye_shader()
	s.value_changed.connect(func(v: float):
		if guard[0]: return
		guard[0] = true; sp.value = v; apply_fn.call(v); guard[0] = false
	)
	sp.value_changed.connect(func(v: float):
		if guard[0]: return
		guard[0] = true; s.value = v; apply_fn.call(v); guard[0] = false
	)
	h.add_child(s)
	h.add_child(sp)

func _build_tab_physics() -> void:
	var vb := _make_scroll_tab("1. Camera & Physics")
	var p_defs := [
		["camera_offset_y", 0.8, 6.0, 0.1], ["camera_offset_x", -2.5, 2.5, 0.05],
		["camera_pitch_bias", -45.0, 15.0, 1.0], ["camera_distance", 1.5, 14.0, 0.2],
		["base_fov", 50.0, 115.0, 1.0], ["camera_sensitivity", 0.05, 1.0, 0.01],
		["run_speed", 4.0, 45.0, 0.5], ["sprint_speed", 10.0, 70.0, 0.5],
		["dash_speed", 20.0, 120.0, 1.0], ["dash_duration", 0.05, 0.6, 0.01],
		["dash_cooldown", 0.0, 0.5, 0.01], ["jump_velocity", 5.0, 35.0, 0.5],
		["air_combo_gravity_scale", 0.02, 1.0, 0.02], ["feint_threshold_px", 40.0, 180.0, 2.0]
	]
	for d in p_defs:
		_add_row(vb, player, d[0], d[1], d[2], d[3])

func _build_tab_races() -> void:
	var vb := _make_scroll_tab("2. Profile & Dash")
	var top := HBoxContainer.new()
	vb.add_child(top)
	var r_opt := OptionButton.new()
	r_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["Profile_1", "Profile_2", "Profile_3", "Profile_4"]:
		r_opt.add_item(k)
	top.add_child(r_opt)

	var style_row := HBoxContainer.new()
	var s_lbl := Label.new(); s_lbl.text = "Dash Style:"; s_lbl.custom_minimum_size = Vector2(140, 0)
	style_row.add_child(s_lbl)
	var style_opt := OptionButton.new()
	for st in PlayerController.DashStyle.keys(): style_opt.add_item(st)
	style_row.add_child(style_opt)

	var chk_after := CheckBox.new()
	chk_after.text = "Paradox Afterimage Clones"
	chk_after.button_pressed = false
	style_row.add_child(chk_after)
	vb.add_child(style_row)

	style_opt.item_selected.connect(func(idx: int):
		if player:
			player.dash_style = idx as PlayerController.DashStyle
			if player.data_store:
				player.data_store.profiles[player.active_race_name]["dash_style"] = idx
	)
	chk_after.toggled.connect(func(on: bool):
		if player:
			player.afterimage_enabled = on
			if player.data_store:
				player.data_store.profiles[player.active_race_name]["afterimage_on"] = on
			if not on and player.dash_vfx:
				player.dash_vfx.clear_afterimages()
	)
	r_opt.item_selected.connect(func(idx: int):
		if player:
			player.apply_race_by_name(r_opt.get_item_text(idx))
			style_opt.selected = player.dash_style
			chk_after.button_pressed = player.afterimage_enabled
	)

	for d in [["max_hp", 200.0, 5000.0, 50.0], ["max_mana", 20.0, 500.0, 10.0], ["physical_strength", 0.2, 5.0, 0.05], ["base_power", 0.2, 5.0, 0.05], ["step_mult", 0.5, 3.0, 0.05]]:
		_add_row(vb, player, d[0], d[1], d[2], d[3])

func _build_tab_moves() -> void:
	var vb := _make_scroll_tab("3. Move Slots")
	var top := HBoxContainer.new(); vb.add_child(top)
	var m_opt := OptionButton.new(); m_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slot_keys := ["Slot_1_Up", "Slot_2_Down", "Slot_3_Left", "Slot_4_Right", "Slot_5_Diag_UL", "Slot_6_Diag_UR", "Slot_7_Burst", "Slot_8_Counter"]
	for k in slot_keys: m_opt.add_item(k)
	top.add_child(m_opt)

	var new_m := LineEdit.new(); new_m.placeholder_text = "New Move Slot Name..."; top.add_child(new_m)
	var b_add := Button.new(); b_add.text = "+ Add Slot"; top.add_child(b_add)

	var dyn := VBoxContainer.new(); vb.add_child(dyn)
	var rebuild := func(m_key: String):
		for c in dyn.get_children(): c.queue_free()
		if not player or not player.data_store or not player.data_store.move_slots.has(m_key): return
		var entry: Dictionary = player.data_store.move_slots[m_key]
		for f in [["step_force", 0.0, 50.0], ["lunge_force", 0.0, 60.0], ["vertical_lift", -30.0, 30.0], ["dmg", 10.0, 600.0], ["posture", 5.0, 300.0], ["knockback", 0.0, 45.0], ["launch_y", -25.0, 25.0], ["roll_deg", -180.0, 180.0]]:
			var row := HBoxContainer.new(); dyn.add_child(row)
			var l := Label.new(); l.text = f[0]; l.custom_minimum_size = Vector2(160, 0); row.add_child(l)
			var sp := SpinBox.new(); sp.min_value = f[1]; sp.max_value = f[2]; sp.step = 0.5; sp.allow_greater = true
			sp.value = float(entry.get(f[0], 10.0))
			var k_name: String = f[0]
			sp.value_changed.connect(func(v: float): entry[k_name] = v)
			row.add_child(sp)

	m_opt.item_selected.connect(func(i: int): rebuild.call(m_opt.get_item_text(i)))
	b_add.pressed.connect(func():
		if not player or not player.data_store or new_m.text.strip_edges().is_empty(): return
		var nk := new_m.text.strip_edges()
		player.data_store.move_slots[nk] = {"dir": "UP", "step_force": 15.0, "lunge_force": 18.0, "vertical_lift": 5.0, "dmg": 100.0, "posture": 45.0, "knockback": 8.0, "launch_y": 5.0, "roll_deg": 45.0}
		m_opt.add_item(nk)
		m_opt.selected = m_opt.item_count - 1
		rebuild.call(nk)
	)
	call_deferred("_deferred_init_moves", rebuild)

func _deferred_init_moves(cb: Callable) -> void:
	cb.call("Slot_1_Up")

func _build_tab_spells() -> void:
	var vb := _make_scroll_tab("4. Spell Maker")
	var top := HBoxContainer.new(); vb.add_child(top)
	var sp_opt := OptionButton.new(); sp_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["Spell_Slot_1", "Spell_Slot_2", "Spell_Slot_3", "Spell_Slot_4", "Spell_Slot_5", "Spell_Slot_6"]:
		sp_opt.add_item(k)
	top.add_child(sp_opt)

	var new_sp := LineEdit.new(); new_sp.placeholder_text = "New Spell Slot Name..."; top.add_child(new_sp)
	var b_add := Button.new(); b_add.text = "+ Add Spell"; top.add_child(b_add)

	var dyn := VBoxContainer.new(); vb.add_child(dyn)
	var rebuild := func(s_key: String):
		for c in dyn.get_children(): c.queue_free()
		if not player or not player.data_store or not player.data_store.spell_slots.has(s_key): return
		var entry: Dictionary = player.data_store.spell_slots[s_key]

		var seq_row := HBoxContainer.new(); dyn.add_child(seq_row)
		var sl := Label.new(); sl.text = "Swipe Sequence (UP,DOWN,LEFT,RIGHT):"; sl.custom_minimum_size = Vector2(240, 0); seq_row.add_child(sl)
		var seq_edit := LineEdit.new(); seq_edit.text = str(entry.get("sequence", "UP,UP")); seq_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seq_edit.text_changed.connect(func(txt: String): entry["sequence"] = txt.to_upper().strip_edges())
		seq_row.add_child(seq_edit)

		for f in [["step_force", 5.0, 50.0], ["vertical_hop", 0.0, 25.0], ["dmg", 20.0, 600.0], ["posture", 10.0, 300.0], ["proj_speed", 15.0, 120.0]]:
			var row := HBoxContainer.new(); dyn.add_child(row)
			var l := Label.new(); l.text = f[0]; l.custom_minimum_size = Vector2(180, 0); row.add_child(l)
			var sp := SpinBox.new(); sp.min_value = f[1]; sp.max_value = f[2]; sp.step = 1.0; sp.allow_greater = true
			sp.value = float(entry.get(f[0], 20.0))
			var k_name: String = f[0]
			sp.value_changed.connect(func(v: float): entry[k_name] = v)
			row.add_child(sp)

	sp_opt.item_selected.connect(func(i: int): rebuild.call(sp_opt.get_item_text(i)))
	b_add.pressed.connect(func():
		if not player or not player.data_store or new_sp.text.strip_edges().is_empty(): return
		var nk := new_sp.text.strip_edges()
		player.data_store.spell_slots[nk] = {"sequence": "UP,DOWN,UP", "step_force": 24.0, "vertical_hop": 6.0, "dmg": 175.0, "posture": 80.0, "proj_speed": 52.0, "color": [0.95, 0.15, 0.2]}
		sp_opt.add_item(nk)
		sp_opt.selected = sp_opt.item_count - 1
		rebuild.call(nk)
	)
	call_deferred("_deferred_init_spells", rebuild)

func _deferred_init_spells(cb: Callable) -> void:
	cb.call("Spell_Slot_1")

func _build_tab_visuals() -> void:
	var vb := _make_scroll_tab("5. Shaders & AI")
	_add_row(vb, player, "anim_step_fps", 6.0, 60.0, 1.0)
	_add_row(vb, player, "cel_cut_threshold", 0.05, 0.95, 0.02)
	_add_row(vb, player, "hatch_width", 0.0, 0.25, 0.01)
	_add_row(vb, player, "outline_width", 0.0, 0.08, 0.002)
	_add_row(vb, player, "rim_strength", 0.0, 2.5, 0.05)
	_add_row(vb, combat, "ai_telegraph_time", 0.15, 1.2, 0.05)
	_add_row(vb, combat, "ai_attack_cooldown", 0.4, 3.5, 0.1)
	_add_row(vb, combat, "ai_adaptation_rate", 0.05, 1.0, 0.05)
	var rst := Button.new()
	rst.text = " [ Reset Dummies & Rebuild Shattered Pillars ] "
	rst.pressed.connect(func():
		if combat:
			combat._init_targets()
			combat.player_habits.clear()
		if player and player.dash_vfx:
			player.dash_vfx.reset_destructibles()
	)
	vb.add_child(rst)

func _build_tab_world_and_char() -> void:
	var vb := _make_scroll_tab("6. World & Char Maker")

	var lbl_c := Label.new(); lbl_c.text = "— CHARACTER PROPORTIONS & OUTFIT LOADER —"
	vb.add_child(lbl_c)
	_add_row(vb, player, "char_height", 0.65, 1.65, 0.02)
	_add_row(vb, player, "char_width", 0.65, 1.55, 0.02)
	_add_row(vb, player, "weapon_scale", 0.5, 2.5, 0.05)

	var lbl_eye := Label.new(); lbl_eye.text = "— 2D UV EYE SHAPE & COLOR CUSTOMIZER —"
	vb.add_child(lbl_eye)
	var erow := HBoxContainer.new(); vb.add_child(erow)
	var elbl := Label.new(); elbl.text = "2D Eye Shape:"; elbl.custom_minimum_size = Vector2(160, 0); erow.add_child(elbl)
	var eopt := OptionButton.new(); eopt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for es in ["0: SLIT_DEMON", "1: HOLLOW_RING", "2: CROSS_STAR", "3: CRESCENT_ECLIPSE"]:
		eopt.add_item(es)
	if player: eopt.selected = clampi(player.eye_shape, 0, 3)
	eopt.item_selected.connect(func(idx: int):
		if player:
			player.eye_shape = idx
			player.update_eye_shader()
	)
	erow.add_child(eopt)
	_add_row(vb, player, "eye_hue", 0.0, 1.0, 0.02)
	_add_row(vb, player, "eye_pupil_scale", 0.4, 2.2, 0.05)
	_add_row(vb, player, "eye_glow_strength", 0.2, 5.0, 0.1)

	var lbl_j := Label.new(); lbl_j.text = "— SPRING-BONE JIGGLE & KNOCKOUT RAGDOLL PHYSICS —"
	vb.add_child(lbl_j)
	_add_row(vb, player, "jiggle_stiffness", 2.0, 45.0, 1.0)
	_add_row(vb, player, "jiggle_damping", 0.5, 15.0, 0.5)
	_add_row(vb, player, "jiggle_gravity", -1.5, 2.5, 0.1)
	_add_row(vb, player, "ragdoll_bouncy", 0.1, 0.9, 0.05)

	var rag_row := HBoxContainer.new(); vb.add_child(rag_row)
	var b_rag_p := Button.new(); b_rag_p.text = " [ Test Player Ragdoll KO ] "
	b_rag_p.pressed.connect(func():
		if player: player.trigger_ragdoll_ko(1.25, Vector3(0, 12.0, 14.0))
	)
	rag_row.add_child(b_rag_p)

	var b_rag_e := Button.new(); b_rag_e.text = " [ Trigger Boss Ragdoll KO ] "
	b_rag_e.pressed.connect(func():
		if combat:
			for t in combat.target_stats.keys():
				if is_instance_valid(t):
					combat.target_stats[t]["posture"] = combat.target_stats[t]["max_posture"]
					combat.apply_damage(t as Node3D, 250.0, 100.0, Vector3(0, 13.0, -16.0))
	)
	rag_row.add_child(b_rag_e)

	var lbl_slots := Label.new(); lbl_slots.text = "— MODULAR CLOTHING SLOT SWITCHER (MIX & MATCH) —"
	vb.add_child(lbl_slots)
	var slot_defs := [
		["Head / Mask:", "slot_head"],
		["Veil / Cloak:", "slot_veil"],
		["Upper Armor:", "slot_upper"],
		["Lower Garb:", "slot_lower"],
		["Weapon Kit:", "slot_weapon"]
	]
	for sd in slot_defs:
		var srow := HBoxContainer.new(); vb.add_child(srow)
		var slbl := Label.new(); slbl.text = sd[0]; slbl.custom_minimum_size = Vector2(160, 0); srow.add_child(slbl)
		var sopt := OptionButton.new(); sopt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var styles := ["HERO", "VEIL", "NONE"]
		for st in styles: sopt.add_item(st)
		var prop_name: String = sd[1]
		if player:
			var cur_val := str(player.get(prop_name))
			var idx := styles.find(cur_val)
			if idx != -1: sopt.selected = idx
		sopt.item_selected.connect(func(i: int):
			if player:
				var chosen := sopt.get_item_text(i)
				player.set(prop_name, chosen)
				if player.data_store and player.data_store.profiles.has(player.active_race_name):
					player.data_store.profiles[player.active_race_name][prop_name] = chosen
				player.apply_modular_clothing_slots()
		)
		srow.add_child(sopt)

	var m_row := HBoxContainer.new(); vb.add_child(m_row)
	var b_hero := Button.new(); b_hero.text = "Equip Dark Seinen Hero"; b_hero.pressed.connect(func(): if player: player.swap_custom_model("res://models/hero.glb")); m_row.add_child(b_hero)
	var b_boss := Button.new(); b_boss.text = "Equip Gilded Veil Boss"; b_boss.pressed.connect(func(): if player: player.swap_custom_model("res://models/boss_veil.glb")); m_row.add_child(b_boss)

	var p_edit := LineEdit.new(); p_edit.placeholder_text = "user://assets/custom.glb or res://models/hero.glb"; p_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; m_row.add_child(p_edit)
	var b_load := Button.new(); b_load.text = " Load .GLB "; b_load.pressed.connect(func(): if player: player.swap_custom_model(p_edit.text)); m_row.add_child(b_load)

	var lbl_w := Label.new(); lbl_w.text = "— MINECRAFT-STYLE ARENA BLOCK & FLORA BUILDER —"
	vb.add_child(lbl_w)

	var b_row := HBoxContainer.new(); vb.add_child(b_row)
	var chk_build := CheckBox.new(); chk_build.text = "Enable Tap-to-Place Build Mode"
	chk_build.toggled.connect(func(on: bool):
		if combat:
			combat.build_mode_active = on
			btn_build.text = "[ BUILD: ON ]" if on else "[ BUILD: OFF ]"
			btn_build.modulate = Color(1.0, 0.85, 0.25) if on else Color.WHITE
	)
	b_row.add_child(chk_build)

	var chk_del := CheckBox.new(); chk_del.text = "Delete Mode (Tap Block to Remove)"
	chk_del.toggled.connect(func(on: bool): if combat: combat.delete_mode_active = on)
	b_row.add_child(chk_del)

	var kind_row := HBoxContainer.new(); vb.add_child(kind_row)
	var k_lbl := Label.new(); k_lbl.text = "Block / Tile Type:"; k_lbl.custom_minimum_size = Vector2(160, 0); kind_row.add_child(k_lbl)
	var k_opt := OptionButton.new(); k_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for bk in ["GOTHIC_PILLAR", "BLAME_MONOLITH", "RUINED_ARCH", "ANIME_FLORA_PATCH"]:
		k_opt.add_item(bk)
	k_opt.item_selected.connect(func(idx: int): if combat: combat.selected_block_kind = k_opt.get_item_text(idx))
	kind_row.add_child(k_opt)

	_add_row(vb, combat, "build_rot_deg", 0.0, 270.0, 45.0)

func _process(_delta: float) -> void:
	if not player or not combat: return
	var fps := Engine.get_frames_per_second()
	var panel_hz := int(DisplayServer.screen_get_refresh_rate())
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	var cpu_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var st_name: String = PlayerController.MoveState.keys()[player.state]
	var dash_name: String = PlayerController.DashStyle.keys()[player.dash_style]
	var seq_txt := " -> ".join(combat.current_swipe_chain) if not combat.current_swipe_chain.is_empty() else combat.active_infusion
	var b_tag := " | [BUILD: %s]" % combat.selected_block_kind if combat.build_mode_active else ""
	telemetry.text = "FPS: %d | Panel Hz: %d (OS Cap) | GPU: %.2f ms | CPU: %.2f ms%s\nProfile: %s | Dash: %s | State: %s | Weave: [%s] | Action: %s" % [
		fps, panel_hz, gpu_ms, cpu_ms, b_tag, player.active_race_name, dash_name, st_name, seq_txt, combat.last_combat_action
	]
	btn_lock.modulate = Color(0.3, 1.0, 0.5) if player.is_locked_on else Color.WHITE
	queue_redraw()

func _draw() -> void:
	if not player or not combat: return

	var l_pos := combat.left_dot_pos
	var l_open := combat.is_left_dot_active or combat.left_dot_pinned
	draw_circle(l_pos, combat.left_dot_collapsed_r, Color(0.15, 0.55, 1.0, 0.45))
	draw_arc(l_pos, combat.left_dot_collapsed_r, 0.0, TAU, 32, Color(0.5, 0.85, 1.0, 0.9), 2.5)
	draw_string(ThemeDB.fallback_font, l_pos + Vector2(-20, 5), "WEAVE", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)
	if l_open:
		draw_circle(l_pos, combat.left_dot_expanded_r, Color(0.05, 0.08, 0.14, 0.72))
		draw_arc(l_pos, combat.left_dot_expanded_r, 0.0, TAU, 48, Color(0.95, 0.2, 0.3, 0.9), 2.5)
		var dirs := [["UP", Vector2(0, -85)], ["DOWN", Vector2(0, 85)], ["LEFT", Vector2(-85, 0)], ["RIGHT", Vector2(85, 0)]]
		for d in dirs:
			var dp: Vector2 = l_pos + d[1]
			var active_d := combat.current_swipe_chain.has(d[0])
			draw_circle(dp, 22.0, Color(0.95, 0.15, 0.25, 0.9) if active_d else Color(0.2, 0.3, 0.45, 0.75))
			draw_string(ThemeDB.fallback_font, dp + Vector2(-14, 5), str(d[0]).substr(0, 2), HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color.WHITE)
		var chain_str := " -> ".join(combat.current_swipe_chain) if not combat.current_swipe_chain.is_empty() else "SWIPE SEQUENCE"
		draw_string(ThemeDB.fallback_font, l_pos + Vector2(-55, -combat.left_dot_expanded_r - 12), chain_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(1.0, 0.85, 0.2))

	var r_pos := combat.right_dot_pos
	var r_open := combat.is_right_dot_active or combat.right_dot_pinned
	var r_col := Color(0.2, 0.9, 1.0, 0.65) if combat.sonic_sway_holding else Color(0.95, 0.22, 0.28, 0.5)
	draw_circle(r_pos, combat.right_dot_collapsed_r, r_col)
	draw_arc(r_pos, combat.right_dot_collapsed_r, 0.0, TAU, 32, Color(1.0, 0.75, 0.75, 0.95), 2.5)
	draw_string(ThemeDB.fallback_font, r_pos + Vector2(-18, 5), "SWAY" if combat.sonic_sway_holding else "ATK", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)
	if r_open:
		var center := combat.right_touch_start if combat.is_right_dot_active else r_pos
		draw_circle(center, combat.right_dot_expanded_r, Color(0.08, 0.04, 0.06, 0.55))
		draw_arc(center, 32.0, 0.0, TAU, 32, Color(0.3, 0.95, 1.0, 0.85), 2.0)
		draw_arc(center, player.feint_threshold_px, 0.0, TAU, 48, Color(1.0, 0.85, 0.15, 0.85), 2.5)
		draw_arc(center, combat.right_dot_expanded_r, 0.0, TAU, 48, Color(1.0, 0.3, 0.35, 0.85), 2.5)

	var hud_p := Vector2(20, get_viewport_rect().size.y - 68)
	var hp_r := clampf(player.hp / maxf(1.0, player.max_hp), 0.0, 1.0)
	var mp_r := clampf(player.mana / maxf(1.0, player.max_mana), 0.0, 1.0)
	draw_rect(Rect2(hud_p, Vector2(240, 18)), Color(0.06, 0.07, 0.1, 0.9))
	draw_rect(Rect2(hud_p + Vector2(2, 2), Vector2(236 * hp_r, 14)), Color(0.2, 0.85, 0.45))
	draw_string(ThemeDB.fallback_font, hud_p + Vector2(8, 14), "HP: %d / %d" % [int(player.hp), int(player.max_hp)], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

	var mp_p := hud_p + Vector2(0, 22)
	draw_rect(Rect2(mp_p, Vector2(200, 14)), Color(0.06, 0.07, 0.1, 0.9))
	draw_rect(Rect2(mp_p + Vector2(2, 2), Vector2(196 * mp_r, 10)), Color(0.95, 0.18, 0.25))
	draw_string(ThemeDB.fallback_font, mp_p + Vector2(8, 11), "TOUKI: %d / %d (%s)" % [int(player.mana), int(player.max_mana), combat.active_infusion], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

	for t in combat.target_stats.keys():
		if is_instance_valid(t) and t is Node3D and not player.camera.is_position_behind(t.global_position):
			var td := t as Node3D
			var sp := player.camera.unproject_position(td.global_position + Vector3(0, 2.2, 0))
			var s: Dictionary = combat.target_stats[td]
			var thp := clampf(s["hp"] / s["max_hp"], 0.0, 1.0)
			var tpo := clampf(s["posture"] / s["max_posture"], 0.0, 1.0)
			draw_rect(Rect2(sp - Vector2(45, 0), Vector2(90, 8)), Color(0.05, 0.05, 0.07, 0.9))
			draw_rect(Rect2(sp - Vector2(44, -1), Vector2(88 * thp, 6)), Color(0.9, 0.2, 0.22))
			draw_rect(Rect2(sp - Vector2(45, -10), Vector2(90, 5)), Color(0.05, 0.05, 0.07, 0.9))
			draw_rect(Rect2(sp - Vector2(44, -9), Vector2(88 * tpo, 3)), Color(1.0, 0.82, 0.15))

			var st_txt := str(s["ai_state"])
			var st_col := Color(1, 0.9, 0.4)
			if st_txt == "TELEGRAPH":
				st_txt = "!! PARRY / SWAY NOW !!"
				st_col = Color(1.0, 0.15, 0.2)
				var body_sp := player.camera.unproject_position(td.global_position + Vector3(0, 1.0, 0))
				var ring_r := clampf((s["state_timer"] / maxf(0.1, combat.ai_telegraph_time)) * 75.0, 18.0, 75.0)
				draw_arc(body_sp, ring_r, 0.0, TAU, 36, Color(1.0, 0.15, 0.2, 0.95), 3.5)
				draw_arc(body_sp, 22.0, 0.0, TAU, 32, Color(1.0, 0.9, 0.3, 0.8), 2.0)
			elif st_txt == "STRIKE_ACTIVE":
				st_txt = ">> STRIKE! <<"
				st_col = Color(1.0, 0.95, 0.3)
			draw_string(ThemeDB.fallback_font, sp + Vector2(-52, -14), st_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, st_col)

	if combat.impact_flash_timer > 0.0:
		draw_rect(get_viewport_rect(), Color(1, 1, 1, 0.92))
