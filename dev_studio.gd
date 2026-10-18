class_name DevStudio extends Control

## High-Performance Modular Dev Overlay, Telemetry & Gesture Visualizer

var last_telemetry_time: float = 0.0
var fps_cycle_index: int = 0
var xray_cycle_index: int = 0

# UI References
var stats_label: Label
var top_bar: HBoxContainer
var dev_panel: PanelContainer
var btn_fps: Button
var btn_lock: Button
var btn_fly: Button
var btn_xray: Button
var btn_mouse: Button
var btn_dev: Button

# Slider References
var slider_run: HSlider
var slider_sprint: HSlider
var slider_flight: HSlider
var slider_dash: HSlider
var slider_jump: HSlider
var slider_feint: HSlider

@onready var player: PlayerController = get_parent().get_parent() as PlayerController


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = true

	_build_telemetry_hud()
	_build_quick_action_bar()
	_build_dev_panel()


func _build_telemetry_hud() -> void:
	stats_label = Label.new()
	stats_label.position = Vector2(16, 16)
	stats_label.mouse_filter = MOUSE_FILTER_IGNORE
	stats_label.add_theme_color_override("font_outline_color", Color.BLACK)
	stats_label.add_theme_constant_override("outline_size", 5)
	stats_label.add_theme_font_size_override("font_size", 14)
	add_child(stats_label)


func _build_quick_action_bar() -> void:
	top_bar = HBoxContainer.new()
	top_bar.anchor_left = 1.0
	top_bar.anchor_right = 1.0
	top_bar.offset_left = -660
	top_bar.offset_top = 16
	top_bar.offset_right = -16
	top_bar.offset_bottom = 54
	top_bar.alignment = BoxContainer.ALIGNMENT_END
	top_bar.add_theme_constant_override("separation", 8)
	add_child(top_bar)

	btn_fps = _create_bar_button("[ FPS: VSYNC ]", _on_fps_cycle_pressed)
	btn_lock = _create_bar_button("[ LOCK (Q) ]", _on_lock_pressed)
	btn_fly = _create_bar_button("[ FLY (F) ]", _on_fly_pressed)
	btn_xray = _create_bar_button("[ X-RAY ]", _on_xray_pressed)
	btn_mouse = _create_bar_button("[ MOUSE (Esc) ]", _on_mouse_toggle_pressed)
	btn_dev = _create_bar_button("[ DEV (Tab) ]", _on_dev_toggle_pressed)


func _create_bar_button(title: String, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text = title
	btn.focus_mode = FOCUS_NONE
	btn.mouse_filter = MOUSE_FILTER_STOP
	btn.pressed.connect(callback)
	top_bar.add_child(btn)
	return btn


func _build_dev_panel() -> void:
	dev_panel = PanelContainer.new()
	dev_panel.position = Vector2(16, 230)
	dev_panel.custom_minimum_size = Vector2(300, 340)
	dev_panel.visible = false
	add_child(dev_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	dev_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var header = Label.new()
	header.text = "=== PHYSICS & FEINT TUNER ==="
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	slider_run = _add_slider(vbox, "Run Speed (m/s):", 8.0, 36.0, 16.0, func(v): if player: player.run_speed = v)
	slider_sprint = _add_slider(vbox, "Sprint Speed (m/s):", 16.0, 56.0, 28.0, func(v): if player: player.sprint_speed = v)
	slider_flight = _add_slider(vbox, "Flight Speed (m/s):", 16.0, 64.0, 32.0, func(v): if player: player.flight_speed = v)
	slider_dash = _add_slider(vbox, "Dash Speed (m/s):", 24.0, 96.0, 54.0, func(v): if player: player.dash_speed = v)
	slider_jump = _add_slider(vbox, "Jump Velocity (m/s):", 6.0, 24.0, 12.0, func(v): if player: player.jump_velocity = v)
	slider_feint = _add_slider(vbox, "Feint Threshold (px):", 40.0, 180.0, 95.0, func(v):
		if player:
			player.feint_threshold_px = v
			if player.combat: player.combat.feint_threshold_px = v
	)

	var btn_save = Button.new()
	btn_save.text = "[ Save dev_profile.json & Copy ]"
	btn_save.focus_mode = FOCUS_NONE
	btn_save.pressed.connect(_on_save_profile_pressed)
	vbox.add_child(btn_save)


func _add_slider(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, default_v: float, callback: Callable) -> HSlider:
	var lbl = Label.new()
	lbl.text = "%s %.1f" % [label_text, default_v]
	parent.add_child(lbl)

	var slider = HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 1.0
	slider.value = default_v
	slider.value_changed.connect(func(val):
		lbl.text = "%s %.1f" % [label_text, val]
		callback.call(val)
	)
	parent.add_child(slider)
	return slider


func _process(_delta: float) -> void:
	# Hotkeys
	if Input.is_action_just_pressed("dev_tab"):
		_on_dev_toggle_pressed()

	if Input.is_key_pressed(KEY_ESCAPE) and Input.is_action_just_pressed("ui_cancel"):
		_on_mouse_toggle_pressed()

	if Input.is_key_label_pressed(KEY_F) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if Input.is_action_just_pressed("move_forward") == false:
			pass

	# Throttle telemetry to 5 Hz (0.2s) to avoid allocations & GC pressure
	var now = Time.get_ticks_msec() / 1000.0
	if now - last_telemetry_time >= 0.2:
		_update_telemetry()
		last_telemetry_time = now

	queue_redraw()


func _update_telemetry() -> void:
	if not player:
		return

	var fps = Engine.get_frames_per_second()
	var cpu_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var gpu_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var state_name = PlayerController.MoveState.keys()[player.current_state]
	var speed = player.velocity.length()

	var target_text = "None"
	if player.is_locked_on and is_instance_valid(player.lock_target):
		target_text = player.lock_target.name

	var mana_val = 0.0
	var combat_st = "N/A"
	var tape_str = "[]"
	if player.combat:
		mana_val = player.combat.mana
		combat_st = player.combat.combat_state
		tape_str = str(player.combat.input_tape)

	stats_label.text = (
		"FPS: %d | CPU: %.2f ms | Physics: %.2f ms\n" % [fps, cpu_ms, gpu_ms] +
		"State: %s | Speed: %.1f m/s | Lock Target: %s\n" % [state_name, speed, target_text] +
		"Mana: %.1f | Combat: %s\n" % [mana_val, combat_st] +
		"Input Tape: %s" % tape_str
	)

	# Update Lock button visual
	if player.is_locked_on:
		btn_lock.modulate = Color(0.2, 1.0, 0.4, 1.0)
	else:
		btn_lock.modulate = Color.WHITE


func _on_fps_cycle_pressed() -> void:
	fps_cycle_index = (fps_cycle_index + 1) % 5
	match fps_cycle_index:
		0:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			Engine.max_fps = 0
			btn_fps.text = "[ FPS: VSYNC ]"
		1:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
			btn_fps.text = "[ FPS: UNLIMITED ]"
		2:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 165
			btn_fps.text = "[ FPS: 165 ]"
		3:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 120
			btn_fps.text = "[ FPS: 120 ]"
		4:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 60
			btn_fps.text = "[ FPS: 60 ]"


func _on_lock_pressed() -> void:
	if player:
		player.toggle_lock()


func _on_fly_pressed() -> void:
	if player:
		if player.current_state == PlayerController.MoveState.FLIGHT:
			player.current_state = PlayerController.MoveState.NORMAL
		else:
			player.current_state = PlayerController.MoveState.FLIGHT
			player.velocity.y = 4.0


func _on_xray_pressed() -> void:
	xray_cycle_index = (xray_cycle_index + 1) % 3
	match xray_cycle_index:
		0:
			get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
			btn_xray.text = "[ X-RAY: OFF ]"
		1:
			get_viewport().debug_draw = Viewport.DEBUG_DRAW_OVERDRAW
			btn_xray.text = "[ X-RAY: OVERDRAW ]"
		2:
			get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
			btn_xray.text = "[ X-RAY: WIREFRAME ]"


func _on_mouse_toggle_pressed() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_dev_toggle_pressed() -> void:
	dev_panel.visible = not dev_panel.visible


func _on_save_profile_pressed() -> void:
	if not player:
		return

	var profile = {
		"run_speed": player.run_speed,
		"sprint_speed": player.sprint_speed,
		"flight_speed": player.flight_speed,
		"dash_speed": player.dash_speed,
		"jump_velocity": player.jump_velocity,
		"feint_threshold_px": player.feint_threshold_px
	}

	var json_str = JSON.stringify(profile, "\t")

	# Save to res://
	var file_res = FileAccess.open("res://dev_profile.json", FileAccess.WRITE)
	if file_res:
		file_res.store_string(json_str)
		file_res.close()

	# Save to user://
	var file_usr = FileAccess.open("user://dev_profile.json", FileAccess.WRITE)
	if file_usr:
		file_usr.store_string(json_str)
		file_usr.close()

	# Copy to clipboard
	DisplayServer.clipboard_set(json_str)
	if player.combat:
		player.combat._log_input("PROFILE SAVED!")


func _draw() -> void:
	if not player or not player.combat:
		return

	var c = player.combat
	if c.is_right_dragging:
		var center = c.right_start_pos
		var feint_r = c.feint_threshold_px

		# Inner Deadzone (30px)
		draw_circle(center, 30.0, Color(1, 1, 1, 0.15))
		draw_arc(center, 30.0, 0, TAU, 32, Color(1, 1, 1, 0.3), 1.5)

		# Yellow Feint Ring (feint_threshold_px)
		draw_circle(center, feint_r, Color(1, 0.85, 0.1, 0.08))
		draw_arc(center, feint_r, 0, TAU, 48, Color(1, 0.85, 0.1, 0.5), 2.0)

		# Cyan Commit Zone (> feint_r)
		draw_arc(center, feint_r + 20.0, 0, TAU, 48, Color(0.1, 0.9, 1.0, 0.35), 1.5)

		# Gesture Polyline Trail
		if c.gesture_segments.size() > 1:
			draw_polyline(c.gesture_segments, Color(0, 1.0, 1.0, 0.8), 3.5)
