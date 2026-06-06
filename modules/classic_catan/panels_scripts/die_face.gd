extends Control

# Une face de dé dessinée avec des points (pips). set_value(1..6) la met à jour.
# Pas de class_name volontairement : référencée par preload() dans dice_panel.gd.

var value: int = 0

func set_value(v: int) -> void:
	value = clampi(v, 0, 6)
	queue_redraw()

func _draw() -> void:
	var s := size
	var body := Rect2(Vector2.ZERO, s)
	draw_rect(body, Color(0.96, 0.96, 0.92))               # corps blanc cassé
	draw_rect(body, Color(0.12, 0.12, 0.12), false, 2.0)   # contour
	if value < 1:
		return
	var r := minf(s.x, s.y) * 0.11                         # rayon d'un point
	var xs := [s.x * 0.27, s.x * 0.5, s.x * 0.73]
	var ys := [s.y * 0.27, s.y * 0.5, s.y * 0.73]
	var col := Color(0.12, 0.12, 0.12)
	var pips: Array = []
	match value:
		1: pips = [Vector2(xs[1], ys[1])]
		2: pips = [Vector2(xs[0], ys[0]), Vector2(xs[2], ys[2])]
		3: pips = [Vector2(xs[0], ys[0]), Vector2(xs[1], ys[1]), Vector2(xs[2], ys[2])]
		4: pips = [Vector2(xs[0], ys[0]), Vector2(xs[2], ys[0]), Vector2(xs[0], ys[2]), Vector2(xs[2], ys[2])]
		5: pips = [Vector2(xs[0], ys[0]), Vector2(xs[2], ys[0]), Vector2(xs[1], ys[1]), Vector2(xs[0], ys[2]), Vector2(xs[2], ys[2])]
		6: pips = [Vector2(xs[0], ys[0]), Vector2(xs[2], ys[0]), Vector2(xs[0], ys[1]), Vector2(xs[2], ys[1]), Vector2(xs[0], ys[2]), Vector2(xs[2], ys[2])]
	for p in pips:
		draw_circle(p, r, col)
