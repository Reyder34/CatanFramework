extends Node3D

@onready var info_label: Label = $UI/HUD/InfoLabel

var registry: GameRegistry
var state: GameState
var board: Board
var board_view: BoardView
var ui: UIManager

var loaded_mods: Array[GameMod] = []

func _ready() -> void:
	registry = GameRegistry.new()
	registry.setup_ui($UI/HUD)
	registry.events.subscribe("flash_tile", _flash_tile_handler, 0, "core")
	
	# Chargement des mods (sera remplacé par un ModLoader plus tard)
	_load_mods()
	
	# Création de l'état après chargement (le registry est rempli)
	board = Board.new()
	board_view = BoardView.new(registry, board)
	board_view.on_tile_click = _on_tile_clicked
	board_view.on_vertex_click = _on_vertex_clicked
	board_view.on_edge_click = _on_edge_clicked
	board_view.generate(self)
	
	state = GameState.new(registry, 4)
	state.build_mode_id = "settlement"  # commence en mode colonie pour la phase initiale
	
	for p in state.players:
		for res_id in registry.resources:
			if not registry.resources[res_id].get("is_desert", false):
				p.resources[res_id] = 10	
	
	ui = UIManager.new(info_label, state, board)
	ui.update()
	
	registry.events.emit("game_start", {
		"state": state,
		"board": board,
		"registry": registry,
		"board_view": board_view,
	})
	
	print("Jeu prêt. Mods chargés: ", registry._origin.size(), " entrées dans le registry")

func _load_mods() -> void:
	var robber_mod := VanillaRobberMod.new()
	loaded_mods = [
		ClassicCatanMod.new(),
		robber_mod,
	]
	for mod in loaded_mods:
		registry._set_current_mod(mod.mod_id)
		mod.register(registry)
	registry._set_current_mod("core")


# === ENTRÉES UTILISATEUR ===

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if state.phase == GameState.Phase.GAME_OVER:
		return
	# Bloquer les actions globales tant qu'un panneau est ouvert
	if registry.ui != null and registry.ui.is_any_panel_open():
		return
	var action: GameAction = registry.find_action_by_hotkey(event.keycode)
	if action == null:
		return
	if not action.can_trigger():
		return
	action.callback.call()
	ui.update()


# === CLICS ===

func _on_tile_clicked(_cam, event, _pos, _norm, _idx, tile: StaticBody3D) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if state.phase == GameState.Phase.GAME_OVER:
		return
	var ctx := ClickContext.new()
	ctx.state = state
	ctx.board = board
	ctx.player_id = state.current_player_index
	ctx.target_coords = tile.get_meta("coords")
	registry.events.emit("tile_clicked", ctx)
	ui.update()

func _on_vertex_clicked(_cam, event, _pos, _norm, _idx, body: StaticBody3D) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if state.phase == GameState.Phase.GAME_OVER:
		return
	var ctx := ClickContext.new()
	ctx.state = state
	ctx.board = board
	ctx.player_id = state.current_player_index
	ctx.target_key = body.get_meta("key")
	registry.events.emit("vertex_clicked", ctx)
	ui.update()

func _on_edge_clicked(_cam, event, _pos, _norm, _idx, body: StaticBody3D) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if state.phase == GameState.Phase.GAME_OVER:
		return
	var ctx := ClickContext.new()
	ctx.state = state
	ctx.board = board
	ctx.player_id = state.current_player_index
	ctx.target_key = body.get_meta("key")
	registry.events.emit("edge_clicked", ctx)
	ui.update()

func _flash_tile_handler(ctx: Dictionary) -> void:
	var coords: Vector2 = ctx.get("coords", Vector2.ZERO)
	var tile: StaticBody3D = board_view.tile_nodes.get(coords)
	if tile == null:
		return
	var mesh_inst: MeshInstance3D = tile.get_child(0)
	var mat: StandardMaterial3D = mesh_inst.material_override
	var original := mat.albedo_color
	mat.albedo_color = Color.WHITE
	await get_tree().create_timer(0.4).timeout
	mat.albedo_color = original
