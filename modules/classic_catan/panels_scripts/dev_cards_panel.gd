extends PanelContainer

signal closed(result: Variant)

var title_label: Label
var cards_list: VBoxContainer
var close_button: Button

var registry: GameRegistry
var player: Player

func _ready() -> void:
	title_label = get_node("Content/TitleLabel")
	cards_list = get_node("Content/CardsList")
	close_button = get_node("Content/ActionRow/CloseButton")
	close_button.pressed.connect(_on_close)

func show_panel(params: Dictionary) -> void:
	registry = params["registry"]
	player = params["player"]
	var cards: Array = params["cards"]                  # Array[DevelopmentCard]
	var bought_this_turn: Array = params["bought_this_turn"]  # Array[DevelopmentCard]
	var state: GameState = params["state"]
	title_label.text = "Joueur %d — Cartes développement" % player.id
	for child in cards_list.get_children():
		child.queue_free()
	if cards.is_empty():
		var empty := Label.new()
		empty.text = "(aucune carte)"
		cards_list.add_child(empty)
	else:
		for card in cards:
			_build_card_row(card, bought_this_turn.has(card), state)

func _build_card_row(card: DevelopmentCard, bought_this_turn: bool, state: GameState) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s — %s" % [card.display_name, card.description]
	label.custom_minimum_size = Vector2(450, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var play_btn := Button.new()
	play_btn.text = "Jouer"
	var can_play := card.is_playable(state, player, bought_this_turn)
	play_btn.disabled = not can_play
	if card.is_passive:
		play_btn.text = "Passive"
	elif bought_this_turn:
		play_btn.tooltip_text = "Achetée ce tour, jouable au prochain tour"
	play_btn.pressed.connect(_on_play_card.bind(card))
	row.add_child(play_btn)
	cards_list.add_child(row)

func _on_play_card(card: DevelopmentCard) -> void:
	closed.emit({"action": "play", "card": card})

func _on_close() -> void:
	closed.emit({"action": "close"})
