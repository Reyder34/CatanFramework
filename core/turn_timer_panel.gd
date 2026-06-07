extends PanelContainer

# Affichage du temps restant du tour (panneau persistant core). update_panel({seconds}).

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := get_node_or_null("Content")
	if c != null:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE

func update_panel(params: Dictionary) -> void:
	var lbl := get_node_or_null("Content/Time")
	if lbl == null:
		return
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := int(params.get("seconds", 0))
	lbl.text = "%d s" % s
	lbl.modulate = Color(1, 0.4, 0.4) if s <= 5 else Color(1, 1, 1)
