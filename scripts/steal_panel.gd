class_name StealPanel
extends PanelContainer

signal target_chosen(target_id: int)

var title_label: Label
var target_buttons: HBoxContainer

func _ready() -> void:
	title_label = get_node("Content/TitleLabel")
	target_buttons = get_node("Content/TargetButtons")
	visible = false

func show_targets(players: Array, target_ids: Array) -> void:
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
	visible = true

func _on_target_clicked(target_id: int) -> void:
	visible = false
	target_chosen.emit(target_id)
