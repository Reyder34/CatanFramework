class_name HexMath
extends RefCounted

const HEX_SIZE := 1.0
const TILE_HEIGHT := 0.2

const NEIGHBOR_OFFSETS := [
	Vector2(1, 0),   # E
	Vector2(0, 1),   # SE
	Vector2(-1, 1),  # SW
	Vector2(-1, 0),  # W
	Vector2(0, -1),  # NW
	Vector2(1, -1)   # NE
]

static func hex_to_world(q: int, r: int) -> Vector3:
	var x := HEX_SIZE * sqrt(3.0) * (q + r / 2.0)
	var z := HEX_SIZE * 1.5 * r
	return Vector3(x, 0, z)

static func vertex_position(q: int, r: int, corner: int) -> Vector3:
	var center := hex_to_world(q, r)
	var angle := deg_to_rad(60.0 * corner + 30.0)
	return Vector3(
		center.x + HEX_SIZE * cos(angle),
		TILE_HEIGHT / 2 + 0.05,
		center.z + HEX_SIZE * sin(angle)
	)

static func edge_position(q: int, r: int, side: int) -> Vector3:
	var center := hex_to_world(q, r)
	var a1 := deg_to_rad(60.0 * side - 30.0)
	var a2 := deg_to_rad(60.0 * side + 30.0)
	var mx := (cos(a1) + cos(a2)) / 2.0
	var mz := (sin(a1) + sin(a2)) / 2.0
	return Vector3(center.x + HEX_SIZE * mx, TILE_HEIGHT / 2 + 0.05, center.z + HEX_SIZE * mz)

static func edge_rotation(side: int) -> float:
	return deg_to_rad(-90.0 - 60.0 * side)

static func vertex_key(trio: Array) -> String:
	trio.sort_custom(func(a, b):
		if a.x != b.x: return a.x < b.x
		return a.y < b.y
	)
	return "%s,%s|%s,%s|%s,%s" % [
		trio[0].x, trio[0].y, trio[1].x, trio[1].y, trio[2].x, trio[2].y
	]

static func edge_key(a: Vector2, b: Vector2) -> String:
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		var tmp := a
		a = b
		b = tmp
	return "%s,%s|%s,%s" % [a.x, a.y, b.x, b.y]
