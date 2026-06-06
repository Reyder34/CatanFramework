class_name GameAction
extends RefCounted

var id: String = ""
var label: String = ""           # affiché dans l'UI (HUD)
var hotkey: int = -1             # touche Godot (KEY_*)
var callback: Callable           # appelée quand la touche est pressée
var is_available: Callable       # optionnel: func() -> bool, retourne false = action grisée/ignorée
var category: String = "default" # pour grouper dans le HUD ("game", "build", "cards", "trade", "debug")

# Affichage riche dans le HUD (tooltips) — tout vient du mod :
var building_id: String = ""     # si l'action sélectionne un bâtiment -> tooltip = coût/PV/effet du BuildingType
var tooltip: String = ""         # texte d'aide libre (sinon)
var cost: Dictionary = {}        # coût éventuel (ex: acheter une carte) -> affiché en tooltip

# Helper: l'action est-elle déclenchable maintenant?
func can_trigger() -> bool:
	if not is_available.is_valid():
		return true
	return is_available.call()
