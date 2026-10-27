class_name DevStudio
extends Control

@onready var player: PlayerController = get_node("../Player")
@onready var combat: GestureCombat = get_node("../CombatManager")

var dev_panel: PanelContainer
var tab_container: TabContainer
var telemetry: Label

func _ready() -> void: _build_ui()

func _build_ui() -> void:
	telemetry = Label.new(); add_child(telemetry)
	dev_panel = PanelContainer.new(); dev_panel.visible = false; add_child(dev_panel)
	tab_container = TabContainer.new(); dev_panel.add_child(tab_container)
	_add_tab("Physics", ["run_speed", "sprint_speed", "flight_speed", "dash_speed", "camera_distance", "base_fov", "camera_whip_lag"])
	_add_tab("Race/Dash", ["vanish_strobe_hz", "letterbox_amount"])
	_add_tab("AI/Shader", ["cel_cut_threshold", "outline_width", "rim_strength"])
	_add_tab_ai("Adaptive AI", ["ai_reaction_delay", "ai_adaptation_rate"])

func _add_tab(name: String, props: Array) -> void:
	var vbox = VBoxContainer.new(); vbox.name = name; tab_container.add_child(vbox)
	for p in props: _add_row(vbox, player, p)

func _add_tab_ai(name: String, props: Array) -> void:
	var vbox = VBoxContainer.new(); vbox.name = name; tab_container.add_child(vbox)
	for p in props: _add_row(vbox, combat, p)

func _add_row(parent: Control, target: Object, prop: String) -> void:
	var row = HBoxContainer.new(); parent.add_child(row)
	var lbl = Label.new(); lbl.text = prop; row.add_child(lbl)
	var spin = SpinBox.new(); spin.allow_greater = true; spin.allow_lesser = true
	spin.value = target.get(prop) if target.get(prop) != null else 0.0
	spin.value_changed.connect(func(v): target.set(prop, v))
	row.add_child(spin)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fly"): # Temporary hijack for Tab simulation in headless
		dev_panel.visible = !dev_panel.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if dev_panel.visible else Input.MOUSE_MODE_CAPTURED

func _process(_delta: float) -> void:
	telemetry.text = "FPS: %d" % Engine.get_frames_per_second()
	queue_redraw()

func _draw() -> void:
	if not combat: return
	_draw_dot(combat.left_dot_pos, 32.0, combat.is_left_dot_active, Color(0.2, 0.6, 1.0, 0.5))
	_draw_dot(combat.right_dot_pos, 34.0, combat.is_right_dot_active, Color(1.0, 0.3, 0.3, 0.5))
	if combat.impact_flash_timer > 0: draw_rect(get_viewport_rect(), Color.WHITE)

func _draw_dot(pos: Vector2, r: float, active: bool, col: Color) -> void:
	draw_circle(pos, r, col)
	if active: draw_arc(pos, r * 4.0, 0, TAU, 32, col, 2.0)
