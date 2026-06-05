class_name KnightCard
extends DevelopmentCard

func _init() -> void:
	id = "knight"
	display_name = "Chevalier"
	description = "Déplace le voleur. Compte pour la plus grande armée."

func on_play(state: GameState, board: Board, registry: GameRegistry, player: Player) -> bool:
	# La carte annonce seulement qu'elle est jouée. Le mod du voleur (s'il est
	# chargé) déplace le voleur et gère la plus grande armée. Sans mod voleur,
	# la carte est inerte (modularité).
	registry.emit(ClassicCatanMod.EVT_KNIGHT_PLAYED, {
		"state": state,
		"board": board,
		"player": player,
	})
	return true
