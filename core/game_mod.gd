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

# Slots à fournisseur UNIQUE que ce mod remplit (ex: ["map_generator"]).
# Deux mods activés qui fournissent le même slot s'excluent mutuellement
# (boutons radio dans le lobby; garde-fou côté ModLoader).
var provides: Array[String] = []

# Surchargée par chaque mod: déclare ses ressources, bâtiments, hooks, etc.
func register(registry: GameRegistry) -> void:
	pass
