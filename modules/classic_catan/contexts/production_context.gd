class_name ProductionContext
extends RefCounted

var state: GameState
var board: Board
var tile_coords: Vector2
var resource_id: String = ""

# Pour before_produce: annule la production sur cette tuile
var cancelled: bool = false

# Pour compute_production_amount: modifié par les hooks
var vertex_key: String = ""
var player_id: int = -1
var building_id: String = ""
var amount: int = 0

# Pour after_produce: récap des distributions (player_id -> count)
var distributions: Dictionary = {}
