extends CanvasLayer
## Overlay d'options réutilisable (menu principal ET en jeu).
## S'affiche au-dessus de tout, se ferme avec « Fermer » ou Échap.
## Réglages : volume master, mode d'affichage, résolution, limite FPS.
## Pour en ajouter un -> un widget dans la scène + l'init/branchement ici, et une clé dans settings.gd.

@onready var _slider: HSlider = %MasterSlider
@onready var _value: Label = %MasterValue
@onready var _display: OptionButton = %DisplayMode
@onready var _res: OptionButton = %ResolutionMode
@onready var _fps: OptionButton = %FpsCap
@onready var _close_btn: Button = %CloseBtn

# Sliders de volume par bus (en plus du master = volume général). Ordre = ordre des bus.
@onready var _ui_slider: HSlider = %UISlider
@onready var _ui_value: Label = %UIValue
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _sfx_value: Label = %SfxValue
@onready var _notif_slider: HSlider = %NotifSlider
@onready var _notif_value: Label = %NotifValue
@onready var _music_slider: HSlider = %MusicSlider
@onready var _music_value: Label = %MusicValue

# Graphismes : preset de qualité (Low/Medium/Ultra) + toggle cycle jour/nuit.
@onready var _gfx: OptionButton = %GfxPreset
@onready var _lamp: CheckButton = %LampToggle
@onready var _wind: CheckButton = %WindToggle
@onready var _smoke: CheckButton = %SmokeToggle
@onready var _reflect: CheckButton = %ReflectToggle
@onready var _shadows: CheckButton = %ShadowToggle
@onready var _msaa: OptionButton = %MsaaOption
@onready var _scale: OptionButton = %ScaleOption
@onready var _daynight: CheckButton = %DayNightToggle
@onready var _fps_toggle: CheckButton = %FpsToggle
@onready var _quit_game_btn: Button = %QuitGameBtn

var _game: Node = null  # défini par main.gd en jeu -> affiche le bouton "Quitter la partie"

# Résolutions proposées en mode Fenêtré (l'index du menu -> la taille).
const RESOLUTIONS := [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440,1440),
]
# Caps proposés (l'index du menu -> la valeur ; 0 = illimité).
const FPS_VALUES := [0, 30, 60, 120, 144, 240]
const FPS_LABELS := ["Illimité", "30", "60", "120", "144", "240"]
# Anticrénelage (index -> Viewport.MSAA_*) et échelle de rendu (index -> facteur).
const MSAA_VALUES := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]
const MSAA_LABELS := ["Désactivé", "2×", "4×", "8×"]
const SCALE_VALUES := [0.5, 0.75, 1.0, 1.25, 1.5]
const SCALE_LABELS := ["50 %", "75 %", "100 %", "125 %", "150 %"]

func _ready() -> void:
	layer = 128  # au-dessus du HUD et de tout le reste

	# Volume général (master) + un slider par bus secondaire.
	_slider.value = Settings.master_volume
	_update_value(Settings.master_volume)
	_slider.value_changed.connect(_on_slider)
	_wire_bus(_ui_slider, _ui_value, "UI")
	_wire_bus(_sfx_slider, _sfx_value, "SFX")
	_wire_bus(_notif_slider, _notif_value, "Notification")
	_wire_bus(_music_slider, _music_value, "Musique")

	# Mode d'affichage (l'ordre des items correspond à l'enum de Settings : 0/1/2)
	_display.clear()
	_display.add_item("Fenêtré")
	_display.add_item("Plein écran")
	_display.add_item("Sans bordure")
	_display.selected = Settings.display_mode
	_display.item_selected.connect(_on_display_selected)

	# Résolution (s'applique en mode Fenêtré ; sans bordure/plein écran = taille de l'écran)
	_res.clear()
	for r in RESOLUTIONS:
		if r.x == 3440 and r.y == 1440:
			_res.add_item("%d × %d (Goat)" % [r.x, r.y])
		else:
			_res.add_item("%d × %d" % [r.x, r.y])
	_res.selected = maxi(RESOLUTIONS.find(Settings.resolution), 0)
	_res.item_selected.connect(func(i: int) -> void: Settings.set_resolution(RESOLUTIONS[i]))

	# Limite FPS
	_fps.clear()
	for label in FPS_LABELS:
		_fps.add_item(label)
	_fps.selected = maxi(FPS_VALUES.find(Settings.max_fps), 0)
	_fps.item_selected.connect(func(i: int) -> void: Settings.set_max_fps(FPS_VALUES[i]))

	# Graphismes : preset (l'ordre Low/Medium/Ultra/Custom = enum 0/1/2/3).
	_gfx.clear()
	_gfx.add_item("Low")
	_gfx.add_item("Medium")
	_gfx.add_item("Ultra")
	_gfx.add_item("Custom")
	_gfx.selected = Settings.graphics_preset
	_gfx.item_selected.connect(_on_preset_selected)
	# Options individuelles (modifiables une à une -> passe le preset en « Custom »).
	_wire_gfx_toggle(_lamp, "lamp")
	_wire_gfx_toggle(_wind, "wind")
	_wire_gfx_toggle(_smoke, "smoke")
	_wire_gfx_toggle(_reflect, "reflections")
	_wire_gfx_toggle(_shadows, "shadows")
	# Anticrénelage + échelle de rendu (listes déroulantes -> aussi « Custom » au changement).
	_msaa.clear()
	for label in MSAA_LABELS:
		_msaa.add_item(label)
	_msaa.item_selected.connect(_on_msaa_selected)
	_scale.clear()
	for label in SCALE_LABELS:
		_scale.add_item(label)
	_scale.item_selected.connect(_on_scale_selected)
	_refresh_gfx_toggles()
	# Cycle jour/nuit (décoché = toujours midi).
	_daynight.button_pressed = Settings.day_night_enabled
	_daynight.toggled.connect(func(on: bool) -> void: Settings.set_day_night_enabled(on))
	# Affichage des FPS (haut à droite).
	_fps_toggle.button_pressed = Settings.show_fps
	_fps_toggle.toggled.connect(func(on: bool) -> void: Settings.set_show_fps(on))

	_quit_game_btn.pressed.connect(_on_quit_game)
	_close_btn.pressed.connect(close)
	_update_res_enabled()

# Appelé par main.gd à l'ouverture en jeu : passe la réf au jeu + affiche "Quitter la partie".
func set_game(g: Node) -> void:
	_game = g
	if _quit_game_btn != null:
		_quit_game_btn.visible = g != null

func _on_quit_game() -> void:
	if _game == null or not _game.has_method("request_quit_to_menu"):
		return
	var g := _game
	close()  # ferme l'overlay options
	g.request_quit_to_menu()

func _on_display_selected(i: int) -> void:
	Settings.set_display_mode(i)
	_update_res_enabled()

# La résolution n'a de sens qu'en Fenêtré (0) : plein écran / sans bordure = taille de l'écran.
func _update_res_enabled() -> void:
	_res.disabled = Settings.display_mode != 0

# --- Graphismes : preset <-> options individuelles ---

func _on_preset_selected(i: int) -> void:
	Settings.set_graphics_preset(i)
	_refresh_gfx_toggles()   # un preset recalcule les options -> on reflète l'état sur les cases

func _wire_gfx_toggle(toggle: CheckButton, option: String) -> void:
	toggle.toggled.connect(_on_gfx_toggle.bind(option))

func _on_gfx_toggle(on: bool, option: String) -> void:
	Settings.set_gfx_option(option, on)
	_gfx.selected = Settings.graphics_preset   # le preset est passé en « Custom » -> l'afficher

func _on_msaa_selected(i: int) -> void:
	Settings.set_msaa(MSAA_VALUES[i])
	_gfx.selected = Settings.graphics_preset   # -> « Custom »

func _on_scale_selected(i: int) -> void:
	Settings.set_render_scale(SCALE_VALUES[i])
	_gfx.selected = Settings.graphics_preset   # -> « Custom »

# Reflète l'état courant de Settings sur toutes les options (sans déclencher leurs signaux).
func _refresh_gfx_toggles() -> void:
	_lamp.set_pressed_no_signal(Settings.lamp_lights_enabled)
	_wind.set_pressed_no_signal(Settings.wind_anim_enabled)
	_smoke.set_pressed_no_signal(Settings.smoke_enabled)
	_reflect.set_pressed_no_signal(Settings.reflections_enabled)
	_shadows.set_pressed_no_signal(Settings.shadows_enabled)
	_msaa.selected = maxi(MSAA_VALUES.find(Settings.msaa_3d), 0)
	_scale.selected = _closest_index(SCALE_VALUES, Settings.render_scale)

# Index de la valeur la plus proche de v (l'échelle issue d'un preset peut ne pas tomber pile sur un item).
func _closest_index(values: Array, v: float) -> int:
	var best := 0
	var best_d := INF
	for i in values.size():
		var d: float = absf(float(values[i]) - v)
		if d < best_d:
			best_d = d
			best = i
	return best

func _on_slider(v: float) -> void:
	Settings.set_master_volume(v)
	_update_value(v)

func _update_value(v: float) -> void:
	_value.text = "%d %%" % roundi(v * 100.0)

# Branche un slider de bus sur Settings : init depuis la valeur sauvegardée + maj du %.
func _wire_bus(slider: HSlider, value_label: Label, bus: String) -> void:
	var v: float = float(Settings.bus_volumes.get(bus, 1.0))
	slider.value = v
	value_label.text = "%d %%" % roundi(v * 100.0)
	slider.value_changed.connect(_on_bus_slider.bind(bus, value_label))

func _on_bus_slider(v: float, bus: String, value_label: Label) -> void:
	Settings.set_bus_volume(bus, v)
	value_label.text = "%d %%" % roundi(v * 100.0)

func close() -> void:
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
