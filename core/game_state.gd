class_name GameState
extends RefCounted

const PLAYER_COLORS := [
	Color.CRIMSON,
	Color.DODGER_BLUE,
	Color.WHITE,
	Color.ORANGE,
]

enum Phase {
	INITIAL_PLACEMENT,
	PLAY,
	GAME_OVER,
}

enum SubPhase {
	NONE,
	ROBBER_DISCARD,
	ROBBER_MOVE,
	ROBBER_STEAL,
}

var registry: GameRegistry  # remplace l'ancien "module"
var players: Array = []
var current_player_index: int = 0
var build_mode_id: String = ""
var phase: int = Phase.INITIAL_PLACEMENT
var sub_phase: int = SubPhase.NONE
var winner_index: int = -1

# Phase initiale
var initial_placements: Array = []
var initial_direction: int = 1
var last_initial_settlement_key: String = ""

# Voleur (pour les mods futurs qui géreront ces sous-phases)
var discard_queue: Array = []
var roller_index: int = 0

func _init(p_registry: GameRegistry, player_count: int = 4) -> void:
	registry = p_registry
	for i in player_count:
		var p := Player.new(i, PLAYER_COLORS[i])
		_init_player_resources(p)
		players.append(p)
		initial_placements.append(0)

func _init_player_resources(player: Player) -> void:
	player.resources = {}
	for res_id in registry.resources:
		player.resources[res_id] = 0

func current_player() -> Player:
	return players[current_player_index]

func next_player() -> void:
	if phase == Phase.INITIAL_PLACEMENT:
		return
	current_player_index = (current_player_index + 1) % players.size()
	build_mode_id = ""

func advance_initial_placement() -> void:
	initial_placements[current_player_index] += 1
	last_initial_settlement_key = ""
	
	var all_done := true
	for count in initial_placements:
		if count < 2:
			all_done = false
			break
	if all_done:
		phase = Phase.PLAY
		current_player_index = 0
		build_mode_id = ""
		return
	
	if initial_direction == 1 and current_player_index == players.size() - 1:
		initial_direction = -1
	elif initial_direction == -1 and current_player_index == 0:
		pass
	else:
		current_player_index += initial_direction
	build_mode_id = ""

func mode_label() -> String:
	if build_mode_id == "":
		return "AUCUN"
	var b: BuildingType = registry.get_building(build_mode_id)
	return b.display_name if b else "?"

func phase_label() -> String:
	match phase:
		Phase.INITIAL_PLACEMENT:
			var step := "colonie" if last_initial_settlement_key == "" else "route"
			return "Placement initial (poser %s)" % step
		Phase.PLAY:
			match sub_phase:
				SubPhase.ROBBER_DISCARD:
					return "Défausse en cours"
				SubPhase.ROBBER_MOVE:
					return "Déplace le voleur (clique une tuile)"
				SubPhase.ROBBER_STEAL:
					return "Choisis une cible à voler"
				_:
					return "Tour de jeu"
		Phase.GAME_OVER:
			return "Joueur %d gagne!" % winner_index
	return ""
