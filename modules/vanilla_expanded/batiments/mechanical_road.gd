class_name MechanicalRoad
extends BuildingType

func _init() -> void:
	id = "mech_road"
	display_name = "Mechanical Road"
	description = "Route qui récupère une ressource"
	target = "edge"
	cost = {"ore": 1}
	victory_points = 0
	mesh_radius = 0.3
	mesh_height = 0.6
	model_scene = preload("res://modules/vanilla_expanded/batiments_models/mech_road.tscn")

func can_place(board: Board, player_id: int, key: String) -> bool:
	if board.is_edge_occupied(key):
		return false
	for v_key in board.edge_endpoints.get(key, []):
		if board.get_vertex_owner(v_key) == player_id:
			return true
		for adj_e in board.vertex_edges.get(v_key, []):
			if adj_e != key and board.get_edge_owner(adj_e) == player_id:
				return true
	return false

func on_placed(board: Board, player_id: int, key: String) -> void:
	board.place_on_edge(key, player_id, id)

# Combien de ressources elle récupère quand une de ses 2 tuiles adjacentes sort.
func get_production_amount() -> int:
	return 1
