class_name BoardView
extends RefCounted

const WATER_RADIUS := 4
const WATER_COLOR := Color(0.15, 0.4, 0.7)

var module: GameModule
var board: Board

# Maps des Nodes visuels (pour pouvoir les retrouver et les mettre à jour)
var tile_nodes: Dictionary = {}    # Vector2(q,r) -> StaticBody3D
var vertex_nodes: Dictionary = {}  # key -> StaticBody3D
var edge_nodes: Dictionary = {}    # key -> StaticBody3D

var on_tile_click: Callable
var on_vertex_click: Callable
var on_edge_click: Callable

var robber_node: MeshInstance3D

func _init(p_module: GameModule, p_board: Board) -> void:
	module = p_module
	board = p_board
	board.vertex_changed.connect(_refresh_vertex)
	board.edge_changed.connect(_refresh_edge)
	board.tile_changed.connect(_on_tile_changed)

func generate(parent: Node3D) -> void:
	var pool := module.tile_pool.duplicate()
	pool.shuffle()
	var numbers := module.number_pool.duplicate()
	numbers.shuffle()
	
	var radius := module.board_radius
	var index := 0
	var num_index := 0
	for r in range(-radius, radius + 1):
		var q_start: int = max(-radius, -radius - r)
		var q_end: int = min(radius, radius - r)
		for q in range(q_start, q_end + 1):
			var resource: String = pool[index]
			var number := 0
			if module.is_producing_resource(resource):
				number = numbers[num_index]
				num_index += 1
			# Stocke dans le Board
			board.tile_data[Vector2(q, r)] = {"resource": resource, "number": number}
			if number > 0:
				if not board.tiles_by_number.has(number):
					board.tiles_by_number[number] = []
				board.tiles_by_number[number].append(Vector2(q, r))
			# Crée le visuel
			_create_tile(parent, q, r, resource, number)
			_register_vertices(parent, q, r)
			_register_edges(parent, q, r)
			index += 1
	
	_generate_water(parent)
	_build_graph()
	_create_robber(parent)

func _create_tile(parent: Node3D, q: int, r: int, resource: String, number: int) -> void:
	var body := StaticBody3D.new()
	body.position = HexMath.hex_to_world(q, r)
	body.name = "Tile_%s_%d" % [resource, number]
	body.set_meta("coords", Vector2(q, r))
	
	var mesh_inst := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = HexMath.HEX_SIZE
	mesh.bottom_radius = HexMath.HEX_SIZE
	mesh.height = HexMath.TILE_HEIGHT
	mesh.radial_segments = 6
	mesh_inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = module.get_resource_color(resource)
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
		label.position = Vector3(0, HexMath.TILE_HEIGHT / 2 + 0.01, 0)
		label.rotation_degrees = Vector3(-90, 0, 0)
		label.modulate = Color.RED if number == 6 or number == 8 else Color.BLACK
		body.add_child(label)
	
	if on_tile_click.is_valid():
		body.input_event.connect(on_tile_click.bind(body))
	tile_nodes[Vector2(q, r)] = body
	parent.add_child(body)

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
		# Lien tile -> vertex (pour la production)
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

func _generate_water(parent: Node3D) -> void:
	var land_radius := module.board_radius
	for r in range(-WATER_RADIUS, WATER_RADIUS + 1):
		var q_start: int = max(-WATER_RADIUS, -WATER_RADIUS - r)
		var q_end: int = min(WATER_RADIUS, WATER_RADIUS - r)
		for q in range(q_start, q_end + 1):
			if _is_land(q, r, land_radius):
				continue
			_create_water_tile(parent, q, r)

func _is_land(q: int, r: int, radius: int) -> bool:
	if r < -radius or r > radius:
		return false
	var q_start: int = max(-radius, -radius - r)
	var q_end: int = min(radius, radius - r)
	return q >= q_start and q <= q_end

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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WATER_COLOR
	mesh_inst.material_override = mat
	parent.add_child(mesh_inst)

func _build_graph() -> void:
	var radius := module.board_radius
	for r in range(-radius, radius + 1):
		var q_start: int = max(-radius, -radius - r)
		var q_end: int = min(radius, radius - r)
		for q in range(q_start, q_end + 1):
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

# === MISE À JOUR VISUELLE QUAND LE BOARD CHANGE ===

func _refresh_vertex(key: String) -> void:
	var node: StaticBody3D = vertex_nodes.get(key)
	if node == null:
		return
	var mesh_inst: MeshInstance3D = node.get_child(0)
	var mat: StandardMaterial3D = mesh_inst.material_override
	var mesh: SphereMesh = mesh_inst.mesh
	var owner_id := board.get_vertex_owner(key)
	if owner_id < 0:
		mat.albedo_color = Color(0.3, 0.3, 0.3)
		mesh.radius = 0.1
		mesh.height = 0.2
		return
	var building_id := board.get_vertex_type(key)
	var building: BuildingType = module.get_building(building_id)
	var player_color: Color = GameState.PLAYER_COLORS[owner_id]
	if building != null:
		mat.albedo_color = building.get_color(player_color)
		mesh.radius = building.mesh_radius
		mesh.height = building.mesh_height
	else:
		mat.albedo_color = player_color
		mesh.radius = 0.2
		mesh.height = 0.4

func _refresh_edge(key: String) -> void:
	var node: StaticBody3D = edge_nodes.get(key)
	if node == null:
		return
	var mesh_inst: MeshInstance3D = node.get_child(0)
	var mat: StandardMaterial3D = mesh_inst.material_override
	var owner_id := board.get_edge_owner(key)
	if owner_id < 0:
		mat.albedo_color = Color(0.4, 0.4, 0.4)
		return
	var building_id := board.get_edge_type(key) if board.has_method("get_edge_type") else "road"
	var building: BuildingType = module.get_building(building_id)
	var player_color: Color = GameState.PLAYER_COLORS[owner_id]
	if building != null:
		mat.albedo_color = building.get_color(player_color)
	else:
		mat.albedo_color = player_color


func _create_robber(parent: Node3D) -> void:
	robber_node = MeshInstance3D.new()
	robber_node.name = "Robber"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.15
	mesh.bottom_radius = 0.25
	mesh.height = 0.6
	mesh.radial_segments = 12
	robber_node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.1)
	robber_node.material_override = mat
	parent.add_child(robber_node)
	# Place sur la tuile actuelle du Board
	_refresh_robber()

func _refresh_robber() -> void:
	if robber_node == null:
		return
	if board.robber_position == Vector2.INF:
		robber_node.visible = false
		return
	robber_node.visible = true
	var world := HexMath.hex_to_world(int(board.robber_position.x), int(board.robber_position.y))
	world.y = HexMath.TILE_HEIGHT / 2 + 0.3
	robber_node.position = world

func _on_tile_changed(_coords: Vector2) -> void:
	_refresh_robber()
