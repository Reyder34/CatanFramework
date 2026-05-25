class_name YearOfPlentyCard
extends DevelopmentCard

func _init() -> void:
	id = "year_of_plenty"
	display_name = "Invention"
	description = "Reçois 2 ressources de ton choix dans la banque."

func on_play(state: GameState, board: Board, registry: GameRegistry, player: Player) -> bool:
	print("[Invention] joué par J%d (effet à implémenter)" % player.id)
	return true
