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

func _ready() -> void:
	_load()
	_apply_master()
	_apply_fps()
	_apply_display.call_deferred()  # la fenêtre racine doit être prête

# === SETTERS (appelés par le menu d'options) ===

func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_apply_master()
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

# === APPLICATION ===

func _apply_master() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		bus = 0
	AudioServer.set_bus_mute(bus, master_volume <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))

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
	display_mode = clampi(int(cfg.get_value("video", "display_mode", DISPLAY_WINDOWED)), DISPLAY_WINDOWED, DISPLAY_BORDERLESS)
	resolution = Vector2i(
		maxi(int(cfg.get_value("video", "res_w", 1280)), 320),
		maxi(int(cfg.get_value("video", "res_h", 720)), 240))
	max_fps = maxi(int(cfg.get_value("video", "max_fps", 0)), 0)

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("video", "display_mode", display_mode)
	cfg.set_value("video", "res_w", resolution.x)
	cfg.set_value("video", "res_h", resolution.y)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.save(SAVE_PATH)
