class_name UIRegistry
extends RefCounted

# Point d'ancrage dans la scène (un CanvasLayer fourni par main)
var ui_root: Node

# id -> PackedScene déclarée par un mod
var panel_scenes: Dictionary = {}

# id -> mod_id qui l'a déclaré (pour debug)
var panel_origins: Dictionary = {}

# Compte le nombre de panneaux actuellement ouverts
var _open_count: int = 0

# id -> instance des panneaux persistants (non bloquants, mis à jour en continu)
var _persistent: Dictionary = {}

func _init(p_ui_root: Node) -> void:
	ui_root = p_ui_root

# Appelée par les mods via GameRegistry
func register_panel(panel_id: String, scene: PackedScene, mod_id: String = "unknown") -> void:
	if panel_scenes.has(panel_id):
		push_warning("Panel '%s' déjà déclaré par %s, écrasé par %s" % [
			panel_id, panel_origins[panel_id], mod_id
		])
	panel_scenes[panel_id] = scene
	panel_origins[panel_id] = mod_id

# Affiche un panneau, attend sa fermeture, retourne le résultat
# Le panneau doit implémenter:
#   - func show_panel(params: Dictionary) -> void
#   - signal closed(result: Variant)
func show_panel(panel_id: String, params: Dictionary = {}) -> Variant:
	if not panel_scenes.has(panel_id):
		push_error("Panel inconnu: %s" % panel_id)
		return null
	_open_count += 1
	var instance: Node = panel_scenes[panel_id].instantiate()
	if instance is CanvasItem:
		instance.visible = true
	ui_root.add_child(instance)
	# Affiche le panneau en haut-centre (pour ne pas masquer les ressources en haut-gauche).
	if instance is Control:
		_place_top_center(instance)
	await ui_root.get_tree().process_frame
	if instance.has_method("show_panel"):
		instance.show_panel(params)
	else:
		push_warning("Le panneau %s n'a pas de méthode show_panel(params)" % panel_id)
	# Rend le pop-up déplaçable (barre de titre) + redimensionnable, position retenue.
	# Fait APRÈS show_panel() pour que la poignée de redim s'ajoute après le contenu.
	if instance is Control:
		_make_movable(instance, panel_id)
	var result: Variant = null
	if instance.has_signal("closed"):
		result = await instance.closed
	instance.queue_free()
	_open_count -= 1
	return result

# === PANNEAUX PERSISTANTS (NON bloquants, mis à jour en continu) ===
# Contrairement à show_panel (modal, await closed), ceux-ci restent à l'écran et se
# mettent à jour via leur méthode `update_panel(params)`. Idéal pour un afficheur live
# (dés, minuterie, score…). Le panneau doit implémenter : func update_panel(params).
#
# Affiche le panneau (le crée s'il n'existe pas, sinon le met à jour) et le retourne.
func show_persistent(panel_id: String, params: Dictionary = {}) -> Node:
	var current = _persistent.get(panel_id, null)
	if is_instance_valid(current):
		if current.has_method("update_panel"):
			current.update_panel(params)
		return current
	if not panel_scenes.has(panel_id):
		push_error("Panel inconnu: %s" % panel_id)
		return null
	var instance: Node = panel_scenes[panel_id].instantiate()
	if instance is CanvasItem:
		instance.visible = true
	ui_root.add_child(instance)
	if instance is Control:
		_place_top_center(instance)
	if instance.has_method("update_panel"):
		instance.update_panel(params)
	if instance is Control:
		_make_movable(instance, panel_id)  # déplaçable + redimensionnable, comme les pop-ups
	_persistent[panel_id] = instance
	return instance

# Met à jour un panneau persistant déjà affiché (ne fait rien s'il est absent).
func update_persistent(panel_id: String, params: Dictionary = {}) -> void:
	var inst = _persistent.get(panel_id, null)
	if is_instance_valid(inst) and inst.has_method("update_panel"):
		inst.update_panel(params)

# Retire un panneau persistant.
func hide_persistent(panel_id: String) -> void:
	var inst = _persistent.get(panel_id, null)
	if is_instance_valid(inst):
		inst.queue_free()
	_persistent.erase(panel_id)

# Récupère l'instance d'un panneau persistant (ou null).
func get_persistent(panel_id: String) -> Node:
	var inst = _persistent.get(panel_id, null)
	return inst if is_instance_valid(inst) else null

# Rend un pop-up déplaçable + redimensionnable, avec position/taille persistées
# (partage le même mécanisme que le HUD via WindowMover). La poignée de déplacement
# est le titre du panneau ("Content/TitleLabel"), sinon le conteneur "Content".
func _make_movable(panel: Control, panel_id: String) -> void:
	var handle: Control = panel.get_node_or_null("Content/TitleLabel")
	if handle == null:
		handle = panel.get_node_or_null("Content")
	var mover := WindowMover.new()
	panel.add_child(mover)
	mover.setup(panel, handle, "popup_" + panel_id)

# Place un panneau en haut-centre de l'écran (centré horizontalement, près du haut).
func _place_top_center(c: Control) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_END
	c.offset_left = 0.0
	c.offset_right = 0.0
	c.offset_top = 12.0
	c.offset_bottom = 12.0

func is_any_panel_open() -> bool:
	return _open_count > 0

# Comptés comme "ouverts" même si le panneau s'affiche sur un AUTRE peer (réseau) :
# Net appelle ceci autour d'un panneau distant en attente -> le timer de tour se met
# en pause pendant qu'un joueur répond à une pop-up, où qu'elle soit.
func note_external_open() -> void:
	_open_count += 1

func note_external_close() -> void:
	_open_count = max(0, _open_count - 1)
