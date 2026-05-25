extends PanelContainer

signal closed(result: Variant)

var title_label: Label
var target_buttons: HBoxContainer

func _ready() -> void:
	title_label = get_node("Content/TitleLabel")
	target_buttons = get_node("Content/TargetButtons")

func show_panel(params: Dictionary) -> void:
	var players: Array = params["players"]
	var target_ids: Array = params["target_ids"]
	for child in target_buttons.get_children():
		child.queue_free()
	for tid in target_ids:
		var p: Player = players[tid]
		var total: int = 0
		for v in p.resources.values():
			total += v
		var btn := Button.new()
		btn.text = "Joueur %d (%d cartes)" % [p.id, total]
		btn.modulate = p.color
		btn.pressed.connect(_on_target_clicked.bind(tid))
		target_buttons.add_child(btn)

func _on_target_clicked(target_id: int) -> void:
	closed.emit({"target_id": target_id})
