class_name Settlement
extends BuildingType

var require_road: bool = true

func _init() -> void:
	id = "settlement"
	display_name = "Colonie"
	target = "vertex"
	hotkey = KEY_1
	cost = {"wood": 1, "brick": 1, "sheep": 1, "wheat": 1}
	victory_points = 1
	mesh_radius = 0.2
	mesh_height = 0.4

func can_place(board: Board, player_id: int, key: String) -> bool:
	if board.is_vertex_occupied(key):
		return false
	for n in board.vertex_neighbors.get(key, []):
		if board.is_vertex_occupied(n):
			return false
	if require_road:
		for e in board.vertex_edges.get(key, []):
			if board.get_edge_owner(e) == player_id:
				return true
		return false
	return true

func on_placed(board: Board, player_id: int, key: String) -> void:
	board.place_on_vertex(key, player_id, id)

func get_production_amount() -> int:
	return 1
