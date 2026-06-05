class_name Player
extends RefCounted

signal resources_changed(player_id: int)
signal custom_data_changed(player_id: int, key: String)
signal buildings_changed(player_id: int)
signal cards_changed(player_id: int)
signal effects_changed(player_id: int)

var id: int
var color: Color
var display_name: String = ""  # pseudo (réseau); vide -> fallback "J<id>"

# === DONNÉES TYPÉES (universelles) ===
var resources: Dictionary = {}
var buildings: Array = []   # Array[PlacedBuilding]
var cards: Array = []       # Array[DevelopmentCard]
var effects: Array = []     # Array[PlayerEffect]

# === DONNÉES LIBRES (spécifiques mod) ===
var custom_data: Dictionary = {}

func _init(p_id: int, p_color: Color) -> void:
	id = p_id
	color = p_color

# Libellé affichable: le pseudo s'il existe (réseau), sinon "J<id>".
func label() -> String:
	return display_name if display_name != "" else "J%d" % id

# === Ressources ===

func add_resource(res: String, amount: int = 1) -> void:
	if resources.has(res):
		resources[res] += amount
		resources_changed.emit(id)

func set_resource(res: String, value: int) -> void:
	resources[res] = value
	resources_changed.emit(id)

# === Custom data ===

func get_data(key: String, default_value = null):
	return custom_data.get(key, default_value)

func set_data(key: String, value) -> void:
	custom_data[key] = value
	custom_data_changed.emit(id, key)

# === Bâtiments ===

func add_building(placed: PlacedBuilding) -> void:
	buildings.append(placed)
	buildings_changed.emit(id)

func remove_building_at(key: String) -> PlacedBuilding:
	for i in range(buildings.size() - 1, -1, -1):
		if buildings[i].key == key:
			var removed: PlacedBuilding = buildings[i]
			buildings.remove_at(i)
			buildings_changed.emit(id)
			return removed
	return null

func get_building_at(key: String) -> PlacedBuilding:
	for b in buildings:
		if b.key == key:
			return b
	return null

# === Cartes ===

func add_card(card: DevelopmentCard) -> void:
	cards.append(card)
	cards_changed.emit(id)

func remove_card(card: DevelopmentCard) -> bool:
	if cards.has(card):
		cards.erase(card)
		cards_changed.emit(id)
		return true
	return false

# === Effets ===

func add_effect(effect: PlayerEffect) -> void:
	effects.append(effect)
	effects_changed.emit(id)

func remove_effect_by_id(effect_id: String) -> void:
	for i in range(effects.size() - 1, -1, -1):
		if effects[i].id == effect_id:
			effects.remove_at(i)
	effects_changed.emit(id)

func get_effect(effect_id: String) -> PlayerEffect:
	for e in effects:
		if e.id == effect_id:
			return e
	return null

func has_effect(effect_id: String) -> bool:
	return get_effect(effect_id) != null
