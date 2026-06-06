class_name ClassicCatanMod
extends GameMod

var _state: GameState
var _board: Board
var _registry: GameRegistry

const DEV_CARD_COST := {"wheat": 1, "sheep": 1, "ore": 1}

# === ÉVÉNEMENTS POSSÉDÉS PAR CE MOD (ids namespacés) ===
# Les mods dépendants (ex: vanilla_robber) s'y abonnent via ces constantes.
const EVT_DICE_ROLL := "classic_catan:dice_roll"
const EVT_AFTER_DICE := "classic_catan:after_dice_rolled"
const EVT_BEFORE_PRODUCE := "classic_catan:before_produce"
const EVT_BEFORE_PLACE := "classic_catan:before_place"
const EVT_AFTER_PLACE := "classic_catan:after_place"
const EVT_TRADE_COMPLETED := "classic_catan:trade_completed"
const EVT_BANK_TRADE_COMPLETED := "classic_catan:bank_trade_completed"
const EVT_KNIGHT_PLAYED := "classic_catan:knight_played"
const EVT_ROAD_BUILDING_PLAYED := "classic_catan:road_building_played"
const EVT_REQUEST_TRADE_WITH := "classic_catan:request_trade_with"
const EVT_REQUEST_PLAY_CARD := "classic_catan:request_play_card"

# Sous-phase: pose de routes gratuites (carte Construction de routes)
const SP_FREE_ROAD := "classic_catan:free_road"
# "Dés lancés ce tour" (par joueur, dans custom_data): empêche relance/skip du tour.
const ROLLED_KEY := "classic_catan:rolled_dice"

var _free_roads_remaining: int = 0

# Cartes développement
var _dev_deck: Array = []  # Array[DevelopmentCard]

# Placement initial (règle de setup Catan, pilotée par ce mod)
var _initial_placements: Array = []
var _initial_direction: int = 1
var _last_initial_settlement_key: String = ""

# Ports: vertex_key -> {"ratio": int, "resource": String}  (resource "" = générique 3:1)
var _port_at_vertex: Dictionary = {}
var _ports_info: Array = []  # pour le visuel: [{"pos": Vector3, "label": String}]

func _init() -> void:
	mod_id = "classic_catan"
	mod_name = "Catan classique"
	description = "Le jeu de base: ressources, colonies, villes, routes, voleur sur 7"
	version = "1.0.0"
	author = "Toi"

func register(reg: GameRegistry) -> void:
	_declare_resources(reg)
	_declare_buildings(reg)
	_declare_pools(reg)
	_declare_parameters(reg)
	_subscribe_hooks(reg)
	_register_actions(reg)
	reg.register_panel("dev_cards", preload("res://modules/classic_catan/panels/dev_cards_panel.tscn"))
	reg.on("game_start", _init_dev_deck, 0)
	reg.register_panel("hello", preload("res://modules/classic_catan/panels/hello_panel.tscn"))
	reg.register_panel("trade_proposal", preload("res://modules/classic_catan/panels/trade_proposal_panel.tscn"))
	reg.register_panel("trade_response", preload("res://modules/classic_catan/panels/trade_response_panel.tscn"))
	reg.register_panel("bank_trade", preload("res://modules/classic_catan/panels/bank_trade_panel.tscn"))
	reg.register_panel("resource_picker", preload("res://modules/classic_catan/panels/resource_picker_panel.tscn"))
	reg.register_sub_phase_label(SP_FREE_ROAD, "Pose 2 routes gratuites")

# === DONNÉES ===

func _declare_resources(reg: GameRegistry) -> void:
	var tiles := "res://modules/classic_catan/tiles/"
	reg.declare_resource("wood",   {"name": "Bois",    "color": Color(0.2, 0.5, 0.1), "model": tiles + "wood.glb"})
	reg.declare_resource("brick",  {"name": "Brique",  "color": Color(0.7, 0.3, 0.1), "model": tiles + "brick.glb"})
	reg.declare_resource("sheep",  {"name": "Mouton",  "color": Color(0.6, 0.9, 0.4), "model": tiles + "sheep.glb"})
	reg.declare_resource("wheat",  {"name": "Blé",     "color": Color(0.9, 0.8, 0.2), "model": tiles + "wheat.glb"})
	reg.declare_resource("ore",    {"name": "Minerai", "color": Color(0.5, 0.5, 0.6), "model": tiles + "ore.glb"})
	reg.declare_resource("desert", {"name": "Désert",  "color": Color(0.9, 0.8, 0.5), "is_desert": true, "model": tiles + "desert.glb"})

func _declare_buildings(reg: GameRegistry) -> void:
	reg.declare_building(Settlement.new())
	reg.declare_building(Road.new())
	reg.declare_building(City.new())

func _declare_pools(reg: GameRegistry) -> void:
	for r in ["wood","wood","wood","wood","brick","brick","brick","sheep","sheep","sheep","sheep","wheat","wheat","wheat","wheat","ore","ore","ore","desert"]:
		reg.add_to_tile_pool(r)
	for n in [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12]:
		reg.add_to_number_pool(n)

func _declare_parameters(reg: GameRegistry) -> void:
	reg.set_board_radius(2)
	reg.set_victory_threshold(10)

# === HOOKS ===

func _subscribe_hooks(reg: GameRegistry) -> void:
	reg.on(EVT_DICE_ROLL, _on_dice_roll, 0)
	reg.on(EVT_AFTER_DICE, _on_after_dice_rolled, 0)
	reg.on("vertex_clicked", _on_vertex_clicked, 0)
	reg.on("edge_clicked", _on_edge_clicked, 0)
	reg.on("game_start", _on_game_start_for_actions, 0)
	reg.on(EVT_ROAD_BUILDING_PLAYED, _on_road_building_played, 0)
	reg.on(EVT_REQUEST_TRADE_WITH, _on_request_trade_with, 0)
	reg.on(EVT_REQUEST_PLAY_CARD, _on_request_play_card, 0)

# Lancer 2d6 si personne n'a fourni de résultat
func _on_dice_roll(ctx: RollContext) -> void:
	if ctx.result == -1:
		ctx.result = randi_range(1, 6) + randi_range(1, 6)

# Distribution des ressources (saute le 7, c'est pour le voleur ailleurs)
func _on_after_dice_rolled(ctx: RollContext) -> void:
	if ctx.cancel_production or ctx.result == 7:
		return
	if not ctx.board.tiles_by_number.has(ctx.result):
		return
	for coords in ctx.board.tiles_by_number[ctx.result]:
		_distribute_resource(ctx.state, ctx.board, coords)

func _distribute_resource(state: GameState, board: Board, coords: Vector2) -> void:
	# before_produce permet à un mod (ex: voleur) d'annuler la production d'une tuile
	var pctx := ProductionContext.new()
	pctx.state = state
	pctx.board = board
	pctx.tile_coords = coords
	pctx.resource_id = board.tile_data[coords]["resource"]
	state.registry.emit(EVT_BEFORE_PRODUCE, pctx)
	if pctx.cancelled:
		return
	
	var resource: String = pctx.resource_id
	for v_key in board.tile_vertices.get(coords, []):
		var owner_id := board.get_vertex_owner(v_key)
		if owner_id < 0:
			continue
		var v_type := board.get_vertex_type(v_key)
		var building: BuildingType = state.registry.get_building(v_type)
		if building == null:
			continue
		state.players[owner_id].add_resource(resource, building.get_production_amount())

# Clic sommet: distribue selon la phase
func _on_vertex_clicked(ctx: ClickContext) -> void:
	if ctx.handled:
		return
	if ctx.state.phase == GameState.Phase.SETUP:
		_handle_initial_settlement(ctx)
	elif ctx.state.phase == GameState.Phase.PLAY:
		if ctx.state.sub_phase == SP_FREE_ROAD:
			return  # pendant la pose de routes gratuites, ignorer les sommets
		_handle_normal_vertex_click(ctx)

func _on_edge_clicked(ctx: ClickContext) -> void:
	if ctx.handled:
		return
	if ctx.state.phase == GameState.Phase.SETUP:
		_handle_initial_road(ctx)
	elif ctx.state.phase == GameState.Phase.PLAY:
		if ctx.state.sub_phase == SP_FREE_ROAD:
			_handle_free_road(ctx)
		else:
			_handle_normal_edge_click(ctx)

# === PHASE INITIALE ===

func _handle_initial_settlement(ctx: ClickContext) -> void:
	var state := ctx.state
	var board := ctx.board
	var key := ctx.target_key
	if state.build_mode_id != "settlement":
		print("Pose d'abord une colonie (touche 1)")
		return
	if _last_initial_settlement_key != "":
		print("Tu as déjà posé ta colonie, pose maintenant la route adjacente")
		return
	var settlement: Settlement = state.registry.get_building("settlement")
	settlement.require_road = false
	var ok := settlement.can_place(board, state.current_player().id, key)
	settlement.require_road = true
	if not ok:
		print("Placement invalide (règle de distance)")
		return
	settlement.on_placed(board, state.current_player().id, key)
	_register_building_for_player(state.current_player(), settlement, key)
	_last_initial_settlement_key = key
	# Sur la 2e colonie: ressources adjacentes
	var placement_index: int = _initial_placements[state.current_player_index]
	if placement_index == 1:
		_distribute_initial_resources(state, board, key)

func _handle_initial_road(ctx: ClickContext) -> void:
	var state := ctx.state
	var board := ctx.board
	var key := ctx.target_key
	if state.build_mode_id != "road":
		print("Pose maintenant ta route (touche 2)")
		return
	if _last_initial_settlement_key == "":
		print("Pose d'abord ta colonie")
		return
	var endpoints: Array = board.edge_endpoints.get(key, [])
	if not endpoints.has(_last_initial_settlement_key):
		print("La route doit être adjacente à ta colonie")
		return
	if board.is_edge_occupied(key):
		print("Cette arête est déjà occupée")
		return
	var road: Road = state.registry.get_building("road")
	road.on_placed(board, state.current_player().id, key)
	_register_building_for_player(state.current_player(), road, key)
	_advance_initial_placement()
	state.build_mode_id = "settlement"

func _distribute_initial_resources(state: GameState, board: Board, vertex_key: String) -> void:
	var v_data: Dictionary = board.vertex_data.get(vertex_key, {})
	if v_data.is_empty():
		return
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
		var resource: String = board.tile_data[coords]["resource"]
		if not state.registry.is_producing_resource(resource):
			continue
		state.players[state.current_player_index].add_resource(resource, 1)

# Avance le placement initial (snake-draft): chaque joueur pose 2 colonies+routes.
# Pilote directement current_player_index/phase du core (le core ne connaît pas cette règle).
func _advance_initial_placement() -> void:
	_initial_placements[_state.current_player_index] += 1
	_last_initial_settlement_key = ""
	var all_done := true
	for count in _initial_placements:
		if count < 2:
			all_done = false
			break
	if all_done:
		_state.phase = GameState.Phase.PLAY
		_state.current_player_index = 0
		_state.build_mode_id = ""
		return
	if _initial_direction == 1 and _state.current_player_index == _state.players.size() - 1:
		_initial_direction = -1
	elif _initial_direction == -1 and _state.current_player_index == 0:
		pass
	else:
		_state.current_player_index += _initial_direction
	_state.build_mode_id = ""

# === PHASE NORMALE ===

func _handle_normal_vertex_click(ctx: ClickContext) -> void:
	_try_place(ctx, "vertex")

func _handle_normal_edge_click(ctx: ClickContext) -> void:
	_try_place(ctx, "edge")

func _try_place(ctx: ClickContext, expected_target: String) -> void:
	var state := ctx.state
	var board := ctx.board
	var key := ctx.target_key
	var building: BuildingType = state.registry.get_building(state.build_mode_id)
	if building == null or building.target != expected_target:
		return
	var p := state.current_player()
	# En phase de jeu, il faut avoir lancé les dés avant de construire.
	if state.phase == GameState.Phase.PLAY and not p.get_data(ROLLED_KEY, false):
		print("Lance les dés avant de construire")
		return
	if not building.can_place(board, p.id, key):
		print("Placement de %s invalide" % building.display_name)
		return
	# Émettre before_place pour permettre des mods de bloquer
	var pctx := PlaceContext.new()
	pctx.state = state
	pctx.board = board
	pctx.player_id = p.id
	pctx.building_id = building.id
	pctx.target_key = key
	pctx.cost = building.cost.duplicate()
	state.registry.emit(EVT_BEFORE_PLACE, pctx)
	if pctx.cancelled:
		print("Placement annulé: %s" % pctx.cancel_reason)
		return
	# Vérifier coût
	for res in pctx.cost:
		if p.resources.get(res, 0) < pctx.cost[res]:
			print("Pas assez de ressources pour %s" % building.display_name)
			return
	# Payer et placer
	for res in pctx.cost:
		p.add_resource(res, -pctx.cost[res])
	building.on_placed(board, p.id, key)
	_register_building_for_player(p, building, key)
	state.registry.emit(EVT_AFTER_PLACE, pctx)
	state.registry.emit("game_log", {"text": "%s a construit : %s" % [p.label(), building.display_name]})
	_update_longest_road(state, board)
	state.registry.check_victory(state)


# === ROUTES GRATUITES (carte Construction de routes) ===

func _on_road_building_played(_ctx) -> void:
	if not _has_placeable_road(_state.current_player_index):
		print("[Construction de routes] aucune route posable")
		return
	_free_roads_remaining = 2
	_state.sub_phase = SP_FREE_ROAD

func _handle_free_road(ctx: ClickContext) -> void:
	var state := ctx.state
	var board := ctx.board
	var p := state.current_player()
	var road: BuildingType = state.registry.get_building("road")
	if not road.can_place(board, p.id, ctx.target_key):
		print("Route gratuite: placement invalide")
		return
	road.on_placed(board, p.id, ctx.target_key)
	_register_building_for_player(p, road, ctx.target_key)
	_free_roads_remaining -= 1
	_update_longest_road(state, board)
	if _free_roads_remaining <= 0 or not _has_placeable_road(p.id):
		_free_roads_remaining = 0
		state.sub_phase = ""
	state.registry.check_victory(state)

func _has_placeable_road(player_id: int) -> bool:
	var road: BuildingType = _registry.get_building("road")
	for key in _board.edge_data:
		if road.can_place(_board, player_id, key):
			return true
	return false

# === PLUS LONGUE ROUTE ===

# Recalcule l'effet longest_road pour tous les joueurs (détenteur gardé en cas d'égalité).
func _update_longest_road(state: GameState, board: Board) -> void:
	var lengths: Dictionary = {}
	for p in state.players:
		lengths[p.id] = _compute_longest_road(board, p.id)
	var holder_id := -1
	for p in state.players:
		if p.has_effect("longest_road"):
			holder_id = p.id
	# Le détenteur perd l'effet si sa route est tombée sous 5 (coupée).
	if holder_id >= 0 and int(lengths[holder_id]) < 5:
		state.players[holder_id].remove_effect_by_id("longest_road")
		holder_id = -1
	var target_id := holder_id
	var target_len: int = int(lengths[holder_id]) if holder_id >= 0 else 4
	for p in state.players:
		var l: int = int(lengths[p.id])
		if l >= 5 and l > target_len:
			target_len = l
			target_id = p.id
	if target_id != holder_id and target_id >= 0:
		if holder_id >= 0:
			state.players[holder_id].remove_effect_by_id("longest_road")
		var eff := PlayerEffect.new()
		eff.id = "longest_road"
		eff.source_mod = mod_id
		eff.display_name = "Route la plus longue"
		eff.description = "Au moins 5 segments de route contigus"
		eff.victory_points = 2
		eff.data = {"length": target_len}
		state.players[target_id].add_effect(eff)
		print("Route la plus longue -> Joueur %d (%d segments)" % [target_id, target_len])

# Longueur du plus long chemin de routes du joueur (coupé par un bâtiment adverse).
func _compute_longest_road(board: Board, player_id: int) -> int:
	var best := 0
	for e in board.edge_state:
		if board.get_edge_owner(e) != player_id:
			continue
		for start in board.edge_endpoints.get(e, []):
			var other: String = _other_endpoint(board, e, start)
			var used: Dictionary = {e: true}
			best = max(best, 1 + _road_dfs(board, player_id, other, used))
	return best

func _road_dfs(board: Board, player_id: int, vertex: String, used: Dictionary) -> int:
	# Un bâtiment adverse sur ce sommet coupe la route: interdit de le traverser.
	var owner := board.get_vertex_owner(vertex)
	if owner >= 0 and owner != player_id:
		return 0
	var best := 0
	for e in board.vertex_edges.get(vertex, []):
		if used.has(e):
			continue
		if board.get_edge_owner(e) != player_id:
			continue
		var other: String = _other_endpoint(board, e, vertex)
		used[e] = true
		best = max(best, 1 + _road_dfs(board, player_id, other, used))
		used.erase(e)
	return best

func _other_endpoint(board: Board, edge_key: String, vertex: String) -> String:
	for v in board.edge_endpoints.get(edge_key, []):
		if v != vertex:
			return v
	return ""

func _on_game_start_for_actions(ctx) -> void:
	_state = ctx["state"]
	_board = ctx["board"]
	_registry = ctx["registry"]
	# Initialise le setup Catan: chaque joueur posera 2 colonies + 2 routes.
	_initial_placements.clear()
	for i in _state.players.size():
		_initial_placements.append(0)
	_initial_direction = 1
	_last_initial_settlement_key = ""
	_state.build_mode_id = "settlement"  # on démarre en pose de colonie
	_compute_ports()
	_create_port_visuals(ctx["board_view"])

# === PORTS (commerce réduit si on a une colonie/ville sur un sommet de port) ===

func _compute_ports() -> void:
	_port_at_vertex.clear()
	_ports_info.clear()
	# Arêtes côtières: la tuile voisine de l'autre côté est de l'eau (hors plateau).
	var coastal: Array = []
	for e in _board.edge_data:
		var d: Dictionary = _board.edge_data[e]
		var n: Vector2 = HexMath.NEIGHBOR_OFFSETS[d["side"]]
		var neighbor := Vector2(d["q"] + n.x, d["r"] + n.y)
		if _board.tile_data.has(neighbor):
			continue  # arête intérieure
		coastal.append({"edge": e, "q": d["q"], "r": d["r"], "side": d["side"]})
	if coastal.is_empty():
		return
	# Indexées par angle autour du centre (pour mesurer l'espacement sur le pourtour).
	coastal.sort_custom(func(a, b): return _edge_angle(a) < _edge_angle(b))
	var count := coastal.size()
	# Sélection ALÉATOIRE mais espacée: on tire les arêtes dans un ordre mélangé et
	# on n'en garde une que si elle est à >= 2 arêtes des ports déjà posés.
	var order: Array = []
	for i in count:
		order.append(i)
	order.shuffle()
	var picked: Array = []
	for idx in order:
		if picked.size() >= 9:
			break
		var ok := true
		for pidx in picked:
			var diff: int = abs(idx - pidx)
			if min(diff, count - diff) < 2:
				ok = false
				break
		if ok:
			picked.append(idx)
	# Types mélangés (4 génériques 3:1 + 5 spécifiques 2:1).
	var port_types: Array = [
		{"ratio": 3, "resource": ""}, {"ratio": 3, "resource": ""},
		{"ratio": 3, "resource": ""}, {"ratio": 3, "resource": ""},
		{"ratio": 2, "resource": "wood"}, {"ratio": 2, "resource": "brick"},
		{"ratio": 2, "resource": "sheep"}, {"ratio": 2, "resource": "wheat"},
		{"ratio": 2, "resource": "ore"},
	]
	port_types.shuffle()
	for k in picked.size():
		var c: Dictionary = coastal[picked[k]]
		var pt: Dictionary = port_types[k]
		var eps: Array = _board.edge_endpoints.get(c["edge"], [])
		for v in eps:
			_port_at_vertex[v] = {"ratio": pt["ratio"], "resource": pt["resource"]}
		# Position: ancrée sur le sommet côtier le plus au large (MÊME fonction que les
		# colonies: vertex_position), avec un léger retrait vers l'eau pour ne pas
		# masquer le spot de construction. Bas pour éviter la parallaxe.
		var anchor := HexMath.edge_position(c["q"], c["r"], c["side"])
		var best_d := -1.0
		for v in eps:
			var vd: Dictionary = _board.vertex_data.get(v, {})
			if vd.is_empty():
				continue
			var vpos := HexMath.vertex_position(vd["q"], vd["r"], vd["corner"])
			var d := Vector2(vpos.x, vpos.z).length()
			if d > best_d:
				best_d = d
				anchor = vpos
		var outward := Vector3(anchor.x, 0, anchor.z)
		if outward.length() > 0.001:
			outward = outward.normalized()
		var pos := anchor + outward * 0.1
		pos.y = 0.14
		_ports_info.append({"pos": pos, "ratio": pt["ratio"], "resource": pt["resource"]})

func _edge_angle(c: Dictionary) -> float:
	var pos := HexMath.edge_position(c["q"], c["r"], c["side"])
	return atan2(pos.z, pos.x)

# Meilleur ratio d'échange banque du joueur pour une ressource (4 par défaut).
func _best_bank_ratio(player: Player, resource: String) -> int:
	var best := 4
	for placed in player.buildings:
		if placed.target != "vertex":
			continue
		if not _port_at_vertex.has(placed.key):
			continue
		var port: Dictionary = _port_at_vertex[placed.key]
		if port["resource"] == "" or port["resource"] == resource:
			best = min(best, int(port["ratio"]))
	return best

func _create_port_visuals(board_view) -> void:
	if board_view == null or board_view.tile_nodes.is_empty():
		return
	var parent: Node = board_view.tile_nodes.values()[0].get_parent()
	for info in _ports_info:
		var res: String = info["resource"]
		# Juste le ratio, coloré par la ressource (blanc pour le port générique 3:1),
		# gardé au premier plan pour rester lisible même avec un bâtiment dessus.
		var label := Label3D.new()
		label.text = "%d:1" % int(info["ratio"])
		label.font_size = 48
		label.outline_size = 12
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = _registry.get_resource_color(res) if res != "" else Color.WHITE
		var pos: Vector3 = info["pos"]
		pos.y = 0.32
		label.position = pos
		parent.add_child(label)

func _register_actions(reg: GameRegistry) -> void:
	# === Action: Lancer les dés ===
	var roll := GameAction.new()
	roll.id = "roll_dice"
	roll.label = "Lancer les dés"
	roll.hotkey = KEY_SPACE
	roll.category = "game"
	roll.callback = _action_roll_dice
	roll.is_available = func() -> bool:
		return _state != null \
			and _state.phase == GameState.Phase.PLAY \
			and not _state.is_busy() \
			and not _state.current_player().get_data(ROLLED_KEY, false)
	reg.register_action(roll)
	
	# === Action: Joueur suivant ===
	var next_turn := GameAction.new()
	next_turn.id = "next_player"
	next_turn.label = "Joueur suivant"
	next_turn.hotkey = KEY_ENTER
	next_turn.category = "game"
	next_turn.callback = _action_next_player
	next_turn.is_available = func() -> bool:
		return _state != null \
			and _state.phase == GameState.Phase.PLAY \
			and _state.sub_phase == "" \
			and _state.current_player().get_data(ROLLED_KEY, false)
	reg.register_action(next_turn)
	
	# === Action: Annuler build mode ===
	var cancel := GameAction.new()
	cancel.id = "cancel_build"
	cancel.label = "Annuler"
	cancel.hotkey = KEY_ESCAPE
	cancel.category = "game"
	cancel.callback = _action_cancel_build
	reg.register_action(cancel)
	
	# === Actions: sélection de bâtiment (une par bâtiment) ===
	# On les déclare ici car les bâtiments avec hotkey sont des décisions
	# de ce mod (Catan). Un autre mod pourrait remapper.
	_register_building_action(reg, "settlement", KEY_1)
	_register_building_action(reg, "road", KEY_2)
	_register_building_action(reg, "city", KEY_3)
	
	# === DEBUG: panneau hello ===
	var hello := GameAction.new()
	hello.id = "debug_hello"
	hello.label = "Test panneau hello"
	hello.hotkey = KEY_H
	hello.category = "debug"
	hello.callback = func() -> void:
		var result = await _registry.ui.show_panel("hello", {"message": "Test via GameAction"})
		print("Panneau fermé avec: ", result)
	reg.register_action(hello)
	
	# === Action: Proposer un échange ===
	var trade := GameAction.new()
	trade.id = "propose_trade"
	trade.label = "Proposer un échange"
	trade.hotkey = KEY_T
	trade.category = "trade"
	trade.callback = _action_propose_trade
	trade.is_available = func() -> bool:
		return _state != null \
			and _state.phase == GameState.Phase.PLAY \
			and _state.sub_phase == ""
	reg.register_action(trade)
	
	# === Action: Échanger 4:1 avec la banque ===
	var bank := GameAction.new()
	bank.id = "bank_trade"
	bank.label = "Échange 4:1 banque"
	bank.hotkey = KEY_B
	bank.category = "trade"
	bank.callback = _action_bank_trade
	bank.is_available = func() -> bool:
		return _state != null \
			and _state.phase == GameState.Phase.PLAY \
			and _state.sub_phase == ""
	reg.register_action(bank)
	
	# === Action: Acheter une carte développement ===
	var buy := GameAction.new()
	buy.id = "buy_dev_card"
	buy.label = "Acheter une carte"
	buy.hotkey = KEY_D
	buy.category = "cards"
	buy.cost = DEV_CARD_COST  # -> tooltip "Coût : ..."
	buy.tooltip = "Pioche une carte développement."
	buy.callback = _action_buy_dev_card
	buy.is_available = func() -> bool:
		return _state != null \
			and _state.phase == GameState.Phase.PLAY \
			and _state.sub_phase == "" \
			and _dev_deck.size() > 0
	reg.register_action(buy)

	# === Action: Voir / jouer mes cartes ===
	var show := GameAction.new()
	show.id = "show_dev_cards"
	show.label = "Mes cartes"
	show.hotkey = KEY_J
	show.category = "cards"
	show.callback = _action_show_dev_cards
	show.is_available = func() -> bool:
		return _state != null \
			and _state.phase == GameState.Phase.PLAY \
			and _state.sub_phase == ""
	reg.register_action(show)

func _register_building_action(reg: GameRegistry, building_id: String, key: int) -> void:
	var b: BuildingType = reg.get_building(building_id)
	if b == null:
		return
	var action := GameAction.new()
	action.id = "select_" + building_id
	action.label = "Sélectionner: " + b.display_name
	action.hotkey = key
	action.category = "build"
	action.building_id = building_id  # -> le HUD affiche coût/PV/effet du BuildingType en tooltip
	action.callback = func() -> void:
		_state.build_mode_id = building_id
	action.is_available = func() -> bool:
		return _state != null \
			and _state.phase != GameState.Phase.GAME_OVER \
			and _state.sub_phase == ""
	reg.register_action(action)

# === IMPLÉMENTATIONS DES ACTIONS ===

func _action_roll_dice() -> void:
	var roll_ctx := RollContext.new()
	roll_ctx.state = _state
	roll_ctx.board = _board
	roll_ctx.roller_id = _state.current_player_index
	_registry.emit(EVT_DICE_ROLL, roll_ctx)
	if roll_ctx.result == -1:
		roll_ctx.result = randi_range(1, 6) + randi_range(1, 6)
	print("Dés: %d" % roll_ctx.result)
	_registry.emit("game_log", {"text": "🎲 %s a lancé les dés : %d" % [_state.current_player().label(), roll_ctx.result]})
	_registry.emit(EVT_AFTER_DICE, roll_ctx)
	if _board.tiles_by_number.has(roll_ctx.result):
		for coords in _board.tiles_by_number[roll_ctx.result]:
			_flash_tile(coords)
	_state.current_player().set_data(ROLLED_KEY, true)

func _action_next_player() -> void:
	var p := _state.current_player()
	p.set_data(_CARDS_BOUGHT_KEY, [])
	p.set_data(ROLLED_KEY, false)  # le prochain joueur devra relancer
	_state.next_player()
	
func _action_cancel_build() -> void:
	if _state.sub_phase == SP_FREE_ROAD:
		_free_roads_remaining = 0
		_state.sub_phase = ""
		return
	_state.build_mode_id = ""

func _flash_tile(coords: Vector2) -> void:
	_registry.emit("flash_tile", {"coords": coords})

func _action_propose_trade() -> void:
	var proposer := _state.current_player()
	if _state.phase != GameState.Phase.PLAY or _state.is_busy():
		return
	# Le proposeur choisit son offre.
	var result = await Net.show_panel_for(proposer.id, "trade_proposal", {})
	if result == null or result.get("action") != "propose":
		return
	var offer: Dictionary = result["offer"]
	var demand: Dictionary = result["demand"]
	# Envoie la proposition à TOUS les autres EN MÊME TEMPS (réseau) / à la suite (solo).
	var requests: Array = []
	var indices: Array = []
	for i in _state.players.size():
		if i == proposer.id:
			continue
		indices.append(i)
		requests.append({
			"player_index": i,
			"panel_id": "trade_response",
			"raw": {"proposer_index": proposer.id, "offer": offer, "demand": demand},
		})
	var responses: Array = await Net.show_panels_parallel(requests)
	# Premier qui accepte remporte l'échange.
	for k in responses.size():
		var r = responses[k]
		if r != null and r.get("action") == "accept":
			var responder: Player = _state.players[indices[k]]
			_execute_trade(proposer, responder, offer, demand)
			_registry.emit("game_log", {"text": "%s a échangé avec %s" % [proposer.label(), responder.label()]})
			return
	_registry.emit("game_log", {"text": "Personne n'a accepté l'échange de %s" % proposer.label()})

func _execute_trade(proposer: Player, responder: Player, offer: Dictionary, demand: Dictionary) -> void:
	# Vérification finale (le répondant pourrait avoir vu ses ressources changer entre temps, mais en solo non)
	for res_id in offer:
		if offer[res_id] <= 0:
			continue
		proposer.resources[res_id] -= offer[res_id]
		responder.add_resource(res_id, offer[res_id])
	for res_id in demand:
		if demand[res_id] <= 0:
			continue
		responder.resources[res_id] -= demand[res_id]
		proposer.add_resource(res_id, demand[res_id])
	print("Échange J%d <-> J%d effectué" % [proposer.id, responder.id])
	# Événement pour les mods qui veulent réagir (taxe, etc.)
	_registry.emit(EVT_TRADE_COMPLETED, {
		"proposer": proposer,
		"responder": responder,
		"offer": offer,
		"demand": demand,
	})

func _action_bank_trade() -> void:
	var p := _state.current_player()
	var ratios: Dictionary = {}
	for res_id in _registry.resources:
		if _registry.resources[res_id].get("is_desert", false):
			continue
		ratios[res_id] = _best_bank_ratio(p, res_id)
	var result = await Net.show_panel_for(_state.current_player_index, "bank_trade", {
		"ratios": ratios,
	})
	if result == null or result.get("action") != "trade":
		return
	var give: String = result["give"]
	var receive: String = result["receive"]
	var ratio: int = _best_bank_ratio(p, give)
	# Validation finale (sécurité)
	if p.resources.get(give, 0) < ratio:
		print("Pas assez de ressources pour l'échange")
		return
	p.add_resource(give, -ratio)
	p.add_resource(receive, 1)
	print("Échange banque J%d: -%d %s, +1 %s" % [p.id, ratio, give, receive])
	# Événement pour les mods qui veulent réagir (taxe, taux modifié...)
	_registry.emit(EVT_BANK_TRADE_COMPLETED, {
		"player": p,
		"give": give,
		"receive": receive,
	})


# Échange ciblé vers un joueur précis (déclenché par le HUD au clic sur un joueur).
func _on_request_trade_with(ctx) -> void:
	var target_id: int = ctx["target_id"]
	var proposer := _state.current_player()
	if target_id == proposer.id:
		return
	if _state.phase != GameState.Phase.PLAY or _state.is_busy():
		return
	var result = await Net.show_panel_for(proposer.id, "trade_proposal", {})
	if result == null or result.get("action") != "propose":
		return
	var offer: Dictionary = result["offer"]
	var demand: Dictionary = result["demand"]
	var responder: Player = _state.players[target_id]
	var response = await Net.show_panel_for(target_id, "trade_response", {
		"proposer_index": proposer.id,
		"offer": offer,
		"demand": demand,
	})
	if response != null and response.get("action") == "accept":
		_execute_trade(proposer, responder, offer, demand)
	else:
		print("J%d a refusé l'échange" % target_id)

# Joue une carte précise de la main (déclenché par le HUD).
func _on_request_play_card(ctx) -> void:
	var card: DevelopmentCard = ctx["card"]
	var p := _state.current_player()
	if not p.cards.has(card):
		return
	var bought := _get_bought_this_turn(p)
	if not card.is_playable(_state, p, card in bought):
		print("Carte non jouable maintenant")
		return
	var consumed: bool = await card.on_play(_state, _board, _registry, p)
	if consumed:
		p.remove_card(card)
	_registry.emit("game_log", {"text": "%s a joué : %s" % [p.label(), card.display_name]})

func _init_dev_deck(_ctx) -> void:
	_dev_deck.clear()
	# Composition officielle Catan
	for i in 14: _dev_deck.append(KnightCard.new())
	for i in 5:  _dev_deck.append(VictoryPointCard.new())
	for i in 2:  _dev_deck.append(RoadBuildingCard.new())
	for i in 2:  _dev_deck.append(MonopolyCard.new())
	for i in 2:  _dev_deck.append(YearOfPlentyCard.new())
	_dev_deck.shuffle()
	print("Deck cartes développement initialisé: %d cartes" % _dev_deck.size())


# === CARTES DÉVELOPPEMENT ===

const _CARDS_BOUGHT_KEY := "catan:dev_cards_bought_this_turn"

func _get_bought_this_turn(player: Player) -> Array:
	return player.get_data(_CARDS_BOUGHT_KEY, [])

func _action_buy_dev_card() -> void:
	var p := _state.current_player()
	for res in DEV_CARD_COST:
		if p.resources.get(res, 0) < DEV_CARD_COST[res]:
			print("Pas assez de ressources pour une carte")
			return
	if _dev_deck.is_empty():
		print("Le deck est vide")
		return
	for res in DEV_CARD_COST:
		p.add_resource(res, -DEV_CARD_COST[res])
	var card: DevelopmentCard = _dev_deck.pop_back()
	p.add_card(card)
	var bought: Array = _get_bought_this_turn(p)
	bought.append(card)
	p.set_data(_CARDS_BOUGHT_KEY, bought)
	print("J%d a pioché: %s (deck restant: %d)" % [p.id, card.display_name, _dev_deck.size()])
	_registry.check_victory(_state)

func _action_show_dev_cards() -> void:
	var p := _state.current_player()
	var result = await _registry.ui.show_panel("dev_cards", {
		"registry": _registry,
		"player": p,
		"cards": p.cards,
		"bought_this_turn": _get_bought_this_turn(p),
		"state": _state,
	})
	if result == null or result.get("action") != "play":
		return
	var card: DevelopmentCard = result["card"]
	var consumed: bool = await card.on_play(_state, _board, _registry, p)
	if consumed:
		p.remove_card(card)
	_registry.emit("game_log", {"text": "%s a joué : %s" % [p.label(), card.display_name]})

# Maintient player.buildings cohérent avec le board.
# - Pour les villes: retire d'abord l'ancienne colonie qu'on upgrade
# - Pour le reste: ajoute simplement la nouvelle entrée
func _register_building_for_player(p: Player, building: BuildingType, key: String) -> void:
	if building.id == "city":
		# Retire la colonie qui était sur ce vertex
		p.remove_building_at(key)
	var placed := PlacedBuilding.new(building, key, building.target)
	p.add_building(placed)
