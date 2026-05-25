extends Node3D

@onready var info_label: Label = $UI/HUD/InfoLabel
@onready var discard_panel: DiscardPanel = $UI/HUD/DiscardPanel
@onready var steal_panel: StealPanel = $UI/HUD/StealPanel

var module: GameModule
var state: GameState
var board: Board
var board_view: BoardView
var ui: UIManager


func _ready() -> void:
	module = ClassicCatan.new()
	state = GameState.new(module, 4)
	state.build_mode_id = "settlement"
	
	board = Board.new()
	board_view = BoardView.new(module, board)
	board_view.on_tile_click = _on_tile_clicked
	board_view.on_vertex_click = _on_vertex_clicked
	board_view.on_edge_click = _on_edge_clicked
	board_view.generate(self)
	board.move_robber(board.find_desert_tile())
	
	for p in state.players:
		for res_id in p.resources:
			p.resources[res_id] = 100
	
	discard_panel.discard_confirmed.connect(_on_discard_confirmed)
	steal_panel.target_chosen.connect(_on_target_chosen)
	
	ui = UIManager.new(info_label, state, board)
	ui.update()
	print("Prêt. ESPACE=dés, ENTRÉE=joueur suivant")

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if state.phase == GameState.Phase.GAME_OVER:
		return
	# Touches universelles
	match event.keycode:
		KEY_SPACE:
			_roll_dice()
			ui.update()
			return
		KEY_ENTER:
			state.next_player()
			ui.update()
			return
		KEY_ESCAPE:
			state.build_mode_id = ""
			ui.update()
			return
	# Touches définies par le module (bâtiments)
	for b in module.get_build_modes():
		if b.hotkey == event.keycode:
			state.build_mode_id = b.id
			ui.update()
			return

func _roll_dice() -> void:
	if state.phase != GameState.Phase.PLAY:
		print("Pas le moment de lancer les dés")
		return
	if state.sub_phase != GameState.SubPhase.NONE:
		print("Termine d'abord l'action en cours")
		return
	var total := module.roll_dice()
	print("Dés: %d" % total)
	module.on_dice_rolled(total, state, board)
	if board.tiles_by_number.has(total):
		for coords in board.tiles_by_number[total]:
			_flash_tile(coords)
	# Si on est entré en sous-phase de défausse, ouvrir le panneau
	if state.sub_phase == GameState.SubPhase.ROBBER_DISCARD:
		_show_next_discard()
	ui.update()

func _flash_tile(coords: Vector2) -> void:
	var tile: StaticBody3D = board_view.tile_nodes.get(coords)
	if tile == null:
		return
	var mesh_inst: MeshInstance3D = tile.get_child(0)
	var mat: StandardMaterial3D = mesh_inst.material_override
	var original := mat.albedo_color
	mat.albedo_color = Color.WHITE
	await get_tree().create_timer(0.4).timeout
	mat.albedo_color = original

func _on_tile_clicked(_cam, event, _pos, _norm, _idx, tile: StaticBody3D) -> void:
	if state.phase == GameState.Phase.GAME_OVER:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var coords: Vector2 = tile.get_meta("coords")
	module.on_tile_clicked(coords, state, board)
	# Si on vient d'entrer en phase de vol, ouvrir le panneau
	if state.sub_phase == GameState.SubPhase.ROBBER_STEAL:
		var targets: Array = module.get_current_steal_targets(state, board)
		steal_panel.show_targets(state.players, targets)
	ui.update()

func _on_vertex_clicked(_cam, event, _pos, _norm, _idx, body: StaticBody3D) -> void:
	if state.phase == GameState.Phase.GAME_OVER:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var key: String = body.get_meta("key")
	module.on_vertex_clicked(key, state, board)
	ui.update()

func _on_edge_clicked(_cam, event, _pos, _norm, _idx, body: StaticBody3D) -> void:
	if state.phase == GameState.Phase.GAME_OVER:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var key: String = body.get_meta("key")
	module.on_edge_clicked(key, state, board)
	ui.update()

func _show_next_discard() -> void:
	if state.discard_queue.is_empty():
		# Tout le monde a défaussé, on passe au déplacement
		state.sub_phase = GameState.SubPhase.ROBBER_MOVE
		print("Voleur: déplace-le (clique une tuile)")
		ui.update()
		return
	var player_id: int = state.discard_queue[0]
	var p: Player = state.players[player_id]
	var total: int = 0
	for v in p.resources.values():
		total += v
	var to_discard: int = total / 2  # arrondi au plus petit
	discard_panel.show_for(module, p, to_discard)

func _on_discard_confirmed(player_id: int, to_discard: Dictionary) -> void:
	var p: Player = state.players[player_id]
	for res_id in to_discard:
		p.resources[res_id] -= to_discard[res_id]
	state.discard_queue.pop_front()
	ui.update()
	_show_next_discard()

func _on_target_chosen(target_id: int) -> void:
	module.steal_from(target_id, state)
	ui.update()
