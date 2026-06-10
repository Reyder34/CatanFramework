extends Node
## Banderole de musique (autoload "MusicBanner") : un bandeau en haut à gauche qui se DÉROULE quand
## une nouvelle piste démarre (affiche son nom) avec ⏸/▶ et ⏭. Une poignée (▾/▴) la déroule/replie à
## la main. Présente partout (menu + jeu) ; se replie seule après quelques secondes.

const BANNER_W := 340.0
const BANNER_H := 40.0
const HANDLE_W := 70.0
const HANDLE_H := 16.0
const AUTOHIDE := 4.5
const SLIDE := 0.4

var _layer: CanvasLayer
var _root: Control
var _title: Label
var _pause_btn: Button
var _handle: Button
var _open := false
var _tween: Tween
var _timer: Timer

func _ready() -> void:
	if Net.is_relay:
		return  # process relais : pas d'UI
	_build()
	Music.track_changed.connect(_on_track_changed)
	Music.paused_changed.connect(_on_paused_changed)

func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 120  # au-dessus du HUD, sous le menu d'options (128) et les FPS (200)
	add_child(_layer)
	# Groupe coulissant (on anime son offset_top). Replié = bandeau au-dessus de l'écran, poignée visible.
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.offset_left = 12.0
	_root.offset_top = -BANNER_H
	_layer.add_child(_root)
	# Le bandeau.
	var banner := Panel.new()
	banner.position = Vector2.ZERO
	banner.size = Vector2(BANNER_W, BANNER_H)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE  # le fond laisse passer les clics ; les boutons captent
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.93)
	sb.set_corner_radius_all(8)
	banner.add_theme_stylebox_override("panel", sb)
	_root.add_child(banner)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 10.0
	hb.offset_right = -6.0
	hb.offset_top = 4.0
	hb.offset_bottom = -4.0
	hb.add_theme_constant_override("separation", 6)
	banner.add_child(hb)
	var note := Label.new()
	note.text = "♪"
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(note)
	_title = Label.new()
	_title.text = "♪"
	_title.clip_text = true
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_title)
	_pause_btn = _mk_button("⏸", _on_pause)
	hb.add_child(_pause_btn)
	hb.add_child(_mk_button("⏭", _on_skip))
	# La poignée (centrée sous le bandeau) : déroule/replie à la main.
	_handle = _mk_button("▾", _toggle)
	_handle.position = Vector2((BANNER_W - HANDLE_W) * 0.5, BANNER_H)
	_handle.size = Vector2(HANDLE_W, HANDLE_H)
	_root.add_child(_handle)
	# Repli automatique.
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_hide)
	add_child(_timer)

func _mk_button(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

func _on_track_changed(title: String) -> void:
	_title.text = title if title != "" else "♪"
	_show(true)

func _on_paused_changed(paused: bool) -> void:
	if _pause_btn != null:
		_pause_btn.text = "▶" if paused else "⏸"

func _on_pause() -> void:
	Music.toggle_pause()
	_kick()

func _on_skip() -> void:
	Music.skip()
	_kick()

func _toggle() -> void:
	if _open:
		_hide()
	else:
		_show(false)  # déroulé manuel -> reste ouvert jusqu'au repli manuel

func _show(auto_hide: bool) -> void:
	_open = true
	_handle.text = "▴"
	_slide(0.0)
	if auto_hide:
		_timer.start(AUTOHIDE)
	else:
		_timer.stop()

func _hide() -> void:
	_open = false
	_handle.text = "▾"
	_slide(-BANNER_H)
	_timer.stop()

# Prolonge le repli auto quand on interagit (sans annuler un déroulé manuel).
func _kick() -> void:
	if _timer.time_left > 0.0:
		_timer.start(AUTOHIDE)

func _slide(target: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(_root, "offset_top", target, SLIDE)
