class_name Board
extends RefCounted

# === STRUCTURE STATIQUE (remplie à la génération) ===
var tile_data: Dictionary = {}
var vertex_data: Dictionary = {}
var edge_data: Dictionary = {}

# === GRAPHE ===
var vertex_neighbors: Dictionary = {}
var edge_endpoints: Dictionary = {}
var vertex_edges: Dictionary = {}
var tiles_by_number: Dictionary = {}
var tile_vertices: Dictionary = {}

# === ÉTAT DYNAMIQUE (change pendant la partie) ===
var vertex_state: Dictionary = {}
var edge_state: Dictionary = {}

# Marqueurs sur tuiles (génériques: voleur, tempête, etc.)
# marker_id -> Vector2 (position)
var tile_markers: Dictionary = {}

# === SIGNAUX ===
signal vertex_changed(vertex_key: String)
signal edge_changed(edge_key: String)
signal tile_changed(coords: Vector2)
signal marker_changed(marker_id: String, coords: Vector2)

# === REQUÊTES: SOMMETS ===

func get_vertex_owner(key: String) -> int:
	if not vertex_state.has(key):
		return -1
	return vertex_state[key].get("owner", -1)

func get_vertex_type(key: String) -> String:
	if not vertex_state.has(key):
		return ""
	return vertex_state[key].get("type", "")

func is_vertex_occupied(key: String) -> bool:
	return vertex_state.has(key)

# === REQUÊTES: ARÊTES ===

func get_edge_owner(key: String) -> int:
	if not edge_state.has(key):
		return -1
	return edge_state[key].get("owner", -1)

func get_edge_type(key: String) -> String:
	if not edge_state.has(key):
		return ""
	return edge_state[key].get("type", "")

func is_edge_occupied(key: String) -> bool:
	return edge_state.has(key)

# === REQUÊTES: TUILES ===

# Cherche la première tuile satisfaisant le prédicat
# Usage: board.find_tile_where(func(t): return t["resource"] == "desert")
func find_tile_where(predicate: Callable) -> Vector2:
	for coords in tile_data:
		if predicate.call(tile_data[coords]):
			return coords
	return Vector2.INF

# Retourne toutes les tuiles satisfaisant le prédicat
func find_tiles_where(predicate: Callable) -> Array:
	var result: Array = []
	for coords in tile_data:
		if predicate.call(tile_data[coords]):
			result.append(coords)
	return result

# === REQUÊTES: MARQUEURS ===

func get_marker(marker_id: String) -> Vector2:
	return tile_markers.get(marker_id, Vector2.INF)

func has_marker_at(marker_id: String, coords: Vector2) -> bool:
	return tile_markers.get(marker_id, Vector2.INF) == coords

func has_any_marker_at(coords: Vector2) -> bool:
	for pos in tile_markers.values():
		if pos == coords:
			return true
	return false

# === MODIFICATIONS: SOMMETS/ARÊTES ===

func place_on_vertex(key: String, player_id: int, building_id: String) -> void:
	vertex_state[key] = {"owner": player_id, "type": building_id}
	vertex_changed.emit(key)

func place_on_edge(key: String, player_id: int, building_id: String) -> void:
	edge_state[key] = {"owner": player_id, "type": building_id}
	edge_changed.emit(key)

func clear_vertex(key: String) -> void:
	vertex_state.erase(key)
	vertex_changed.emit(key)

func clear_edge(key: String) -> void:
	edge_state.erase(key)
	edge_changed.emit(key)

# === MODIFICATIONS: MARQUEURS ===

func set_marker(marker_id: String, coords: Vector2) -> void:
	var old_coords: Vector2 = tile_markers.get(marker_id, Vector2.INF)
	tile_markers[marker_id] = coords
	marker_changed.emit(marker_id, coords)
	# Aussi notifier les tuiles affectées (pour rafraîchir le visuel)
	if old_coords != Vector2.INF:
		tile_changed.emit(old_coords)
	tile_changed.emit(coords)

func clear_marker(marker_id: String) -> void:
	var old_coords: Vector2 = tile_markers.get(marker_id, Vector2.INF)
	tile_markers.erase(marker_id)
	marker_changed.emit(marker_id, Vector2.INF)
	if old_coords != Vector2.INF:
		tile_changed.emit(old_coords)
