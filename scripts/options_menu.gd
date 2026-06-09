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

# Résolutions proposées en mode Fenêtré (l'index du menu -> la taille).
const RESOLUTIONS := [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440,1440),
]
# Caps proposés (l'index du menu -> la valeur ; 0 = illimité).
const FPS_VALUES := [0, 30, 60, 120, 144, 240]
const FPS_LABELS := ["Illimité", "30", "60", "120", "144", "240"]

func _ready() -> void:
	layer = 128  # au-dessus du HUD et de tout le reste

	# Volume master
	_slider.value = Settings.master_volume
	_update_value(Settings.master_volume)
	_slider.value_changed.connect(_on_slider)

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

	_close_btn.pressed.connect(close)
	_update_res_enabled()

func _on_display_selected(i: int) -> void:
	Settings.set_display_mode(i)
	_update_res_enabled()

# La résolution n'a de sens qu'en Fenêtré (0) : plein écran / sans bordure = taille de l'écran.
func _update_res_enabled() -> void:
	_res.disabled = Settings.display_mode != 0

func _on_slider(v: float) -> void:
	Settings.set_master_volume(v)
	_update_value(v)

func _update_value(v: float) -> void:
	_value.text = "%d %%" % roundi(v * 100.0)

func close() -> void:
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
