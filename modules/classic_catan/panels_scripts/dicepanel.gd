extends PanelContainer

signal closed(result: Variant)

# Panneau flottant — affiche les 2 dés du dernier lancer.
# Layout : 0=TL  1=TR  2=ML  3=MR  4=BL  5=BR  6=Centre

const _DOT_COLOR  := Color(0.08, 0.09, 0.14)
const _DIE_SIZE   := 60.0
const _DOT_RADIUS := 6.0

const _ACTIVE_DOTS := {
	1: [6],
	2: [1, 4],
	3: [1, 6, 4],
	4: [0, 1, 4, 5],
	5: [0, 1, 6, 4, 5],
	6: [0, 1, 2, 3, 4, 5],
}

var _die1_dots: Array = []
var _die2_dots: Array = []
var _total_label: Label


func _ready() -> void:
	var t: Theme = load("res://ui/theme.tres")
	theme = t
	custom_minimum_size = Vector2(240, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	# ── Barre de titre ────────────────────────────────────────────────────────
	var title_bar := PanelContainer.new()
	title_bar.add_theme_stylebox_override("panel",
			t.get_stylebox("panel", "TitleBar").duplicate())
	var title_hbox := HBoxContainer.new()
	title_bar.add_child(title_hbox)

	var title_lbl := Label.new()
	title_lbl.text = "🎲  Dés"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_hbox.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(func() -> void: closed.emit(null))
	title_hbox.add_child(close_btn)

	vbox.add_child(title_bar)

	# ── Contenu : dé1  +  dé2  =  total ─────────────────────────────────────
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  16)
	margin.add_theme_constant_override("margin_top",    12)
	margin.add_theme_constant_override("margin_bottom", 12)
	vbox.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	hbox.add_child(_build_die_node(_die1_dots))
	hbox.add_child(_make_op_label("+"))
	hbox.add_child(_build_die_node(_die2_dots))
	hbox.add_child(_make_op_label("="))

	_total_label = Label.new()
	_total_label.text = "—"
	_total_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total_label.add_theme_font_size_override("font_size", 34)
	_total_label.custom_minimum_size = Vector2(50, 0)
	hbox.add_child(_total_label)

	# ── WindowMover (drag via la barre de titre) ──────────────────────────────
	var mover := WindowMover.new()
	add_child(mover)
	await get_tree().process_frame
	mover.setup(self, title_lbl, "dice_panel_float")


# Appelé par UIRegistry après instanciation.
func show_panel(params: Dictionary) -> void:
	_update_die(_die1_dots, params.get("d1", 1))
	_update_die(_die2_dots, params.get("d2", 1))
	_total_label.text = str(params.get("total", 2))


# ── Helpers visuels ───────────────────────────────────────────────────────────

func _make_op_label(txt: String) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	return lbl


func _build_die_node(dots_out: Array) -> Control:
	var container := Control.new()
	container.custom_minimum_size = Vector2(_DIE_SIZE, _DIE_SIZE)

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color                   = Color(0.96, 0.96, 0.97)
	bg_style.corner_radius_top_left     = 8
	bg_style.corner_radius_top_right    = 8
	bg_style.corner_radius_bottom_left  = 8
	bg_style.corner_radius_bottom_right = 8
	bg_style.border_color               = Color(0.50, 0.50, 0.56)
	bg_style.border_width_left   = 1
	bg_style.border_width_top    = 1
	bg_style.border_width_right  = 1
	bg_style.border_width_bottom = 1
	bg.add_theme_stylebox_override("panel", bg_style)
	container.add_child(bg)

	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color                   = _DOT_COLOR
	dot_style.corner_radius_top_left     = int(_DOT_RADIUS)
	dot_style.corner_radius_top_right    = int(_DOT_RADIUS)
	dot_style.corner_radius_bottom_left  = int(_DOT_RADIUS)
	dot_style.corner_radius_bottom_right = int(_DOT_RADIUS)

	var centers := _dot_slot_centers()
	for i in 7:
		var dot := Panel.new()
		dot.add_theme_stylebox_override("panel", dot_style)
		dot.size     = Vector2(_DOT_RADIUS * 2.0, _DOT_RADIUS * 2.0)
		dot.position = centers[i] - Vector2(_DOT_RADIUS, _DOT_RADIUS)
		dot.visible  = false
		container.add_child(dot)
		dots_out.append(dot)

	return container


func _dot_slot_centers() -> Array:
	const S := _DIE_SIZE
	const P := 14.0
	const C := S * 0.5
	return [
		Vector2(P,     P),      # 0  TL
		Vector2(S - P, P),      # 1  TR
		Vector2(P,     C),      # 2  ML
		Vector2(S - P, C),      # 3  MR
		Vector2(P,     S - P),  # 4  BL
		Vector2(S - P, S - P),  # 5  BR
		Vector2(C,     C),      # 6  Centre
	]


func _update_die(dots: Array, value: int) -> void:
	var active: Array = _ACTIVE_DOTS.get(value, [])
	for i in 7:
		dots[i].visible = active.has(i)
