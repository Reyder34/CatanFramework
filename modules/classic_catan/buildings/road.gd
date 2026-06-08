class_name Road
extends BuildingType

func _init() -> void:
	id = "road"
	display_name = "Route"
	description = "Relie tes constructions ; sert à t'étendre et à la plus longue route."
	target = "edge"
	cost = {"wood": 1, "brick": 1}
	victory_points = 0
	model_scene = preload("res://modules/classic_catan/buildings_models/road.tscn")

func can_place(board, player_id, key) -> bool:
	return not board.is_edge_occupied(key) 
	
func on_placed(board, player_id, key) -> void:
	board.place_on_edge(key, player_id, id)
