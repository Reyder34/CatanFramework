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

# Générateur de map optionnel fourni par un mod (sinon: distribution par défaut).
# Signature: func(reg: GameRegistry) -> Dictionary
#   -> { Vector2(q, r): {"resource": String, "number": int} }
var map_generator: Callable = Callable()

# Actions globales déclarées par les mods
# id -> GameAction
var actions: Dictionary = {}

# Paramètres
var board_radius: int = 2
var min_players: int = 2
var max_players: int = 10
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

# Image d'une ressource, fournie par le MOD dans declare_resource :
#   "icon"    -> petite image pour l'UI (HUD, à côté du nom)
#   "texture" -> image de la tuile hexagonale (repli sur "icon" si absent)
# La valeur peut être un chemin "res://..." OU une Texture2D déjà chargée.
# Renvoie null si rien -> le HUD/plateau retombe sur la couleur.
func get_resource_icon(id: String) -> Texture2D:
	return _as_texture(resources.get(id, {}).get("icon", null))

func get_resource_texture(id: String) -> Texture2D:
	var d: Dictionary = resources.get(id, {})
	return _as_texture(d.get("texture", d.get("icon", null)))

func _as_texture(v) -> Texture2D:
	if v is Texture2D:
		return v
	if v is String and v != "" and ResourceLoader.exists(v):
		return load(v)
	return null

# Modèle 3D de la tuile (optionnel), fourni par le mod dans declare_resource via
# "model" (PackedScene ou chemin res://). Remplace l'hexagone procédural au rendu.
func get_resource_model(id: String) -> PackedScene:
	return _as_scene(resources.get(id, {}).get("model", null))

func _as_scene(v) -> PackedScene:
	if v is PackedScene:
		return v
	if v is String and v != "" and ResourceLoader.exists(v):
		var res = load(v)
		if res is PackedScene:
			return res
	return null

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

# Un mod fournit sa propre génération de map (disposition tuiles/numéros, forme).
# cb: func(reg: GameRegistry) -> Dictionary { Vector2(q,r): {"resource","number"} }.
# Le cœur appelle ce Callable au lieu de la distribution par défaut.
func set_map_generator(cb: Callable) -> void:
	if map_generator.is_valid():
		push_warning("map_generator déjà défini; un autre mod le remplace.")
	map_generator = cb

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

# Points "publics" (ce que les AUTRES joueurs voient) : on retire les cartes à PV,
# cachées en main jusqu'à la victoire. L'hôte garde le total complet pour détecter le gain.
func compute_public_victory_points(player: Player) -> int:
	var total := compute_victory_points(player)
	for card in player.cards:
		total -= card.victory_points
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

# Ventilation des PV d'un joueur, regroupée par source (générique).
# Le core ne connaît pas les types concrets: il lit display_name + victory_points
# des bâtiments/cartes/effets définis par les mods. Tout nouveau bâtiment/carte/
# effet à PV est donc détecté et nommé automatiquement.
# Retourne un Array de {"name": String, "count": int, "points": int} (sources à PV > 0).
func compute_victory_breakdown(player: Player, hide_cards := false) -> Array:
	var entries: Array = []
	# Bâtiments regroupés par type
	var by_building: Dictionary = {}
	for placed in player.buildings:
		var bt: BuildingType = placed.building_type
		if bt == null or bt.victory_points == 0:
			continue
		if not by_building.has(bt.id):
			by_building[bt.id] = {"name": bt.display_name, "count": 0, "points": 0}
		by_building[bt.id]["count"] += 1
		by_building[bt.id]["points"] += bt.victory_points
	for id in by_building:
		entries.append(by_building[id])
	# Cartes à PV regroupées par type (cachées aux AUTRES joueurs en réseau)
	if not hide_cards:
		var by_card: Dictionary = {}
		for card in player.cards:
			if card.victory_points == 0:
				continue
			if not by_card.has(card.id):
				by_card[card.id] = {"name": card.display_name, "count": 0, "points": 0}
			by_card[card.id]["count"] += 1
			by_card[card.id]["points"] += card.victory_points
		for id in by_card:
			entries.append(by_card[id])
	# Effets (un par effet: route la plus longue, plus grande armée, trophées…)
	for effect in player.effects:
		if effect.victory_points == 0:
			continue
		entries.append({"name": effect.display_name, "count": 1, "points": effect.victory_points})
	return entries
