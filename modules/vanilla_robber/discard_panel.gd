extends PanelContainer

signal closed(result: Variant)

var title_label: Label
var resource_buttons: HBoxContainer
var remaining_label: Label
var confirm_button: Button

var registry: GameRegistry
var player: Player
var to_discard: Dictionary = {}
var target_amount: int = 0

func _ready() -> void:
	title_label = get_node("Content/TitleLabel")
	resource_buttons = get_node("Content/ResourceButtons")
	remaining_label = get_node("Content/RemainingLabel")
	confirm_button = get_node("Content/ConfirmButton")
	confirm_button.pressed.connect(_on_confirm)

func show_panel(params: Dictionary) -> void:
	registry = params["registry"]
	player = params["player"]
	target_amount = params["target_amount"]
	to_discard.clear()
	title_label.text = "Joueur %d défausse %d ressources" % [player.id, target_amount]
	for child in resource_buttons.get_children():
		child.queue_free()
	for res_id in registry.resources:
		if registry.resources[res_id].get("is_desert", false):
			continue
		if player.resources[res_id] <= 0:
			continue
		var btn := Button.new()
		btn.text = "%s: %d" % [registry.resources[res_id]["name"], player.resources[res_id]]
		btn.pressed.connect(_on_resource_clicked.bind(res_id))
		resource_buttons.add_child(btn)
		to_discard[res_id] = 0
	_update_labels()

func _on_resource_clicked(res_id: String) -> void:
	var current_total: int = 0
	for v in to_discard.values():
		current_total += v
	if current_total >= target_amount:
		return
	if to_discard[res_id] >= player.resources[res_id]:
		return
	to_discard[res_id] += 1
	_update_labels()

func _update_labels() -> void:
	var current_total: int = 0
	for v in to_discard.values():
		current_total += v
	remaining_label.text = "Reste à défausser: %d" % (target_amount - current_total)
	for i in resource_buttons.get_child_count():
		var btn: Button = resource_buttons.get_child(i)
		var keys: Array = to_discard.keys()
		if i >= keys.size():
			continue
		var res_id: String = keys[i]
		var orig: int = player.resources[res_id]
		var selected: int = to_discard[res_id]
		btn.text = "%s: %d (-%d)" % [registry.resources[res_id]["name"], orig, selected]
	confirm_button.disabled = current_total < target_amount

func _on_confirm() -> void:
	closed.emit({"player_id": player.id, "to_discard": to_discard.duplicate()})
