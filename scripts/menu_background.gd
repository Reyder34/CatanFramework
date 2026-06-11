extends Node3D
## Fond animé du menu : un plateau Catan DÉCORATIF (colonies/villes/routes posées) avec le
## cycle jour/nuit (soleil + lune) et une caméra qui tourne lentement. Rendu dans un SubViewport
## derrière l'UI du menu. Aucune logique de jeu : juste du décor (pas de tours, pas de clics).

var board: Board
var board_view: BoardView
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _sky_mat: ShaderMaterial
var _cam: Camera3D
var _angle := 0.0

func _ready() -> void:
	DayNight.cycle_seconds = 120.0  # menu : 1 min jour + 1 min nuit
	_build_lighting()
	_build_camera()
	_build_board()
	_apply_day_night()
	Settings.graphics_changed.connect(_apply_graphics)
	_apply_graphics()

func _build_lighting() -> void:
	# Ciel : le shader sky.gdshader sur un ColorRect (CanvasLayer -10), comme dans le jeu.
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -10
	add_child(sky_layer)
	var sky_rect := ColorRect.new()
	sky_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://ui/shader/sky.gdshader")
	_sky_mat.set_shader_parameter("cycle_duration", 120.0)  # = DayNight.cycle_seconds du menu (sync)
	sky_rect.material = _sky_mat
	sky_layer.add_child(sky_rect)
	# Environnement : fond = le canvas (ciel), + ambiance modulée jour/nuit.
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_CANVAS
	_env.background_canvas_max_layer = -10
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Glow à seuil HDR : seules les ampoules émissives (lampadaires la nuit) bloomment ;
	# l'eau / le plateau (LDR < seuil) ne changent pas.
	_env.glow_enabled = true
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	_env.glow_hdr_threshold = 1.5
	_env.glow_bloom = 0.0
	_env.glow_intensity = 1.0
	_env.glow_strength = 1.1
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 40.0
	add_child(_sun)
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.66, 0.74, 1.0)
	add_child(_moon)

func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 12.0
	_cam.h_offset = -5.0  # décale le plateau vers la DROITE (le menu est à gauche)
	add_child(_cam)
	_cam.current = true

func _build_board() -> void:
	var registry := GameRegistry.new()
	# UIRegistry veut un root dans l'arbre (aucun panneau ne sera montré ici).
	var ui_layer := CanvasLayer.new()
	add_child(ui_layer)
	var ui_root := Control.new()
	ui_layer.add_child(ui_root)
	registry.setup_ui(ui_root)
	ModLoader.load_mods(registry, [ClassicCatanMod.new()])
	registry.set_board_radius(2)
	board = Board.new()
	board_view = BoardView.new(registry, board)
	board_view.generate(self)   # tuiles + sommets + arêtes + eau + graphe
	_place_decor()
	_hide_labels(self)          # pas de numéros flottants en fond de menu

# Pose ~12 colonies/villes espacées (4 couleurs) + 1-2 routes chacune -> plateau "en cours de partie".
func _place_decor() -> void:
	var vkeys: Array = board.vertex_data.keys()
	vkeys.shuffle()
	var placed := 0
	var pid := 0
	for vkey in vkeys:
		if placed >= 12:
			break
		if board.get_vertex_owner(vkey) >= 0:
			continue
		# Espacement : on saute si un sommet voisin est déjà occupé (règle de distance).
		var blocked := false
		for e in board.vertex_edges.get(vkey, []):
			for ov in board.edge_endpoints.get(e, []):
				if ov != vkey and board.get_vertex_owner(ov) >= 0:
					blocked = true
		if blocked:
			continue
		board.place_on_vertex(vkey, pid, ("city" if placed % 3 == 0 else "settlement"))
		var edges: Array = board.vertex_edges.get(vkey, []).duplicate()
		edges.shuffle()
		var roads := 0
		for e in edges:
			if board.get_edge_owner(e) >= 0:
				continue
			board.place_on_edge(e, pid, "road")
			roads += 1
			if roads >= 2:
				break
		placed += 1
		pid = (pid + 1) % 4
	board_view.refresh_all()    # instancie les modèles des bâtiments posés

func _hide_labels(node: Node) -> void:
	for c in node.get_children():
		if c is Label3D:
			c.visible = false
		_hide_labels(c)

func _process(delta: float) -> void:
	# Caméra orbite lente autour du plateau.
	_angle += delta * 0.12
	_cam.position = Vector3(cos(_angle) * 14.0, 6.0, sin(_angle) * 14.0)  # plus bas = angle plus serré
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	_apply_day_night()
	Weather.apply_sky(_sky_mat)   # météo -> ciel (nuages/pluie/neige/tempête/éclair)

# Même logique que main.gd : soleil orienté selon l'arc du cycle, lune la nuit, ambiance.
func _apply_day_night() -> void:
	if _sun != null:
		var dir: Vector3 = DayNight.sun_direction
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.BACK
		_sun.look_at(_sun.global_position + dir, up)
		_sun.light_energy = DayNight.sun_energy
		_sun.light_color = DayNight.sun_color
		_sun.visible = DayNight.sun_energy > 0.001
	if _moon != null:
		_moon.light_energy = DayNight.moon_energy
		_moon.visible = DayNight.moon_energy > 0.001
	if _env != null:
		_env.ambient_light_color = DayNight.ambient_color
		_env.ambient_light_energy = DayNight.ambient_energy

# Réglages graphiques (preset + cycle jour/nuit) appliqués au SubViewport du menu.
func _apply_graphics() -> void:
	Settings.apply_world(_env, _sun, get_viewport())
	if _sky_mat != null:
		var cd := 120.0 if Settings.day_night_enabled else 1.0e9
		_sky_mat.set_shader_parameter("cycle_duration", cd)
