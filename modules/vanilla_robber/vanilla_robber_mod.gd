class_name VanillaRobberMod
extends GameMod

# Ids des sous-phases (constantes pour éviter les fautes de frappe)
const SP_DISCARD := "vanilla_robber:discard"
const SP_MOVE := "vanilla_robber:move"
const SP_STEAL := "vanilla_robber:steal"

# Plus grande armée
const EFF_LARGEST_ARMY := "largest_army"
const KNIGHTS_KEY := "vanilla_robber:knights"

var _robber_node: Node3D
var _board: Board
var _registry: GameRegistry
var _state: GameState

# Joueur qui a déclenché le voleur (état local au mod, plus dans GameState)
var _roller_index: int = 0

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
	# Labels de sous-phases
	reg.register_sub_phase_label(SP_DISCARD, "Défausse en cours")
	reg.register_sub_phase_label(SP_MOVE, "Déplace le voleur (clique une tuile)")
	reg.register_sub_phase_label(SP_STEAL, "Choisis une cible à voler")
	# Hooks
	reg.on("game_start", _on_game_start, 0)
	reg.on(ClassicCatanMod.EVT_AFTER_DICE, _on_after_dice_rolled, 10)
	reg.on(ClassicCatanMod.EVT_BEFORE_PRODUCE, _on_before_produce, 0)
	reg.on("tile_clicked", _on_tile_clicked, 0)
	reg.on(ClassicCatanMod.EVT_KNIGHT_PLAYED, _on_knight_played, 0)

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
	# Modèle 3D du voleur (robber.glb) ; repli sur un cône sombre si le .glb est absent.
	var path := "res://modules/vanilla_robber/robber.glb"
	var scene: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if scene != null:
		_robber_node = scene.instantiate()
	else:
		var m := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.15
		mesh.bottom_radius = 0.25
		mesh.height = 0.6
		mesh.radial_segments = 12
		m.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.1, 0.1)
		m.material_override = mat
		_robber_node = m
	_robber_node.name = "Robber"
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
	ctx.cancel_production = true
	_run_robber_sequence(ctx.state)

func _run_robber_sequence(state: GameState) -> void:
	_roller_index = state.current_player_index
	state.sub_phase = SP_DISCARD
	# Tous les joueurs concernés défaussent EN MÊME TEMPS (panneaux ouverts en parallèle).
	var requests: Array = []
	var discarders: Array = []
	for i in state.players.size():
		var total: int = 0
		for v in state.players[i].resources.values():
			total += v
		if total <= 7:
			continue
		requests.append({"player_index": i, "panel_id": "robber_discard", "raw": {"target_amount": total / 2}})
		discarders.append(i)
	var results: Array = await Net.show_panels_parallel(requests)
	for k in results.size():
		var result = results[k]
		if result != null:
			var p: Player = state.players[discarders[k]]
			var discarded: Dictionary = result["to_discard"]
			for res_id in discarded:
				p.add_resource(res_id, -discarded[res_id])
	state.sub_phase = SP_MOVE

# === DÉPLACEMENT (via clic tuile) ===

func _on_tile_clicked(ctx: ClickContext) -> void:
	if ctx.state.sub_phase != SP_MOVE:
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
	var targets := _get_steal_targets(board, ctx.state, coords)
	if targets.is_empty():
		ctx.state.sub_phase = ""
		return
	ctx.state.sub_phase = SP_STEAL
	_run_steal_choice(ctx.state, targets)

func _run_steal_choice(state: GameState, targets: Array) -> void:
	var result = await Net.show_panel_for(_roller_index, "robber_steal", {
		"target_ids": targets,
	})
	if result != null:
		var target_id: int = result["target_id"]
		_perform_steal(state, target_id)
	state.sub_phase = ""

func _get_steal_targets(board: Board, state: GameState, coords: Vector2) -> Array:
	var targets: Array = []
	for v_key in board.tile_vertices.get(coords, []):
		var owner_id := board.get_vertex_owner(v_key)
		if owner_id < 0 or owner_id == _roller_index:
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
	var thief: Player = state.players[_roller_index]
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

# === CARTE CHEVALIER / PLUS GRANDE ARMÉE ===

func _on_knight_played(ctx) -> void:
	var player: Player = ctx["player"]
	var count: int = int(player.get_data(KNIGHTS_KEY, 0)) + 1
	player.set_data(KNIGHTS_KEY, count)
	_update_largest_army()
	# Déplace le voleur comme sur un 7, mais sans défausse préalable.
	_roller_index = _state.current_player_index
	_state.sub_phase = SP_MOVE

# Attribue l'effet largest_army au joueur ayant le plus de chevaliers (>=3),
# pris à l'ancien détenteur seulement si strictement plus (égalité = détenteur garde).
func _update_largest_army() -> void:
	var holder_id := -1
	for p in _state.players:
		if p.has_effect(EFF_LARGEST_ARMY):
			holder_id = p.id
	var holder_count := 0
	if holder_id >= 0:
		holder_count = int(_state.players[holder_id].get_data(KNIGHTS_KEY, 0))
	var best_id := holder_id
	var best_count: int = max(holder_count, 2)  # il faut au moins 3 chevaliers
	for p in _state.players:
		var c: int = int(p.get_data(KNIGHTS_KEY, 0))
		if c >= 3 and c > best_count:
			best_count = c
			best_id = p.id
	if best_id != holder_id and best_id >= 0:
		if holder_id >= 0:
			_state.players[holder_id].remove_effect_by_id(EFF_LARGEST_ARMY)
		var eff := PlayerEffect.new()
		eff.id = EFF_LARGEST_ARMY
		eff.source_mod = mod_id
		eff.display_name = "Plus grande armée"
		eff.description = "Au moins 3 chevaliers joués"
		eff.victory_points = 2
		eff.data = {"knights": best_count}
		_state.players[best_id].add_effect(eff)
		print("Plus grande armée -> Joueur %d (%d chevaliers)" % [best_id, best_count])
	_registry.check_victory(_state)
