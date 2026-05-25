class_name BuildingType
extends RefCounted

# Identité
var id: String = ""
var display_name: String = ""
var target: String = "vertex"  # "vertex" ou "edge"
var hotkey: int = -1

# Économie
var cost: Dictionary = {}
var victory_points: int = 0

# Visuel
var mesh_radius: float = 0.2
var mesh_height: float = 0.4

# === À surcharger par chaque bâtiment ===

func can_place(board: Board, player_id: int, key: String) -> bool:
	return false

func on_placed(board: Board, player_id: int, key: String) -> void:
	pass

func get_production_amount() -> int:
	return 0

func get_color(player_color: Color) -> Color:
	return player_color
