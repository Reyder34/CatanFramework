class_name Player
extends RefCounted

signal resources_changed(player_id: int)
signal custom_data_changed(player_id: int, key: String)

var id: int
var color: Color
var resources: Dictionary = {}

# Espace de stockage générique pour les mods
# Convention: clés préfixées par mod_id (ex: "catan:dev_cards", "espionnage:agents")
var custom_data: Dictionary = {}

func _init(p_id: int, p_color: Color) -> void:
	id = p_id
	color = p_color

func add_resource(res: String, amount: int = 1) -> void:
	if resources.has(res):
		resources[res] += amount
		resources_changed.emit(id)

func set_resource(res: String, value: int) -> void:
	resources[res] = value
	resources_changed.emit(id)

# === Accès au custom_data avec signal ===

func get_data(key: String, default_value = null):
	return custom_data.get(key, default_value)

func set_data(key: String, value) -> void:
	custom_data[key] = value
	custom_data_changed.emit(id, key)
