class_name KnightCard
extends DevelopmentCard

func _init() -> void:
	id = "knight"
	display_name = "Chevalier"
	description = "Déplace le voleur. Compte pour la plus grande armée."

func on_play(state: GameState, board: Board, registry: GameRegistry, player: Player) -> bool:
	print("[Chevalier] joué par J%d (effet à implémenter)" % player.id)
	return true
