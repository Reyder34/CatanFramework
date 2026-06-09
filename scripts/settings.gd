extends Node
## Réglages persistants de l'application (app-level, hors core/modules).
## Volume master + mode d'affichage + résolution (fenêtré) + limite FPS. Conçu pour s'étendre :
## ajoute une variable + un setter + une clé dans _load/_save, et un widget dans options_menu.
##
## Autoload "Settings" (voir project.godot) -> appliqué au démarrage, quelle que soit la scène.

const SAVE_PATH := "user://settings.cfg"

# Modes d'affichage (l'index est stocké tel quel dans le .cfg et correspond à l'ordre du menu).
enum { DISPLAY_WINDOWED, DISPLAY_FULLSCREEN, DISPLAY_BORDERLESS }

var master_volume: float = 1.0     # linéaire 0..1 (1 = 100 %)
var display_mode: int = DISPLAY_WINDOWED
var resolution: Vector2i = Vector2i(1280, 720)  # taille de la fenêtre en mode Fenêtré
var max_fps: int = 0               # 0 = illimité

# Volumes des bus secondaires (linéaire 0..1). Le master reste géré à part : c'est le
# volume général, tous ces bus y sont routés. Les bus sont créés par l'autoload UISound,
# placé AVANT Settings dans project.godot pour qu'ils existent au moment de l'application.
const EXTRA_BUSES := ["UI", "SFX", "Notification", "Musique"]
var bus_volumes := {"UI": 1.0, "SFX": 1.0, "Notification": 1.0, "Musique": 1.0}

# === GRAPHISMES (perf) ===
# Émis quand un réglage graphique change ; LampLight + les scènes 3D (main/menu) s'y abonnent
# pour se ré-appliquer.
signal graphics_changed

# 3 presets de qualité. Chacun déduit les réglages détaillés ci-dessous (_recompute_quality).
enum { GFX_LOW, GFX_MEDIUM, GFX_ULTRA }
var graphics_preset: int = GFX_MEDIUM
# Toggle indépendant : false -> cycle figé à MIDI (lumières via DayNight + ciel via les scènes).
var day_night_enabled: bool = true
var show_fps: bool = false  # compteur de FPS en haut à droite (autoload FpsCounter)

# Réglages déduits du preset (lus par LampLight + apply_world ; ne pas régler à la main).
var lamp_lights_enabled: bool = true   # flaques de lumière des lampadaires (LampLight)
var glow_enabled: bool = true          # bloom des ampoules (Environment.glow)
var shadows_enabled: bool = true       # ombres du soleil (DirectionalLight3D.shadow)
var msaa_3d: int = Viewport.MSAA_2X    # anticrénelage 3D
var render_scale: float = 1.0          # échelle de rendu 3D (< 1 = plus rapide, plus flou)

func _ready() -> void:
	_load()
	_apply_master()
	_apply_bus_volumes()
	_recompute_quality()
	DayNight.set_running(day_night_enabled)  # DayNight est avant Settings dans les autoloads
	_apply_fps()
	_apply_display.call_deferred()  # la fenêtre racine doit être prête

# === SETTERS (appelés par le menu d'options) ===

func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_apply_master()
	_save()

func set_bus_volume(bus: String, v: float) -> void:
	if not bus_volumes.has(bus):
		return
	bus_volumes[bus] = clampf(v, 0.0, 1.0)
	_apply_bus_volume(bus, bus_volumes[bus])
	_save()

func set_display_mode(m: int) -> void:
	display_mode = clampi(m, DISPLAY_WINDOWED, DISPLAY_BORDERLESS)
	_apply_display()
	_save()

func set_resolution(res: Vector2i) -> void:
	resolution = Vector2i(maxi(res.x, 320), maxi(res.y, 240))
	_apply_display()  # sans effet hors Fenêtré (plein écran / sans bordure = taille écran)
	_save()

func set_max_fps(v: int) -> void:
	max_fps = maxi(v, 0)
	_apply_fps()
	_save()

func set_graphics_preset(p: int) -> void:
	graphics_preset = clampi(p, GFX_LOW, GFX_ULTRA)
	_recompute_quality()
	graphics_changed.emit()  # LampLight + scènes 3D (main/menu) se ré-appliquent
	_save()

func set_day_night_enabled(b: bool) -> void:
	day_night_enabled = b
	DayNight.set_running(b)
	graphics_changed.emit()
	_save()

func set_show_fps(b: bool) -> void:
	show_fps = b  # lu chaque frame par l'autoload FpsCounter
	_save()

# === APPLICATION ===

func _apply_master() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		bus = 0
	AudioServer.set_bus_mute(bus, master_volume <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))

func _apply_bus_volumes() -> void:
	for b in EXTRA_BUSES:
		_apply_bus_volume(b, float(bus_volumes.get(b, 1.0)))

# Applique un volume linéaire à un bus nommé. No-op si le bus n'existe pas encore
# (sécurité : UISound crée les bus, mais l'ordre des autoloads garantit leur présence).
func _apply_bus_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))

# Déduit les réglages détaillés du preset choisi. LOW = perf max (mais on garde les modèles).
func _recompute_quality() -> void:
	match graphics_preset:
		GFX_LOW:
			lamp_lights_enabled = false
			glow_enabled = false
			shadows_enabled = false
			msaa_3d = Viewport.MSAA_DISABLED
			render_scale = 0.8
		GFX_ULTRA:
			lamp_lights_enabled = true
			glow_enabled = true
			shadows_enabled = true
			msaa_3d = Viewport.MSAA_4X
			render_scale = 1.0
		_:  # GFX_MEDIUM
			lamp_lights_enabled = true
			glow_enabled = true
			shadows_enabled = true
			msaa_3d = Viewport.MSAA_2X
			render_scale = 1.0

# Applique les réglages graphiques à une scène 3D (environnement + soleil + viewport). Appelée par
# main.gd et menu_background.gd au démarrage + sur graphics_changed (ces nœuds leur appartiennent).
func apply_world(env: Environment, sun: Light3D, viewport: Viewport) -> void:
	if env != null:
		env.glow_enabled = glow_enabled
	if sun != null:
		sun.shadow_enabled = shadows_enabled
	if viewport != null:
		viewport.msaa_3d = msaa_3d
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = render_scale

func _apply_fps() -> void:
	Engine.max_fps = max_fps

func _apply_display() -> void:
	var win := get_window()
	if win == null:
		return
	# On change d'ABORD le mode / le flag sans-bordure, PUIS la géométrie (taille + position)
	# une fois la fenêtre stabilisée. Combiner « retrait du flag sans-bordure » et « resize »
	# dans la même frame laisse le viewport à l'ancienne taille -> bandes noires
	# (il fallait alors re-changer la résolution à la main pour forcer la mise à jour).
	match display_mode:
		DISPLAY_FULLSCREEN:
			win.borderless = false
			win.mode = Window.MODE_FULLSCREEN
		DISPLAY_BORDERLESS:
			win.mode = Window.MODE_WINDOWED
			win.borderless = true
		_:  # DISPLAY_WINDOWED
			win.mode = Window.MODE_WINDOWED
			win.borderless = false
	_apply_geometry_deferred()

# Applique taille + position APRÈS stabilisation de la fenêtre (2 frames), pour que le
# viewport suive la nouvelle taille -> corrige les bandes noires sans-bordure -> fenêtré.
func _apply_geometry_deferred() -> void:
	if not is_inside_tree():
		_apply_geometry()  # filet de sécurité (très tôt au démarrage)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_geometry()

func _apply_geometry() -> void:
	var win := get_window()
	if win == null or display_mode == DISPLAY_FULLSCREEN:
		return  # plein écran : la taille est gérée par le mode lui-même
	var scr := win.current_screen
	var screen_size := DisplayServer.screen_get_size(scr)
	var screen_pos := DisplayServer.screen_get_position(scr)
	var has_screen := screen_size.x > 0 and screen_size.y > 0
	if display_mode == DISPLAY_BORDERLESS:
		if has_screen:               # sans bordure = taille de l'écran
			win.size = screen_size
			win.position = screen_pos
	else:                            # DISPLAY_WINDOWED : résolution choisie, fenêtre centrée
		win.size = resolution
		if has_screen:
			win.position = screen_pos + (screen_size - resolution) / 2

# === PERSISTANCE ===

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return  # pas encore de fichier : on garde les valeurs par défaut
	master_volume = clampf(float(cfg.get_value("audio", "master", 1.0)), 0.0, 1.0)
	for b in EXTRA_BUSES:
		bus_volumes[b] = clampf(float(cfg.get_value("audio", b.to_lower(), 1.0)), 0.0, 1.0)
	display_mode = clampi(int(cfg.get_value("video", "display_mode", DISPLAY_WINDOWED)), DISPLAY_WINDOWED, DISPLAY_BORDERLESS)
	resolution = Vector2i(
		maxi(int(cfg.get_value("video", "res_w", 1280)), 320),
		maxi(int(cfg.get_value("video", "res_h", 720)), 240))
	max_fps = maxi(int(cfg.get_value("video", "max_fps", 0)), 0)
	graphics_preset = clampi(int(cfg.get_value("graphics", "preset", GFX_MEDIUM)), GFX_LOW, GFX_ULTRA)
	day_night_enabled = bool(cfg.get_value("graphics", "day_night", true))
	show_fps = bool(cfg.get_value("graphics", "show_fps", false))

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	for b in EXTRA_BUSES:
		cfg.set_value("audio", b.to_lower(), float(bus_volumes[b]))
	cfg.set_value("video", "display_mode", display_mode)
	cfg.set_value("video", "res_w", resolution.x)
	cfg.set_value("video", "res_h", resolution.y)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.set_value("graphics", "preset", graphics_preset)
	cfg.set_value("graphics", "day_night", day_night_enabled)
	cfg.set_value("graphics", "show_fps", show_fps)
	cfg.save(SAVE_PATH)
