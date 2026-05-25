class_name Road
extends BuildingType

func _init() -> void:
	id = "road"
	display_name = "Route"
	target = "edge"
	hotkey = KEY_2
	cost = {"wood": 1, "brick": 1}
	victory_points = 0

func can_place(board: Board, player_id: int, key: String) -> bool:
	if board.is_edge_occupied(key):
		return false
	# Connectée à une colonie/ville propre OU à une route propre
	# (mais une colonie adverse coupe le réseau)
	for v_key in board.edge_endpoints.get(key, []):
		var v_owner := board.get_vertex_owner(v_key)
		if v_owner == player_id:
			return true
		if v_owner >= 0 and v_owner != player_id:
			continue
		for adj_e in board.vertex_edges.get(v_key, []):
			if adj_e == key:
				continue
			if board.get_edge_owner(adj_e) == player_id:
				return true
	return false

func on_placed(board: Board, player_id: int, key: String) -> void:
	board.place_road(key, player_id)
