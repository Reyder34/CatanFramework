extends PanelContainer

signal closed(result: Variant)

var title_label: Label
var give_buttons: HBoxContainer
var receive_buttons: HBoxContainer
var confirm_button: Button
var cancel_button: Button

var registry: GameRegistry
var player: Player
var ratios: Dictionary = {}        # res_id -> ratio d'échange (selon les ports du joueur)

var selected_give: String = ""     # ressource à donner
var selected_receive: String = ""  # ressource à recevoir (x1)

const DEFAULT_RATIO := 4

func _ratio_for(res_id: String) -> int:
	return int(ratios.get(res_id, DEFAULT_RATIO))

func _ready() -> void:
	title_label = get_node("Content/TitleLabel")
	give_buttons = get_node("Content/GiveSection/GiveButtons")
	receive_buttons = get_node("Content/ReceiveSection/ReceiveButtons")
	confirm_button = get_node("Content/ActionRow/ConfirmButton")
	cancel_button = get_node("Content/ActionRow/CancelButton")
	confirm_button.pressed.connect(_on_confirm)
	cancel_button.pressed.connect(_on_cancel)

func show_panel(params: Dictionary) -> void:
	registry = params["registry"]
	player = params["player"]
	ratios = params.get("ratios", {})
	title_label.text = "Joueur %d — Échange avec la banque (taux selon tes ports)" % player.id
	_build_buttons()
	_update_state()

func _build_buttons() -> void:
	for child in give_buttons.get_children():
		child.queue_free()
	for child in receive_buttons.get_children():
		child.queue_free()
	for res_id in registry.resources:
		if registry.resources[res_id].get("is_desert", false):
			continue
		# Bouton "donner" — désactivé si le joueur n'a pas 4
		var give_btn := Button.new()
		give_btn.custom_minimum_size = Vector2(90, 60)
		var owned: int = player.resources.get(res_id, 0)
		give_btn.disabled = owned < _ratio_for(res_id)
		give_btn.pressed.connect(_on_give_selected.bind(res_id))
		give_buttons.add_child(give_btn)
		_refresh_give_button(give_btn, res_id)
		# Bouton "recevoir"
		var rcv_btn := Button.new()
		rcv_btn.custom_minimum_size = Vector2(90, 60)
		rcv_btn.pressed.connect(_on_receive_selected.bind(res_id))
		receive_buttons.add_child(rcv_btn)
		_refresh_receive_button(rcv_btn, res_id)

func _refresh_give_button(btn: Button, res_id: String) -> void:
	var res_name: String = registry.resources[res_id]["name"]
	var color: Color = registry.resources[res_id]["color"]
	var owned: int = player.resources.get(res_id, 0)
	btn.text = "%s\n%d  (%d:1)" % [res_name, owned, _ratio_for(res_id)]
	if res_id == selected_give:
		btn.modulate = color
	else:
		btn.modulate = color.lerp(Color.WHITE, 0.6)

func _refresh_receive_button(btn: Button, res_id: String) -> void:
	var res_name: String = registry.resources[res_id]["name"]
	var color: Color = registry.resources[res_id]["color"]
	btn.text = "%s" % res_name
	if res_id == selected_receive:
		btn.modulate = color
	else:
		btn.modulate = color.lerp(Color.WHITE, 0.6)

func _on_give_selected(res_id: String) -> void:
	selected_give = res_id
	_update_state()

func _on_receive_selected(res_id: String) -> void:
	selected_receive = res_id
	_update_state()

func _update_state() -> void:
	# Refresh tous les boutons (pour la couleur)
	for i in give_buttons.get_child_count():
		var btn: Button = give_buttons.get_child(i)
		var res_id: String = _resource_id_at(i)
		_refresh_give_button(btn, res_id)
	for i in receive_buttons.get_child_count():
		var btn: Button = receive_buttons.get_child(i)
		var res_id: String = _resource_id_at(i)
		_refresh_receive_button(btn, res_id)
	# Activer "Échanger" seulement si tout est valide
	var ok: bool = selected_give != "" \
		and selected_receive != "" \
		and selected_give != selected_receive \
		and player.resources.get(selected_give, 0) >= _ratio_for(selected_give)
	confirm_button.disabled = not ok

func _resource_id_at(index: int) -> String:
	# Hypothèse: les ressources sont itérées dans le même ordre dans les deux conteneurs
	var ids: Array = []
	for res_id in registry.resources:
		if registry.resources[res_id].get("is_desert", false):
			continue
		ids.append(res_id)
	if index < ids.size():
		return ids[index]
	return ""

func _on_confirm() -> void:
	closed.emit({
		"action": "trade",
		"give": selected_give,
		"receive": selected_receive,
	})

func _on_cancel() -> void:
	closed.emit({"action": "cancel"})
