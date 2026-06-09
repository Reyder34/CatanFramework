extends Camera3D

# --- Paramètres de Rotation ---
@export var horizontal_sensitivity: float = 0.005
@export var vertical_sensitivity: float = 0.05 # Souvent un peu plus forte que l'horizontale
@export var radius: float = 15.0      
@export var height: float = 10.0      
@export var min_height: float = 2.0    # Limite basse (au ras du plateau)
@export var max_height: float = 30.0   # Limite haute (vue de dessus)
@export var target_point: Vector3 = Vector3.ZERO

# --- Paramètres de Zoom ---
@export var zoom_speed: float = 1.5   
@export var min_zoom: float = 2.0     
@export var max_zoom: float = 20.0    

# --- Paramètres de Cinématique ---
@export var auto_rotate_speed: float = 0.1 # Vitesse de la rotation automatique

var current_angle: float = PI / 4.0
var is_dragging: bool = false # Permet de savoir si on est en train de cliquer-glisser
var is_cinematic_mode: bool = false # Statut du mode cinématique

func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	update_camera_position()

# Appelé à chaque frame pour gérer le mouvement continu
func _process(delta: float) -> void:
	if is_cinematic_mode:
		# On ajoute l'angle en fonction du temps (delta) pour une rotation fluide
		current_angle += auto_rotate_speed * delta
		update_camera_position()

# Toute la logique d'entrée (clavier/souris) se passe ici maintenant
func _unhandled_input(event: InputEvent) -> void:
	
	# --- Nouveau : Détection de la touche de bascule (Toggle) ---
	if event is InputEventKey:
		# Appuie sur 'C' pour activer/désactiver la cinématique
		if event.pressed and event.keycode == KEY_C:
			is_cinematic_mode = !is_cinematic_mode
			
	# 1. On détecte les clics de souris (Gauche et Molette)
	elif event is InputEventMouseButton:
		
		# Activer/Désactiver le "drag" avec le Clic Droit (selon ton code d'origine)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_dragging = event.pressed
			# Optionnel : Désactiver la cinématique si le joueur reprend le contrôle manuel
			if is_dragging:
				is_cinematic_mode = false
			
		# Gérer le zoom avec la molette
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			size -= zoom_speed
			size = clamp(size, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			size += zoom_speed
			size = clamp(size, min_zoom, max_zoom)

	# 2. On détecte le mouvement de la souris sur l'écran
	elif event is InputEventMouseMotion:
		
		# Si le clic droit est maintenu, on tourne
		if is_dragging:
			# event.relative.x donne le déplacement horizontal de la souris en pixels
			current_angle += event.relative.x * horizontal_sensitivity
			height -= event.relative.y * vertical_sensitivity
			height = clamp(height, min_height, max_height)
			update_camera_position()

func update_camera_position() -> void:
	var x = target_point.x + cos(current_angle) * radius
	var z = target_point.z + sin(current_angle) * radius
	
	position = Vector3(x, height, z)
	look_at(target_point, Vector3.UP)
