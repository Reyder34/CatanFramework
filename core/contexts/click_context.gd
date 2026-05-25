class_name ClickContext
extends RefCounted

var state: GameState
var board: Board
var player_id: int = -1
var target_key: String = ""    # vertex_key ou edge_key
var target_coords: Vector2     # pour tile_clicked

# Si un hook a géré le clic, il met handled = true pour éviter
# que les hooks de priorité plus basse le retraitent
var handled: bool = false
