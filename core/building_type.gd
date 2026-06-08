class_name BuildingType
extends RefCounted

# Identité
var id: String = ""
var display_name: String = ""
var description: String = ""  # effet décrit par le mod (affiché en tooltip dans le HUD)
var target: String = "vertex"  # "vertex" ou "edge"

# Économie
var cost: Dictionary = {}
var victory_points: int = 0

# Visuel
var mesh_radius: float = 0.2
var mesh_height: float = 0.4

# === À surcharger par chaque bâtiment ===

func can_place(board: Board, player_id: int, key: String) -> bool:
	return false

func on_placed(board: Board, player_id: int, key: String) -> void:
	pass

func get_production_amount() -> int:
	return 0

func get_color(player_color: Color) -> Color:
	return player_color

# === MODÈLE 3D (point d'extension générique) ===

# Modèle optionnel. Si défini, BoardView l'instancie à la place de la primitive.
var model_scene: PackedScene = null

# Retourne le visuel 3D du bâtiment (Node3D), ou null pour la primitive par défaut.
# Deux façons de personnaliser: assigner model_scene, ou surcharger cette méthode
# (modèle procédural). Les ports/marqueurs des mods créent déjà leurs propres nœuds.
func create_visual(player_color: Color) -> Node3D:
	if model_scene == null:
		return null
	var inst: Node = model_scene.instantiate()
	apply_player_color(inst, get_color(player_color))
	return inst if inst is Node3D else null

# Applique la couleur joueur: appelle set_player_color(color) si le modèle
# l'implémente (contrôle total côté mod), sinon teinte les MeshInstance3D non colorés.
func apply_player_color(node: Node, color: Color) -> void:
	if node.has_method("set_player_color"):
		node.call("set_player_color", color)
		return
	# CONVENTION STRICTE : CHAQUE nœud nommé "Corps" (+ tout son sous-arbre) prend la couleur
	# du joueur — FORCÉE (CSG, MeshInstance3D, .glb…). On gère PLUSIEURS "Corps" dans un même
	# modèle. Aucun "Corps" -> on ne colore RIEN (le modèle garde ses propres matériaux).
	_color_corps(node, color)

# Parcourt l'arbre et colore le sous-arbre de CHAQUE nœud dont le nom commence par "corp"
# (insensible à la casse). Permet plusieurs "Corps" répartis dans le modèle.
func _color_corps(node: Node, color: Color) -> void:
	if node.name.to_lower().begins_with("corp"):
		_force_color(node, color)
		return  # tout son sous-arbre est déjà coloré, inutile de descendre plus
	for c in node.get_children():
		_color_corps(c, color)

# Force la couleur joueur sur TOUS les meshes sous ce nœud (MeshInstance3D ET CSG),
# en écrasant le matériau existant.
func _force_color(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		node.material_override = _colored_mat(color)
	elif node is CSGPrimitive3D or node is CSGMesh3D:
		node.material = _colored_mat(color)
	for c in node.get_children():
		_force_color(c, color)

func _colored_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m
