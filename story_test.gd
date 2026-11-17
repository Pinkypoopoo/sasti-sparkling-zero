extends SceneTree

# Schema gate for res://data/story_nodes.json.
# Run: godot --headless --path . --script res://story_test.gd
# Prints STORY_SCHEMA_PASS only when every origin, node and choice is loadable
# and every choice points at a node that actually exists.

const STORY_PATH := "res://data/story_nodes.json"

var failures: Array[String] = []

func _initialize() -> void:
	var raw := FileAccess.get_file_as_string(STORY_PATH)
	if raw.is_empty():
		print("STORY_SCHEMA_FAIL: %s missing or empty" % STORY_PATH)
		quit(1)
		return
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		print("STORY_SCHEMA_FAIL: %s is not a JSON object" % STORY_PATH)
		quit(1)
		return
	_validate(parsed)
	if failures.is_empty():
		print("STORY_SCHEMA_PASS")
		quit(0)
	else:
		for f in failures:
			print("  FAIL " + f)
		print("STORY_SCHEMA_FAIL: %d problem(s)" % failures.size())
		quit(1)

func need(d: Dictionary, key: String, label: String) -> bool:
	if not d.has(key):
		failures.append("%s is missing '%s'" % [label, key])
		return false
	return true

func _validate(doc: Dictionary) -> void:
	if not need(doc, "schema_version", "document"): return
	if not (typeof(doc["schema_version"]) == TYPE_INT or typeof(doc["schema_version"]) == TYPE_FLOAT):
		failures.append("schema_version must be a number")
	if int(doc["schema_version"]) != 1:
		failures.append("schema_version %s has no loader (expected 1)" % str(doc["schema_version"]))
	if not need(doc, "origins", "document"): return
	if not need(doc, "nodes", "document"): return

	var nodes: Dictionary = doc["nodes"]
	if nodes.is_empty():
		failures.append("nodes is empty")
		return

	var origins: Dictionary = doc["origins"]
	if origins.size() != 4:
		failures.append("expected 4 origins, found %d" % origins.size())
	for okey in origins.keys():
		var o: Dictionary = origins[okey]
		var olab := "origin '%s'" % str(okey)
		for k in ["title", "start_node", "eye_shape", "eye_hue"]:
			need(o, k, olab)
		if o.has("start_node") and not nodes.has(str(o["start_node"])):
			failures.append("%s start_node '%s' is not in nodes" % [olab, str(o["start_node"])])
		if o.has("eye_shape") and not (int(o["eye_shape"]) >= 0 and int(o["eye_shape"]) <= 4):
			failures.append("%s eye_shape must be 0..4" % olab)
		if o.has("eye_hue") and not (float(o["eye_hue"]) >= 0.0 and float(o["eye_hue"]) <= 1.0):
			failures.append("%s eye_hue must be 0..1" % olab)

	for nkey in nodes.keys():
		var n: Dictionary = nodes[nkey]
		var nlab := "node '%s'" % str(nkey)
		for k in ["title", "region", "rival_name", "rival_slots", "rival_hp", "desc", "choices"]:
			need(n, k, nlab)
		if not n.has("choices"): continue
		var choices: Array = n["choices"]
		if choices.is_empty():
			failures.append("%s has no choices (the story would dead-end)" % nlab)
		for i in range(choices.size()):
			var ch: Dictionary = choices[i]
			var clab := "%s choice %d" % [nlab, i]
			for k in ["text", "next"]:
				need(ch, k, clab)
			if ch.has("next") and not nodes.has(str(ch["next"])):
				failures.append("%s points at missing node '%s'" % [clab, str(ch["next"])])
			if ch.has("requires_flags") and typeof(ch["requires_flags"]) != TYPE_ARRAY:
				failures.append("%s requires_flags must be an array" % clab)
			if ch.has("grants_unlocks") and typeof(ch["grants_unlocks"]) != TYPE_ARRAY:
				failures.append("%s grants_unlocks must be an array" % clab)
		if n.has("rival_slots"):
			var slots: Dictionary = n["rival_slots"]
			for s in ["Slot_HeadMask_", "Slot_VeilCloak_", "Slot_UpperGarb_", "Slot_LowerSkirt_", "Slot_Weapon_"]:
				if not slots.has(s):
					failures.append("%s rival_slots is missing %s" % [nlab, s])
				elif not (str(slots[s]) in ["HERO", "VEIL", "NONE", "ANIME_FACE"]):
					failures.append("%s rival_slots.%s = '%s' is not HERO/VEIL/NONE/ANIME_FACE" % [nlab, s, str(slots[s])])
