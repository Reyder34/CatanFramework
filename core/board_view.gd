class_name BoardView
extends RefCounted

const WATER_RADIUS := 4
const WATER_COLOR := Color(0.15, 0.4, 0.7)

# Tuiles 3D (modèles fournis par un mod). Le .glb des tuiles Catan a un hex de rayon
# ≈0.99 ; on remet sa rotation à plat pour aligner les 6 sommets sur le plateau.
const TILE_MODEL_Y_DEG := 0.0      # si les tuiles semblent tournées de 30° : 30 ou -30
const TILE_MODEL_NUMBER_Y := 0.9   # hauteur du numéro au-dessus d'une tuile 3D

var registry: GameRegistry
var board: Board

var tile_nodes: Dictionary = {}
var vertex_nodes: Dictionary = {}
var edge_nodes: Dictionary = {}

var on_tile_click: Callable
var on_vertex_click: Callable
var on_edge_click: Callable

func _init(p_registry: GameRegistry, p_board: Board) -> void:
	registry = p_registry
	board = p_board
	board.vertex_changed.connect(_refresh_vertex)
	board.edge_changed.connect(_refresh_edge)

func generate(parent: Node3D) -> void:
	# 1) PLAN: où va quelle tuile (données pures). Un mod peut le fournir.
	# 2) RENDU: instancie les tuiles/sommets/arêtes + eau + graphe (générique).
	var plan := _build_plan()
	for coords in plan:
		var cell: Dictionary = plan[coords]
		var resource: String = cell.get("resource", "")
		var number: int = int(cell.get("number", 0))
		board.tile_data[coords] = {"resource": resource, "number": number}
		if number > 0:
			if not board.tiles_by_number.has(number):
				board.tiles_by_number[number] = []
			board.tiles_by_number[number].append(coords)
		_create_tile(parent, int(coords.x), int(coords.y), resource, number)
		_register_vertices(parent, int(coords.x), int(coords.y))
		_register_edges(parent, int(coords.x), int(coords.y))
	_generate_water(parent)
	_build_graph()

# Plan de tuiles: Vector2(q, r) -> {"resource": String, "number": int}.
# Si un mod a fourni un générateur (registry.set_map_generator), on l'utilise;
# sinon la distribution par défaut (mélange du tile_pool/number_pool).
func _build_plan() -> Dictionary:
	if registry.map_generator.is_valid():
		var custom = registry.map_generator.call(registry)
		if custom is Dictionary and not custom.is_empty():
			return custom
		push_warning("Le générateur de map a renvoyé un plan vide; repli sur la génération par défaut.")
	return _default_plan()

# Distribution par défaut: distribue les pools sur un disque hexagonal de rayon
# board_radius. Si la map est plus grande que le pool, on RÉPÈTE le pool (sacs
# dimensionnés) -> jamais de cases vides. À rayon 2, identique à l'historique.
# Utilise le RNG global (semé par main.gd).
func _default_plan() -> Dictionary:
	var radius := registry.board_radius
	var coords: Array = []
	for r in range(-radius, radius + 1):
		var q_start: int = max(-radius, -radius - r)
		var q_end: int = min(radius, radius - r)
		for q in range(q_start, q_end + 1):
			coords.append(Vector2(q, r))
	var tiles := _sized_bag(registry.tile_pool, coords.size())
	var producing := 0
	for t in tiles:
		if registry.is_producing_resource(t):
			producing += 1
	var numbers := _sized_bag(registry.number_pool, producing)
	var plan: Dictionary = {}
	var ni := 0
	for i in coords.size():
		var resource: String = tiles[i] if i < tiles.size() else ""
		var number := 0
		if resource != "" and registry.is_producing_resource(resource) and ni < numbers.size():
			number = numbers[ni]
			ni += 1
		plan[coords[i]] = {"resource": resource, "number": number}
	return plan

# Sac mélangé de taille `size`, répétant le pool si la map dépasse sa taille.
# À size == pool.size(), c'est un simple mélange (rétro-compatible, même RNG).
func _sized_bag(pool: Array, size: int) -> Array:
	if pool.is_empty() or size <= 0:
		return []
	var bag: Array = []
	while bag.size() < size:
		bag.append_array(pool)
	bag.shuffle()
	bag.resize(size)
	return bag

func _create_tile(parent: Node3D, q: int, r: int, resource: String, number: int) -> void:
	var body := StaticBody3D.new()
	body.position = HexMath.hex_to_world(q, r)
	body.name = "Tile_%s_%d" % [resource, number]
	body.set_meta("coords", Vector2(q, r))

	# Modèle 3D fourni par un mod (ex: tuiles Catan) -> remplace l'hexagone procédural.
	# Sinon : cylindre 6 segments coloré/texturé (repli générique).
	var model_scene := registry.get_resource_model(resource)
	var has_model := model_scene != null
	if has_model:
		_add_tile_model(body, model_scene)
	else:
		var mesh_inst := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = HexMath.HEX_SIZE
		mesh.bottom_radius = HexMath.HEX_SIZE
		mesh.height = HexMath.TILE_HEIGHT
		mesh.radial_segments = 6
		mesh_inst.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = registry.get_resource_color(resource)
		var tex := registry.get_resource_texture(resource)
		if tex != null:
			mat.albedo_texture = tex
			mat.albedo_color = Color.WHITE  # ne pas teinter l'image
		mesh_inst.material_override = mat
		body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = HexMath.HEX_SIZE
	shape.height = HexMath.TILE_HEIGHT
	col.shape = shape
	body.add_child(col)

	if number > 0:
		var label := Label3D.new()
		label.text = str(number)
		label.font_size = 64
		# Plus haut quand un modèle 3D occupe la tuile (sinon le décor cache le numéro).
		var label_y: float = TILE_MODEL_NUMBER_Y if has_model else HexMath.TILE_HEIGHT / 2 + 0.18
		label.position = Vector3(0, label_y, 0)
		# Billboard: le chiffre fait toujours face à la caméra -> reste lisible
		# quel que soit l'angle (la caméra peut tourner/zoomer).
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color.RED if number == 6 or number == 8 else Color.BLACK
		# Contour blanc épais -> chiffres bien lisibles sur n'importe quelle tuile/décor.
		label.outline_modulate = Color.WHITE
		label.outline_size = 28
		body.add_child(label)

	if on_tile_click.is_valid():
		body.input_event.connect(on_tile_click.bind(body))
	tile_nodes[Vector2(q, r)] = body
	parent.add_child(body)

# Instancie un modèle 3D de tuile à la place de l'hexagone procédural. On met l'échelle
# au rayon HEX_SIZE et on remet la rotation/position à plat (le .glb porte un +30° sur
# sa racine) pour aligner les 6 sommets sur les emplacements de bâtiments du plateau.
func _add_tile_model(body: Node3D, scene: PackedScene) -> void:
	var model := scene.instantiate()
	if model is Node3D:
		model.position = Vector3.ZERO
		model.rotation = Vector3(0, deg_to_rad(TILE_MODEL_Y_DEG + 90), 0)
		model.scale = Vector3.ONE * (HexMath.HEX_SIZE / 0.99)
	body.add_child(model)

func _register_vertices(parent: Node3D, q: int, r: int) -> void:
	for i in 6:
		var n1: Vector2 = HexMath.NEIGHBOR_OFFSETS[i]
		var n2: Vector2 = HexMath.NEIGHBOR_OFFSETS[(i + 1) % 6]
		var trio := [
			Vector2(q, r),
			Vector2(q + n1.x, r + n1.y),
			Vector2(q + n2.x, r + n2.y)
		]
		var key := HexMath.vertex_key(trio)
		var coords := Vector2(q, r)
		if not board.tile_vertices.has(coords):
			board.tile_vertices[coords] = []
		if not board.tile_vertices[coords].has(key):
			board.tile_vertices[coords].append(key)
		if vertex_nodes.has(key):
			continue
		board.vertex_data[key] = {"q": q, "r": r, "corner": i}
		_create_vertex(parent, HexMath.vertex_position(q, r, i), key)

func _create_vertex(parent: Node3D, pos: Vector3, key: String) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.name = "Vertex"
	body.set_meta("key", key)

	var mesh_inst := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	mesh_inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.3)
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.15
	col.shape = shape
	body.add_child(col)

	if on_vertex_click.is_valid():
		body.input_event.connect(on_vertex_click.bind(body))
	vertex_nodes[key] = body
	parent.add_child(body)

func _register_edges(parent: Node3D, q: int, r: int) -> void:
	for i in 6:
		var n: Vector2 = HexMath.NEIGHBOR_OFFSETS[i]
		var neighbor := Vector2(q + n.x, r + n.y)
		var key := HexMath.edge_key(Vector2(q, r), neighbor)
		if edge_nodes.has(key):
			continue
		board.edge_data[key] = {"q": q, "r": r, "side": i}
		_create_edge(parent, HexMath.edge_position(q, r, i), HexMath.edge_rotation(i), key)

func _create_edge(parent: Node3D, pos: Vector3, angle_y: float, key: String) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = angle_y
	body.name = "Edge"
	body.set_meta("key", key)

	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(HexMath.HEX_SIZE * 0.9, 0.08, 0.12)
	mesh_inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.4, 0.4)
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(HexMath.HEX_SIZE * 0.9, 0.08, 0.2)
	col.shape = shape
	body.add_child(col)

	if on_edge_click.is_valid():
		body.input_event.connect(on_edge_click.bind(body))
	edge_nodes[key] = body
	parent.add_child(body)

# Eau: tout hexagone sans tuile dans l'anneau (pilotée par tile_data -> supporte
# n'importe quelle forme de carte produite par un mod, pas seulement le disque).
func _generate_water(parent: Node3D) -> void:
	var extent := _water_extent()
	for r in range(-extent, extent + 1):
		var q_start: int = max(-extent, -extent - r)
		var q_end: int = min(extent, extent - r)
		for q in range(q_start, q_end + 1):
			if board.tile_data.has(Vector2(q, r)):
				continue
			_create_water_tile(parent, q, r)

# Au moins WATER_RADIUS, et toujours un cran au-delà de la terre la plus lointaine
# (pour border correctement une carte plus grande qu'un mod aurait générée).
func _water_extent() -> int:
	var maxr := 0
	for coords in board.tile_data:
		var d := int((abs(coords.x) + abs(coords.y) + abs(coords.x + coords.y)) / 2.0)
		if d > maxr:
			maxr = d
	return maxi(WATER_RADIUS, maxr + 1)

func _create_water_tile(parent: Node3D, q: int, r: int) -> void:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.position = HexMath.hex_to_world(q, r)
	mesh_inst.position.y -= 0.05
	mesh_inst.name = "Water_%d_%d" % [q, r]
	var mesh := CylinderMesh.new()
	mesh.top_radius = HexMath.HEX_SIZE
	mesh.bottom_radius = HexMath.HEX_SIZE
	mesh.height = HexMath.TILE_HEIGHT
	mesh.radial_segments = 6
	mesh_inst.mesh = mesh
	var mat := ShaderMaterial.new()
	var water_shader = load("res://ui/shader/water.gdshader")
	mat.shader = water_shader
	# Dessine l'eau AVANT les Label3D des numéros (dont le contour est à priorité -1) : sinon
	# l'eau transparente passe par-dessus le contour (il disparaît) et "aspire" les chiffres.
	mat.render_priority = -10
	mesh_inst.material_override = mat
	parent.add_child(mesh_inst)

# Graphe sommets/arêtes construit à partir des tuiles réellement générées
# (tile_data), pas d'un rayon fixe -> compatible avec des cartes de forme libre.
func _build_graph() -> void:
	for coords in board.tile_data:
		var q := int(coords.x)
		var r := int(coords.y)
		for i in 6:
			var n: Vector2 = HexMath.NEIGHBOR_OFFSETS[i]
			var neighbor := Vector2(q + n.x, r + n.y)
			var e_key := HexMath.edge_key(Vector2(q, r), neighbor)
			if not edge_nodes.has(e_key):
				continue
			var c1: int = (i - 1 + 6) % 6
			var c2: int = i
			var v1_key := _vertex_key_at_corner(q, r, c1)
			var v2_key := _vertex_key_at_corner(q, r, c2)
			if not vertex_nodes.has(v1_key) or not vertex_nodes.has(v2_key):
				continue
			_link(v1_key, v2_key, e_key)

func _vertex_key_at_corner(q: int, r: int, corner: int) -> String:
	var n1: Vector2 = HexMath.NEIGHBOR_OFFSETS[corner]
	var n2: Vector2 = HexMath.NEIGHBOR_OFFSETS[(corner + 1) % 6]
	return HexMath.vertex_key([
		Vector2(q, r),
		Vector2(q + n1.x, r + n1.y),
		Vector2(q + n2.x, r + n2.y)
	])

func _link(v1: String, v2: String, e: String) -> void:
	if not board.vertex_neighbors.has(v1):
		board.vertex_neighbors[v1] = []
	if not board.vertex_neighbors.has(v2):
		board.vertex_neighbors[v2] = []
	if not board.vertex_neighbors[v1].has(v2):
		board.vertex_neighbors[v1].append(v2)
	if not board.vertex_neighbors[v2].has(v1):
		board.vertex_neighbors[v2].append(v1)
	if not board.edge_endpoints.has(e):
		board.edge_endpoints[e] = [v1, v2]
	if not board.vertex_edges.has(v1):
		board.vertex_edges[v1] = []
	if not board.vertex_edges.has(v2):
		board.vertex_edges[v2] = []
	if not board.vertex_edges[v1].has(e):
		board.vertex_edges[v1].append(e)
	if not board.vertex_edges[v2].has(e):
		board.vertex_edges[v2].append(e)


# Re-rend tous les sommets/arêtes depuis l'état courant du board (utilisé en réseau
# quand un client reçoit un snapshot complet).
func refresh_all() -> void:
	for key in vertex_nodes:
		_refresh_vertex(key)
	for key in edge_nodes:
		_refresh_edge(key)

func _refresh_vertex(key: String) -> void:
	var node: StaticBody3D = vertex_nodes.get(key)
	if node == null:
		return
	var mesh_inst: MeshInstance3D = node.get_child(0)
	_clear_custom_model(node)
	var owner_id := board.get_vertex_owner(key)
	if owner_id < 0:
		mesh_inst.visible = true
		mesh_inst.material_override.albedo_color = Color(0.3, 0.3, 0.3)
		mesh_inst.mesh.radius = 0.1
		mesh_inst.mesh.height = 0.2
		return
	var building: BuildingType = registry.get_building(board.get_vertex_type(key))
	var player_color: Color = GameState.PLAYER_COLORS[owner_id]
	# Modèle custom déclaré par le bâtiment, sinon primitive (sphère).
	var model: Node3D = building.create_visual(player_color) if building != null else null
	if model != null:
		mesh_inst.visible = false
		model.name = "CustomModel"
		node.add_child(model)
		return
	mesh_inst.visible = true
	if building != null:
		mesh_inst.material_override.albedo_color = building.get_color(player_color)
		mesh_inst.mesh.radius = building.mesh_radius
		mesh_inst.mesh.height = building.mesh_height
	else:
		mesh_inst.material_override.albedo_color = player_color
		mesh_inst.mesh.radius = 0.2
		mesh_inst.mesh.height = 0.4

func _refresh_edge(key: String) -> void:
	var node: StaticBody3D = edge_nodes.get(key)
	if node == null:
		return
	var mesh_inst: MeshInstance3D = node.get_child(0)
	_clear_custom_model(node)
	var owner_id := board.get_edge_owner(key)
	if owner_id < 0:
		mesh_inst.visible = true
		mesh_inst.material_override.albedo_color = Color(0.4, 0.4, 0.4)
		return
	var building: BuildingType = registry.get_building(board.get_edge_type(key))
	var player_color: Color = GameState.PLAYER_COLORS[owner_id]
	var model: Node3D = building.create_visual(player_color) if building != null else null
	if model != null:
		mesh_inst.visible = false
		model.name = "CustomModel"
		node.add_child(model)
		return
	mesh_inst.visible = true
	if building != null:
		mesh_inst.material_override.albedo_color = building.get_color(player_color)
	else:
		mesh_inst.material_override.albedo_color = player_color

# Retire un éventuel modèle custom précédent (ex: colonie -> ville).
func _clear_custom_model(node: Node) -> void:
	var old := node.get_node_or_null("CustomModel")
	if old != null:
		node.remove_child(old)
		old.queue_free()
