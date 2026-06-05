class_name PlacedBuilding
extends RefCounted

var building_type: BuildingType
var key: String       # vertex_key ou edge_key
var target: String    # "vertex" ou "edge"

func _init(p_building_type: BuildingType = null, p_key: String = "", p_target: String = "") -> void:
	building_type = p_building_type
	key = p_key
	target = p_target

func victory_points() -> int:
	if building_type == null:
		return 0
	return building_type.victory_points
