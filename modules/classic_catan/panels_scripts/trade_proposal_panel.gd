extends PanelContainer

signal closed(result: Variant)

var title_label: Label
var offer_buttons: HBoxContainer
var demand_buttons: HBoxContainer
var propose_button: Button
var cancel_button: Button

var registry: GameRegistry
var proposer: Player
var offer: Dictionary = {}    # res_id -> count
var demand: Dictionary = {}   # res_id -> count

func _ready() -> void:
	title_label = get_node("Content/TitleLabel")
	offer_buttons = get_node("Content/OfferSection/OfferButtons")
	demand_buttons = get_node("Content/DemandSection/DemandButtons")
	propose_button = get_node("Content/ActionRow/ProposeButton")
	cancel_button = get_node("Content/ActionRow/CancelButton")
	propose_button.pressed.connect(_on_propose)
	cancel_button.pressed.connect(_on_cancel)

func show_panel(params: Dictionary) -> void:
	registry = params["registry"]
	proposer = params["proposer"]
	title_label.text = "Joueur %d propose un échange" % proposer.id
	# Crée les boutons pour chaque ressource productive
	_build_resource_buttons(offer_buttons, offer, true)
	_build_resource_buttons(demand_buttons, demand, false)
	_update_propose_state()

func _build_resource_buttons(container: HBoxContainer, target: Dictionary, is_offer: bool) -> void:
	for child in container.get_children():
		child.queue_free()
	for res_id in registry.resources:
		if registry.resources[res_id].get("is_desert", false):
			continue
		target[res_id] = 0
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(90, 60)
		btn.gui_input.connect(_on_resource_button_input.bind(res_id, target, is_offer, btn))
		container.add_child(btn)
		_refresh_button(btn, res_id, target[res_id])

func _refresh_button(btn: Button, res_id: String, count: int) -> void:
	var res_name: String = registry.resources[res_id]["name"]
	var color: Color = registry.resources[res_id]["color"]
	btn.text = "%s\n%d" % [res_name, count]
	# Modulate par la couleur de la ressource (plus claire si 0)
	btn.modulate = color if count > 0 else color.lerp(Color.WHITE, 0.6)

func _on_resource_button_input(event: InputEvent, res_id: String, target: Dictionary, is_offer: bool, btn: Button) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var delta := 0
	if event.button_index == MOUSE_BUTTON_LEFT:
		delta = 1
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		delta = -1
	else:
		return
	# Validation pour l'offre: pas plus que ce que le proposant possède
	var new_value: int = target[res_id] + delta
	if new_value < 0:
		new_value = 0
	if is_offer and new_value > proposer.resources.get(res_id, 0):
		new_value = proposer.resources.get(res_id, 0)
	target[res_id] = new_value
	_refresh_button(btn, res_id, new_value)
	_update_propose_state()

func _update_propose_state() -> void:
	# Le bouton "Proposer" n'est actif que si offre ET demande contiennent au moins 1 ressource
	var offer_total: int = 0
	for v in offer.values():
		offer_total += v
	var demand_total: int = 0
	for v in demand.values():
		demand_total += v
	propose_button.disabled = offer_total == 0 or demand_total == 0

func _on_propose() -> void:
	closed.emit({"action": "propose", "offer": offer, "demand": demand})

func _on_cancel() -> void:
	closed.emit({"action": "cancel"})
