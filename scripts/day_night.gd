extends Node
## Cycle jour/nuit GLOBAL (autoload "DayNight") — pilote le SOLEIL (arc EST->midi->OUEST, donc les
## ombres balayent est-ouest), la LUNE (faible lumière blanche la nuit) et l'ambiance. Accordé au ciel.
## Globals shader : day_night_time (0..1, lue par sky.gdshader + anims modèles) + day_night_factor (1=jour).
## main.gd lit sun_direction / sun_energy / sun_color / moon_energy / ambient_* pour piloter les lampes.

signal cycle_changed

@export var cycle_seconds: float = 1200.0  # défaut ; réglé par scène (menu=120, jeu=1200). À garder = au cycle_duration du ciel
@export var paused: bool = false
@export_range(0.0, 1.0) var time_of_day: float = 0.0  # 0=midi .25=coucher .5=minuit .75=lever

# Couleurs / énergies (réglables).
const DAY_COLOR := Color(1.0, 0.97, 0.90)     # soleil au zénith (blanc chaud)
const DUSK_COLOR := Color(1.0, 0.40, 0.13)    # soleil à l'horizon (orangé soutenu)
const DAY_AMBIENT := Color(0.62, 0.70, 0.85)  # ambiance de jour
const NIGHT_AMBIENT := Color(0.10, 0.14, 0.30)# ambiance de nuit (bleu sombre)
const SUN_ENERGY := 1.4       # énergie du soleil à midi
const MOON_ENERGY := 0.13     # énergie de la lune (très faible)
const SUN_TILT_Z := 0.30      # léger décalage nord-sud de l'arc (ombres pas pile E-O)

var day_factor: float = 1.0                       # 0 = nuit, 1 = plein jour
var sun_direction: Vector3 = Vector3(0, -1, 0)    # direction de la LUMIÈRE du soleil
var sun_color: Color = DAY_COLOR
var sun_energy: float = SUN_ENERGY
var moon_energy: float = 0.0
var ambient_color: Color = DAY_AMBIENT
var ambient_energy: float = 0.3

func _ready() -> void:
	_recompute()

func _process(_delta: float) -> void:
	# Miroir du ciel : même base de temps que sky.gdshader (fract(TIME / cycle_duration)).
	if not paused and cycle_seconds > 0.0:
		time_of_day = fposmod(Time.get_ticks_msec() / 1000.0 / cycle_seconds, 1.0)
	_recompute()

func _recompute() -> void:
	# Arc du soleil : lever EST (+X) -> midi (zénith +Y) -> coucher OUEST (-X).
	# theta : midi à time=0 (sin=1), coucher à .25 (-X), minuit à .5 (sous l'horizon), lever à .75 (+X).
	var theta := PI * 0.5 + time_of_day * TAU
	var to_sun := Vector3(cos(theta), sin(theta), SUN_TILT_Z).normalized()  # direction VERS le soleil
	sun_direction = -to_sun                                                  # direction de la LUMIÈRE
	var elev := to_sun.y                                                     # hauteur du soleil (-1..1)

	# Intensité : monte jusqu'à midi, redescend jusqu'au coucher, 0 sous l'horizon.
	day_factor = smoothstep(-0.05, 0.25, elev)
	sun_energy = SUN_ENERGY * clampf(elev, 0.0, 1.0)
	# Couleur : orangé au ras de l'horizon (lever/coucher), blanc chaud au zénith.
	sun_color = DUSK_COLOR.lerp(DAY_COLOR, smoothstep(0.0, 0.58, elev))  # orangé plus longtemps

	# Lune : faible lumière blanche quand le soleil est couché.
	moon_energy = MOON_ENERGY * (1.0 - day_factor)

	# Ambiance (remplissage anti-noir) : claire le jour, sombre bleutée la nuit.
	ambient_color = NIGHT_AMBIENT.lerp(DAY_AMBIENT, day_factor)
	ambient_energy = lerpf(0.10, 0.35, day_factor)

	# Globals shader (ciel + anims de modèles 3D).
	RenderingServer.global_shader_parameter_set(&"day_night_time", time_of_day)
	RenderingServer.global_shader_parameter_set(&"day_night_factor", day_factor)
	cycle_changed.emit()
