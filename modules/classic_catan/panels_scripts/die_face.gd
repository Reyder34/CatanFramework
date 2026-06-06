extends Control

# Une face de dé — fond blanc arrondi (StyleBoxFlat) + points circulaires.

var value: int = 0
var _style: StyleBoxFlat


func _ready() -> void:
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.97, 0.97, 0.97)
	_style.corner_radius_top_left     = 8
	_style.corner_radius_top_right    = 8
	_style.corner_radius_bottom_left  = 8
	_style.corner_radius_bottom_right = 8
	_style.border_color        = Color(0.50, 0.50, 0.56)
	_style.border_width_left   = 1
	_style.border_width_top    = 1
	_style.border_width_right  = 1
	_style.border_width_bottom = 1


func set_value(v: int) -> void:
	value = clampi(v, 0, 6)
	queue_redraw()


func _draw() -> void:
	if _style == null:
		return
	var s := size
	_style.draw(get_canvas_item(), Rect2(Vector2.ZERO, s))

	if value < 1:
		return

	var r   := minf(s.x, s.y) * 0.12
	var col := Color(0.08, 0.09, 0.14)
	var xs  := [s.x * 0.27, s.x * 0.5, s.x * 0.73]
	var ys  := [s.y * 0.27, s.y * 0.5, s.y * 0.73]

	var pips: Array = []
	match value:
		1: pips = [Vector2(xs[1], ys[1])]
		2: pips = [Vector2(xs[2], ys[0]), Vector2(xs[0], ys[2])]
		3: pips = [Vector2(xs[2], ys[0]), Vector2(xs[1], ys[1]), Vector2(xs[0], ys[2])]
		4: pips = [Vector2(xs[0], ys[0]), Vector2(xs[2], ys[0]), Vector2(xs[0], ys[2]), Vector2(xs[2], ys[2])]
		5: pips = [Vector2(xs[0], ys[0]), Vector2(xs[2], ys[0]), Vector2(xs[1], ys[1]), Vector2(xs[0], ys[2]), Vector2(xs[2], ys[2])]
		6: pips = [Vector2(xs[0], ys[0]), Vector2(xs[2], ys[0]), Vector2(xs[0], ys[1]), Vector2(xs[2], ys[1]), Vector2(xs[0], ys[2]), Vector2(xs[2], ys[2])]

	for p in pips:
		draw_circle(p, r, col)
