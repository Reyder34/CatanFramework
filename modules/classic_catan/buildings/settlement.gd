class_name Settlement
extends BuildingType

var require_road: bool = true

func _init() -> void:
	id = "settlement"
	display_name = "Colonie"
	description = "Rapporte 1 ressource des tuiles adjacentes quand leur numéro sort."
	target = "vertex"
	cost = {"wood": 1, "brick": 1, "sheep": 1, "wheat": 1}
	victory_points = 1
	mesh_radius = 0.2
	mesh_height = 0.4
	model_scene = preload("res://modules/classic_catan/buildings_models/settlement.tscn")

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

# Modèle: petite maison (corps + toit). Gabarit — assigner model_scene pour remplacer.
func create_visual(player_color: Color) -> Node3D:
	var custom := super.create_visual(player_color)  # model_scene + convention "Corps"
	if custom != null:
		return custom
	# Repli procédural (uniquement si aucun model_scene n'est assigné)
	var color := get_color(player_color)
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.26, 0.22, 0.26)
	body.mesh = bm
	body.position = Vector3(0, 0.11, 0)
	body.material_override = _colored_mat(color)
	root.add_child(body)
	var roof := MeshInstance3D.new()
	var rm := PrismMesh.new()
	rm.size = Vector3(0.3, 0.16, 0.3)
	roof.mesh = rm
	roof.position = Vector3(0, 0.3, 0)
	roof.material_override = _colored_mat(color.darkened(0.25))
	root.add_child(roof)
	return root
