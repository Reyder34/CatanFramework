class_name GameMod
extends RefCounted

# Identité (obligatoires)
var mod_id: String = ""
var mod_name: String = ""
var description: String = ""
var version: String = "1.0.0"
var author: String = ""

# Dépendances
var depends_on: Array[String] = []
var conflicts_with: Array[String] = []

# Surchargée par chaque mod: déclare ses ressources, bâtiments, hooks, etc.
func register(registry: GameRegistry) -> void:
	pass
