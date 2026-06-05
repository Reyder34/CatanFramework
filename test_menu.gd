extends SceneTree

# Test headless: le menu construit bien la liste de mods, et lancer le jeu
# avec une config (3 joueurs, seul vanilla_robber coché) charge aussi sa
# dépendance classic_catan via l'expansion.
func _initialize() -> void:
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	get_root().add_child(menu)
	var mod_list = menu.get_node("Panel/Margin/VBox/ModList")
	print("TEST MENU_MODS=", mod_list.get_child_count())
	menu.free()

	GameConfig.player_count = 3
	GameConfig.enabled_mod_ids = ["vanilla_robber"]
	var game = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(game)
	print("TEST GAME_PLAYERS=", game.state.players.size())
	print("TEST GAME_MODS=", game.loaded_mods.size())
	game.free()
	quit()
