class_name DiscardPanel
extends PanelContainer

signal discard_confirmed(player_id: int, to_discard: Dictionary)

@onready var title_label: Label = $Content/TitleLabel
@onready var resource_buttons: HBoxContainer = $Content/ResourceButtons
@onready var remaining_label: Label = $Content/RemainingLabel
@onready var confirm_button: Button = $Content/ConfirmButton

var registry: GameRegistry
var player: Player
var to_discard: Dictionary = {}  # res_id -> count
var target_amount: int = 0

func _ready() -> void:
	visible = false
	confirm_button.pressed.connect(_on_confirm)

func show_for(p_registry: GameRegistry, p_player: Player, p_target: int) -> void:
	registry = p_registry
	player = p_player
	target_amount = p_target
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
	visible = true

func _on_resource_clicked(res_id: String) -> void:
	# Augmenter d'1 si possible
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
	# Mettre à jour les boutons pour montrer la sélection
	for i in resource_buttons.get_child_count():
		var btn: Button = resource_buttons.get_child(i)
		var res_id: String = to_discard.keys()[i] if i < to_discard.keys().size() else ""
		if res_id == "":
			continue
		var orig: int = player.resources[res_id]
		var selected: int = to_discard[res_id]
		btn.text = "%s: %d (-%d)" % [registry.resources[res_id]["name"], orig, selected]
	confirm_button.disabled = current_total < target_amount

func _on_confirm() -> void:
	visible = false
	discard_confirmed.emit(player.id, to_discard)
