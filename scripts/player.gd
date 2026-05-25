class_name Player
extends RefCounted

var id: int
var color: Color
var resources := {
	"wood": 0, "brick": 0, "sheep": 0, "wheat": 0, "ore": 0
}
var settlements: Array = []  # liste de clés de sommets

func _init(p_id: int, p_color: Color) -> void:
	id = p_id
	color = p_color

func add_resource(res: String, amount: int = 1) -> void:
	if resources.has(res):
		resources[res] += amount

func describe() -> String:
	return "Joueur %d: bois=%d brique=%d mouton=%d blé=%d minerai=%d" % [
		id, resources["wood"], resources["brick"],
		resources["sheep"], resources["wheat"], resources["ore"]
	]
