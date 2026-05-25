class_name TurnContext
extends RefCounted

var state: GameState
var board: Board
var player_id: int = -1
var cancelled: bool = false  # pour before_turn
