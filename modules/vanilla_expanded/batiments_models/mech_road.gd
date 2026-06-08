@tool
extends Node3D

# --- Interrupteur pour l'éditeur ---
@export var apercu_dans_editeur: bool = false :
	set(value):
		apercu_dans_editeur = value
		# Si on coche la case dans l'éditeur, on lance l'animation
		if apercu_dans_editeur and Engine.is_editor_hint():
			lancer_tous_les_montants()

# --- Paramètres de rotation ---
@export var min_wait_time: float = 1.0  
@export var max_wait_time: float = 4.0  
@export var rotation_speed: float = 1.5 

func _ready() -> void:
	if not Engine.is_editor_hint():
		lancer_tous_les_montants()

func lancer_tous_les_montants() -> void:
	var montants = find_all_montants(self)
	print("Montants trouvés pour l'animation : ", montants.size())
	for montant in montants:
		start_rotation_cycle(montant)

func find_all_montants(parent: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in parent.get_children():
		if child is MeshInstance3D and child.name.begins_with("Montant"):
			result.append(child)
		result.append_array(find_all_montants(child))
	return result

func start_rotation_cycle(node: Node3D) -> void:
	# On remplace la fonction qui s'appelle elle-même par une boucle infinie propre
	while is_instance_valid(node):
		
		# SÉCURITÉ : Si on décoche la case dans l'éditeur, on casse la boucle (break)
		if Engine.is_editor_hint() and not apercu_dans_editeur:
			break

		var wait_time = randf_range(min_wait_time, max_wait_time)
		await get_tree().create_timer(wait_time).timeout
		
		# On revérifie au cas où on a décoché la case PENDANT les secondes d'attente
		if not is_instance_valid(node) or (Engine.is_editor_hint() and not apercu_dans_editeur):
			break
			
		var tween = create_tween()
		var target_rotation = node.rotation_degrees + Vector3(0, 180, 0)
		
		tween.tween_property(node, "rotation_degrees", target_rotation, rotation_speed)\
			 .set_trans(Tween.TRANS_SINE)\
			 .set_ease(Tween.EASE_IN_OUT)
		
		await tween.finished
