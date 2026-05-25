class_name UIManager
extends RefCounted

var info_label: Label
var state: GameState
var board: Board

func _init(p_label: Label, p_state: GameState, p_board: Board) -> void:
	info_label = p_label
	state = p_state
	board = p_board

func _get_board() -> Board:
	return board
func update() -> void:
	var p := state.current_player()
	var text := "Joueur %d  |  %s\n" % [p.id, state.phase_label()]
	text += "Mode: %s\n" % state.mode_label()
	text += "\nPoints:\n"
	for pl in state.players:
		var pts := state.module.calculate_victory_points(pl.id, _get_board())
		text += "  J%d: %d/%d\n" % [pl.id, pts, state.module.points_to_win()]
	for res_id in state.module.resources:
		if state.module.resources[res_id].get("is_desert", false):
			continue
		var res_name: String = state.module.resources[res_id]["name"]
		text += "%s:%d  " % [res_name, p.resources[res_id]]
	# Raccourcis dynamiques depuis le module
	text += "\n\n"
	for b in state.module.get_build_modes():
		if b.hotkey >= 0:
			var key_name := OS.get_keycode_string(b.hotkey)
			text += "[%s]%s  " % [key_name, b.display_name]
	text += "[ENTRÉE]Joueur suivant  [ESPACE]Dés"
	info_label.text = text
	info_label.modulate = p.color
