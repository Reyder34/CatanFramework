extends PanelContainer

signal closed(result: Variant)

var title_label: Label
var prompt_label: Label
var resource_buttons: HBoxContainer
var confirm_button: Button
var cancel_button: Button

var registry: GameRegistry
var max_count: int = 1
var allow_cancel: bool = true
var selected: Dictionary = {}
var _buttons: Dictionary = {}  # res_id -> Button

func _ready() -> void:
	title_label = get_node("Content/TitleLabel")
	prompt_label = get_node("Content/PromptLabel")
	resource_buttons = get_node("Content/ResourceButtons")
	confirm_button = get_node("Content/ActionRow/ConfirmButton")
	cancel_button = get_node("Content/ActionRow/CancelButton")
	confirm_button.pressed.connect(_on_confirm)
	cancel_button.pressed.connect(_on_cancel)

func show_panel(params: Dictionary) -> void:
	registry = params["registry"]
	max_count = params.get("max_count", 1)
	allow_cancel = params.get("allow_cancel", true)
	title_label.text = params.get("title", "Choisis des ressources")
	prompt_label.text = params.get("prompt", "Sélectionne %d ressources" % max_count)
	cancel_button.visible = allow_cancel
	selected.clear()
	_build_buttons()
	_update_state()

func _build_buttons() -> void:
	for child in resource_buttons.get_children():
		child.queue_free()
	_buttons.clear()
	for res_id in registry.resources:
		if registry.resources[res_id].get("is_desert", false):
			continue
		selected[res_id] = 0
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(90, 60)
		btn.gui_input.connect(_on_button_input.bind(res_id, btn))
		resource_buttons.add_child(btn)
		_buttons[res_id] = btn
		_refresh_button(btn, res_id)

func _selected_total() -> int:
	var total: int = 0
	for v in selected.values():
		total += v
	return total

func _refresh_all() -> void:
	for res_id in _buttons:
		_refresh_button(_buttons[res_id], res_id)

func _refresh_button(btn: Button, res_id: String) -> void:
	var res_name: String = registry.resources[res_id]["name"]
	var color: Color = registry.resources[res_id]["color"]
	var count: int = selected[res_id]
	btn.text = "%s\n%d" % [res_name, count]
	btn.modulate = color if count > 0 else color.lerp(Color.WHITE, 0.6)

func _on_button_input(event: InputEvent, res_id: String, _btn: Button) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	# Clic droit: décrémente explicitement.
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if selected[res_id] > 0:
			selected[res_id] -= 1
		_refresh_all()
		_update_state()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	# Clic gauche: ajoute, ou désélectionne si on est déjà au max.
	var total: int = _selected_total()
	if total < max_count:
		selected[res_id] += 1
	elif selected[res_id] > 0:
		selected[res_id] -= 1  # déjà au max: reclic = désélectionne
	elif max_count == 1:
		# Pioche unique: bascule la sélection sur cette ressource.
		for k in selected:
			selected[k] = 0
		selected[res_id] = 1
	_refresh_all()
	_update_state()

func _update_state() -> void:
	var total: int = 0
	for v in selected.values():
		total += v
	confirm_button.disabled = total != max_count
	prompt_label.text = "Sélectionne %d ressources (%d/%d)" % [max_count, total, max_count]

func _on_confirm() -> void:
	closed.emit({"action": "confirm", "selected": selected.duplicate()})

func _on_cancel() -> void:
	closed.emit({"action": "cancel"})
