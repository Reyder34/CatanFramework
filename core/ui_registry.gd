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
	print("[UI] instance créée: ", instance, " script=", instance.get_script())
	print("[UI] has show_panel: ", instance.has_method("show_panel"))
	print("[UI] has signal closed: ", instance.has_signal("closed"))
	if instance is CanvasItem:
		instance.visible = true
	ui_root.add_child(instance)
	await ui_root.get_tree().process_frame
	print("[UI] taille panneau: ", instance.size, " position: ", instance.position)
	print("[UI] visible: ", instance.visible, " modulate alpha: ", instance.modulate.a)
	if instance.has_method("show_panel"):
		instance.show_panel(params)
	else:
		push_warning("Le panneau %s n'a pas de méthode show_panel(params)" % panel_id)
	var result: Variant = null
	if instance.has_signal("closed"):
		result = await instance.closed
	instance.queue_free()
	_open_count -= 1
	return result

func is_any_panel_open() -> bool:
	return _open_count > 0
