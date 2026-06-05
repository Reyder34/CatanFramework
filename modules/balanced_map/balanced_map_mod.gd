class_name BalancedMapMod
extends GameMod

# Mod de DÉMONSTRATION: remplace la génération de map par une disposition
# "équilibrée".
#
# IL NE DÉPEND DE RIEN (depends_on vide). Il lit le tile_pool / number_pool du
# registre — peu importe quel autre mod les a remplis. Il fonctionne donc pour
# Catan classique comme pour n'importe quel jeu de tuiles: aucun nom de ressource
# ("wood", "brick"…) n'est codé en dur.
#
# Règle d'équilibre, volontairement GÉNÉRIQUE (sans rien savoir de Catan ni des dés):
#   - deux tuiles voisines ne portent jamais le MÊME numéro (numéros étalés);
#   - une tuile non productrice (désert) n'est pas pile au centre.
# Pour une règle « façon Catan » (pas deux 6/8 adjacents), il suffirait d'ajouter
# une condition dans _is_balanced — sans toucher au reste.

const MAX_ATTEMPTS := 1500

func _init() -> void:
	mod_id = "balanced_map"
	mod_name = "Carte équilibrée"
	description = "Étale les numéros (pas deux voisins identiques). Indépendant de tout jeu."
	version = "1.0.0"
	author = "Toi"
	# depends_on reste VIDE: c'est tout l'intérêt (voir l'en-tête).
	provides = ["map_generator"]  # un seul mod de map actif à la fois

func register(reg: GameRegistry) -> void:
	reg.set_map_generator(_generate)

# Générateur: reg -> { Vector2(q, r): {"resource": String, "number": int} }.
# RÉSEAU: on n'utilise que le RNG global (shuffle), déjà semé par main.gd, donc
# tous les joueurs obtiennent EXACTEMENT la même carte.
func _generate(reg: GameRegistry) -> Dictionary:
	if reg.tile_pool.is_empty():
		return {}  # aucun jeu de tuiles chargé -> repli sur la génération par défaut
	var coords := _hex_coords(reg.board_radius)
	# Tirage par rejet, mais on garde la MEILLEURE carte vue (best-of): même si
	# l'équilibre parfait échappe, on renvoie la moins déséquilibrée (jamais pire
	# qu'un tirage au hasard). En pratique score 0 est atteint très vite.
	# Sacs dimensionnés -> remplit n'importe quelle taille de map (répète le pool).
	var best: Dictionary = {}
	var best_score := 1 << 30
	for attempt in MAX_ATTEMPTS:
		var tiles := _sized_bag(reg.tile_pool, coords.size())
		var producing := 0
		for t in tiles:
			if reg.is_producing_resource(t):
				producing += 1
		var numbers := _sized_bag(reg.number_pool, producing)
		var plan := _assemble(reg, coords, tiles, numbers)
		var score := _imbalance(reg, plan)
		if score < best_score:
			best_score = score
			best = plan
			if score == 0:
				return best
	if best_score > 0:
		push_warning("balanced_map: équilibre parfait non atteint (score %d) en %d essais." % [best_score, MAX_ATTEMPTS])
	return best

# Sac mélangé de taille `size`, répétant le pool si la map dépasse sa taille.
func _sized_bag(pool: Array, size: int) -> Array:
	if pool.is_empty() or size <= 0:
		return []
	var bag: Array = []
	while bag.size() < size:
		bag.append_array(pool)
	bag.shuffle()
	bag.resize(size)
	return bag

# Place chaque ressource sur une case; un numéro seulement si la case produit.
func _assemble(reg: GameRegistry, coords: Array, tiles: Array, numbers: Array) -> Dictionary:
	var plan: Dictionary = {}
	var num_index := 0
	for i in coords.size():
		var resource: String = tiles[i] if i < tiles.size() else ""
		var number := 0
		if resource != "" and reg.is_producing_resource(resource):
			if num_index < numbers.size():
				number = numbers[num_index]
				num_index += 1
		plan[coords[i]] = {"resource": resource, "number": number}
	return plan

# Score de déséquilibre (0 = parfait): +1 par adjacence de même numéro,
# +1 si le désert (non producteur) est pile au centre. On le MINIMISE.
func _imbalance(reg: GameRegistry, plan: Dictionary) -> int:
	var score := 0
	for coords in plan:
		var cell: Dictionary = plan[coords]
		if not reg.is_producing_resource(cell.get("resource", "")) and coords == Vector2.ZERO:
			score += 1
		var number: int = int(cell.get("number", 0))
		if number <= 0:
			continue
		for offset in HexMath.NEIGHBOR_OFFSETS:
			var nb: Vector2 = coords + offset
			if plan.has(nb) and int(plan[nb].get("number", 0)) == number:
				score += 1
	return score

# Coordonnées d'un disque hexagonal de rayon donné (ordre stable).
func _hex_coords(radius: int) -> Array:
	var out: Array = []
	for r in range(-radius, radius + 1):
		var q_start: int = max(-radius, -radius - r)
		var q_end: int = min(radius, radius - r)
		for q in range(q_start, q_end + 1):
			out.append(Vector2(q, r))
	return out
