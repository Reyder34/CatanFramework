class_name Board
extends RefCounted

# === STRUCTURE STATIQUE (remplie à la génération) ===
# tile_data[Vector2(q,r)] = {"resource": str, "number": int}
var tile_data: Dictionary = {}
# vertex_data[key] = {"q": int, "r": int, "corner": int}  (info géométrique)
var vertex_data: Dictionary = {}
# edge_data[key] = {"q": int, "r": int, "side": int}
var edge_data: Dictionary = {}

# === GRAPHE ===
var vertex_neighbors: Dictionary = {}  # vertex_key -> [vertex_keys]
var edge_endpoints: Dictionary = {}    # edge_key -> [v_key, v_key]
var vertex_edges: Dictionary = {}      # vertex_key -> [edge_keys]
# Pour la production: pour chaque numéro, liste des tuiles
var tiles_by_number: Dictionary = {}   # number -> [Vector2(q,r)]
# Pour la production inverse: pour chaque tuile, ses 6 sommets
var tile_vertices: Dictionary = {}     # Vector2(q,r) -> [vertex_keys]

# === ÉTAT DYNAMIQUE (change pendant la partie) ===
# vertex_state[key] = {"owner": int, "type": "settlement"|"city"} ou null
var vertex_state: Dictionary = {}
# edge_state[key] = {"owner": int} ou null
var edge_state: Dictionary = {}
# Position du voleur (Vector2(q,r))
var robber_position: Vector2 = Vector2.INF

# === SIGNAUX (la View s'y abonne) ===
signal vertex_changed(vertex_key: String)
signal edge_changed(edge_key: String)
signal tile_changed(coords: Vector2)

# === REQUÊTES ===

func get_vertex_owner(key: String) -> int:
	if not vertex_state.has(key):
		return -1
	return vertex_state[key].get("owner", -1)

func get_vertex_type(key: String) -> String:
	if not vertex_state.has(key):
		return ""
	return vertex_state[key].get("type", "")

func get_edge_owner(key: String) -> int:
	if not edge_state.has(key):
		return -1
	return edge_state[key].get("owner", -1)

func is_vertex_occupied(key: String) -> bool:
	return vertex_state.has(key)

func is_edge_occupied(key: String) -> bool:
	return edge_state.has(key)
	

func get_edge_type(key: String) -> String:
	if not edge_state.has(key):
		return ""
	return edge_state[key].get("type", "road")

# === MODIFICATIONS (émettent un signal) ===

func place_settlement(key: String, player_id: int, building_id: String = "settlement") -> void:
	vertex_state[key] = {"owner": player_id, "type": building_id}
	vertex_changed.emit(key)

func upgrade_to_city(key: String, building_id: String = "city") -> void:
	if not vertex_state.has(key):
		return
	vertex_state[key]["type"] = building_id
	vertex_changed.emit(key)

func place_road(key: String, player_id: int, building_id: String = "road") -> void:
	edge_state[key] = {"owner": player_id, "type": building_id}
	edge_changed.emit(key)

func move_robber(coords: Vector2) -> void:
	robber_position = coords
	tile_changed.emit(coords)
	
func find_desert_tile() -> Vector2:
	for coords in tile_data:
		var info: Dictionary = tile_data[coords]
		if info["number"] == 0:  # désert n'a pas de numéro
			return coords
	return Vector2.ZERO

func is_robber_blocking(coords: Vector2) -> bool:
	return robber_position == coords
