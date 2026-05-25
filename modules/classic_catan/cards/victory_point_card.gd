class_name VictoryPointCard
extends DevelopmentCard

func _init() -> void:
	id = "victory_point"
	display_name = "Point de victoire"
	description = "Donne 1 point de victoire (caché jusqu'à la fin)."
	victory_points = 1
	is_passive = true
