class_name WorldStoryManager
extends Node

var active_origin_id: String = "Profile_1"
var current_node_id: String = "node_start_sanctuary"
var story_flags: Dictionary = {}
var completed_nodes: Array[String] = []

var origins: Dictionary = {
	"Profile_1": {
		"title": "Ash Inquisitor (Ink Cathedral)",
		"start_node": "node_start_sanctuary",
		"eye_shape": 0, "eye_hue": 0.98
	},
	"Profile_2": {
		"title": "Gilded Veil Apostate (Cathedral Choir)",
		"start_node": "node_boss_veil_duel",
		"eye_shape": 2, "eye_hue": 0.14
	},
	"Profile_3": {
		"title": "Silicon Nomad (Blame! Megastructure)",
		"start_node": "node_megastructure_descent",
		"eye_shape": 1, "eye_hue": 0.52
	},
	"Profile_4": {
		"title": "Eclipse Sovereign (Gothic Dusk)",
		"start_node": "node_eclipse_summit",
		"eye_shape": 3, "eye_hue": 0.02
	}
}

var story_nodes: Dictionary = {
	"node_start_sanctuary": {
		"title": "Node 1: The Shattered Threshold",
		"region": "INK_CATHEDRAL",
		"rival_name": "INQUISITOR VANGUARD",
		"rival_slots": {"Slot_HeadMask_": "HERO", "Slot_VeilCloak_": "VEIL", "Slot_UpperGarb_": "HERO", "Slot_LowerSkirt_": "VEIL", "Slot_Weapon_": "HERO"},
		"rival_scale": 1.05,
		"rival_hp": 1500.0,
		"desc": "You wake beneath the weeping arches of the Ink Cathedral. A scarred Inquisitor in hybrid obsidian-and-lace vestments blocks the stairway to the Megastructure elevator.",
		"choices": [
			{"text": "Draw blade & challenge the Gilded Veil Apostate", "next": "node_boss_veil_duel", "flag": "fought_inquisitor"},
			{"text": "Descend into the Blame! Megastructure shaft", "next": "node_megastructure_descent", "flag": "took_elevator"}
		]
	},
	"node_boss_veil_duel": {
		"title": "Node 2: The Gilded Veil Duel",
		"region": "INK_CATHEDRAL",
		"rival_name": "LADY OF THE GILDED VEIL",
		"rival_slots": {"Slot_HeadMask_": "VEIL", "Slot_VeilCloak_": "VEIL", "Slot_UpperGarb_": "VEIL", "Slot_LowerSkirt_": "VEIL", "Slot_Weapon_": "VEIL"},
		"rival_scale": 1.12,
		"rival_hp": 1950.0,
		"desc": "The Gilded Veil Boss descends in a storm of porcelain lilies and gold filigree. Her ritual blade hums with cathedral resonance.",
		"choices": [
			{"text": "Shatter her posture & claim the Cathedral Relic", "next": "node_eclipse_summit", "flag": "claimed_relic"},
			{"text": "Spare her & pursue the Silicon Nomad into the Abyss", "next": "node_megastructure_descent", "flag": "allied_with_veil"}
		]
	},
	"node_megastructure_descent": {
		"title": "Node 3: The Abyssal Megastructure (Blame!)",
		"region": "BLAME_MEGASTRUC",
		"rival_name": "SILICON NOMADEXECUTIONER",
		"rival_slots": {"Slot_HeadMask_": "HERO", "Slot_VeilCloak_": "NONE", "Slot_UpperGarb_": "HERO", "Slot_LowerSkirt_": "HERO", "Slot_Weapon_": "VEIL"},
		"rival_scale": 1.18,
		"rival_hp": 2200.0,
		"desc": "Cold cyan fog rolls across brutalist megastructure bridges. The Silicon Nomad intercepts your path with Sandevistan afterimages.",
		"choices": [
			{"text": "Overload the reactor & ascend to the Gothic Eclipse", "next": "node_eclipse_summit", "flag": "reactor_overloaded"},
			{"text": "Return to the Ink Cathedral Sanctuary", "next": "node_start_sanctuary", "flag": "returned_sanctuary"}
		]
	},
	"node_eclipse_summit": {
		"title": "Node 4: The Gothic Eclipse Convergence",
		"region": "GOTHIC_ECLIPSE",
		"rival_name": "ECLIPSE SOVEREIGN (FINAL RIVAL)",
		"rival_slots": {"Slot_HeadMask_": "VEIL", "Slot_VeilCloak_": "HERO", "Slot_UpperGarb_": "VEIL", "Slot_LowerSkirt_": "HERO", "Slot_Weapon_": "HERO"},
		"rival_scale": 1.25,
		"rival_hp": 2600.0,
		"desc": "Beneath a blood-red eclipsed sun, your intertwined paths collide. The Eclipse Sovereign awaits at the shattered altar for the final duel.",
		"choices": [
			{"text": "Begin New Cycle (Keep Unlocks & Replay)", "next": "node_start_sanctuary", "flag": "cycle_complete"}
		]
	}
}

func get_current_node() -> Dictionary:
	return story_nodes.get(current_node_id, story_nodes["node_start_sanctuary"])

func select_origin(profile_key: String) -> Dictionary:
	if origins.has(profile_key):
		active_origin_id = profile_key
		current_node_id = str(origins[profile_key].get("start_node", "node_start_sanctuary"))
	return get_current_node()

func make_choice(choice_idx: int) -> Dictionary:
	var node := get_current_node()
	var choices: Array = node.get("choices", [])
	if choice_idx >= 0 and choice_idx < choices.size():
		var ch: Dictionary = choices[choice_idx]
		var flag: String = str(ch.get("flag", ""))
		if not flag.is_empty():
			story_flags[flag] = true
		completed_nodes.append(current_node_id)
		current_node_id = str(ch.get("next", "node_start_sanctuary"))
	return get_current_node()
