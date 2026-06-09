class_name LampLight
extends OmniLight3D
## Flaque de lumière d'un lampadaire : un OmniLight TRÈS FAIBLE autour de la lampe, allumé la NUIT
## et éteint le JOUR (suit DayNight, comme l'ampoule émissive du shader lamp_glow).
##
## Tu n'as PAS à poser ce nœud toi-même : l'autoload LampLights le crée AUTOMATIQUEMENT sous tout
## mesh portant le shader lamp_glow (cf. lamp_lights.gd). Ce script ne gère que le comportement
## (position = posée par le spawner).
##
## Perf : sans ombre, invisible le jour (zéro coût), et coupé d'un bloc par
## Settings.lamp_lights_enabled. Réglage global de l'allure : édite les défauts ci-dessous.

@export var night_energy: float = 0.4          # intensité en pleine nuit (volontairement très faible)
@export var pool_range: float = 4.0            # portée (locale) -> taille du halo
@export var pool_color: Color = Color(1.0, 0.82, 0.45)  # blanc chaud

var _enabled := true

func _ready() -> void:
	omni_range = pool_range
	light_color = pool_color
	shadow_enabled = false  # ombres dynamiques = trop cher pour des dizaines de lampes
	_enabled = Settings.lamp_lights_enabled
	Settings.graphics_changed.connect(_on_graphics_changed)
	DayNight.cycle_changed.connect(_refresh)
	_refresh()

func _on_graphics_changed() -> void:
	_enabled = Settings.lamp_lights_enabled
	_refresh()

# Allumée uniquement la nuit (énergie ∝ obscurité) ET si le réglage l'autorise.
# Le jour, ou si désactivée -> invisible, donc aucun coût de rendu.
func _refresh() -> void:
	var night := clampf(1.0 - DayNight.day_factor, 0.0, 1.0)
	var on := _enabled and night > 0.01
	visible = on
	if on:
		light_energy = night_energy * night
