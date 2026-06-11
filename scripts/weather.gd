extends Node
## Météo GLOBALE (autoload "Weather"), SYNCHRONISÉE en multi via un SEED (comme le plateau).
## Les trois valeurs 0..1 (vent, humidité, température) sont des fonctions DÉTERMINISTES de
## (seed + temps). Même seed + même horloge -> même météo chez tous. L'état en découle.
##
## Sync multi : main.gd appelle Weather.set_seed(GameConfig.game_seed) (identique chez tous).
## Le temps vient de l'horloge système (get_unix_time_from_system, grossièrement synchronisée par
## NTP) -> météo identique à quelques secondes près (cosmétique), et ça gère le rejoin (même horloge).
##
## Règles :
##   humidité > 0.7                        -> pluie
##   vent > 0.7  ET  humidité > 0.7        -> tempête
##   température < 0.1  ET  humidité > 0.5 -> neige
##   sinon                                 -> clair

signal weather_changed(state: String)   # "clear" / "rain" / "storm" / "snow"

# Les trois valeurs (0..1), recalculées chaque frame depuis (seed + temps).
var wind := 0.3
var humidity := 0.4
var temperature := 0.5
var state := "clear"

const WIND_PUSH := 0.4         # poussée horizontale max de la fumée (à vent = 1)
const EPOCH := 1735689600.0    # 2025-01-01 : retranché pour garder le temps petit (précision)
const F := [0.0262, 0.0698, 0.1698]   # fréquences des octaves (~ périodes 240 / 90 / 37 s)
const AMP := [0.32, 0.13, 0.05]
const DIR_ROT := 0.015         # vitesse de rotation de la direction du vent (rad/s)

var _rng := RandomNumberGenerator.new()
var _ph: Array = []   # 4 canaux (0=vent, 1=humidité, 2=température, 3=direction) -> [p0, p1, p2]
var _lightning := 0.0   # éclair (frappe à des secondes synchronisées, déclin local fluide)
var _last_sec := -1
var debug_override := false   # panneau debug (F8) : fige les valeurs et les pilote à la main
var _cloud_phase := 0.0   # phase de défilement météo des nuages (intégrée -> aucun à-coup vers 0.70)
var _rain_phase := 0.0    # idem pour la chute de pluie

func _ready() -> void:
	set_seed(0)   # défaut (menu) : aléatoire ; le jeu re-seedera via main.gd

# Fixe la graine. 0 -> aléatoire (solo / menu) ; sinon déterministe (multi : le même seed partout).
func set_seed(s: int) -> void:
	if s == 0:
		_rng.randomize()
	else:
		_rng.seed = s
	_ph = []
	for ch in 4:
		_ph.append([_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU])
	_update(_now())

func _process(delta: float) -> void:
	_update(_now())
	_update_lightning(delta)
	# Défilement météo INTÉGRÉ côté CPU (mêmes coefs que le shader) : changer la vitesse n'altère pas
	# la distance déjà parcourue. Sinon TIME × vitesse-qui-change fait "sauter" nuages/pluie vers 0.70.
	_cloud_phase += delta * (sky_rain() * 0.15 + sky_storm() * 0.2)
	_rain_phase += delta * ((12.0 + sky_storm() * 6.0) * (1.0 - sky_snow() * 0.6) - 12.0)
	# Params GLOBAUX pour les surcouches de TUILES (comme day_night_factor) :
	#   - neige  : couche blanche sur le dessus des cases
	#   - mouillé : voile sombre pour la pluie, mais COUPÉ pendant la neige (×(1-neige)) -> sous la
	#     neige il ne reste que l'overlay neige (la pluie continue, elle, dans le ciel).
	RenderingServer.global_shader_parameter_set(&"weather_snow", sky_snow())
	RenderingServer.global_shader_parameter_set(&"weather_wet", clampf(sky_rain() + sky_storm(), 0.0, 1.0) * (1.0 - sky_snow()))

func _now() -> float:
	return Time.get_unix_time_from_system() - EPOCH

func _update(t: float) -> void:
	if not debug_override:   # en pilotage manuel (debug), on ne recalcule pas les valeurs
		wind = _channel(0, t)
		humidity = _channel(1, t)
		temperature = _channel(2, t)
	_recompute_state()

# Valeur 0..1 déterministe d'un canal au temps t (somme d'octaves sinus, phases issues du seed).
func _channel(ch: int, t: float) -> float:
	var p: Array = _ph[ch]
	var v := 0.5
	for i in 3:
		v += AMP[i] * sin(t * F[i] + p[i])
	return clampf(v, 0.0, 1.0)

# Vecteur de vent horizontal pour la fumée : direction (déterministe, tourne) × force (`wind`).
func wind_vector() -> Vector3:
	var ang: float = _now() * DIR_ROT
	if _ph.size() > 3:
		ang += float(_ph[3][0])
	return Vector3(cos(ang), 0.0, sin(ang)) * wind * WIND_PUSH

func _recompute_state() -> void:
	var s := "clear"
	if temperature < 0.1 and humidity > 0.5:
		s = "snow"
	elif wind > 0.7 and humidity > 0.7:
		s = "storm"
	elif humidity > 0.7:
		s = "rain"
	if s != state:
		state = s
		weather_changed.emit(s)

# === MÉTÉO -> CIEL (shader sky.gdshader) ===
# Influences 0..1 dérivées DIRECTEMENT des valeurs -> lisses + synchronisées (aucun easing local).
func sky_cloudy() -> float:
	return smoothstep(0.45, 0.72, humidity)

# La neige coupe la TEMPÊTE (pas de tempête pendant la neige), MAIS pas la pluie du ciel : le shader
# `sky` garde sa précipitation (rendue blanche -> neige qui tombe). L'overlay MOUILLÉ des tuiles, lui,
# est coupé pendant la neige (voir weather_wet dans _process) -> sur les cases, seule la neige reste.
func sky_rain() -> float:
	return smoothstep(0.68, 0.78, humidity)

func sky_snow() -> float:
	return (1.0 - smoothstep(0.04, 0.12, temperature)) * smoothstep(0.45, 0.55, humidity)

func sky_storm() -> float:
	return smoothstep(0.68, 0.78, wind) * smoothstep(0.68, 0.78, humidity) * (1.0 - sky_snow())

# Pose les uniformes météo sur un matériau de ciel (appelé chaque frame par main.gd / menu_background).
func apply_sky(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("meteo_nuageux", sky_cloudy())
	mat.set_shader_parameter("meteo_pluie", sky_rain())
	mat.set_shader_parameter("meteo_neige", sky_snow())
	mat.set_shader_parameter("meteo_tempete", sky_storm())
	mat.set_shader_parameter("lightning_flash", _lightning)
	mat.set_shader_parameter("weather_cloud_phase", _cloud_phase)
	mat.set_shader_parameter("weather_rain_phase", _rain_phase)

# Éclair : frappe à des SECONDES déterministes (donc synchronisées) pendant la tempête ; déclin local.
func _update_lightning(delta: float) -> void:
	_lightning = maxf(0.0, _lightning - delta * 4.0)
	if sky_storm() <= 0.3:
		return
	var sec := int(_now())
	if sec != _last_sec:
		_last_sec = sec
		var h := sin(float(sec) * 12.9898) * 43758.5453   # hash 0..1 déterministe par seconde
		h -= floor(h)
		if h > 0.88:
			_lightning = 1.0
