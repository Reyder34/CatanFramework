class_name ModLoader
extends RefCounted

# Charge une liste de mods: vérifie les dépendances et conflits, ordonne par
# depends_on (tri topologique), puis appelle register() dans le bon ordre.
# Retourne la liste ordonnée des mods chargés (vide si erreur).
static func load_mods(registry: GameRegistry, mods: Array) -> Array:
	var by_id: Dictionary = {}
	for mod in mods:
		if by_id.has(mod.mod_id):
			push_error("Mod en double: '%s'" % mod.mod_id)
			return []
		by_id[mod.mod_id] = mod

	# Slots à fournisseur UNIQUE (ex: "map_generator"): on garde le PREMIER mod
	# qui fournit chaque slot et on écarte les suivants. Garde-fou — le lobby
	# empêche déjà d'en activer deux (exclusion mutuelle).
	var slot_owner: Dictionary = {}
	var kept: Array = []
	for mod in mods:
		var drop := false
		for slot in mod.provides:
			if slot_owner.has(slot):
				push_warning("Slot '%s' déjà fourni par '%s'; mod '%s' écarté." % [slot, slot_owner[slot], mod.mod_id])
				drop = true
			else:
				slot_owner[slot] = mod.mod_id
		if drop:
			by_id.erase(mod.mod_id)
		else:
			kept.append(mod)
	mods = kept

	# Dépendances présentes ?
	for mod in mods:
		for dep in mod.depends_on:
			if not by_id.has(dep):
				push_error("Mod '%s' dépend de '%s' (absent)" % [mod.mod_id, dep])
				return []

	# Conflits ?
	for mod in mods:
		for c in mod.conflicts_with:
			if by_id.has(c):
				push_error("Conflit: '%s' incompatible avec '%s'" % [mod.mod_id, c])
				return []

	# Tri topologique: les dépendances sont enregistrées avant leurs dépendants.
	var ordered: Array = []
	var visited: Dictionary = {}
	var visiting: Dictionary = {}
	for mod in mods:
		if not _visit(mod, by_id, visited, visiting, ordered):
			return []

	# Enregistrement dans l'ordre, avec traçabilité du mod courant.
	for mod in ordered:
		registry._set_current_mod(mod.mod_id)
		mod.register(registry)
	registry._set_current_mod("core")
	return ordered

static func _visit(mod, by_id: Dictionary, visited: Dictionary, visiting: Dictionary, ordered: Array) -> bool:
	if visited.has(mod.mod_id):
		return true
	if visiting.has(mod.mod_id):
		push_error("Cycle de dépendances détecté autour de '%s'" % mod.mod_id)
		return false
	visiting[mod.mod_id] = true
	for dep in mod.depends_on:
		if not _visit(by_id[dep], by_id, visited, visiting, ordered):
			return false
	visiting.erase(mod.mod_id)
	visited[mod.mod_id] = true
	ordered.append(mod)
	return true
