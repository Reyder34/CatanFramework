extends PanelContainer
signal closed(result: Variant)

var title_label: Label
var offer_buttons: HBoxContainer
var demand_buttons: HBoxContainer
var propose_button: Button
var cancel_button: Button
var registry: GameRegistry
var proposer: Player
var offer: Dictionary = {}
var demand: Dictionary = {}

# Garde une référence aux stack_containers pour les mettre à jour
var offer_stacks: Dictionary = {}
var demand_stacks: Dictionary = {}

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
	title_label.text = "%s propose un échange" % proposer.label()
	_build_resource_buttons(offer_buttons, offer, offer_stacks, true)
	_build_resource_buttons(demand_buttons, demand, demand_stacks, false)
	_update_propose_state()

func _build_resource_buttons(container: HBoxContainer, target: Dictionary, stacks: Dictionary, is_offer: bool) -> void:
	for child in container.get_children():
		child.queue_free()
	stacks.clear()

	for res_id in registry.resources:
		if registry.resources[res_id].get("is_desert", false):
			continue
		target[res_id] = 0

		# Zone cliquable englobant la pile de cartes
		var click_area := Control.new()
		click_area.custom_minimum_size = Vector2(90, 120)
		click_area.gui_input.connect(_on_resource_click.bind(res_id, target, is_offer, stacks))
		container.add_child(click_area)

		# Stack container positionné dans la zone cliquable
		var stack_container := Control.new()
		stack_container.custom_minimum_size = Vector2(90, 120)
		stack_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		click_area.add_child(stack_container)
		stacks[res_id] = stack_container

		_refresh_stack(stack_container, res_id, 0)

func _refresh_stack(stack_container: Control, res_id: String, count: int) -> void:
	# Vider le conteneur
	for child in stack_container.get_children():
		child.queue_free()

	var card_w: int = 80
	var card_h: int = 110
	var offset: int = 6
	var icon := registry.get_resource_icon(res_id)
	var res_color := registry.get_resource_color(res_id)

	# Toujours afficher au moins une carte (même à 0)
	var visible_cards: int = max(min(count, 3), 1)

	for i in range(visible_cards):
		var card := Panel.new()
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0, 0, 0, 0)
		card_style.border_width_left = 0
		card_style.border_width_top = 0
		card_style.border_width_right = 0
		card_style.border_width_bottom = 0
		card.add_theme_stylebox_override("panel", card_style)

		# À count == 0 on n'affiche qu'une seule carte sans décalage
		var shift: int = 0
		if count > 1:
			shift = (visible_cards - 1 - i) * offset
		card.position = Vector2(shift, shift)
		card.size = Vector2(card_w, card_h)
		card.clip_contents = true
		card.modulate = Color(1, 1, 1, 1)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack_container.add_child(card)

		# Icône sur toutes les cartes
		if icon != null:
			var tr := TextureRect.new()
			tr.texture = icon
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			tr.offset_left = 0
			tr.offset_top = 0
			tr.offset_right = 0
			tr.offset_bottom = 0
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(tr)

		# Overlay sombre quand count == 0 pour indiquer non-sélectionné
		if count == 0:
			var overlay := ColorRect.new()
			overlay.color = Color(0, 0, 0, 0.55)
			overlay.position = Vector2(0, 0)
			overlay.size = Vector2(card_w, card_h)
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(overlay)

		# Badge compteur uniquement sur la carte du dessus
		if i == visible_cards - 1:
			var badge := Panel.new()
			var badge_style := StyleBoxFlat.new()
			badge_style.bg_color = Color(0.1, 0.1, 0.1, 0.85)
			badge_style.corner_radius_top_left = 10
			badge_style.corner_radius_top_right = 10
			badge_style.corner_radius_bottom_left = 10
			badge_style.corner_radius_bottom_right = 10
			badge.add_theme_stylebox_override("panel", badge_style)
			badge.size = Vector2(20, 20)
			badge.position = Vector2(card_w - 22, 2)
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(badge)

			var count_label := Label.new()
			count_label.text = str(count)
			count_label.add_theme_color_override("font_color", Color.WHITE)
			count_label.add_theme_font_size_override("font_size", 12)
			count_label.size = Vector2(20, 20)
			count_label.position = Vector2(card_w - 22, 2)
			count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(count_label)

func _on_resource_click(event: InputEvent, res_id: String, target: Dictionary, is_offer: bool, stacks: Dictionary) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return

	var delta := 0
	if event.button_index == MOUSE_BUTTON_LEFT:
		delta = 1
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		delta = -1
	else:
		return

	var new_value: int = target[res_id] + delta
	if new_value < 0:
		new_value = 0
	if is_offer and new_value > proposer.resources.get(res_id, 0):
		new_value = proposer.resources.get(res_id, 0)

	target[res_id] = new_value
	_refresh_stack(stacks[res_id], res_id, new_value)
	_update_propose_state()

func _update_propose_state() -> void:
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
