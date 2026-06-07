class_name Temple
extends BuildingType

func _init() -> void:
	id = "temple"
	display_name = "Temple"
	target = "vertex"            # "vertex" (sommet) ou "edge" (arête)
	cost = {"ore": 3, "wheat": 2}
	victory_points = 3           # <-- détecté et compté automatiquement par le core
	description = "Le gros cul de pio"

# Où peut-on le poser ? (ici : sur une de SES colonies, comme une ville)
func can_place(board: Board, player_id: int, key: String) -> bool:
	return board.get_vertex_owner(key) == player_id \
		and board.get_vertex_type(key) == "settlement"

# Ce qui se passe à la pose : on inscrit le bâtiment sur le plateau.
func on_placed(board: Board, player_id: int, key: String) -> void:
	board.place_on_vertex(key, player_id, id)

# Combien de ressources il produit quand son numéro tombe.
func get_production_amount() -> int:
	return 3
