class_name UIManager
extends RefCounted

var info_label: Label
var state: GameState
var board: Board

func _init(p_label: Label, p_state: GameState, p_board: Board) -> void:
	info_label = p_label
	state = p_state
	board = p_board
	# Rafraîchir à chaque changement de ressource
	for pl in state.players:
		pl.resources_changed.connect(_on_resources_changed)
		pl.custom_data_changed.connect(_on_custom_data_changed)
		pl.buildings_changed.connect(_on_buildings_changed)
		pl.cards_changed.connect(_on_cards_changed)
		pl.effects_changed.connect(_on_effects_changed)
	# Et aussi aux changements de plateau (pour les points)
	board.vertex_changed.connect(_on_board_changed)
	board.edge_changed.connect(_on_board_changed)


func _on_resources_changed(_player_id: int) -> void:
	update()

func _on_board_changed(_key: String) -> void:
	update()

func update() -> void:
	var p := state.current_player()
	var text := "Joueur %d  |  %s\n" % [p.id, state.phase_label()]
	text += "Mode: %s\n" % state.mode_label()
	# Ressources
	for res_id in state.registry.resources:
		if state.registry.resources[res_id].get("is_desert", false):
			continue
		var res_name: String = state.registry.resources[res_id]["name"]
		text += "%s:%d  " % [res_name, p.resources[res_id]]
	
	# Cartes développement (générique: lit le custom_data du mod Catan)
	if not p.cards.is_empty():
		text += "\nCartes: %d" % p.cards.size()
	# Points de tous les joueurs
	text += "\nPoints:\n"
	for pl in state.players:
		var pts := _compute_points(pl.id)
		text += "  J%d: %d/%d\n" % [pl.id, pts, state.registry.victory_threshold]
	# Raccourcis
	text += "\n"
	for action in state.registry.actions.values():
		if action.hotkey >= 0:
			var key_name := OS.get_keycode_string(action.hotkey)
			text += "[%s]%s  " % [key_name, action.label]
	info_label.text = text
	info_label.modulate = p.color

func _compute_points(player_id: int) -> int:
	var p: Player = state.players[player_id]
	return state.registry.compute_victory_points(p)

func _on_custom_data_changed(_player_id: int, _key: String) -> void:
	update()

func _on_buildings_changed(_player_id: int) -> void:
	update()

func _on_cards_changed(_player_id: int) -> void:
	update()

func _on_effects_changed(_player_id: int) -> void:
	update()
