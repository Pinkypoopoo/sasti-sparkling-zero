class_name WorldStoryManager
extends Node

var current_node_id: String = "node_start_sanctuary"
var story_flags: Dictionary = {}
var completed_nodes: Array[String] = []

var story_nodes: Dictionary = {
	"node_start_sanctuary": {
		"title": "Node 1: The Shattered Threshold",
		"region": "INK_CATHEDRAL",
		"desc": "You wake beneath the weeping arches of the Ink Cathedral. A scarred figure in obsidian vestments blocks the stairway to the megastructure elevator.",
		"choices": [
			{"text": "Draw blade and challenge the Inquisitor (Fight Profile 2)", "next": "node_boss_veil_duel", "flag": "fought_inquisitor"},
			{"text": "Offer silent passage through the catacombs (Gain Touki Mana)", "next": "node_megastructure_descent", "flag": "pacifist_catacombs"}
		]
	},
	"node_boss_veil_duel": {
		"title": "Node 2: The Gilded Veil Duel",
		"region": "INK_CATHEDRAL",
		"desc": "The Gilded Veil Boss descends in a cloud of white lilies and gold filigree. She demands to know your allegiance.",
		"choices": [
			{"text": "Seize the Cathedral Relic by force", "next": "node_eclipse_summit", "flag": "claimed_relic"},
			{"text": "Bargain with her for regional intelligence", "next": "node_megastructure_descent", "flag": "allied_with_veil"}
		]
	},
	"node_megastructure_descent": {
		"title": "Node 3: The Abyssal Megastructure (*Blame!*)",
		"desc": "You plunge into the endless vertical rust pipes of the Megastructure. Automated defense drones and rogue warriors bar the elevator shaft.",
		"choices": [
			{"text": "Overload the reactor core with Riptide Spells", "next": "node_eclipse_summit", "flag": "reactor_overloaded"},
			{"text": "Slash through the vanguard hand-to-hand", "next": "node_eclipse_summit", "flag": "vanguard_slain"}
		]
	},
	"node_eclipse_summit": {
		"title": "Node 4: The Gothic Eclipse & Final Confrontation",
		"desc": "The red sun eclipses the cathedral spires. All surviving rival characters converge for the final duel.",
		"choices": [
			{"text": "Ascend to the God-Eater Throne (Victory)", "next": "node_start_sanctuary", "flag": "game_completed"}
		]
	}
}

func get_current_node() -> Dictionary:
	return story_nodes.get(current_node_id, story_nodes["node_start_sanctuary"])

func make_choice(choice_idx: int) -> void:
	var node := get_current_node()
	var choices: Array = node.get("choices", [])
	if choice_idx >= 0 and choice_idx < choices.size():
		var ch: Dictionary = choices[choice_idx]
		var flag: String = str(ch.get("flag", ""))
		if not flag.is_empty():
			story_flags[flag] = true
		completed_nodes.append(current_node_id)
		current_node_id = str(ch.get("next", "node_start_sanctuary"))
