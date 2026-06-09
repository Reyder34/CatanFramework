extends Node
## Convention générique « lumière sous le shader » — l'équivalent lumière du « Corp » (couleur joueur) :
## TOUT MeshInstance3D dont un matériau utilise le shader ui/shader/lamp_glow.gdshader reçoit
## AUTOMATIQUEMENT une flaque de lumière (OmniLight très faible, cf. LampLight) dessous — où qu'il
## soit, dans n'importe quel model (jeu, menu, modules…).
##
## Autoload "LampLights". Repère les meshes via get_tree().node_added (présents + à venir), comme
## UISound câble les boutons. Aucune action requise côté model : il suffit de poser le shader.

const LAMP_SHADER_PATH := "res://ui/shader/lamp_glow.gdshader"
const LAMP_LIGHT_SCRIPT := preload("res://scripts/lamp_light.gd")

var _lamp_shader: Shader

func _ready() -> void:
	if ResourceLoader.exists(LAMP_SHADER_PATH):
		_lamp_shader = load(LAMP_SHADER_PATH)
	get_tree().node_added.connect(_on_node_added)
	_scan(get_tree().root)  # filet : meshes déjà dans l'arbre au lancement

func _on_node_added(node: Node) -> void:
	if node is MeshInstance3D and _uses_lamp_shader(node):
		_spawn_light.call_deferred(node)

func _scan(node: Node) -> void:
	_on_node_added(node)
	for c in node.get_children():
		_scan(c)

# Une flaque par mesh-ampoule : OmniLight ajouté au PARENT du mesh, à la position locale du mesh
# -> halo faible autour de la lampe, qui la suit.
func _spawn_light(mesh: MeshInstance3D) -> void:
	if not is_instance_valid(mesh) or not mesh.is_inside_tree():
		return
	if mesh.has_meta(&"lamp_light_done"):
		return
	var parent := mesh.get_parent()
	if parent == null:
		return
	mesh.set_meta(&"lamp_light_done", true)
	var light := OmniLight3D.new()
	light.set_script(LAMP_LIGHT_SCRIPT)
	light.position = mesh.position
	parent.add_child(light)

func _uses_lamp_shader(mi: MeshInstance3D) -> bool:
	if _lamp_shader == null:
		return false
	if _is_lamp_mat(mi.material_override) or _is_lamp_mat(mi.material_overlay):
		return true
	var mesh := mi.mesh
	if mesh == null:
		return false
	for i in mesh.get_surface_count():
		if _is_lamp_mat(mi.get_surface_override_material(i)):
			return true
		if _is_lamp_mat(mesh.surface_get_material(i)):
			return true
	return false

func _is_lamp_mat(m: Material) -> bool:
	return m is ShaderMaterial and (m as ShaderMaterial).shader == _lamp_shader
