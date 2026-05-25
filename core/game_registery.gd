class_name GameRegistry
extends RefCounted

# === BUS D'ÉVÉNEMENTS ===
var events: EventBus

# == UI reg ===

var ui: UIRegistry

# === DONNÉES DÉCLARÉES ===
# Toutes les ressources connues du jeu
# id -> {"name": String, "color": Color, "is_desert": bool, ...}
var resources: Dictionary = {}

# Tous les bâtiments connus
# id -> BuildingType
var buildings: Dictionary = {}

# Pools de génération
var tile_pool: Array = []
var number_pool: Array = []

# Actions globales déclarées par les mods
# id -> GameAction
var actions: Dictionary = {}

# Paramètres
var board_radius: int = 2
var min_players: int = 2
var max_players: int = 4
var victory_threshold: int = 10

# Trace de qui a déclaré quoi (pour debug + détection conflits)
# resource_id/building_id -> [mod_ids qui l'ont touché]
var _origin: Dictionary = {}
# Mod actuellement en train de register (pour traçabilité automatique)
var _current_mod_id: String = "unknown"

func _init() -> void:
	events = EventBus.new()

func setup_ui(ui_root: Node) -> void:
	ui = UIRegistry.new(ui_root)

# === INTERNE: appelé par le ModLoader ===
func _set_current_mod(mod_id: String) -> void:
	_current_mod_id = mod_id

func _track_origin(key: String) -> void:
	if not _origin.has(key):
		_origin[key] = []
	_origin[key].append(_current_mod_id)

# === API: DÉCLARATION DE RESSOURCES ===

func declare_resource(id: String, definition: Dictionary) -> void:
	resources[id] = definition
	_track_origin("resource:" + id)

func remove_resource(id: String) -> void:
	resources.erase(id)
	_track_origin("resource:" + id + ":removed")

func get_resource_color(id: String) -> Color:
	if not resources.has(id):
		return Color.MAGENTA
	return resources[id].get("color", Color.MAGENTA)

func is_producing_resource(id: String) -> bool:
	if not resources.has(id):
		return false
	return not resources[id].get("is_desert", false)

# === API: BÂTIMENTS ===

func declare_building(building: BuildingType) -> void:
	buildings[building.id] = building
	_track_origin("building:" + building.id)

func remove_building(id: String) -> void:
	buildings.erase(id)
	_track_origin("building:" + id + ":removed")

func get_building(id: String) -> BuildingType:
	return buildings.get(id)

func override_building_cost(id: String, new_cost: Dictionary) -> void:
	if not buildings.has(id):
		return
	buildings[id].cost = new_cost
	_track_origin("building:" + id + ":cost")

# === API: POOLS DE GÉNÉRATION ===

func add_to_tile_pool(resource_id: String, count: int = 1) -> void:
	for i in count:
		tile_pool.append(resource_id)

func clear_tile_pool() -> void:
	tile_pool.clear()

func add_to_number_pool(number: int, count: int = 1) -> void:
	for i in count:
		number_pool.append(number)

func clear_number_pool() -> void:
	number_pool.clear()

# === API: PARAMÈTRES ===

func set_board_radius(r: int) -> void:
	board_radius = r

func set_victory_threshold(n: int) -> void:
	victory_threshold = n

func set_player_count_range(min_p: int, max_p: int) -> void:
	min_players = min_p
	max_players = max_p

# === API: UI ===

func register_panel(panel_id: String, scene: PackedScene) -> void:
	if ui == null:
		push_error("UIRegistry pas initialisé. Appeler setup_ui() avant.")
		return
	ui.register_panel(panel_id, scene, _current_mod_id)
	_track_origin("panel:" + panel_id)

# === API: HOOKS (wrappers vers EventBus) ===
# Convention: l'argument priority est optionnel, défaut 0

func on_game_setup(callback: Callable, priority: int = 0) -> void:
	events.subscribe("game_setup", callback, priority, _current_mod_id)

func on_game_start(callback: Callable, priority: int = 0) -> void:
	events.subscribe("game_start", callback, priority, _current_mod_id)

func on_game_over(callback: Callable, priority: int = 0) -> void:
	events.subscribe("game_over", callback, priority, _current_mod_id)

func on_before_turn(callback: Callable, priority: int = 0) -> void:
	events.subscribe("before_turn", callback, priority, _current_mod_id)

func on_turn_start(callback: Callable, priority: int = 0) -> void:
	events.subscribe("turn_start", callback, priority, _current_mod_id)

func on_turn_end(callback: Callable, priority: int = 0) -> void:
	events.subscribe("turn_end", callback, priority, _current_mod_id)

func on_before_dice_roll(callback: Callable, priority: int = 0) -> void:
	events.subscribe("before_dice_roll", callback, priority, _current_mod_id)

func on_dice_roll(callback: Callable, priority: int = 0) -> void:
	events.subscribe("dice_roll", callback, priority, _current_mod_id)

func on_after_dice_rolled(callback: Callable, priority: int = 0) -> void:
	events.subscribe("after_dice_rolled", callback, priority, _current_mod_id)

func on_before_produce(callback: Callable, priority: int = 0) -> void:
	events.subscribe("before_produce", callback, priority, _current_mod_id)

func on_compute_production_amount(callback: Callable, priority: int = 0) -> void:
	events.subscribe("compute_production_amount", callback, priority, _current_mod_id)

func on_after_produce(callback: Callable, priority: int = 0) -> void:
	events.subscribe("after_produce", callback, priority, _current_mod_id)

func on_before_place(callback: Callable, priority: int = 0) -> void:
	events.subscribe("before_place", callback, priority, _current_mod_id)

func on_pay_for_building(callback: Callable, priority: int = 0) -> void:
	events.subscribe("pay_for_building", callback, priority, _current_mod_id)

func on_after_place(callback: Callable, priority: int = 0) -> void:
	events.subscribe("after_place", callback, priority, _current_mod_id)

func on_vertex_clicked(callback: Callable, priority: int = 0) -> void:
	events.subscribe("vertex_clicked", callback, priority, _current_mod_id)

func on_edge_clicked(callback: Callable, priority: int = 0) -> void:
	events.subscribe("edge_clicked", callback, priority, _current_mod_id)

func on_tile_clicked(callback: Callable, priority: int = 0) -> void:
	events.subscribe("tile_clicked", callback, priority, _current_mod_id)

func on_compute_victory_points(callback: Callable, priority: int = 0) -> void:
	events.subscribe("compute_victory_points", callback, priority, _current_mod_id)

func on_victory_check(callback: Callable, priority: int = 0) -> void:
	events.subscribe("victory_check", callback, priority, _current_mod_id)

func on_before_resource_change(callback: Callable, priority: int = 0) -> void:
	events.subscribe("before_resource_change", callback, priority, _current_mod_id)

func on_after_resource_change(callback: Callable, priority: int = 0) -> void:
	events.subscribe("after_resource_change", callback, priority, _current_mod_id)

# === API: ACTIONS ===

func register_action(action: GameAction) -> void:
	actions[action.id] = action
	_track_origin("action:" + action.id)

func find_action_by_hotkey(keycode: int) -> GameAction:
	for action in actions.values():
		if action.hotkey == keycode:
			return action
	return null

func get_actions_by_category(category: String) -> Array:
	var result: Array = []
	for action in actions.values():
		if action.category == category:
			result.append(action)
	return result
