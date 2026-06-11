extends Node3D

# Natural sheep animation: steering-based random walk + graze + night barn
# Attach to root "Sheep" node of sheep.tscn

# Movement
const WALK_SPEED  := 0.055
const TURN_SPEED  := 5.0
const BOB_FREQ    := 7.0
const BOB_AMP     := 0.005
const GRAZE_PROB  := 0.35

# State timers
const IDLE_MIN  := 0.8;   const IDLE_MAX  := 2.5
const WALK_MIN  := 1.0;   const WALK_MAX  := 2.8
const GRAZE_MIN := 1.5;   const GRAZE_MAX := 3.5

# Hard clamp (absolute last resort)
const P_XMIN := -0.68;  const P_XMAX := 0.70
const P_YMIN := -0.62;  const P_YMAX := 0.28

# Fence segments: pairs of posts (Pivot XY). Sheep are pushed away from these.
const FENCE_SEGS := [
	[Vector2(-0.664,  0.025), Vector2(-0.588, -0.251)],
	[Vector2(-0.588, -0.251), Vector2(-0.403, -0.469)],
	[Vector2(-0.403, -0.469), Vector2(-0.143, -0.589)],
	[Vector2(-0.143, -0.589), Vector2( 0.143, -0.589)],
	[Vector2( 0.143, -0.589), Vector2( 0.403, -0.469)],
	[Vector2( 0.403, -0.469), Vector2( 0.588, -0.251)],
	[Vector2( 0.588, -0.251), Vector2( 0.664,  0.025)],
	# Top "walls" connecting fence ends to barn sides
	[Vector2(-0.664,  0.025), Vector2(-0.50,   0.28)],
	[Vector2( 0.664,  0.025), Vector2( 0.50,   0.28)],
]
const FENCE_AVOID_R  := 0.13   # soft repulsion radius from fence

# Obstacle avoidance
const BARN_XY      := Vector2(-0.3, 0.34)
const BARN_AVOID_R := 0.22
const SEPARATION_R := 0.14

# How strongly steering overrides walk intent
const STEER_STRENGTH := 3.0

# Day/night
const NIGHT_THRESH := 0.40
const DAY_THRESH   := 0.55

enum SheepState { IDLE, WALKING, GRAZING }

var _pivot: Node3D
var _animals:       Array[Node3D]  = []
var _z_scales:      Array[float]   = []
var _heads:         Array[Node3D]  = []
var _day_pos:       Array[Vector3] = []
var _angle:         Array[float]   = []
var _target_angle:  Array[float]   = []
var _state:         Array[int]     = []
var _timer:         Array[float]   = []
var _walk_dir:      Array[Vector2] = []
var _bob_phase:     Array[float]   = []

var _barn_pos:    Vector3
var _night_blend: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_pivot = get_node_or_null("Pivot")
	if _pivot == null:
		return

	for aname in ["Sheep_1", "Sheep_2", "Sheep_3", "Lamb"]:
		var n: Node3D = _pivot.get_node_or_null(aname)
		if n == null:
			continue
		_animals.append(n)
		_day_pos.append(n.position)
		_z_scales.append(n.transform.basis.get_scale().z)
		var bx: Vector3 = n.transform.basis.x
		var init_angle := atan2(bx.y, bx.x)
		_angle.append(init_angle)
		_target_angle.append(init_angle)
		_heads.append(n.get_node_or_null("head"))
		_state.append(SheepState.IDLE)
		_timer.append(_rng.randf_range(0.0, 1.0))
		_walk_dir.append(_random_dir())
		_bob_phase.append(_rng.randf() * TAU)

	var barn: Node3D = _pivot.get_node_or_null("Barn")
	_barn_pos = barn.position if barn else Vector3(-0.3, 0.34, 0.0)

	if _day_factor() < NIGHT_THRESH:
		_night_blend = 1.0
		_snap_to_barn()

func _process(delta: float) -> void:
	if _pivot == null or _animals.is_empty():
		return

	var df    := _day_factor()
	var t_sec := Time.get_ticks_msec() / 1000.0

	# Night blend
	var target_blend := 0.0
	if df <= NIGHT_THRESH:
		target_blend = 1.0
	elif df < DAY_THRESH:
		target_blend = 1.0 - (df - NIGHT_THRESH) / (DAY_THRESH - NIGHT_THRESH)
	_night_blend = move_toward(_night_blend, target_blend, delta * 0.7)

	for i in _animals.size():
		_tick(i, delta, t_sec)

func _tick(i: int, delta: float, t: float) -> void:
	var animal := _animals[i]
	_timer[i] -= delta

	match _state[i]:
		SheepState.IDLE:
			if _timer[i] <= 0.0:
				if _rng.randf() < GRAZE_PROB:
					_state[i] = SheepState.GRAZING
					_timer[i] = _rng.randf_range(GRAZE_MIN, GRAZE_MAX)
				else:
					_state[i] = SheepState.WALKING
					_timer[i] = _rng.randf_range(WALK_MIN, WALK_MAX)
					_walk_dir[i] = _random_dir()
					_target_angle[i] = atan2(_walk_dir[i].y, _walk_dir[i].x)

		SheepState.WALKING:
			# Compute steering forces
			var steer := _steering(i)
			# Blend walk intent with steering
			var desired := (_walk_dir[i] + steer * STEER_STRENGTH).normalized()
			_target_angle[i] = atan2(desired.y, desired.x)

			# Smooth turn
			_angle[i] = _lerp_angle(_angle[i], _target_angle[i], TURN_SPEED * delta)

			# Advance
			var dir := Vector2(cos(_angle[i]), sin(_angle[i]))
			var next := _day_pos[i] + Vector3(dir.x, dir.y, 0.0) * WALK_SPEED * delta
			# Hard clamp only as last resort
			next.x = clampf(next.x, P_XMIN + 0.05, P_XMAX - 0.05)
			next.y = clampf(next.y, P_YMIN + 0.05, P_YMAX - 0.05)
			_day_pos[i] = next

			# Body bob + tilt
			var bob   := sin(t * BOB_FREQ + _bob_phase[i]) * BOB_AMP
			var tilt  := Basis(Vector3(1, 0, 0), 0.035 * sin(t * BOB_FREQ + _bob_phase[i]))
			var final_pos := _day_pos[i] + Vector3(0, 0, bob)
			final_pos = final_pos.lerp(_barn_entry_pos(i), _stagger_blend(i))
			animal.visible = _stagger_blend(i) < 0.95
			animal.position = final_pos
			animal.transform.basis = _make_basis(_angle[i], _z_scales[i]) * tilt

			if _timer[i] <= 0.0:
				_state[i] = SheepState.IDLE
				_timer[i] = _rng.randf_range(IDLE_MIN, IDLE_MAX)
			return

		SheepState.GRAZING:
			if _heads[i] != null:
				_heads[i].rotation.y = 0.25 * sin(t * 0.4 + _bob_phase[i])
			if _timer[i] <= 0.0:
				if _heads[i] != null:
					_heads[i].rotation.y = 0.0
				_state[i] = SheepState.IDLE
				_timer[i] = _rng.randf_range(IDLE_MIN, IDLE_MAX)

	# Default position apply (IDLE / GRAZING)
	var final_pos := _day_pos[i].lerp(_barn_entry_pos(i), _stagger_blend(i))
	animal.visible = _stagger_blend(i) < 0.95
	animal.position = final_pos

# Returns steering force pushing this sheep away from obstacles
func _steering(i: int) -> Vector2:
	var pos := Vector2(_day_pos[i].x, _day_pos[i].y)
	var force := Vector2.ZERO

	# Separation from other sheep
	for j in _animals.size():
		if j == i:
			continue
		var other := Vector2(_day_pos[j].x, _day_pos[j].y)
		var diff  := pos - other
		var dist  := diff.length()
		if dist < SEPARATION_R and dist > 0.001:
			force += diff.normalized() * (1.0 - dist / SEPARATION_R)

	# Fence segment repulsion
	for seg in FENCE_SEGS:
		var closest := _closest_on_segment(pos, seg[0], seg[1])
		var diff    := pos - closest
		var dist    := diff.length()
		if dist < FENCE_AVOID_R and dist > 0.001:
			force += diff.normalized() * (1.0 - dist / FENCE_AVOID_R)

	# Barn repulsion
	var to_barn   := pos - BARN_XY
	var barn_dist := to_barn.length()
	if barn_dist < BARN_AVOID_R and barn_dist > 0.001:
		force += to_barn.normalized() * (1.0 - barn_dist / BARN_AVOID_R)

	return force

# Returns the closest point on segment [a,b] to point p
func _closest_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var len_sq := ab.dot(ab)
	if len_sq < 0.00001:
		return a
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return a + ab * t

# ---- helpers ----

func _day_factor() -> float:
	return DayNight.day_factor if DayNight != null else 1.0

func _stagger_blend(i: int) -> float:
	return clampf(_night_blend * 1.3 - i * 0.07, 0.0, 1.0)

func _random_dir() -> Vector2:
	var a := _rng.randf_range(0.0, TAU)
	return Vector2(cos(a), sin(a))

func _lerp_angle(from: float, to: float, w: float) -> float:
	return from + _angle_diff(from, to) * minf(w, 1.0)

func _angle_diff(from: float, to: float) -> float:
	var d := fmod(to - from, TAU)
	if d >  PI: d -= TAU
	if d < -PI: d += TAU
	return d

func _make_basis(angle: float, z_scale: float) -> Basis:
	var c := cos(angle); var s := sin(angle)
	return Basis(Vector3(c, s, 0), Vector3(-s, c, 0), Vector3(0, 0, z_scale))

func _snap_to_barn() -> void:
	for i in _animals.size():
		_animals[i].position = _barn_entry_pos(i)
		_animals[i].visible  = false

func _barn_entry_pos(i: int) -> Vector3:
	var offsets := [Vector3(0.0,0.0,0.0), Vector3(-0.06,0.05,0.0),
					Vector3(0.05,0.07,0.0), Vector3(-0.03,-0.04,0.0)]
	return _barn_pos + (offsets[i] if i < offsets.size() else Vector3.ZERO)
