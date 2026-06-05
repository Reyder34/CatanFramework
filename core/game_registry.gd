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

# === API: ÉVÉNEMENTS (générique) ===
# Le core ne connaît AUCUN nom d'événement de gameplay: les ids sont définis
# par les mods (convention: "mod_id:event"). Les events de cycle de vie
# ("game_start", ...) et d'interaction plateau ("vertex_clicked", ...) sont
# émis par le core/main mais restent de simples chaînes.

# S'abonne à un événement. mod_id rempli automatiquement (traçabilité).
func on(event_id: String, callback: Callable, priority: int = 0) -> void:
	events.subscribe(event_id, callback, priority, _current_mod_id)

# Émet un événement; le contexte (mutable) est transmis aux abonnés.
func emit(event_id: String, context = null) -> void:
	events.emit(event_id, context)

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

# Labels des sous-phases (id -> string affichable)
var _sub_phase_labels: Dictionary = {}

func register_sub_phase_label(sub_phase_id: String, label: String) -> void:
	_sub_phase_labels[sub_phase_id] = label
	_track_origin("sub_phase:" + sub_phase_id)

func get_sub_phase_label(sub_phase_id: String) -> String:
	return _sub_phase_labels.get(sub_phase_id, sub_phase_id)  # fallback: l'id brut

# Calcule les PV totaux d'un joueur:
# Itère sur ses buildings, cards et effects.
# Le board n'est plus utilisé directement (les buildings du joueur sont la source de vérité).
func compute_victory_points(player: Player) -> int:
	var total := 0
	for placed in player.buildings:
		if placed.building_type != null:
			total += placed.building_type.victory_points
	for card in player.cards:
		total += card.victory_points
	for effect in player.effects:
		total += effect.victory_points
	return total

# Détection de victoire (core): si un joueur atteint le seuil, bascule en
# GAME_OVER et émet "game_over". À appeler par les mods après tout changement
# de points (pose, carte PV, effet gagné, etc.).
func check_victory(state: GameState) -> bool:
	if state.phase == GameState.Phase.GAME_OVER:
		return true
	for p in state.players:
		var points := compute_victory_points(p)
		if points >= victory_threshold:
			state.phase = GameState.Phase.GAME_OVER
			state.winner_index = p.id
			print("Joueur %d atteint %d points et gagne!" % [p.id, points])
			emit("game_over", {"state": state, "winner": p.id})
			return true
	return false
