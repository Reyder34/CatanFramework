class_name MonopolyCard
extends DevelopmentCard

func _init() -> void:
	id = "monopoly"
	display_name = "Monopole"
	description = "Choisis une ressource. Tous les joueurs te donnent toutes celles qu'ils possèdent."

func on_play(state: GameState, board: Board, registry: GameRegistry, player: Player) -> bool:
	print("[Monopole] joué par J%d (effet à implémenter)" % player.id)
	return true
