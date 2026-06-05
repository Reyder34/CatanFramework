class_name GameState
extends RefCounted

const PLAYER_COLORS := [
	Color.CRIMSON,
	Color.DODGER_BLUE,
	Color.WHITE,
	Color.ORANGE,
]

enum Phase {
	SETUP,
	PLAY,
	GAME_OVER,
}

var registry: GameRegistry
var players: Array = []
var current_player_index: int = 0
var build_mode_id: String = ""
var phase: int = Phase.SETUP

# Sous-phase libre, gérée par les mods.
# Convention: ids préfixés par mod_id (ex: "vanilla_robber:move", "classic_catan:free_road_building")
# "" = aucune sous-phase active
var sub_phase: String = ""

var winner_index: int = -1

func _init(p_registry: GameRegistry, player_count: int = 4) -> void:
	registry = p_registry
	for i in player_count:
		var p := Player.new(i, PLAYER_COLORS[i])
		_init_player_resources(p)
		players.append(p)

func _init_player_resources(player: Player) -> void:
	player.resources = {}
	for res_id in registry.resources:
		player.resources[res_id] = 0

func current_player() -> Player:
	return players[current_player_index]

# Tour suivant: round-robin pur. Les règles de setup (ordre snake, etc.)
# sont gérées par le mod qui pilote current_player_index pendant SETUP.
func next_player() -> void:
	current_player_index = (current_player_index + 1) % players.size()
	build_mode_id = ""

# Vrai si une sous-phase est active (le joueur ne peut pas faire d'actions globales)
func is_busy() -> bool:
	return sub_phase != ""

func mode_label() -> String:
	if build_mode_id == "":
		return "AUCUN"
	var b: BuildingType = registry.get_building(build_mode_id)
	return b.display_name if b else "?"

func phase_label() -> String:
	match phase:
		Phase.SETUP:
			if sub_phase != "":
				return registry.get_sub_phase_label(sub_phase)
			return "Mise en place"
		Phase.PLAY:
			if sub_phase != "":
				return registry.get_sub_phase_label(sub_phase)
			return "Tour de jeu"
		Phase.GAME_OVER:
			return "Joueur %d gagne!" % winner_index
	return ""
