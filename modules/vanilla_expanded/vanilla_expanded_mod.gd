class_name BalancedMapMod
extends GameMod

var _state: GameState

func _init() -> void:
	mod_id = "v_expanded"
	mod_name = "Vanilla expanded"
	description = "Ajoute divers batiment et carte au jeu de base"
	version = "1.0.0"
	author = "Reyder"
	depends_on = ["classic_catan"]

func register(reg: GameRegistry) -> void:
	reg.declare_building(MechanicalRoad.new())          
	
	var act := GameAction.new()
	act.id = "select_mech_road"
	act.label = "Mechanical Road"
	act.hotkey = KEY_9
	act.category = "build"
	act.callback = func() -> void:
		_state.build_mode_id = "mech_road"
	act.is_available = func() -> bool:
		return _state != null and _state.phase != GameState.Phase.GAME_OVER
	reg.register_action(act)
	
	reg.on("game_start", func(ctx): _state = ctx["state"])  

func _produce_edges(ctx) -> void:          
	if ctx.result == 7 or ctx.cancel_production: return
	var board: Board = ctx.board
	var state: GameState = ctx.state
	for tile in board.tiles_by_number.get(ctx.result, []):
		if board.has_any_marker_at(tile): continue          # voleur bloque
		var res: String = board.tile_data[tile]["resource"]
		if res == "" or not state.registry.is_producing_resource(res): continue
		for e in _edges_of_tile(board, tile):
			if board.get_edge_type(e) == "mech_road":
				var owner := board.get_edge_owner(e)
				if owner >= 0:
					ClassicCatanMod.give_capped(state, state.players[owner], res, 1)  

func _edges_of_tile(board, tile) -> Array:
	var verts: Array = board.tile_vertices.get(tile, [])
	var out: Array = []
	for e in board.edge_endpoints:
		var ep = board.edge_endpoints[e]
		if ep[0] in verts and ep[1] in verts: out.append(e)
	return out
