class_name GameModule
extends RefCounted

# === IDENTITÉ ===
var module_id: String = "base"
var display_name: String = "Module de base"

# === RESSOURCES ===
var resources: Dictionary = {}

# === GÉNÉRATION DU PLATEAU ===
var tile_pool: Array = []
var number_pool: Array = []
var board_radius: int = 2

# === BÂTIMENTS ===
# id -> BuildingType
var buildings: Dictionary = {}

# === MÉTHODES UTILITAIRES ===

func get_resource_color(res_id: String) -> Color:
	if not resources.has(res_id):
		return Color.MAGENTA
	return resources[res_id]["color"]

func is_producing_resource(res_id: String) -> bool:
	if not resources.has(res_id):
		return false
	return not resources[res_id].get("is_desert", false)

func init_player_resources(player: Player) -> void:
	player.resources = {}
	for res_id in resources:
		player.resources[res_id] = 0

# === BÂTIMENTS: API ===

func register_building(building: BuildingType) -> void:
	buildings[building.id] = building

func get_building(id: String) -> BuildingType:
	return buildings.get(id)

func can_afford(player: Player, building_id: String) -> bool:
	var b := get_building(building_id)
	if b == null:
		return false
	for res in b.cost:
		if player.resources.get(res, 0) < b.cost[res]:
			return false
	return true

func pay(player: Player, building_id: String) -> void:
	var b := get_building(building_id)
	if b == null:
		return
	for res in b.cost:
		player.resources[res] -= b.cost[res]

# Retourne la liste des build modes proposés (pour l'UI et les raccourcis)
func get_build_modes() -> Array:
	return buildings.values()

# === HOOKS DE PHASE (à surcharger par les modules concrets) ===

# Lance les dés (un mod peut surcharger pour faire un dé pipé, 1d20, etc.)
func roll_dice() -> int:
	return randi_range(1, 6) + randi_range(1, 6)

# Que se passe-t-il quand les dés ont été lancés? (production, voleur, etc.)
func on_dice_rolled(total: int, state: GameState, board: Board) -> void:
	pass

# Quand un joueur clique sur un sommet
func on_vertex_clicked(key: String, state: GameState, board: Board) -> void:
	pass

# Quand un joueur clique sur une arête
func on_edge_clicked(key: String, state: GameState, board: Board) -> void:
	pass

func on_tile_clicked(coords: Vector2, state: GameState, board: Board) -> void:
	pass


# Calcule les points de victoire d'un joueur
# Compte tous les bâtiments du joueur sur le plateau
func calculate_victory_points(player_id: int, board: Board) -> int:
	var points := 0
	# Sommets (colonies, villes, futures tours...)
	for v_key in board.vertex_state:
		var info: Dictionary = board.vertex_state[v_key]
		if info.get("owner", -1) != player_id:
			continue
		var building_id: String = info.get("type", "")
		var b: BuildingType = buildings.get(building_id)
		if b != null:
			points += b.victory_points
	# Arêtes (peu probable d'avoir des points, mais on couvre le cas)
	for e_key in board.edge_state:
		var info: Dictionary = board.edge_state[e_key]
		if info.get("owner", -1) != player_id:
			continue
		var building_id: String = info.get("type", "road")
		var b: BuildingType = buildings.get(building_id)
		if b != null:
			points += b.victory_points
	return points

# Score total à atteindre pour gagner (modules peuvent surcharger)
func points_to_win() -> int:
	return 10
