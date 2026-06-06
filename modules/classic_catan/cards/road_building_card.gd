class_name RoadBuildingCard
extends DevelopmentCard

func _init() -> void:
	id = "road_building"
	display_name = "Construction de routes"
	description = "Pose 2 routes gratuitement."
	image = "truc"

func on_play(state: GameState, board: Board, registry: GameRegistry, player: Player) -> bool:
	# Délègue à classic_catan qui ouvre la sous-phase de pose de 2 routes gratuites.
	registry.emit(ClassicCatanMod.EVT_ROAD_BUILDING_PLAYED, {
		"state": state,
		"player": player,
	})
	return true
