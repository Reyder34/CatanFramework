extends Node
## Compteur de FPS optionnel (autoload "FpsCounter") : un label en HAUT À DROITE, au-dessus de
## tout (menu + jeu + options), affiché selon Settings.show_fps. Mis à jour chaque frame.

var _layer: CanvasLayer
var _label: Label

func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 200  # au-dessus du HUD et du menu d'options (128)
	add_child(_layer)
	_label = Label.new()
	# Ancrage explicite en haut à droite (set_anchors_preset seul est peu fiable).
	_label.anchor_left = 1.0
	_label.anchor_right = 1.0
	_label.anchor_top = 0.0
	_label.anchor_bottom = 0.0
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.offset_left = -130.0
	_label.offset_right = -10.0
	_label.offset_top = 6.0
	_label.offset_bottom = 34.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # ne bloque pas les clics dessous
	# Lisibilité sur n'importe quel fond : texte blanc + contour noir.
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 4)
	_layer.add_child(_label)
	_layer.visible = Settings.show_fps

func _process(_delta: float) -> void:
	if _layer.visible != Settings.show_fps:
		_layer.visible = Settings.show_fps
	if _layer.visible:
		_label.text = "%d FPS" % Engine.get_frames_per_second()
