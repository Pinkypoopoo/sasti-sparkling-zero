extends SceneTree

# Schema gate for res://data/story_nodes.json.
# Run: godot --headless --path . --script res://story_test.gd
# Prints STORY_SCHEMA_PASS only when every origin, node and choice is loadable
# and every choice points at a node that actually exists.

const STORY_PATH := "res://data/story_nodes.json"
const PROFILE_PATH := "user://dev_profile.json"

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
	_check_merged_save()
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
		if n["choices"] == null:
			continue
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
				elif not(["HERO", "VEIL", "NONE"].has(str(slots[s]))):
					failures.append("%s rival_slots.%s = '%s' is not HERO/VEIL/NONE" % [nlab, s, str(slots[s])])

		# V8 Lore Pack: every region must be represented and every node must be
		# reachable from at least one origin start_node through the choice graph.
		var regions: Dictionary = {}
		var reachable: Dictionary = {}
		for okey in origins.keys():
			var start := str(origins[okey].get("start_node", ""))
			if not start.is_empty() and nodes.has(start):
				_regions_add(regions, nodes[start].get("region", "UNKNOWN"))
				_reachable_dfs(start, nodes, reachable)
		for nk2 in nodes.keys():
			var nn: Dictionary = nodes[nk2]
			if nn != null:
				_regions_add(regions, nn.get("region", "UNKNOWN"))
			if not reachable.has(nk2):
				failures.append("node '%s' is not reachable from any origin start_node" % str(nk2))
		var wanted_regions: Array[String] = ["INK_CATHEDRAL", "BLAME_MEGASTRUC", "GOTHIC_ECLIPSE"]
		var missing_regions: Array[String] = []
		for rkey in wanted_regions:
			if not regions.has(rkey):
				missing_regions.append(rkey)
		if not missing_regions.is_empty():
			var mr: String = ""
			for i in range(missing_regions.size()):
				if i > 0:
					mr += ", "
				mr += missing_regions[i]
			if not mr.is_empty():
				failures.append("story nodes are missing region(s): " + mr)

func _regions_add(regions: Dictionary, region: String) -> void:
	if region == "":
		return
	regions[region] = true

func _reachable_dfs(start: String, nodes: Dictionary, reachable: Dictionary) -> void:
	if reachable.has(start):
		return
	reachable[start] = true
	var node: Dictionary = nodes.get(start, {})
	if typeof(node) != TYPE_DICTIONARY:
		return
	var choices: Array = node.get("choices", [])
	if typeof(choices) != TYPE_ARRAY:
		return
	for ch in choices:
		if typeof(ch) != TYPE_DICTIONARY:
			continue
		var nxt: String = str(ch.get("next", ""))
		if not nxt.is_empty() and nodes.has(nxt):
			_reachable_dfs(nxt, nodes, reachable)


# Merged-write round trip. The profile is shared by CombatData ("tuning") and
# WorldStoryManager ("story_state"); either side overwriting the file blindly
# would silently delete the other's progress. The real profile is backed up and
# restored, so running the gate never costs a playtester their save.
func _check_merged_save() -> void:
	var had := FileAccess.file_exists(PROFILE_PATH)
	var backup := FileAccess.get_file_as_string(PROFILE_PATH) if had else ""
	var mgr = load("res://world_story.gd").new()
	if not mgr.load_story_data():
		failures.append("world_story could not load res://data/story_nodes.json")
		mgr.free()
		return
	var seed_f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if seed_f:
		seed_f.store_string(JSON.stringify({
			"tuning": {"enemy_damage": 77.0},
			"story_state": {
				"schema_version": 1,
				"active_origin_id": "Profile_4",
				"current_node_id": "node_eclipse_summit",
				"story_flags": {"probe_flag": true},
				"completed_nodes": ["node_start_sanctuary"],
			},
		}))
		seed_f.close()
	mgr.load_state()
	if not bool(mgr.story_flags.get("probe_flag", false)):
		failures.append("story_state did not round-trip through load_state()")
	mgr.story_flags["written_by_story"] = true
	mgr.save_state()
	var after_story = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if typeof(after_story) != TYPE_DICTIONARY:
		failures.append("profile unreadable after a story save")
	else:
		var d: Dictionary = after_story
		if not d.has("tuning"):
			failures.append("a story save erased 'tuning'")
		if not d.has("story_state"):
			failures.append("a story save did not write 'story_state'")
		if d.has("story"):
			failures.append("a story save still writes the legacy 'story' key")
	# ... and a combat save over that file must keep the story section.
	var cd = load("res://combat_data.gd").new()
	cd.save_to_disk(null, null)
	var after_combat = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if typeof(after_combat) != TYPE_DICTIONARY:
		failures.append("profile unreadable after a combat save")
	else:
		var d2: Dictionary = after_combat
		if not d2.has("tuning"):
			failures.append("a combat save did not write 'tuning'")
		var st = d2.get("story_state", null)
		if typeof(st) != TYPE_DICTIONARY:
			failures.append("a combat save erased 'story_state'")
		else:
			var s: Dictionary = st
			var flags = s.get("story_flags", {})
			if typeof(flags) != TYPE_DICTIONARY or not bool((flags as Dictionary).get("written_by_story", false)):
				failures.append("a combat save lost the story flags")
	cd.free()
	mgr.free()
	if had:
		var rf := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
		if rf:
			rf.store_string(backup)
			rf.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
