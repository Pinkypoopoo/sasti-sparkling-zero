extends SceneTree

var frames_run := 0
var scene_node: Node = null

func _init() -> void:
	print("SMOKE TEST: Script _init() called.")

func _initialize() -> void:
	print("SMOKE TEST: Loading scene...")
	var packed_scene = load("res://character_movement_test.tscn")
	if packed_scene == null:
		print("SMOKE TEST FAIL: Could not load character_movement_test.tscn")
		quit(1)
		return
		
	scene_node = packed_scene.instantiate()
	if scene_node == null:
		print("SMOKE TEST FAIL: Could not instantiate scene.")
		quit(1)
		return
		
	root.add_child(scene_node)
	print("SMOKE TEST: Scene loaded successfully. Running frames...")

func _process(delta: float) -> bool:
	frames_run += 1
	
	# Simulate touch on frame 3
	if frames_run == 3:
		var vp_size = root.get_visible_rect().size
		if vp_size.x == 0: vp_size = Vector2(1152, 648) 
		var left_dot := Vector2(vp_size.x * 0.18, vp_size.y * 0.56)
		var ev := InputEventScreenTouch.new()
		ev.position = left_dot
		ev.pressed = true
		Input.parse_input_event(ev)
		print("SMOKE TEST: Simulated left orb touch.")
		
	# Simulate release on frame 4
	if frames_run == 4:
		var ev := InputEventScreenTouch.new()
		ev.pressed = false
		Input.parse_input_event(ev)
		
	# Simulate touch on right orb frame 5
	if frames_run == 5:
		var vp_size = root.get_visible_rect().size
		if vp_size.x == 0: vp_size = Vector2(1152, 648)
		var right_dot := Vector2(vp_size.x * 0.82, vp_size.y * 0.64)
		var ev := InputEventScreenTouch.new()
		ev.position = right_dot
		ev.pressed = true
		Input.parse_input_event(ev)
		print("SMOKE TEST: Simulated right orb touch.")

	# Toggle DevStudio on frame 7
	if frames_run == 7:
		var dev_studio = scene_node.get_node_or_null("DevStudio")
		if dev_studio and dev_studio.has_method("_toggle_dev_panel"):
			dev_studio._toggle_dev_panel()
			print("SMOKE TEST: Toggled DevStudio panel.")
			
	# Finish on frame 15
	if frames_run >= 15:
		print("SMOKE_TEST_PASS")
		quit(0)
		return true 
		
	return false 
