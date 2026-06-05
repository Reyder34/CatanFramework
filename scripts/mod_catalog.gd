class_name ModCatalog
extends RefCounted

# Détecte AUTOMATIQUEMENT tous les mods disponibles (plus besoin de liste en dur).
# - Mods du projet: via le registre de classes global (tout ce qui `extends GameMod`).
# - Mods externes: packs .pck/.zip déposés dans un dossier `mods/` (chargés au runtime),
#   + dossiers source déposés dans `res://mods/`.
# Renvoie des instances FRAÎCHES à chaque appel.

const GAME_MOD_PATH := "res://core/game_mod.gd"

static func create_all() -> Array:
	_load_external_packs()
	var mods: Array = []
	var seen: Dictionary = {}  # chemin de script -> déjà ajouté
	# 1) Mods compilés dans le projet
	for entry in ProjectSettings.get_global_class_list():
		if entry.get("base", "") == "GameMod":
			_try_add(entry.get("path", ""), mods, seen)
	# 2) Mods déposés dans res://mods/ (dossiers source ou packs montés)
	_scan_dir("res://mods", mods, seen)
	return mods

# Charge les packs .pck/.zip d'un dossier `mods/` à côté de l'exécutable (export).
# En éditeur/dev, on utilise les mods source (modules/ ou res://mods/).
static func _load_external_packs() -> void:
	if OS.has_feature("editor"):
		return
	var dir_path := OS.get_executable_path().get_base_dir().path_join("mods")
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and (f.ends_with(".pck") or f.ends_with(".zip")):
			ProjectSettings.load_resource_pack(dir_path.path_join(f))
		f = d.get_next()
	d.list_dir_end()

static func _scan_dir(path: String, mods: Array, seen: Dictionary) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var full := path.path_join(f)
		if d.current_is_dir():
			_scan_dir(full, mods, seen)
		elif f.ends_with(".gd"):
			_try_add(full, mods, seen)
		f = d.get_next()
	d.list_dir_end()

static func _try_add(script_path: String, mods: Array, seen: Dictionary) -> void:
	if script_path == "" or seen.has(script_path):
		return
	seen[script_path] = true
	var script = load(script_path)
	if not (script is GDScript) or not _extends_game_mod(script):
		return
	var inst = script.new()
	if inst is GameMod:
		mods.append(inst)

# Vrai si la chaîne d'héritage du script passe par game_mod.gd (sans l'instancier).
static func _extends_game_mod(script: GDScript) -> bool:
	var s = script.get_base_script()
	while s != null:
		if s.resource_path == GAME_MOD_PATH:
			return true
		s = s.get_base_script()
	return false
