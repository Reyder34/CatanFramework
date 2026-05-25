class_name City
extends BuildingType

func _init() -> void:
	id = "city"
	display_name = "Ville"
	target = "vertex"
	hotkey = KEY_3
	cost = {"wheat": 2, "ore": 3}
	victory_points = 2
	mesh_radius = 0.3
	mesh_height = 0.6

func can_place(board: Board, player_id: int, key: String) -> bool:
	if board.get_vertex_owner(key) != player_id:
		return false
	return board.get_vertex_type(key) == "settlement"

func on_placed(board: Board, player_id: int, key: String) -> void:
	board.place_on_vertex(key, player_id, id)

func get_production_amount() -> int:
	return 2
