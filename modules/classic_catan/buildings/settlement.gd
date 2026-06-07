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
	var custom := super.create_visual(player_color)  # model_scene si assigné
	var color := get_color(player_color)
	if custom != null:
		_apply_color_to_model(custom, color)
		return custom
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

func _apply_color_to_model(node: Node, color: Color) -> void:
	# Si c'est un MeshInstance3D standard
	if node is MeshInstance3D:
		node.material_override = _colored_mat(color)
		if node.mesh:
			for i in range(node.get_mesh_material_count()):
				node.set_surface_override_material(i, _colored_mat(color))
				
	# Si c'est un nœud CSG (Comme dans ton modèle actuel)
	elif node is CSGPrimitive3D or node is CSGMesh3D:
		node.material = _colored_mat(color)
		
	for child in node.get_children():
		_apply_color_to_model(child, color)
