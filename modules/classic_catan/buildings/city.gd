class_name City
extends BuildingType

func _init() -> void:
	id = "city"
	display_name = "Ville"
	description = "Améliore une colonie. Produit ×2 les ressources."
	target = "vertex"
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

# Modèle: bâtiment plus imposant (corps + tour + toit). Gabarit.
func create_visual(player_color: Color) -> Node3D:
	var custom := super.create_visual(player_color)  # model_scene si assigné
	if custom != null:
		return custom
	var color := get_color(player_color)
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.34, 0.3, 0.34)
	body.mesh = bm
	body.position = Vector3(0, 0.15, 0)
	body.material_override = _colored_mat(color)
	root.add_child(body)
	var tower := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.16, 0.28, 0.16)
	tower.mesh = tm
	tower.position = Vector3(0.09, 0.4, 0.09)
	tower.material_override = _colored_mat(color)
	root.add_child(tower)
	var roof := MeshInstance3D.new()
	var rm := PrismMesh.new()
	rm.size = Vector3(0.38, 0.16, 0.38)
	roof.mesh = rm
	roof.position = Vector3(0, 0.38, 0)
	roof.material_override = _colored_mat(color.darkened(0.25))
	root.add_child(roof)
	return root
