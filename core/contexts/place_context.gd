class_name PlaceContext
extends RefCounted

var state: GameState
var board: Board
var player_id: int = -1
var building_id: String = ""
var target_key: String = ""

# Annulation par un hook (validation, coût insuffisant, etc.)
var cancelled: bool = false
var cancel_reason: String = ""

# Le coût appliqué (modifiable par les hooks pay_for_building)
var cost: Dictionary = {}
