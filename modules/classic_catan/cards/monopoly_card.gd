class_name MonopolyCard
extends DevelopmentCard

func _init() -> void:
	id = "monopoly"
	display_name = "Monopole"
	description = "Choisis une ressource. Tous les autres joueurs te donnent toute leur quantité."
	image = "truc"

func on_play(state: GameState, board: Board, registry: GameRegistry, player: Player) -> bool:
	var result = await Net.show_panel_for(player.id, "resource_picker", {
		"max_count": 1,
		"title": "Monopole",
		"prompt": "Choisis la ressource à monopoliser",
		"allow_cancel": true,
	})
	if result == null or result.get("action") != "confirm":
		return false
	var selected: Dictionary = result["selected"]
	var target_res: String = ""
	for res_id in selected:
		if selected[res_id] > 0:
			target_res = res_id
			break
	if target_res == "":
		return false
	var total_stolen: int = 0
	for other in state.players:
		if other.id == player.id:
			continue
		var amount: int = other.resources.get(target_res, 0)
		if amount <= 0:
			continue
		other.add_resource(target_res, -amount)
		player.add_resource(target_res, amount)
		total_stolen += amount
	var res_name: String = registry.resources[target_res]["name"]
	print("[Monopole] J%d prend %d %s aux autres joueurs" % [player.id, total_stolen, res_name])
	return true
