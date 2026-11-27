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

# V7 Task 1: read-only origin label for the HUD. The titles stay authored JSON;
# a missing entry falls back to the stored id and never invents narrative.
func active_origin_title() -> String:
	var entry = origins.get(active_origin_id, null)
	if typeof(entry) == TYPE_DICTIONARY:
		var title := str((entry as Dictionary).get("title", ""))
		if not title.is_empty():
			return title
	return active_origin_id

# --- V6 Task 2B: shortcut gate flags ----------------------------------------
# Progress flags only. The narrative graph stays in data/story_nodes.json; this
# is the single place that copies a shortcut flag into story_flags and persists
# it through the merged "story_state" write, which never touches "tuning".
const SHORTCUT_BLAME_FLAG: String = "shortcut_blame_unlocked"
const SHORTCUT_ECLIPSE_FLAG: String = "shortcut_eclipse_unlocked"
# V6 Task 6: the dead-end sanctum grants the finale flag instead of a shortcut.
const ECLIPSE_SANCTUM_FLAG: String = "eclipse_sanctum_cleared"
const REGION_CLEAR_FLAGS: Array[String] = [SHORTCUT_BLAME_FLAG, SHORTCUT_ECLIPSE_FLAG, ECLIPSE_SANCTUM_FLAG]
const REGION_CLEAR_NOTES: Array[String] = [
	"SHORTCUT UNLOCKED — BLAME! MEGASTRUCTURE",
	"SHORTCUT UNLOCKED — GOTHIC ECLIPSE",
	"ECLIPSE SANCTUM MASTERED",
]
const RANK_VALUE: Dictionary = {"S": 4, "A": 3, "B": 2, "C": 1}

# Per-region bests, persisted inside "story_state" next to the flags.
var region_mastery: Dictionary = {}
# V7 Task 1: authored story-choice rivals already K.O.'d (deduplicated ids).
var story_rivals_defeated: Array[String] = []

# Region order matches REGION_NAMES / CURATED_REGION_LAYOUTS: 0 hub, 1 megastruc,
# 2 sanctum. Region 2 owns no outgoing shortcut, so its clear flag is the V6
# finale flag; the KO handler uses this as the one place progression is granted.
func shortcut_flag_for_region(region_idx: int) -> String:
	match region_idx:
		0: return SHORTCUT_BLAME_FLAG
		1: return SHORTCUT_ECLIPSE_FLAG
		2: return ECLIPSE_SANCTUM_FLAG
	return ""

func region_clear_note(region_idx: int) -> String:
	return REGION_CLEAR_NOTES[clampi(region_idx, 0, REGION_CLEAR_NOTES.size() - 1)]

# --- V6 Task 6 + V7 Task 1: regional mastery --------------------------------
# Writes the region's clear flag plus its best rank/time/count, the origin that
# owns the best and the origins that have cleared it in one merged save, so a
# defeat card and a stored best can never disagree. Ranks only ever move up.
# The extra arguments default, so the 3-argument callers keep working.
func record_region_victory(region_idx: int, rank: String, elapsed: float, origin_id: String = "", is_story_rival: bool = false, rival_name: String = "") -> Dictionary:
	var idx: int = clampi(region_idx, 0, REGION_CLEAR_FLAGS.size() - 1)
	story_flags[REGION_CLEAR_FLAGS[idx]] = true
	var key := str(idx)
	var prev: Dictionary = {}
	if typeof(region_mastery.get(key, null)) == TYPE_DICTIONARY:
		prev = region_mastery[key]
	var origin: String = origin_id if not origin_id.is_empty() else active_origin_id
	var prev_best: String = str(prev.get("best_rank", ""))
	var new_best: bool = prev_best.is_empty() or _rank_value(rank) > _rank_value(prev_best)
	var best_rank: String = prev_best
	if new_best:
		best_rank = rank if _rank_value(rank) > 0 else "C"
	var best_time: float = float(prev.get("best_time", 0.0))
	if elapsed > 0.0 and (best_time <= 0.0 or elapsed < best_time):
		best_time = elapsed
	var best_origin: String = str(prev.get("best_origin", ""))
	if new_best or best_origin.is_empty():
		best_origin = origin
	var cleared_origins: Array[String] = []
	var raw_cleared = prev.get("cleared_origins", [])
	if typeof(raw_cleared) == TYPE_ARRAY:
		for o in raw_cleared:
			var cleared_id := str(o)
			if not cleared_id.is_empty() and not cleared_origins.has(cleared_id):
				cleared_origins.append(cleared_id)
	if not origin.is_empty() and not cleared_origins.has(origin):
		cleared_origins.append(origin)
	var entry := {
		"best_rank": best_rank,
		"best_time": best_time,
		"clears": maxi(0, int(prev.get("clears", 0))) + 1,
		"last_rank": rank,
		"best_origin": best_origin,
		"cleared_origins": cleared_origins,
	}
	region_mastery[key] = entry
	if is_story_rival:
		_note_story_rival(rival_name)
	save_state()
	return entry.duplicate(true)

# Authored story-choice rivals only. Ids are the node's rival_name, deduplicated
# so replaying the same encounter cannot inflate the tally.
func _note_story_rival(rival_name: String) -> void:
	var rival_id := rival_name.strip_edges()
	if rival_id.is_empty():
		rival_id = "STORY_RIVAL"
	if not story_rivals_defeated.has(rival_id):
		story_rivals_defeated.append(rival_id)

func story_rivals_defeated_count() -> int:
	return story_rivals_defeated.size()

func get_region_mastery(region_idx: int) -> Dictionary:
	var saved = region_mastery.get(str(clampi(region_idx, 0, REGION_CLEAR_FLAGS.size() - 1)), null)
	if typeof(saved) == TYPE_DICTIONARY:
		return (saved as Dictionary).duplicate(true)
	return {"best_rank": "", "best_time": 0.0, "clears": 0, "last_rank": "", "best_origin": "", "cleared_origins": []}

func is_vertical_slice_cleared() -> bool:
	for f in REGION_CLEAR_FLAGS:
		if not has_flag(f):
			return false
	return true

# Wipes progression only: shortcut/finale flags and every mastery record. The
# merged writer leaves "tuning" untouched, so tuned sliders survive a replay.
func reset_progression_flags() -> void:
	for f in REGION_CLEAR_FLAGS:
		story_flags.erase(f)
	region_mastery.clear()
	story_rivals_defeated.clear()
	save_state()

func _rank_value(rank: String) -> int:
	return int(RANK_VALUE.get(rank, 0))

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
		"region_mastery": region_mastery,
		"story_rivals_defeated": story_rivals_defeated,
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
	region_mastery = {}
	if typeof(s.get("region_mastery", null)) == TYPE_DICTIONARY:
		region_mastery = s["region_mastery"]
	story_rivals_defeated.clear()
	if typeof(s.get("story_rivals_defeated", null)) == TYPE_ARRAY:
		for r in s["story_rivals_defeated"]:
			var rival_id := str(r)
			if not rival_id.is_empty() and not story_rivals_defeated.has(rival_id):
				story_rivals_defeated.append(rival_id)
	if typeof(s.get("completed_nodes", null)) == TYPE_ARRAY:
		completed_nodes.clear()
		for n in s["completed_nodes"]:
			completed_nodes.append(str(n))
	if typeof(s.get("unlocks", null)) == TYPE_DICTIONARY:
		unlocks = s["unlocks"]
