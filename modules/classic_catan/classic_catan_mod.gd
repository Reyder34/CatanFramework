class_name ClassicCatanMod
extends GameMod

var _state: GameState
var _board: Board
var _registry: GameRegistry

const DEV_CARD_COST := {"wheat": 1, "sheep": 1, "ore": 1}

# Cartes développement
var _dev_deck: Array = []  # Array[DevelopmentCard]

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
	reg.on_game_start(_init_dev_deck, 0)
	reg.register_panel("hello", preload("res://modules/classic_catan/panels/hello_panel.tscn"))
	reg.register_panel("trade_proposal", preload("res://modules/classic_catan/panels/trade_proposal_panel.tscn"))
	reg.register_panel("trade_response", preload("res://modules/classic_catan/panels/trade_response_panel.tscn"))
	reg.register_panel("bank_trade", preload("res://modules/classic_catan/panels/bank_trade_panel.tscn"))

# === DONNÉES ===

func _declare_resources(reg: GameRegistry) -> void:
	reg.declare_resource("wood",   {"name": "Bois",    "color": Color(0.2, 0.5, 0.1)})
	reg.declare_resource("brick",  {"name": "Brique",  "color": Color(0.7, 0.3, 0.1)})
	reg.declare_resource("sheep",  {"name": "Mouton",  "color": Color(0.6, 0.9, 0.4)})
	reg.declare_resource("wheat",  {"name": "Blé",     "color": Color(0.9, 0.8, 0.2)})
	reg.declare_resource("ore",    {"name": "Minerai", "color": Color(0.5, 0.5, 0.6)})
	reg.declare_resource("desert", {"name": "Désert",  "color": Color(0.9, 0.8, 0.5), "is_desert": true})

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
	reg.on_dice_roll(_on_dice_roll, 0)
	reg.on_after_dice_rolled(_on_after_dice_rolled, 0)
	reg.on_vertex_clicked(_on_vertex_clicked, 0)
	reg.on_edge_clicked(_on_edge_clicked, 0)
	reg.on_compute_victory_points(_on_compute_victory_points, 0)
	reg.on_game_start(_on_game_start_for_actions, 0)

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
	state.registry.events.emit("before_produce", pctx)
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
	if ctx.state.phase == GameState.Phase.INITIAL_PLACEMENT:
		_handle_initial_settlement(ctx)
	elif ctx.state.phase == GameState.Phase.PLAY:
		_handle_normal_vertex_click(ctx)

func _on_edge_clicked(ctx: ClickContext) -> void:
	if ctx.handled:
		return
	if ctx.state.phase == GameState.Phase.INITIAL_PLACEMENT:
		_handle_initial_road(ctx)
	elif ctx.state.phase == GameState.Phase.PLAY:
		_handle_normal_edge_click(ctx)

# === PHASE INITIALE ===

func _handle_initial_settlement(ctx: ClickContext) -> void:
	var state := ctx.state
	var board := ctx.board
	var key := ctx.target_key
	if state.build_mode_id != "settlement":
		print("Pose d'abord une colonie (touche 1)")
		return
	if state.last_initial_settlement_key != "":
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
	state.last_initial_settlement_key = key
	# Sur la 2e colonie: ressources adjacentes
	var placement_index: int = state.initial_placements[state.current_player_index]
	if placement_index == 1:
		_distribute_initial_resources(state, board, key)

func _handle_initial_road(ctx: ClickContext) -> void:
	var state := ctx.state
	var board := ctx.board
	var key := ctx.target_key
	if state.build_mode_id != "road":
		print("Pose maintenant ta route (touche 2)")
		return
	if state.last_initial_settlement_key == "":
		print("Pose d'abord ta colonie")
		return
	var endpoints: Array = board.edge_endpoints.get(key, [])
	if not endpoints.has(state.last_initial_settlement_key):
		print("La route doit être adjacente à ta colonie")
		return
	if board.is_edge_occupied(key):
		print("Cette arête est déjà occupée")
		return
	var road: Road = state.registry.get_building("road")
	road.on_placed(board, state.current_player().id, key)
	state.advance_initial_placement()
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
	state.registry.events.emit("before_place", pctx)
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
	# after_place (mods peuvent réagir: bonus, etc.)
	state.registry.events.emit("after_place", pctx)
	# Vérifier victoire
	_check_victory(state, board)

# === VICTOIRE ===

func _on_compute_victory_points(ctx: VictoryContext) -> void:
	var pts := 0
	for v_key in ctx.board.vertex_state:
		var info: Dictionary = ctx.board.vertex_state[v_key]
		if info.get("owner", -1) != ctx.player_id:
			continue
		var b: BuildingType = ctx.state.registry.get_building(info.get("type", ""))
		if b != null:
			pts += b.victory_points
	for e_key in ctx.board.edge_state:
		var info: Dictionary = ctx.board.edge_state[e_key]
		if info.get("owner", -1) != ctx.player_id:
			continue
		var b: BuildingType = ctx.state.registry.get_building(info.get("type", "road"))
		if b != null:
			pts += b.victory_points
	# Cartes Point de victoire
	var p: Player = ctx.state.players[ctx.player_id]
	var cards: Array = p.get_data(_CARDS_KEY, [])
	for c in cards:
		pts += c.victory_points
	ctx.points += pts

func _check_victory(state: GameState, board: Board) -> void:
	var p := state.current_player()
	var vctx := VictoryContext.new()
	vctx.state = state
	vctx.board = board
	vctx.player_id = p.id
	vctx.threshold = state.registry.victory_threshold
	state.registry.events.emit("compute_victory_points", vctx)
	if vctx.points >= vctx.threshold:
		state.phase = GameState.Phase.GAME_OVER
		state.winner_index = p.id
		print("Joueur %d a gagné avec %d points!" % [p.id, vctx.points])

func _on_game_start_for_actions(ctx) -> void:
	_state = ctx["state"]
	_board = ctx["board"]
	_registry = ctx["registry"]

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
			and _state.sub_phase == GameState.SubPhase.NONE
	reg.register_action(roll)
	
	# === Action: Joueur suivant ===
	var next_turn := GameAction.new()
	next_turn.id = "next_player"
	next_turn.label = "Joueur suivant"
	next_turn.hotkey = KEY_ENTER
	next_turn.category = "game"
	next_turn.callback = _action_next_player
	next_turn.is_available = func() -> bool:
		return _state != null and _state.sub_phase == GameState.SubPhase.NONE
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
			and _state.sub_phase == GameState.SubPhase.NONE
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
			and _state.sub_phase == GameState.SubPhase.NONE
	reg.register_action(bank)
	
	# === Action: Acheter une carte développement ===
	var buy := GameAction.new()
	buy.id = "buy_dev_card"
	buy.label = "Acheter carte (-1 blé/mouton/minerai)"
	buy.hotkey = KEY_D
	buy.category = "build"
	buy.callback = _action_buy_dev_card
	buy.is_available = func() -> bool:
		return _state != null \
			and _state.phase == GameState.Phase.PLAY \
			and _state.sub_phase == GameState.SubPhase.NONE \
			and _dev_deck.size() > 0
	reg.register_action(buy)

	# === Action: Voir / jouer mes cartes ===
	var show := GameAction.new()
	show.id = "show_dev_cards"
	show.label = "Mes cartes"
	show.hotkey = KEY_J
	show.category = "build"
	show.callback = _action_show_dev_cards
	show.is_available = func() -> bool:
		return _state != null \
			and _state.phase == GameState.Phase.PLAY \
			and _state.sub_phase == GameState.SubPhase.NONE
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
	action.callback = func() -> void:
		_state.build_mode_id = building_id
	action.is_available = func() -> bool:
		return _state != null \
			and _state.phase != GameState.Phase.GAME_OVER \
			and _state.sub_phase == GameState.SubPhase.NONE
	reg.register_action(action)

# === IMPLÉMENTATIONS DES ACTIONS ===

func _action_roll_dice() -> void:
	var roll_ctx := RollContext.new()
	roll_ctx.state = _state
	roll_ctx.board = _board
	roll_ctx.roller_id = _state.current_player_index
	_registry.events.emit("dice_roll", roll_ctx)
	if roll_ctx.result == -1:
		roll_ctx.result = randi_range(1, 6) + randi_range(1, 6)
	print("Dés: %d" % roll_ctx.result)
	_registry.events.emit("after_dice_rolled", roll_ctx)
	if _board.tiles_by_number.has(roll_ctx.result):
		for coords in _board.tiles_by_number[roll_ctx.result]:
			_flash_tile(coords)

func _action_next_player() -> void:
	var p := _state.current_player()
	p.set_data(_CARDS_BOUGHT_KEY, [])
	_state.next_player()

func _action_cancel_build() -> void:
	_state.build_mode_id = ""

func _flash_tile(coords: Vector2) -> void:
	_registry.events.emit("flash_tile", {"coords": coords})

func _action_propose_trade() -> void:
	var proposer := _state.current_player()
	# Ouvrir le panneau de proposition
	var result = await _registry.ui.show_panel("trade_proposal", {
		"registry": _registry,
		"proposer": proposer,
	})
	if result == null or result.get("action") != "propose":
		return
	var offer: Dictionary = result["offer"]
	var demand: Dictionary = result["demand"]
	# Demander à chaque autre joueur séquentiellement
	for i in _state.players.size():
		if i == _state.current_player_index:
			continue
		var responder: Player = _state.players[i]
		var response = await _registry.ui.show_panel("trade_response", {
			"registry": _registry,
			"proposer": proposer,
			"responder": responder,
			"offer": offer,
			"demand": demand,
		})
		if response != null and response.get("action") == "accept":
			_execute_trade(proposer, responder, offer, demand)
			return
	print("Personne n'a accepté l'échange")

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
	_registry.events.emit("trade_completed", {
		"proposer": proposer,
		"responder": responder,
		"offer": offer,
		"demand": demand,
	})

func _action_bank_trade() -> void:
	var p := _state.current_player()
	var result = await _registry.ui.show_panel("bank_trade", {
		"registry": _registry,
		"player": p,
	})
	if result == null or result.get("action") != "trade":
		return
	var give: String = result["give"]
	var receive: String = result["receive"]
	# Validation finale (sécurité)
	if p.resources.get(give, 0) < 4:
		print("Pas assez de ressources pour l'échange")
		return
	p.add_resource(give, -4)
	p.add_resource(receive, 1)
	print("Échange banque J%d: -4 %s, +1 %s" % [p.id, give, receive])
	# Événement pour les mods qui veulent réagir (taxe, taux modifié...)
	_registry.events.emit("bank_trade_completed", {
		"player": p,
		"give": give,
		"receive": receive,
	})


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

const _CARDS_KEY := "catan:dev_cards"
const _CARDS_BOUGHT_KEY := "catan:dev_cards_bought_this_turn"

func _get_cards(player: Player) -> Array:
	return player.get_data(_CARDS_KEY, [])

func _get_bought_this_turn(player: Player) -> Array:
	return player.get_data(_CARDS_BOUGHT_KEY, [])

func _action_buy_dev_card() -> void:
	var p := _state.current_player()
	# Vérifier coût
	for res in DEV_CARD_COST:
		if p.resources.get(res, 0) < DEV_CARD_COST[res]:
			print("Pas assez de ressources pour une carte")
			return
	if _dev_deck.is_empty():
		print("Le deck est vide")
		return
	# Payer
	for res in DEV_CARD_COST:
		p.add_resource(res, -DEV_CARD_COST[res])
	# Piocher
	var card: DevelopmentCard = _dev_deck.pop_back()
	var hand: Array = _get_cards(p)
	hand.append(card)
	p.set_data(_CARDS_KEY, hand)
	var bought: Array = _get_bought_this_turn(p)
	bought.append(card)
	p.set_data(_CARDS_BOUGHT_KEY, bought)
	print("J%d a pioché: %s (deck restant: %d)" % [p.id, card.display_name, _dev_deck.size()])

func _action_show_dev_cards() -> void:
	var p := _state.current_player()
	var result = await _registry.ui.show_panel("dev_cards", {
		"registry": _registry,
		"player": p,
		"cards": _get_cards(p),
		"bought_this_turn": _get_bought_this_turn(p),
		"state": _state,
	})
	if result == null or result.get("action") != "play":
		return
	var card: DevelopmentCard = result["card"]
	var consumed: bool = await card.on_play(_state, _board, _registry, p)
	if consumed:
		var hand: Array = _get_cards(p)
		hand.erase(card)
		p.set_data(_CARDS_KEY, hand)
