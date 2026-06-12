extends PanelContainer

signal closed(result: Variant)

var title_label: Label
var offer_label: Label
var demand_label: Label
var accept_button: Button
var refuse_button: Button

var registry: GameRegistry
var responder: Player

func _ready() -> void:
	title_label = get_node("Content/TitleLabel")
	offer_label = get_node("Content/OfferLabel")
	demand_label = get_node("Content/DemandLabel")
	accept_button = get_node("Content/ActionRow/AcceptButton")
	refuse_button = get_node("Content/ActionRow/RefuseButton")
	accept_button.pressed.connect(_on_accept)
	refuse_button.pressed.connect(_on_refuse)

func show_panel(params: Dictionary) -> void:
	registry = params["registry"]
	responder = params["responder"]
	var proposer: Player = params["proposer"]
	var offer: Dictionary = params["offer"]
	var demand: Dictionary = params["demand"]
	title_label.text = "%s te propose :" % proposer.label()
	offer_label.text = "Il offre: " + _format_resources(offer)
	demand_label.text = "Il demande: " + _format_resources(demand)
	# Si le répondant n'a pas les ressources demandées, désactive Accepter
	accept_button.disabled = not _can_pay(demand)

func _format_resources(d: Dictionary) -> String:
	var parts: Array = []
	for res_id in d:
		if d[res_id] <= 0:
			continue
		var name: String = registry.resources[res_id]["name"]
		parts.append("%d %s" % [d[res_id], name])
	return ", ".join(parts) if not parts.is_empty() else "(rien)"

func _can_pay(demand: Dictionary) -> bool:
	for res_id in demand:
		if responder.resources.get(res_id, 0) < demand[res_id]:
			return false
	return true

func _on_accept() -> void:
	closed.emit({"action": "accept"})

func _on_refuse() -> void:
	closed.emit({"action": "refuse"})
