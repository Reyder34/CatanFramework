class_name GameConfig
extends RefCounted

# Configuration choisie dans le menu, lue par la scène de jeu.
# Les `static var` persistent entre les changements de scène.
static var player_count: int = 4
static var enabled_mod_ids: Array = ["classic_catan", "vanilla_robber"]
static var map_size: int = 2  # rayon hex du plateau (réglé au lobby), lu par les générateurs
static var turn_timer: int = 0  # secondes par tour (0 = désactivé), réglé au lobby/solo
static var player_names: Array = []  # index joueur -> pseudo (réseau); vide en solo

# Multijoueur
static var is_multiplayer: bool = false
static var game_seed: int = 0          # 0 = aléatoire; sinon plateau déterministe (réseau)
static var local_player_index: int = 0  # quel joueur ce peer contrôle
static var peer_to_player: Dictionary = {}  # peer_id -> index joueur (réseau)

# === SAUVEGARDES (JSON) ===
const SAVES_DIR := "user://saves"
static var resume_snapshot: Dictionary = {}  # snapshot JSON à appliquer au boot (autorité); {} = aucun

# Liste des saves: [{slot, meta}] (meta = mods/seed/names/...). Lue par le salon.
static func list_saves() -> Array:
	var out: Array = []
	var d := DirAccess.open(SAVES_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var data := load_save(f.get_basename())
		if not data.is_empty():
			out.append({"slot": f.get_basename(), "meta": data.get("meta", {})})
	return out

static func load_save(slot: String) -> Dictionary:
	var path := "%s/%s.json" % [SAVES_DIR, slot]
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
