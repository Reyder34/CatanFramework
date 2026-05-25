class_name RoadBuildingCard
extends DevelopmentCard

func _init() -> void:
	id = "road_building"
	display_name = "Construction de routes"
	description = "Pose 2 routes gratuitement."

func on_play(state: GameState, board: Board, registry: GameRegistry, player: Player) -> bool:
	print("[RoadBuilding] joué par J%d (effet à implémenter)" % player.id)
	return true
