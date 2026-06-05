class_name ModCatalog
extends RefCounted

# Liste des mods disponibles dans le jeu. Renvoie des instances FRAÎCHES à chaque
# appel (le menu les lit pour l'affichage, le jeu en crée pour le chargement).
# C'est la couche application: c'est ici qu'on connaît les mods concrets, pas le core.
static func create_all() -> Array:
	return [
		ClassicCatanMod.new(),
		VanillaRobberMod.new(),
	]
