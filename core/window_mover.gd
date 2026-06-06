class_name WindowMover
extends Node

# Rend n'importe quel panneau (Control) DÉPLAÇABLE (via une poignée de titre) et
# REDIMENSIONNABLE (via une poignée en bas-droite), avec position + taille
# PERSISTÉES. Générique : utilisé par le HUD ET par les pop-ups (UIRegistry).
#
# Usage : créer un WindowMover, l'ajouter en enfant du panneau, puis setup().
#   var m := WindowMover.new(); panel.add_child(m)
#   m.setup(panel, handle, "id_unique")   # handle = la barre de titre (drag)
#
# La sauvegarde est partagée (un seul ConfigFile pour tous les panneaux) → le HUD
# et les pop-ups n'écrasent pas leurs positions respectives.

const LAYOUT_PATH := "user://hud_layout.cfg"
const MIN_SCALE := 0.6
const MAX_SCALE := 2.5

static var _cfg: ConfigFile = null  # partagé entre tous les movers

var _panel: Control
var _id: String
var _default: Dictionary = {}
var _dragging := false
var _grab := Vector2.ZERO
var _resizing := false
var _base := Vector2.ZERO
var _origin := Vector2.ZERO

static func _config() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(LAYOUT_PATH)  # ignore l'erreur si absent
	return _cfg

# Efface TOUTES les positions/tailles sauvegardées (pour un reset global, ex. F1).
static func forget_all() -> void:
	var cfg := _config()
	cfg.clear()
	cfg.save(LAYOUT_PATH)

func setup(panel: Control, handle: Control, id: String, resizable := true) -> void:
	_panel = panel
	_id = id
	_default = _capture(panel)  # ancrage d'origine (pour reset)
	if handle != null:
		handle.mouse_filter = Control.MOUSE_FILTER_STOP
		handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
		handle.tooltip_text = "Glisser pour déplacer"
		if not handle.gui_input.is_connected(_on_handle_input):
			handle.gui_input.connect(_on_handle_input)
	if resizable:
		_add_grip()
	_apply_saved()

# Ajoute une petite poignée de redimensionnement en bas-droite (dans le 1er VBox/HBox).
func _add_grip() -> void:
	var box := _first_box(_panel)
	if box == null:
		return
	var grip := ColorRect.new()
	grip.color = Color(1, 1, 1, 0.45)
	grip.custom_minimum_size = Vector2(14, 14)
	grip.size_flags_horizontal = Control.SIZE_SHRINK_END
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.tooltip_text = "Glisser pour redimensionner"
	grip.add_to_group("hud_resize")  # exempté du passe-clic du HUD
	grip.gui_input.connect(_on_grip_input)
	box.add_child(grip)

func _first_box(c: Node) -> BoxContainer:
	for ch in c.get_children():
		if ch is BoxContainer:
			return ch
		var f := _first_box(ch)
		if f != null:
			return f
	return null

func _apply_saved() -> void:
	var cfg := _config()
	if cfg.has_section_key("layout", _id):
		_free(cfg.get_value("layout", _id))
	if cfg.has_section_key("scale", _id):
		_panel.pivot_offset = Vector2.ZERO
		_panel.scale = Vector2.ONE * float(cfg.get_value("scale", _id))

# Positionnement libre (ancré haut-gauche, grandit vers le bas-droite).
func _free(pos: Vector2) -> void:
	_panel.anchor_left = 0.0; _panel.anchor_top = 0.0
	_panel.anchor_right = 0.0; _panel.anchor_bottom = 0.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	_panel.offset_left = pos.x
	_panel.offset_top = pos.y

func _on_handle_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		var gp: Vector2 = _panel.global_position
		_free(gp)
		_dragging = true
		_grab = gp - _panel.get_global_mouse_position()
		_panel.get_viewport().set_input_as_handled()

func _on_grip_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		var gp: Vector2 = _panel.global_position
		_free(gp)
		_panel.pivot_offset = Vector2.ZERO
		_resizing = true
		_base = _panel.size
		_origin = gp
		_panel.get_viewport().set_input_as_handled()

func _input(e: InputEvent) -> void:
	if _resizing:
		if e is InputEventMouseMotion:
			var m: Vector2 = _panel.get_global_mouse_position()
			var sx: float = (m.x - _origin.x) / maxf(40.0, _base.x)
			var sy: float = (m.y - _origin.y) / maxf(40.0, _base.y)
			_panel.scale = Vector2.ONE * clampf(maxf(sx, sy), MIN_SCALE, MAX_SCALE)
			_panel.get_viewport().set_input_as_handled()
		elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			_resizing = false
			_save("scale", _panel.scale.x)
			_save("layout", Vector2(_panel.offset_left, _panel.offset_top))
		return
	if _dragging:
		if e is InputEventMouseMotion:
			var p: Vector2 = _panel.get_global_mouse_position() + _grab
			var maxp: Vector2 = _panel.get_viewport_rect().size - _panel.size
			p.x = clampf(p.x, 0.0, maxf(0.0, maxp.x))
			p.y = clampf(p.y, 0.0, maxf(0.0, maxp.y))
			_free(p)
			_panel.get_viewport().set_input_as_handled()
		elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			_dragging = false
			_save("layout", Vector2(_panel.offset_left, _panel.offset_top))

func _save(section: String, value) -> void:
	var cfg := _config()
	cfg.set_value(section, _id, value)
	cfg.save(LAYOUT_PATH)

func _capture(c: Control) -> Dictionary:
	return {
		"al": c.anchor_left, "at": c.anchor_top, "ar": c.anchor_right, "ab": c.anchor_bottom,
		"ol": c.offset_left, "ot": c.offset_top, "ore": c.offset_right, "ob": c.offset_bottom,
		"gh": c.grow_horizontal, "gv": c.grow_vertical,
	}

# Restaure le panneau à son ancrage d'origine + échelle 1 (sans toucher au fichier).
func reset_visual() -> void:
	var d := _default
	_panel.anchor_left = d["al"]; _panel.anchor_top = d["at"]
	_panel.anchor_right = d["ar"]; _panel.anchor_bottom = d["ab"]
	_panel.offset_left = d["ol"]; _panel.offset_top = d["ot"]
	_panel.offset_right = d["ore"]; _panel.offset_bottom = d["ob"]
	_panel.grow_horizontal = d["gh"]; _panel.grow_vertical = d["gv"]
	_panel.scale = Vector2.ONE
	_panel.pivot_offset = Vector2.ZERO
