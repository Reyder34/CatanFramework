class_name RulesEngine
extends RefCounted

var board: Board

func _init(p_board: Board) -> void:
	board = p_board

func can_place_settlement(vertex_key: String, player_id: int, require_road: bool = true) -> bool:
	if board.is_vertex_occupied(vertex_key):
		return false
	# Règle de distance: aucun voisin direct occupé
	for neighbor_key in board.vertex_neighbors.get(vertex_key, []):
		if board.is_vertex_occupied(neighbor_key):
			return false
	# Règle de connexion: au moins une arête adjacente est ta route
	if require_road:
		var has_own_road := false
		for edge_key in board.vertex_edges.get(vertex_key, []):
			if board.get_edge_owner(edge_key) == player_id:
				has_own_road = true
				break
		if not has_own_road:
			return false
	return true

func can_upgrade_to_city(vertex_key: String, player_id: int) -> bool:
	if board.get_vertex_owner(vertex_key) != player_id:
		return false
	return board.get_vertex_type(vertex_key) == "settlement"

func can_place_road(edge_key: String, player_id: int) -> bool:
	if board.is_edge_occupied(edge_key):
		return false
	for v_key in board.edge_endpoints.get(edge_key, []):
		var v_owner := board.get_vertex_owner(v_key)
		if v_owner == player_id:
			return true
		if v_owner >= 0 and v_owner != player_id:
			continue  # colonie adverse coupe le réseau
		for adj_edge_key in board.vertex_edges.get(v_key, []):
			if adj_edge_key == edge_key:
				continue
			if board.get_edge_owner(adj_edge_key) == player_id:
				return true
	return false
