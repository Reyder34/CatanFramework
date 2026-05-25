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

var module: GameModule
var players: Array = []
var current_player_index: int = 0
var build_mode_id: String = ""
var phase: int = Phase.INITIAL_PLACEMENT
var winner_index: int = -1

var sub_phase: int = SubPhase.NONE
# File des joueurs devant défausser (indices)
var discard_queue: Array = []
# Joueur qui a lancé le 7 (pour les sous-phases suivantes)
var roller_index: int = 0

# === État de la phase de placement initial ===
# Compte combien de placements (colonie+route = 1 placement) chaque joueur a faits
var initial_placements: Array = []
# Direction du serpent: 1 normal, -1 inversé
var initial_direction: int = 1
# Dernière colonie posée par le joueur actif (pour forcer la route adjacente)
var last_initial_settlement_key: String = ""

func _init(p_module: GameModule, player_count: int = 4) -> void:
	module = p_module
	for i in player_count:
		var p := Player.new(i, PLAYER_COLORS[i])
		module.init_player_resources(p)
		players.append(p)
		initial_placements.append(0)

func current_player() -> Player:
	return players[current_player_index]

func next_player() -> void:
	if phase == Phase.INITIAL_PLACEMENT:
		return  # géré par advance_initial_placement
	current_player_index = (current_player_index + 1) % players.size()
	build_mode_id = ""

# Appelé après que le joueur a posé colonie + route en phase initiale
func advance_initial_placement() -> void:
	initial_placements[current_player_index] += 1
	last_initial_settlement_key = ""
	
	# Tous les joueurs ont-ils fait leurs 2 placements?
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
	
	# Sinon: serpent
	# Si on est en aller (direction=1) et qu'on vient de finir le dernier joueur,
	# il rejoue (direction passe à -1, on ne change pas d'index)
	# Si on est en retour (direction=-1) et qu'on vient de finir le premier joueur,
	# c'est la fin (gérée plus haut par all_done)
	if initial_direction == 1 and current_player_index == players.size() - 1:
		initial_direction = -1
		# le dernier joueur joue son 2e placement: pas de changement d'index
	elif initial_direction == -1 and current_player_index == 0:
		# le premier joueur finit son 2e, mais all_done aurait dû déclencher
		pass
	else:
		current_player_index += initial_direction
	build_mode_id = ""

func mode_label() -> String:
	if build_mode_id == "":
		return "AUCUN"
	var b: BuildingType = module.get_building(build_mode_id)
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
