class_name VanillaRobberMod
extends GameMod

# Références aux panneaux UI (injectées par main.gd via setter)
var discard_panel: DiscardPanel
var steal_panel: StealPanel

var _robber_node: MeshInstance3D

var _board: Board

func _init() -> void:
	mod_id = "vanilla_robber"
	mod_name = "Voleur classique"
	description = "Sur un 7: défausse, déplacement, vol"
	version = "1.0.0"
	depends_on = ["classic_catan"]

func setup_ui(p_discard: DiscardPanel, p_steal: StealPanel) -> void:
	discard_panel = p_discard
	steal_panel = p_steal
	discard_panel.discard_confirmed.connect(_on_discard_confirmed)
	steal_panel.target_chosen.connect(_on_target_chosen)

func register(reg: GameRegistry) -> void:
	# Au démarrage: poser le voleur sur le désert
	reg.on_game_start(_on_game_start, 0)
	# Priorité haute pour intercepter avant production
	reg.on_after_dice_rolled(_on_after_dice_rolled, 10)
	# Bloquer la production sur la tuile du voleur
	reg.on_before_produce(_on_before_produce, 0)
	# Gérer le clic sur tuile pour déplacer
	reg.on_tile_clicked(_on_tile_clicked, 0)

# === DÉMARRAGE ===

func _on_game_start(ctx) -> void:
	_board = ctx["board"]
	var board_view: BoardView = ctx["board_view"]
	var desert: Vector2 = _board.find_tile_where(func(t): return t.get("number", 0) == 0)
	if desert != Vector2.INF:
		_board.set_marker("robber", desert)
	_create_robber_visual(board_view, _board)
	_board.marker_changed.connect(_on_marker_changed)

func _create_robber_visual(board_view: BoardView, board: Board) -> void:
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
	# Trouve un parent: on utilise le ui_root du registry? Non, on a besoin du Node3D 3D.
	# On ajoute au même parent que les tiles
	var any_tile: Node = board_view.tile_nodes.values()[0]
	any_tile.get_parent().add_child(_robber_node)
	_refresh_robber_visual(board)

func _on_marker_changed(marker_id: String, coords: Vector2) -> void:
	if marker_id != "robber":
		return
	# Récupère le board depuis l'état stocké
	if _board != null:
		_refresh_robber_visual(_board)

func _refresh_robber_visual(board: Board) -> void:
	if _robber_node == null:
		return
	var pos: Vector2 = board.get_marker("robber")
	if pos == Vector2.INF:
		_robber_node.visible = false
		return
	_robber_node.visible = true
	var world := HexMath.hex_to_world(int(pos.x), int(pos.y))
	world.y = HexMath.TILE_HEIGHT / 2 + 0.3
	_robber_node.position = world

# === SUR LE 7 ===

func _on_after_dice_rolled(ctx: RollContext) -> void:
	if ctx.result != 7:
		return
	# Empêcher la production de ClassicCatan (priorité plus basse, jouera après)
	ctx.cancel_production = true
	var state: GameState = ctx.state
	state.roller_index = state.current_player_index
	# Identifier joueurs avec > 7 ressources
	state.discard_queue.clear()
	for i in state.players.size():
		var total: int = 0
		for v in state.players[i].resources.values():
			total += v
		if total > 7:
			state.discard_queue.append(i)
	if state.discard_queue.is_empty():
		state.sub_phase = GameState.SubPhase.ROBBER_MOVE
		print("Voleur: déplace le voleur (clique une tuile)")
	else:
		state.sub_phase = GameState.SubPhase.ROBBER_DISCARD
		_show_next_discard(state)

# === BLOCAGE ===
func _on_before_produce(ctx: ProductionContext) -> void:
	if ctx.board.has_marker_at("robber", ctx.tile_coords):
		ctx.cancelled = true

# === DÉFAUSSE ===
var _current_state: GameState

func _show_next_discard(state: GameState) -> void:
	print("_show_next_discard appelé, queue: ", state.discard_queue)
	if state.discard_queue.is_empty():
		state.sub_phase = GameState.SubPhase.ROBBER_MOVE
		print("Voleur: déplace le voleur (clique une tuile)")
		return
	var player_id: int = state.discard_queue[0]
	var p: Player = state.players[player_id]
	var total: int = 0
	for v in p.resources.values():
		total += v
	var to_discard: int = total / 2
	print("Ouverture panneau pour J%d, défausser %d" % [player_id, to_discard])
	_current_state = state
	discard_panel.show_for(state.registry, p, to_discard)

func _on_discard_confirmed(player_id: int, to_discard: Dictionary) -> void:
	print("Défausse confirmée par J%d: %s" % [player_id, str(to_discard)])
	if _current_state == null:
		print("ERREUR: _current_state est null")
		return
	var p: Player = _current_state.players[player_id]
	for res_id in to_discard:
		p.resources[res_id] -= to_discard[res_id]
	_current_state.discard_queue.pop_front()
	_show_next_discard(_current_state)

# === DÉPLACEMENT ===

func _on_tile_clicked(ctx: ClickContext) -> void:
	if ctx.state.sub_phase != GameState.SubPhase.ROBBER_MOVE:
		return
	var coords := ctx.target_coords
	var board := ctx.board
	if not board.tile_data.has(coords):
		print("Tuile invalide")
		return
	if board.has_marker_at("robber", coords):
		print("Le voleur doit être déplacé ailleurs")
		return
	board.set_marker("robber", coords)
	print("Voleur déplacé sur ", coords)
	var targets := _get_steal_targets(board, ctx.state, coords)
	if targets.is_empty():
		print("Personne à voler ici, tour terminé")
		ctx.state.sub_phase = GameState.SubPhase.NONE
	else:
		ctx.state.sub_phase = GameState.SubPhase.ROBBER_STEAL
		_current_state = ctx.state
		steal_panel.show_targets(ctx.state.players, targets)
	ctx.handled = true

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

# === VOL ===

func _on_target_chosen(target_id: int) -> void:
	if _current_state == null:
		return
	var state := _current_state
	var target: Player = state.players[target_id]
	var thief: Player = state.players[state.roller_index]
	var pool: Array = []
	for res_id in target.resources:
		for i in target.resources[res_id]:
			pool.append(res_id)
	if pool.is_empty():
		state.sub_phase = GameState.SubPhase.NONE
		return
	var stolen: String = pool.pick_random()
	target.resources[stolen] -= 1
	thief.add_resource(stolen, 1)
	print("Joueur %d vole %s à Joueur %d" % [thief.id, stolen, target.id])
	state.sub_phase = GameState.SubPhase.NONE
