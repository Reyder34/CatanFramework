# boat.gd — Bateau visiteur (3 instances max).
# Choisit un port aléatoire, arrive en longeant la côte (parallèle au rivage),
# attend à quai, repart hors-écran. Vérifie qu'il reste dans l'eau à tout moment.
extends Node3D

var ports_info: Array    = []   # [{pos: Vector3, ...}]
var land_positions: Array = []  # Vector3 centre de chaque tuile terrestre
var start_delay: float   = 0.0

const OFFSCREEN      := 7.0   # distance hors-écran (unités)
const SPEED          := 0.9   # unités / seconde
const DOCK_WAIT_MIN  := 3.0
const DOCK_WAIT_MAX  := 7.0
const IDLE_MIN       := 5.0
const IDLE_MAX       := 13.0
const MIN_LAND_DIST  := 1.05  # distance minimale du centre d'une tuile terrestre


func _ready() -> void:
	visible = false
	_loop()


func _loop() -> void:
	await get_tree().create_timer(start_delay).timeout
	while is_inside_tree():
		await get_tree().create_timer(randf_range(IDLE_MIN, IDLE_MAX)).timeout
		if ports_info.is_empty():
			continue
		await _do_visit()


func _do_visit() -> void:
	# Essaie les ports dans un ordre mélangé pour trouver un trajet sûr
	var indices := range(ports_info.size())
	indices.shuffle()

	for idx in indices:
		var port: Dictionary = ports_info[idx]
		var pos     := port["pos"] as Vector3
		var outward := Vector3(pos.x, 0.0, pos.z).normalized()

		# Tangente : direction le long de la côte (deux sens possibles)
		var tangent := Vector3(-outward.z, 0.0, outward.x)

		# Trouver un point d'accostage sûr (dans l'eau)
		var dock := _safe_dock(pos, outward)
		if dock == Vector3.ZERO:
			continue   # port inaccessible, on essaie le suivant

		# Essayer les deux sens de la tangente
		for flip in [1, -1]:
			var t: Vector3 = tangent * (flip as int)
			var start  := dock - t * OFFSCREEN
			var finish := dock + t * OFFSCREEN

			# Vérifier que la totalité du trajet reste dans l'eau
			if not _path_is_safe(start, dock):
				continue
			if not _path_is_safe(dock, finish):
				continue

			# Trajet validé — on part
			rotation.y = atan2(-t.z, t.x)
			global_position = start
			visible = true

			await _sail_to(dock)
			await get_tree().create_timer(randf_range(DOCK_WAIT_MIN, DOCK_WAIT_MAX)).timeout
			await _sail_to(finish)

			visible = false
			return   # visite terminée, on repassera dans _loop

	# Aucun port valide trouvé ce tour-ci — on attend et on réessaie
	await get_tree().create_timer(3.0).timeout


# Cherche un point dans l'eau en poussant progressivement vers le large.
func _safe_dock(pos: Vector3, outward: Vector3) -> Vector3:
	var offset := 0.6
	while offset < 4.0:
		var candidate := Vector3(pos.x, 0.0, pos.z) + outward * offset
		if _is_water(candidate):
			return candidate
		offset += 0.2
	return Vector3.ZERO   # échec


# Vérifie plusieurs points le long d'un segment (évite de traverser la terre).
func _path_is_safe(from: Vector3, to: Vector3) -> bool:
	for i in 8:
		var t: float = float(i) / 7.0
		if not _is_water(from.lerp(to, t)):
			return false
	return true


func _is_water(point: Vector3) -> bool:
	for entry in land_positions:
		var lp := entry as Vector3
		var dx := point.x - lp.x
		var dz := point.z - lp.z
		if dx * dx + dz * dz < MIN_LAND_DIST * MIN_LAND_DIST:
			return false
	return true


func _sail_to(target: Vector3) -> void:
	var dist := global_position.distance_to(target)
	if dist < 0.001:
		return
	var tw := create_tween()
	tw.tween_property(self, "global_position", target, dist / SPEED)
	await tw.finished
