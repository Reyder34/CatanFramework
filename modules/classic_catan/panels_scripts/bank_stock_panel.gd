extends PanelContainer

# Stock restant de la banque, TOUJOURS visible (panneau persistant). Rafraîchi par
# classic_catan via UIRegistry.show_persistent("bank_stock", {rows:[{name,count,color,icon}]}).

func _ready() -> void:
	# Laisse passer les clics vers le plateau (le titre/poignée restent actifs via WindowMover).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var content := get_node_or_null("Content")
	if content != null:
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE

func update_panel(params: Dictionary) -> void:
	var box := get_node_or_null("Content/Rows")
	if box == null:
		return
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in box.get_children():
		c.queue_free()
	for row in params.get("rows", []):
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 6)
		var icon = row.get("icon", null)
		if icon != null:
			var tr := TextureRect.new()
			tr.texture = icon
			tr.custom_minimum_size = Vector2(18, 18)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(tr)
		else:
			var sw := ColorRect.new()
			sw.color = row.get("color", Color.WHITE)
			sw.custom_minimum_size = Vector2(14, 14)
			sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(sw)
		var lbl := Label.new()
		var n := int(row.get("count", 0))
		lbl.text = "%s : %d" % [str(row.get("name", "?")), n]
		if n <= 0:
			lbl.modulate = Color(1, 0.45, 0.45)  # épuisé -> rouge
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(lbl)
		box.add_child(line)
