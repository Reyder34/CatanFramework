class_name VanillaRobberMod
extends GameMod

var _robber_node: MeshInstance3D
var _board: Board
var _registry: GameRegistry
var _state: GameState

func _init() -> void:
	mod_id = "vanilla_robber"
	mod_name = "Voleur classique"
	description = "Sur un 7: défausse, déplacement, vol"
	version = "1.0.0"
	depends_on = ["classic_catan"]

func register(reg: GameRegistry) -> void:
	# Panneaux UI
	reg.register_panel("robber_discard", preload("res://modules/vanilla_robber/discard_panel.tscn"))
	reg.register_panel("robber_steal", preload("res://modules/vanilla_robber/steal_panel.tscn"))
	# Hooks
	reg.on_game_start(_on_game_start, 0)
	reg.on_after_dice_rolled(_on_after_dice_rolled, 10)
	reg.on_before_produce(_on_before_produce, 0)
	reg.on_tile_clicked(_on_tile_clicked, 0)

# === DÉMARRAGE ===

func _on_game_start(ctx) -> void:
	_board = ctx["board"]
	_state = ctx["state"]
	_registry = ctx["registry"]
	var board_view: BoardView = ctx["board_view"]
	var desert: Vector2 = _board.find_tile_where(func(t): return t.get("number", 0) == 0)
	if desert != Vector2.INF:
		_board.set_marker("robber", desert)
	_create_robber_visual(board_view)
	_board.marker_changed.connect(_on_marker_changed)

func _create_robber_visual(board_view: BoardView) -> void:
	_robber_node = MeshInstance3D.new()
	_robber_node.name = "Robber"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.15
	mesh.bottom_radius = 0.25
	mesh.height = 0.6
	mesh.radial_segments = 12
	_robber_node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.1)
	_robber_node.material_override = mat
	var any_tile: Node = board_view.tile_nodes.values()[0]
	any_tile.get_parent().add_child(_robber_node)
	_refresh_robber_visual()

func _on_marker_changed(marker_id: String, _coords: Vector2) -> void:
	if marker_id == "robber":
		_refresh_robber_visual()

func _refresh_robber_visual() -> void:
	if _robber_node == null or _board == null:
		return
	var pos: Vector2 = _board.get_marker("robber")
	if pos == Vector2.INF:
		_robber_node.visible = false
		return
	_robber_node.visible = true
	var world := HexMath.hex_to_world(int(pos.x), int(pos.y))
	world.y = HexMath.TILE_HEIGHT / 2 + 0.3
	_robber_node.position = world

# === BLOCAGE DE PRODUCTION ===

func _on_before_produce(ctx: ProductionContext) -> void:
	if ctx.board.has_marker_at("robber", ctx.tile_coords):
		ctx.cancelled = true

# === DÉCLENCHEMENT SUR 7 ===

func _on_after_dice_rolled(ctx: RollContext) -> void:
	if ctx.result != 7:
		return
	print("[voleur] 7 détecté")
	ctx.cancel_production = true
	_run_robber_sequence(ctx.state)

func _run_robber_sequence(state: GameState) -> void:
	print("[voleur] démarrage séquence")
	state.roller_index = state.current_player_index
	state.sub_phase = GameState.SubPhase.ROBBER_DISCARD
	for i in state.players.size():
		var p: Player = state.players[i]
		var total: int = 0
		for v in p.resources.values():
			total += v
		print("[voleur] joueur %d a %d cartes" % [i, total])
		if total <= 7:
			continue
		var to_discard_count: int = total / 2
		print("[voleur] ouverture défausse pour J%d (-%d)" % [i, to_discard_count])
		var result = await _registry.ui.show_panel("robber_discard", {
			"registry": _registry,
			"player": p,
			"target_amount": to_discard_count,
		})
		print("[voleur] défausse fermée, result=%s" % str(result))
		if result != null:
			var discarded: Dictionary = result["to_discard"]
			for res_id in discarded:
				p.add_resource(res_id, -discarded[res_id])
	print("[voleur] passage à ROBBER_MOVE")
	state.sub_phase = GameState.SubPhase.ROBBER_MOVE

# === DÉPLACEMENT (via clic tuile) ===

func _on_tile_clicked(ctx: ClickContext) -> void:
	if ctx.state.sub_phase != GameState.SubPhase.ROBBER_MOVE:
		return
	var coords := ctx.target_coords
	var board := ctx.board
	if not board.tile_data.has(coords):
		return
	if board.has_marker_at("robber", coords):
		print("Le voleur doit être déplacé ailleurs")
		return
	board.set_marker("robber", coords)
	ctx.handled = true
	# Identifier les cibles
	var targets := _get_steal_targets(board, ctx.state, coords)
	if targets.is_empty():
		print("Personne à voler ici")
		ctx.state.sub_phase = GameState.SubPhase.NONE
		return
	# Phase 3: choix de la cible via panneau
	ctx.state.sub_phase = GameState.SubPhase.ROBBER_STEAL
	_run_steal_choice(ctx.state, targets)

func _run_steal_choice(state: GameState, targets: Array) -> void:
	var result = await _registry.ui.show_panel("robber_steal", {
		"players": state.players,
		"target_ids": targets,
	})
	if result != null:
		var target_id: int = result["target_id"]
		_perform_steal(state, target_id)
	state.sub_phase = GameState.SubPhase.NONE

func _get_steal_targets(board: Board, state: GameState, coords: Vector2) -> Array:
	var targets: Array = []
	for v_key in board.tile_vertices.get(coords, []):
		var owner_id := board.get_vertex_owner(v_key)
		if owner_id < 0 or owner_id == state.roller_index:
			continue
		if targets.has(owner_id):
			continue
		var has_resources := false
		for v in state.players[owner_id].resources.values():
			if v > 0:
				has_resources = true
				break
		if has_resources:
			targets.append(owner_id)
	return targets

func _perform_steal(state: GameState, target_id: int) -> void:
	var target: Player = state.players[target_id]
	var thief: Player = state.players[state.roller_index]
	var pool: Array = []
	for res_id in target.resources:
		for i in target.resources[res_id]:
			pool.append(res_id)
	if pool.is_empty():
		return
	var stolen: String = pool.pick_random()
	target.add_resource(stolen, -1)
	thief.add_resource(stolen, 1)
	print("Joueur %d vole %s à Joueur %d" % [thief.id, stolen, target.id])
