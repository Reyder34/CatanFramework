extends CanvasLayer
## Panneau de debug météo (F8) — actif UNIQUEMENT en build debug (lancement depuis le moteur).
## Autoload : présent dans le menu ET en jeu, sans câblage par scène.
##
## Coche "Pilotage manuel" (ou clique un preset) pour figer la météo et la régler aux sliders ;
## décoche pour reprendre la météo automatique (synchronisée en multi).

var _panel: PanelContainer
var _chk: CheckBox
var _wind: HSlider
var _humid: HSlider
var _temp: HSlider
var _wind_val: Label
var _humid_val: Label
var _temp_val: Label
var _state_lbl: Label
var _time_chk: CheckBox
var _time: HSlider
var _time_val: Label

func _ready() -> void:
	if not OS.is_debug_build():   # rien en build release
		set_process(false)
		set_process_input(false)
		return
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS   # fonctionne même si l'arbre est en pause
	_build_ui()
	visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		visible = not visible
		get_viewport().set_input_as_handled()

func _process(_dt: float) -> void:
	if not visible:
		return
	if not Weather.debug_override:   # en auto, les sliders suivent les valeurs vivantes
		_wind.set_value_no_signal(Weather.wind)
		_humid.set_value_no_signal(Weather.humidity)
		_temp.set_value_no_signal(Weather.temperature)
	_wind_val.text = "%.2f" % Weather.wind
	_humid_val.text = "%.2f" % Weather.humidity
	_temp_val.text = "%.2f" % Weather.temperature
	_state_lbl.text = "État : %s\nnuageux %.2f   pluie %.2f\nneige %.2f   tempête %.2f\néclair %.2f" % [
		Weather.state, Weather.sky_cloudy(), Weather.sky_rain(),
		Weather.sky_snow(), Weather.sky_storm(), Weather._lightning]
	# Heure : en auto le slider suit le cycle ; en manuel il est piloté à la main.
	if not DayNight.debug_time_override:
		_time.set_value_no_signal(fposmod(DayNight.time_of_day * 24.0 + 12.0, 24.0))
	var tmin := int(round(_time.value * 60.0)) % 1440
	_time_val.text = "%02d:%02d" % [tmin / 60, tmin % 60]

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 16)
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_panel.add_child(vb)

	var title := Label.new()
	title.text = "Météo (debug) — F8"
	vb.add_child(title)

	_chk = CheckBox.new()
	_chk.text = "Pilotage manuel"
	_chk.toggled.connect(_on_override)
	vb.add_child(_chk)

	var rw := _add_slider(vb, "Vent")
	_wind = rw[0]
	_wind_val = rw[1]
	var rh := _add_slider(vb, "Humidité")
	_humid = rh[0]
	_humid_val = rh[1]
	var rt := _add_slider(vb, "Température")
	_temp = rt[0]
	_temp_val = rt[1]
	_wind.value_changed.connect(_on_wind)
	_humid.value_changed.connect(_on_humid)
	_temp.value_changed.connect(_on_temp)

	var presets := HBoxContainer.new()
	vb.add_child(presets)
	_add_preset(presets, "Clair", 0.20, 0.30, 0.50)
	_add_preset(presets, "Pluie", 0.30, 0.85, 0.50)
	_add_preset(presets, "Tempête", 0.85, 0.85, 0.50)
	_add_preset(presets, "Neige", 0.20, 0.70, 0.02)

	_state_lbl = Label.new()
	vb.add_child(_state_lbl)

	var hint := Label.new()
	hint.text = "Décoche \"Pilotage manuel\" pour reprendre la météo auto."
	hint.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(hint)

	# --- Heure du jour (cycle jour/nuit) : pour tester toutes les heures (ciel + soleil + lampes) ---
	_time_chk = CheckBox.new()
	_time_chk.text = "Heure manuelle"
	_time_chk.toggled.connect(_on_time_override)
	vb.add_child(_time_chk)
	var thb := HBoxContainer.new()
	vb.add_child(thb)
	var tlbl := Label.new()
	tlbl.text = "Heure"
	tlbl.custom_minimum_size = Vector2(88, 0)
	thb.add_child(tlbl)
	_time = HSlider.new()
	_time.min_value = 0.0
	_time.max_value = 24.0
	_time.step = 0.25
	_time.editable = false
	_time.custom_minimum_size = Vector2(170, 0)
	_time.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_time.value_changed.connect(_on_time_slider)
	thb.add_child(_time)
	_time_val = Label.new()
	_time_val.text = "12:00"
	_time_val.custom_minimum_size = Vector2(42, 0)
	thb.add_child(_time_val)

	_on_override(false)   # départ en auto : sliders verrouillés

func _add_slider(parent: VBoxContainer, txt: String) -> Array:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var lbl := Label.new()
	lbl.text = txt
	lbl.custom_minimum_size = Vector2(88, 0)
	hb.add_child(lbl)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.custom_minimum_size = Vector2(170, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(s)
	var val := Label.new()
	val.text = "0.00"
	val.custom_minimum_size = Vector2(42, 0)
	hb.add_child(val)
	return [s, val]

func _add_preset(parent: HBoxContainer, txt: String, w: float, h: float, t: float) -> void:
	var b := Button.new()
	b.text = txt
	b.pressed.connect(_apply_preset.bind(w, h, t))
	parent.add_child(b)

func _apply_preset(w: float, h: float, t: float) -> void:
	_chk.button_pressed = true   # -> _on_override(true) : override actif + sliders éditables
	Weather.wind = w
	Weather.humidity = h
	Weather.temperature = t
	_wind.set_value_no_signal(w)
	_humid.set_value_no_signal(h)
	_temp.set_value_no_signal(t)

func _on_override(on: bool) -> void:
	Weather.debug_override = on
	_wind.editable = on
	_humid.editable = on
	_temp.editable = on

func _on_wind(v: float) -> void:
	if Weather.debug_override:
		Weather.wind = v

func _on_humid(v: float) -> void:
	if Weather.debug_override:
		Weather.humidity = v

func _on_temp(v: float) -> void:
	if Weather.debug_override:
		Weather.temperature = v

func _on_time_override(on: bool) -> void:
	_time.editable = on
	if on:
		_apply_time()
	else:
		DayNight.clear_debug_time()

func _on_time_slider(_v: float) -> void:
	if _time_chk.button_pressed:
		_apply_time()

# Heure du slider (0..24 h) -> time_of_day (0=midi, .25=coucher, .5=minuit, .75=lever).
func _apply_time() -> void:
	DayNight.set_debug_time(fposmod((_time.value - 12.0) / 24.0, 1.0))
