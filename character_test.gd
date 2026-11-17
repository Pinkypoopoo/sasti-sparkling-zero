extends SceneTree

# Contract test for the generated character GLBs (tools/build_character.py).
#
# character_body_3d.gd depends on things that a clean headless boot will NOT
# report if they go missing: bone names for the hitbox, the cloak spring and the
# ragdoll list; Slot_* node names for the modular outfit switcher; and the five
# animation clips. A silent regression there looks like "the sword stopped
# following the arm", so it gets its own gate.
#
# Run: godot --headless --path . --script res://character_test.gd

const MODELS: Array[String] = ["res://models/hero.glb", "res://models/boss_veil.glb"]
const BONES: Array[String] = ["Root", "Spine", "Head", "Arm_L", "Arm_R", "Veil_Back"]
const CLIPS: Array[String] = ["idle", "slash_up", "slash_down", "slash_side", "guard_sway"]
const SLOTS: Array[String] = ["Slot_HeadMask_", "Slot_VeilCloak_", "Slot_UpperGarb_", "Slot_LowerSkirt_", "Slot_Weapon_"]

var failures: Array[String] = []

func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   " + label)
	else:
		print("  FAIL " + label)
		failures.append(label)

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r: return r
	return null

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim(c)
		if r: return r
	return null

func _collect_names(n: Node, out: Dictionary) -> void:
	out[str(n.name)] = true
	for c in n.get_children():
		_collect_names(c, out)

func _initialize() -> void:
	for path in MODELS:
		var res = load(path)
		check(res is PackedScene, path + " imports as a PackedScene")
		if not (res is PackedScene):
			continue
		var scene: Node = (res as PackedScene).instantiate()
		root.add_child(scene)

		var skel := _find_skeleton(scene)
		check(skel != null, path + " has a Skeleton3D")
		if skel:
			for b in BONES:
				check(skel.find_bone(b) != -1, path + " bone '" + b + "'")

		var ap := _find_anim(scene)
		check(ap != null, path + " has an AnimationPlayer")
		if ap:
			for clip in CLIPS:
				check(ap.has_animation(clip), path + " clip '" + clip + "'")

		var names: Dictionary = {}
		_collect_names(scene, names)
		for slot in SLOTS:
			check(names.has(slot + "HERO") or names.has(slot + "VEIL"), path + " node '" + slot + "*'")

		scene.queue_free()

func _process(_delta: float) -> bool:
	if failures.is_empty():
		print("CHARACTER_TEST_PASS")
		quit(0)
	else:
		print("CHARACTER_TEST_FAIL: %d check(s) failed" % failures.size())
		quit(1)
	return true
