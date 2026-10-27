class_name DevStudio
extends Control

@onready var player: PlayerController = get_node("../Player")
@onready var combat: GestureCombat = get_node("../CombatManager")

var telemetry: Label
var action_bar: HBoxContainer
var dev_panel: PanelContainer
var tab_container: TabContainer

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	telemetry = Label.new(); telemetry.position = Vector2(16, 16); add_child(telemetry)
	
	action_bar = HBoxContainer.new(); action_bar.anchor_left = 1.0; action_bar.anchor_right = 1.0
	action_bar.offset_left = -500; action_bar.offset_top = 16; action_bar.alignment = BoxContainer.ALIGNMENT_END
	add_child(action_bar)
	_add_quick_btn("FLY (F)", func(): player.state = PlayerController.MoveState.FLIGHT if player.state != PlayerController.MoveState.FLIGHT else PlayerController.MoveState.GROUND)
	_add_quick_btn("AI MODE", func(): combat.ai_mode = (combat.ai_mode + 1) % 4 as GestureCombat.AIMode)
	_add_quick_btn("DEV (Tab)", func(): dev_panel.visible = !dev_panel.visible; Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if dev_panel.visible else Input.MOUSE_MODE_CAPTURED)

	dev_panel = PanelContainer.new(); dev_panel.visible = false
	dev_panel.anchor_left = 0.5; dev_panel.anchor_top = 0.5; dev_panel.anchor_right = 0.5; dev_panel.anchor_bottom = 0.5
	dev_panel.offset_left = -300; dev_panel.offset_top = -200; dev_panel.offset_right = 300; dev_panel.offset_bottom = 200
	add_child(dev_panel)
	
	tab_container = TabContainer.new(); dev_panel.add_child(tab_container)
	_build_physics_tab()
	_build_visuals_tab()

func _add_quick_btn(txt: String, cb: Callable) -> void:
	var b = Button.new(); b.text = txt; b.pressed.connect(cb); action_bar.add_child(b)

func _build_physics_tab() -> void:
	var vbox = VBoxContainer.new(); vbox.name = "Physics"; tab_container.add_child(vbox)
	_add_row(vbox, player, "run_speed", 5, 40); _add_row(vbox, player, "flight_speed", 10, 80)
	_add_row(vbox, player, "camera_distance", 1, 15); _add_row(vbox, player, "base_fov", 50, 120)

func _build_visuals_tab() -> void:
	var vbox = VBoxContainer.new(); vbox.name = "Shaders"; tab_container.add_child(vbox)
	_add_row(vbox, player, "cel_cut_threshold", 0, 1); _add_row(vbox, player, "outline_width", 0, 0.1)

func _add_row(parent: Control, obj: Object, prop: String, min_v: float, max_v: float) -> void:
	var h = HBoxContainer.new(); parent.add_child(h)
	var l = Label.new(); l.text = prop; l.custom_minimum_size = Vector2(150, 0); h.add_child(l)
	var s = HSlider.new(); s.min_value = min_v; s.max_value = max_v; s.step = 0.01; s.size_flags_horizontal = SIZE_EXPAND_FILL
	var sp = SpinBox.new(); sp.min_value = min_v; sp.max_value = max_v; sp.step = 0.01
	s.value = obj.get(prop); sp.value = s.value
	s.value_changed.connect(func(v): sp.value = v; obj.set(prop, v))
	sp.value_changed.connect(func(v): s.value = v; obj.set(prop, v))
	h.add_child(s); h.add_child(sp)

func _process(delta: float) -> void:
	telemetry.text = "FPS: %d | GPU: %.2f ms | State: %s" % [Engine.get_frames_per_second(), RenderingServer.get_rendering_device().get_frame_time() if RenderingServer.get_rendering_device() else 0.0, PlayerController.MoveState.keys()[player.state]]
	queue_redraw()

func _draw() -> void:
	_draw_dot(combat.left_dot_pos, 30, combat.is_left_dot_active, Color(0.2, 0.6, 1, 0.6))
	_draw_dot(combat.right_dot_pos, 30, combat.is_right_dot_active, Color(1, 0.3, 0.3, 0.6))
	if combat.impact_flash_timer > 0.0: draw_rect(get_viewport_rect(), Color.WHITE)
	for t in combat.target_stats.keys():
		var pos = player.camera.unproject_position(t.global_position + Vector3(0, 2.2, 0))
		if not player.camera.is_position_behind(t.global_position):
			draw_rect(Rect2(pos - Vector2(40, 0), Vector2(80, 8)), Color.BLACK)
			draw_rect(Rect2(pos - Vector2(38, -2), Vector2(76 * (combat.target_stats[t]["hp"] / combat.target_stats[t]["max_hp"]), 4)), Color.RED)

func _draw_dot(pos: Vector2, r: float, active: bool, col: Color) -> void:
	draw_circle(pos, r, col); draw_arc(pos, r, 0, TAU, 32, Color.WHITE, 2.0)
	if active: draw_arc(pos, 135, 0, TAU, 64, col, 3.0)
