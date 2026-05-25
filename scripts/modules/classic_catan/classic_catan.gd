class_name ClassicCatan
extends GameModule

func _init() -> void:
	module_id = "classic_catan"
	display_name = "Catan classique"
	board_radius = 2
	
	resources = {
		"wood":   {"name": "Bois",    "color": Color(0.2, 0.5, 0.1)},
		"brick":  {"name": "Brique",  "color": Color(0.7, 0.3, 0.1)},
		"sheep":  {"name": "Mouton",  "color": Color(0.6, 0.9, 0.4)},
		"wheat":  {"name": "Blé",     "color": Color(0.9, 0.8, 0.2)},
		"ore":    {"name": "Minerai", "color": Color(0.5, 0.5, 0.6)},
		"desert": {"name": "Désert",  "color": Color(0.9, 0.8, 0.5), "is_desert": true},
	}
	
	tile_pool = [
		"wood","wood","wood","wood",
		"brick","brick","brick",
		"sheep","sheep","sheep","sheep",
		"wheat","wheat","wheat","wheat",
		"ore","ore","ore",
		"desert"
	]
	
	number_pool = [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12]
	
	# Enregistrement des bâtiments
	register_building(Settlement.new())
	register_building(Road.new())
	register_building(City.new())

# Quand les dés sont lancés, on gère production ou voleur
func on_dice_rolled(total: int, state: GameState, board: Board) -> void:
	if total == 7:
		_trigger_robber(state)
		return
	if not board.tiles_by_number.has(total):
		return
	for coords in board.tiles_by_number[total]:
		var tile_info: Dictionary = board.tile_data[coords]
		_distribute_resource(board, state, coords, tile_info["resource"])

func _trigger_robber(state: GameState) -> void:
	state.roller_index = state.current_player_index
	# Identifier les joueurs avec > 7 ressources
	state.discard_queue.clear()
	for i in state.players.size():
		var total: int = 0
		for res in state.players[i].resources.values():
			total += res
		if total > 7:
			state.discard_queue.append(i)
	if state.discard_queue.is_empty():
		# Personne à défausser, on passe direct au déplacement
		state.sub_phase = GameState.SubPhase.ROBBER_MOVE
		print("Voleur: déplace le voleur (clique une tuile)")
	else:
		state.sub_phase = GameState.SubPhase.ROBBER_DISCARD
		print("Voleur: défausse en cours pour les joueurs %s" % str(state.discard_queue))

func _distribute_resource(board: Board, state: GameState, coords: Vector2, resource: String) -> void:
	if board.is_robber_blocking(coords):
		return
	for v_key in board.tile_vertices.get(coords, []):
		var owner_id := board.get_vertex_owner(v_key)
		if owner_id < 0:
			continue
		var v_type := board.get_vertex_type(v_key)
		var building: BuildingType = buildings.get(v_type)
		if building == null:
			continue
		var amount := building.get_production_amount()
		state.players[owner_id].add_resource(resource, amount)

func on_vertex_clicked(key: String, state: GameState, board: Board) -> void:
	if state.phase == GameState.Phase.INITIAL_PLACEMENT:
		_handle_initial_settlement(key, state, board)
	elif state.phase == GameState.Phase.PLAY:
		_handle_normal_vertex_click(key, state, board)

func on_edge_clicked(key: String, state: GameState, board: Board) -> void:
	if state.phase == GameState.Phase.INITIAL_PLACEMENT:
		_handle_initial_road(key, state, board)
	elif state.phase == GameState.Phase.PLAY:
		_handle_normal_edge_click(key, state, board)

# === PHASE INITIALE ===

func _handle_initial_settlement(key: String, state: GameState, board: Board) -> void:
	# Doit être en mode colonie
	if state.build_mode_id != "settlement":
		print("Pose d'abord une colonie (touche 1)")
		return
	# Et il ne doit pas déjà avoir posé sa colonie ce tour
	if state.last_initial_settlement_key != "":
		print("Tu as déjà posé ta colonie, pose maintenant la route adjacente")
		return
	var settlement: Settlement = get_building("settlement")
	# Validation sans exigence de route (phase initiale)
	settlement.require_road = false
	var ok := settlement.can_place(board, state.current_player().id, key)
	settlement.require_road = true  # remettre tout de suite
	if not ok:
		print("Placement invalide (règle de distance)")
		return
	# Placer (gratuit)
	settlement.on_placed(board, state.current_player().id, key)
	state.last_initial_settlement_key = key
	# Si c'est le 2e placement: distribuer les ressources adjacentes
	var placement_index: int = state.initial_placements[state.current_player_index]
	if placement_index == 1:
		_distribute_initial_resources(state, board, key)

func _handle_initial_road(key: String, state: GameState, board: Board) -> void:
	if state.build_mode_id != "road":
		print("Pose maintenant ta route (touche 2)")
		return
	if state.last_initial_settlement_key == "":
		print("Pose d'abord ta colonie")
		return
	# La route doit être adjacente à la colonie qui vient d'être posée
	var endpoints: Array = board.edge_endpoints.get(key, [])
	if not endpoints.has(state.last_initial_settlement_key):
		print("La route doit être adjacente à ta colonie")
		return
	if board.is_edge_occupied(key):
		print("Cette arête est déjà occupée")
		return
	var road: Road = get_building("road")
	road.on_placed(board, state.current_player().id, key)
	state.advance_initial_placement()
	# Repasser en mode colonie pour le prochain joueur
	state.build_mode_id = "settlement"

func _distribute_initial_resources(state: GameState, board: Board, vertex_key: String) -> void:
	var v_data: Dictionary = board.vertex_data.get(vertex_key, {})
	if v_data.is_empty():
		return
	# On parcourt les 3 hexagones autour de ce sommet
	var q: int = v_data["q"]
	var r: int = v_data["r"]
	var corner: int = v_data["corner"]
	var n1: Vector2 = HexMath.NEIGHBOR_OFFSETS[corner]
	var n2: Vector2 = HexMath.NEIGHBOR_OFFSETS[(corner + 1) % 6]
	var coords_list := [
		Vector2(q, r),
		Vector2(q + n1.x, r + n1.y),
		Vector2(q + n2.x, r + n2.y),
	]
	for coords in coords_list:
		if not board.tile_data.has(coords):
			continue
		var tile: Dictionary = board.tile_data[coords]
		var resource: String = tile["resource"]
		if not is_producing_resource(resource):
			continue
		state.players[state.current_player_index].add_resource(resource, 1)
	print("Ressources distribuées pour la 2e colonie")

# === PHASE NORMALE (renommée depuis on_vertex_clicked/on_edge_clicked) ===

func _handle_normal_vertex_click(key: String, state: GameState, board: Board) -> void:
	var building: BuildingType = buildings.get(state.build_mode_id)
	if building == null or building.target != "vertex":
		return
	var p := state.current_player()
	if not building.can_place(board, p.id, key):
		print("Placement de %s invalide" % building.display_name)
		return
	if not can_afford(p, building.id):
		print("Pas assez de ressources pour %s" % building.display_name)
		return
	pay(p, building.id)
	building.on_placed(board, p.id, key)
	_check_victory(state, board)

func _handle_normal_edge_click(key: String, state: GameState, board: Board) -> void:
	var building: BuildingType = buildings.get(state.build_mode_id)
	if building == null or building.target != "edge":
		return
	var p := state.current_player()
	if not building.can_place(board, p.id, key):
		print("Placement de %s invalide" % building.display_name)
		return
	if not can_afford(p, building.id):
		print("Pas assez de ressources pour %s" % building.display_name)
		return
	pay(p, building.id)
	building.on_placed(board, p.id, key)
	_check_victory(state, board)


func on_tile_clicked(coords: Vector2, state: GameState, board: Board) -> void:
	if state.sub_phase == GameState.SubPhase.ROBBER_MOVE:
		_handle_robber_move(coords, state, board)

func _handle_robber_move(coords: Vector2, state: GameState, board: Board) -> void:
	# La tuile doit exister (être de la terre)
	if not board.tile_data.has(coords):
		print("Tuile invalide")
		return
	if coords == board.robber_position:
		print("Le voleur doit être déplacé ailleurs")
		return
	board.move_robber(coords)
	print("Voleur déplacé sur ", coords)
	# Identifier les cibles potentielles
	var targets := _get_steal_targets(board, state, coords)
	if targets.is_empty():
		print("Personne à voler ici, tour terminé")
		state.sub_phase = GameState.SubPhase.NONE
	else:
		state.sub_phase = GameState.SubPhase.ROBBER_STEAL
		print("Voleur: choisis une cible à voler parmi: ", targets)

func _get_steal_targets(board: Board, state: GameState, coords: Vector2) -> Array:
	# Retourne la liste des player_id ayant une colonie/ville adjacente
	# (autres que le voleur lui-même, et ayant au moins 1 ressource)
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


func get_current_steal_targets(state: GameState, board: Board) -> Array:
	return _get_steal_targets(board, state, board.robber_position)

func steal_from(target_id: int, state: GameState) -> void:
	var target: Player = state.players[target_id]
	var thief: Player = state.players[state.roller_index]
	# Construire une liste de toutes les "cartes" pour tirer au hasard
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


func _check_victory(state: GameState, board: Board) -> void:
	var p := state.current_player()
	var points := calculate_victory_points(p.id, board)
	if points >= points_to_win():
		state.phase = GameState.Phase.GAME_OVER
		state.winner_index = p.id
		print("Joueur %d a gagné avec %d points!" % [p.id, points])
