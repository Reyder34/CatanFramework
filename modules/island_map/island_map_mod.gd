class_name IslandMapMod
extends GameMod

# Mod de génération: une map hexagonale standard, mais découpée par de l'EAU
# (îles / archipels). Le plan ne contient que les cases de TERRE; toute case
# omise devient de l'eau automatiquement (le cœur s'en charge).
#
# Ne dépend de RIEN: il lit tile_pool / number_pool du registre -> agnostique au
# jeu. Occupe le slot "map_generator" (donc exclusif avec les autres mods de map).
#
# ============================ CONFIG (édite ici) ============================
# La TAILLE de la map vient du LOBBY (GameConfig.map_size -> reg.board_radius).
const LAND_RATIO := 0.5     # part de TERRE: 0.5 => 50% terre / 50% eau
const ISLAND_SEEDS := 2     # foyers d'îles: 1 = une île reliée; 2+ = archipel
const MIN_SEED_DIST := 3    # écart minimal entre deux foyers d'archipel
const ROUGHNESS := 0.35     # 0 = côtes rondes/lisses ; 1 = côtes très découpées
# ===========================================================================

func _init() -> void:
	mod_id = "island_map"
	mod_name = "Îles & archipels"
	description = "Map hexagonale séparée par de l'eau (ratio terre/eau configurable)."
	version = "1.0.0"
	author = "Toi"
	provides = ["map_generator"]  # un seul mod de map actif à la fois

func register(reg: GameRegistry) -> void:
	reg.set_map_generator(_generate)

# reg -> { Vector2(q, r): {"resource", "number"} } pour les cases de TERRE seulement.
# RÉSEAU: n'utilise que le RNG global (shuffle/randi/randf), déjà semé par main.gd
# -> même carte chez tous les joueurs.
func _generate(reg: GameRegistry) -> Dictionary:
	if reg.tile_pool.is_empty():
		return {}  # aucun jeu de tuiles -> repli sur la génération par défaut
	var area := _hex_disk(reg.board_radius)
	var target: int = maxi(1, int(round(area.size() * LAND_RATIO)))
	var land := _grow_islands(area, target)
	return _populate(reg, land)

# --- Croissance des îles depuis des foyers: garantit des masses connexes ---
func _grow_islands(area: Array, target: int) -> Array:
	var area_set := {}
	for c in area:
		area_set[c] = true
	var land := {}
	var frontier := {}
	for s in _pick_seeds(area):
		land[s] = true
	for c in land.keys():
		_add_frontier(c, area_set, land, frontier)
	while land.size() < target and not frontier.is_empty():
		var pick: Vector2 = _next_tile(frontier, land)
		land[pick] = true
		frontier.erase(pick)
		_add_frontier(pick, area_set, land, frontier)
	return land.keys()

func _add_frontier(c: Vector2, area_set: Dictionary, land: Dictionary, frontier: Dictionary) -> void:
	for off in HexMath.NEIGHBOR_OFFSETS:
		var nb: Vector2 = c + off
		if area_set.has(nb) and not land.has(nb):
			frontier[nb] = true

# Prochaine case: surtout la plus "entourée de terre" (côtes compactes), parfois
# une au hasard (ROUGHNESS) pour des contours organiques.
func _next_tile(frontier: Dictionary, land: Dictionary) -> Vector2:
	var keys := frontier.keys()
	if randf() < ROUGHNESS:
		return keys[randi() % keys.size()]
	var best: Vector2 = keys[0]
	var best_n := -1
	for c in keys:
		var n := 0
		for off in HexMath.NEIGHBOR_OFFSETS:
			if land.has(c + off):
				n += 1
		if n > best_n:
			best_n = n
			best = c
	return best

func _pick_seeds(area: Array) -> Array:
	var shuffled := area.duplicate()
	shuffled.shuffle()
	var seeds: Array = []
	for c in shuffled:
		if seeds.size() >= ISLAND_SEEDS:
			break
		var ok := true
		for s in seeds:
			if _hex_dist(c, s) < MIN_SEED_DIST:
				ok = false
				break
		if ok:
			seeds.append(c)
	if seeds.is_empty():
		seeds.append(shuffled[0])
	return seeds

# --- Remplissage: ressources + numéros échantillonnés depuis les pools ---
func _populate(reg: GameRegistry, land: Array) -> Dictionary:
	var resources := _sized_bag(reg.tile_pool, land.size())
	var numbers := _sized_bag(reg.number_pool, land.size())
	var plan := {}
	var ni := 0
	for i in land.size():
		var resource: String = resources[i] if i < resources.size() else ""
		var number := 0
		if resource != "" and reg.is_producing_resource(resource) and ni < numbers.size():
			number = numbers[ni]
			ni += 1
		plan[land[i]] = {"resource": resource, "number": number}
	return plan

# Sac mélangé de taille `size` respectant les proportions du pool (répété au besoin).
func _sized_bag(pool: Array, size: int) -> Array:
	if pool.is_empty():
		return []
	var bag: Array = []
	while bag.size() < size:
		bag.append_array(pool)
	bag.shuffle()
	bag.resize(size)
	return bag

# --- Helpers hexagonaux ---
func _hex_disk(radius: int) -> Array:
	var out: Array = []
	for r in range(-radius, radius + 1):
		var q_start: int = max(-radius, -radius - r)
		var q_end: int = min(radius, radius - r)
		for q in range(q_start, q_end + 1):
			out.append(Vector2(q, r))
	return out

func _hex_dist(a: Vector2, b: Vector2) -> int:
	var dq: float = a.x - b.x
	var dr: float = a.y - b.y
	return int((abs(dq) + abs(dr) + abs(dq + dr)) / 2.0)
