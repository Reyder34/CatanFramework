class_name YearOfPlentyCard
extends DevelopmentCard

func _init() -> void:
	id = "year_of_plenty"
	display_name = "Invention"
	description = "Reçois 2 ressources de ton choix dans la banque."

func on_play(state: GameState, board: Board, registry: GameRegistry, player: Player) -> bool:
	var result = await Net.show_panel_for(player.id, "resource_picker", {
		"max_count": 2,
		"title": "Invention",
		"prompt": "Choisis 2 ressources à recevoir",
		"allow_cancel": true,
	})
	if result == null or result.get("action") != "confirm":
		return false
	var selected: Dictionary = result["selected"]
	for res_id in selected:
		if selected[res_id] > 0:
			player.add_resource(res_id, selected[res_id])
	print("[Invention] J%d reçoit: %s" % [player.id, str(selected)])
	return true
