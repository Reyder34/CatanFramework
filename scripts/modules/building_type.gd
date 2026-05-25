class_name BuildingType
extends RefCounted

# Identité
var id: String = ""
var display_name: String = ""
var target: String = "vertex"  # "vertex" ou "edge"
var hotkey: int = -1  # KEY_1, KEY_2, etc. (-1 = pas de raccourci)

# Économie
var cost: Dictionary = {}
var victory_points: int = 0

# Visuel
var mesh_radius: float = 0.2
var mesh_height: float = 0.4

# === À surcharger par chaque bâtiment ===

# Le joueur peut-il placer ce bâtiment ici?
func can_place(board: Board, player_id: int, key: String) -> bool:
	return false

# Effet du placement (modifie le Board)
func on_placed(board: Board, player_id: int, key: String) -> void:
	pass

# Combien de ressources produit ce bâtiment à chaque tour (0 = ne produit pas)
func get_production_amount() -> int:
	return 0

# Apparence visuelle: la couleur vient du joueur, mais peut être surchargée
func get_color(player_color: Color) -> Color:
	return player_color
