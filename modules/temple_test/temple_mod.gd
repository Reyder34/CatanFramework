class_name TempleMod
extends GameMod

var _state: GameState

func _init() -> void:
	mod_id = "temple_mod"
	mod_name = "Temples"
	description = "Ajoute le Temple (3 PV), construit sur une de tes colonies"
	depends_on = ["classic_catan"]   # on réutilise ses ressources + son flux de pose

func register(reg: GameRegistry) -> void:
	# 1) Déclarer le bâtiment au registre
	reg.declare_building(Temple.new())

	# 2) Une action pour passer en "mode temple" (touche 4 + bouton dans le HUD)
	var act := GameAction.new()
	act.id = "select_temple"
	act.label = "Sélectionner : Temple"
	act.hotkey = KEY_4
	act.category = "build"
	act.callback = func() -> void:
		_state.build_mode_id = "temple"
	act.is_available = func() -> bool:
		return _state != null and _state.phase != GameState.Phase.GAME_OVER
	reg.register_action(act)

	# 3) Récupérer l'état au démarrage (pour les callbacks)
	reg.on("game_start", func(ctx): _state = ctx["state"])
