class_name WorldStoryManager
extends Node

# Story graph now lives in res://data/story_nodes.json (validated by story_test.gd
# in verify.sh) instead of hardcoded dictionaries, and the player's position in it
# is persisted next to the combat tuning in user://dev_profile.json.
const STORY_PATH: String = "res://data/story_nodes.json"
const PROFILE_PATH: String = "user://dev_profile.json"
const SCHEMA_VERSION: int = 1

var active_origin_id: String = "Profile_1"
var current_node_id: String = "node_start_sanctuary"
var story_flags: Dictionary = {}
var completed_nodes: Array[String] = []
var unlocks: Dictionary = {}
var schema_ok: bool = false
var last_blocked_reason: String = ""

var origins: Dictionary = {}
var story_nodes: Dictionary = {}

func _ready() -> void:
	load_story_data()
	load_state()

# Returns false (and leaves the story empty) if the JSON is missing or malformed.
# verify.sh runs story_test.gd against the same file, so a broken edit cannot ship.
func load_story_data() -> bool:
	schema_ok = false
	if not FileAccess.file_exists(STORY_PATH):
		push_warning("WorldStory: %s is missing" % STORY_PATH)
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(STORY_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("WorldStory: %s is not a JSON object" % STORY_PATH)
		return false
	var doc: Dictionary = parsed
	if int(doc.get("schema_version", 0)) != SCHEMA_VERSION:
		push_warning("WorldStory: schema_version %s unsupported" % str(doc.get("schema_version", -1)))
		return false
	if typeof(doc.get("origins", null)) != TYPE_DICTIONARY or typeof(doc.get("nodes", null)) != TYPE_DICTIONARY:
		push_warning("WorldStory: origins/nodes missing")
		return false
	var loaded_nodes: Dictionary = doc["nodes"]
	if loaded_nodes.is_empty():
		push_warning("WorldStory: no nodes")
		return false
	origins = doc["origins"]
	story_nodes = loaded_nodes
	if not story_nodes.has(current_node_id):
		current_node_id = _origin_start(active_origin_id, str(story_nodes.keys()[0]))
	schema_ok = true
	return true

func get_current_node() -> Dictionary:
	var node = story_nodes.get(current_node_id, {})
	return node if typeof(node) == TYPE_DICTIONARY else {}

func node_exists(node_id: String) -> bool:
	return story_nodes.has(node_id)

# --- V6 Task 2B: shortcut gate flags ----------------------------------------
# Progress flags only. The narrative graph stays in data/story_nodes.json; this
# is the single place that copies a shortcut flag into story_flags and persists
# it through the merged "story_state" write, which never touches "tuning".
const SHORTCUT_BLAME_FLAG: String = "shortcut_blame_unlocked"
const SHORTCUT_ECLIPSE_FLAG: String = "shortcut_eclipse_unlocked"

# Region order matches REGION_NAMES / CURATED_REGION_LAYOUTS: 0 hub, 1 megastruc.
# Region 2 is the dead end, so it owns no outgoing progression flag.
func shortcut_flag_for_region(region_idx: int) -> String:
	match region_idx:
		0: return SHORTCUT_BLAME_FLAG
		1: return SHORTCUT_ECLIPSE_FLAG
	return ""

func has_flag(flag: String) -> bool:
	return (not flag.is_empty()) and bool(story_flags.get(flag, false))

# Returns true only on a real change, so a repeated KO cannot spam a save.
func unlock_shortcut(flag: String) -> bool:
	if flag.is_empty() or bool(story_flags.get(flag, false)):
		return false
	story_flags[flag] = true
	save_state()
	return true

func select_origin(profile_key: String) -> Dictionary:
	if typeof(origins.get(profile_key, null)) == TYPE_DICTIONARY:
		active_origin_id = profile_key
		current_node_id = _origin_start(profile_key, current_node_id)
		save_state()
	return get_current_node()

# Origin entries are authored JSON: a missing or non-dictionary entry must fall
# back to a node that exists instead of erroring on a null cast.
func _origin_start(profile_key: String, fallback: String) -> String:
	var entry = origins.get(profile_key, null)
	if typeof(entry) != TYPE_DICTIONARY:
		return fallback
	var start := str((entry as Dictionary).get("start_node", fallback))
	if story_nodes.is_empty() or story_nodes.has(start):
		return start
	return fallback

func _flags_met(choice: Dictionary) -> bool:
	var raw_required = choice.get("requires_flags", [])
	if typeof(raw_required) != TYPE_ARRAY:
		return true  # a malformed gate must never lock the player out of the story
	var required: Array = raw_required
	for f in required:
		if not bool(story_flags.get(str(f), false)):
			return false
	return true

func make_choice(choice_idx: int) -> Dictionary:
	var node := get_current_node()
	if node.is_empty():
		return node
	# Half-authored nodes must degrade to "do nothing", never crash the duel.
	var raw_choices = node.get("choices", [])
	if typeof(raw_choices) != TYPE_ARRAY:
		return node
	var choices: Array = raw_choices
	if choice_idx < 0 or choice_idx >= choices.size():
		return node
	if typeof(choices[choice_idx]) != TYPE_DICTIONARY:
		return node
	var ch: Dictionary = choices[choice_idx]
	if not _flags_met(ch):
		# Reserved for later gating: every choice currently requires nothing.
		last_blocked_reason = "LOCKED: needs " + str(ch.get("requires_flags", []))
		return node
	last_blocked_reason = ""
	var flag: String = str(ch.get("flag", ""))
	if not flag.is_empty():
		story_flags[flag] = true
	var raw_unlocks = ch.get("grants_unlocks", [])
	if typeof(raw_unlocks) == TYPE_ARRAY:
		for u in raw_unlocks:
			unlocks[str(u)] = true
	completed_nodes.append(current_node_id)
	current_node_id = str(ch.get("next", current_node_id))
	save_state()
	return get_current_node()

# --- Persistence (shares user://dev_profile.json with CombatData) -------------
func save_state() -> void:
	if not schema_ok:
		return
	var doc: Dictionary = {}
	if FileAccess.file_exists(PROFILE_PATH):
		var old_f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
		if old_f:
			var old = JSON.parse_string(old_f.get_as_text())
			if typeof(old) == TYPE_DICTIONARY:
				doc = old
	# Key name is part of the contract (.agents/rules/world-story.md): "story_state".
	# The old reader/writer used "story"; load_state() still migrates it once and
	# this writer removes it so the two copies can never diverge.
	doc["story_state"] = {
		"schema_version": SCHEMA_VERSION,
		"active_origin_id": active_origin_id,
		"current_node_id": current_node_id,
		"story_flags": story_flags,
		"completed_nodes": completed_nodes,
		"unlocks": unlocks,
	}
	doc.erase("story")
	var w := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if w:
		w.store_string(JSON.stringify(doc, "\t"))

func load_state() -> void:
	if not FileAccess.file_exists(PROFILE_PATH):
		return
	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if not f:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var doc: Dictionary = parsed
	var st = doc.get("story_state", doc.get("story", null))
	if typeof(st) != TYPE_DICTIONARY:
		return
	var s: Dictionary = st
	if int(s.get("schema_version", 0)) != SCHEMA_VERSION:
		return
	active_origin_id = str(s.get("active_origin_id", active_origin_id))
	var saved_node := str(s.get("current_node_id", current_node_id))
	if story_nodes.is_empty() or story_nodes.has(saved_node):
		current_node_id = saved_node
	if typeof(s.get("story_flags", null)) == TYPE_DICTIONARY:
		story_flags = s["story_flags"]
	if typeof(s.get("completed_nodes", null)) == TYPE_ARRAY:
		completed_nodes.clear()
		for n in s["completed_nodes"]:
			completed_nodes.append(str(n))
	if typeof(s.get("unlocks", null)) == TYPE_DICTIONARY:
		unlocks = s["unlocks"]
