extends Node
## Convention générique « AV » (au vent) — l'équivalent VENT du « Corps » (couleur joueur) et de la
## lanterne (lumière sous le shader). CHAQUE enfant direct (Node3D) d'un nœud dont le nom commence par
## "AV" s'incline dans la DIRECTION du vent et ondule, l'amplitude suivant l'INTENSITÉ du vent
## (Weather). Aucune action côté model : il suffit de nommer un nœud "AV" et d'y mettre des enfants.
##
## Autoload "WindSway". Repère les nœuds via get_tree().node_added (présents + à venir), comme
## LampLights câble les lampes. Plusieurs "AV" possibles dans un même modèle (comme plusieurs "Corps").

const SWAY_LEAN := 0.20     # inclinaison constante (radians) à vent = 1  (~11°)
const SWAY_AMP := 0.12      # amplitude d'oscillation (radians) à vent = 1 (~7°)
const SWAY_FREQ := 1.7      # vitesse d'oscillation (rad/s)
const PHASE_STEP := 1.7     # décalage de phase entre enfants -> ondulation organique (pas en bloc)

var _targets: Array = []    # [{ node, rest(basis), pinv(basis), phase }]

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_scan(get_tree().root)   # filet : nœuds déjà dans l'arbre au lancement

func _on_node_added(node: Node) -> void:
	if node.name.begins_with("AV"):
		_register.call_deferred(node)   # différé : les enfants peuvent ne pas être encore dans l'arbre

func _scan(node: Node) -> void:
	_on_node_added(node)
	for c in node.get_children():
		_scan(c)

func _register(av: Node) -> void:
	if not is_instance_valid(av) or not av.is_inside_tree() or av.has_meta(&"av_sway_done"):
		return
	if not (av is Node3D):
		return
	av.set_meta(&"av_sway_done", true)
	# Rotation du parent (sans échelle) : sert à exprimer l'axe du vent (monde) dans l'espace des enfants.
	var pinv := (av as Node3D).global_transform.basis.orthonormalized().inverse()
	var i := 0
	for child in av.get_children():
		if child is Node3D:
			_targets.append({
				"node": child,
				"rest": (child as Node3D).transform.basis,
				"pinv": pinv,
				"phase": float(i) * PHASE_STEP,
			})
			i += 1

func _process(_delta: float) -> void:
	if _targets.is_empty():
		return
	var wv := Weather.wind_vector()
	var dir := Vector3(wv.x, 0.0, wv.z)
	var l := dir.length()
	dir = dir / l if l > 0.0001 else Vector3.FORWARD
	var strength := clampf(Weather.wind, 0.0, 1.0)         # intensité 0..1
	var world_axis := Vector3.UP.cross(dir)                # axe horizontal perpendiculaire au vent
	if world_axis.length() < 0.0001:
		world_axis = Vector3.RIGHT
	world_axis = world_axis.normalized()
	var t := Time.get_ticks_msec() / 1000.0
	for idx in range(_targets.size() - 1, -1, -1):
		var tg: Dictionary = _targets[idx]
		var node = tg["node"]   # NON typé : ne PAS valider le type d'une instance peut-être libérée
		if not is_instance_valid(node):
			_targets.remove_at(idx)   # nœud libéré (changement de scène) -> on l'oublie
			continue
		var n3d := node as Node3D
		var angle: float = (SWAY_LEAN + SWAY_AMP * sin(t * SWAY_FREQ + float(tg["phase"]))) * strength
		var local_axis: Vector3 = (tg["pinv"] * world_axis).normalized()
		n3d.transform.basis = (tg["rest"] as Basis).rotated(local_axis, angle)
