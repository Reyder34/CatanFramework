class_name GameHud
extends Control

# HUD applicatif (couche app, pas core): lit les données génériques du jeu
# (ressources, joueurs, scores, cartes) et les actions déclarées par les mods.
# Les deux interactions spécifiques Catan (échanger avec un joueur, jouer une
# carte) passent par des events que classic_catan traite.

var state: GameState
var registry: GameRegistry
var board: Board

# Actions déjà couvertes ailleurs dans le HUD (pas dans la barre d'actions).
const _HIDDEN_ACTIONS := ["show_dev_cards", "propose_trade", "bank_trade"]

# Conteneurs de la scène hud.tscn (le designer édite la structure/le style dans l'éditeur).
@onready var _res_box: VBoxContainer = %ResourcesContent
@onready var _players_box: VBoxContainer = %PlayersContent
@onready var _build_box: VBoxContainer = %BuildContent
@onready var _actions_box: VBoxContainer = %TurnContent
@onready var _card_actions_box: VBoxContainer = %CardActionsContent
@onready var _cards_box: VBoxContainer = %HandContent
@onready var _log_box: VBoxContainer = %JournalContent
@onready var _log_button: Button = %JournalButton
@onready var _log_scroll: ScrollContainer = %JournalScroll
var _log_open: bool = false
# Panneaux déplaçables (barre de titre) + redimensionnables (poignée bas-droite) + persistance.
var _windows: Dictionary = {}        # id -> {panel, default}
var _drag_panel: Control = null
var _drag_id: String = ""
var _drag_grab: Vector2 = Vector2.ZERO
var _resize_panel: Control = null
var _resize_id: String = ""
var _resize_base: Vector2 = Vector2.ZERO    # taille non scalée au début du redim
var _resize_origin: Vector2 = Vector2.ZERO  # coin haut-gauche figé pendant le redim
const LAYOUT_PATH := "user://hud_layout.cfg"
var _layout := ConfigFile.new()
var _selected_breakdown: int = -1  # joueur dont on affiche le détail des points (-1 = aucun)
var _main: Node = null  # main (pour router les actions en réseau)

# Actions à panneaux/cartes désactivées en réseau (Phase 2b).
const _MP_DEFERRED := ["show_dev_cards"]

func _net_my_turn() -> bool:
	if not GameConfig.is_multiplayer:
		return true
	return state.current_player_index == GameConfig.local_player_index

func _view_player() -> Player:
	if GameConfig.is_multiplayer:
		return state.players[GameConfig.local_player_index]
	return state.current_player()

func setup(p_state: GameState, p_registry: GameRegistry, p_board: Board, p_main: Node = null) -> void:
	state = p_state
	registry = p_registry
	board = p_board
	_main = p_main
	# Plein écran, explicitement (le HUD doit couvrir tout le viewport pour que
	# les ancrages des coins fonctionnent).
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # laisse passer les clics vers le plateau 3D
	_wire_windows()
	_connect_signals()
	update()

# Branche le drag + la persistance sur les panneaux de la SCÈNE (hud.tscn).
# Le designer édite la structure/le style dans l'éditeur ; ici uniquement la logique.
func _wire_windows() -> void:
	_layout.load(LAYOUT_PATH)  # positions sauvegardées (ignore si absent)
	_log_button.pressed.connect(_toggle_log)
	for win in get_tree().get_nodes_in_group("hud_window"):
		if not is_ancestor_of(win):
			continue
		var id: String = win.name
		_windows[id] = {"panel": win, "default": _capture_layout(win)}
		var bar := _find_titlebar(win)
		if bar != null:
			bar.gui_input.connect(_on_titlebar_input.bind(id))
		_add_resize_grip(win, id)  # poignée de redimensionnement (coin bas-droite)
		if _layout.has_section_key("layout", id):
			_set_free_pos(win, _layout.get_value("layout", id))
		if _layout.has_section_key("scale", id):
			win.pivot_offset = Vector2.ZERO
			win.scale = Vector2.ONE * float(_layout.get_value("scale", id))

func _find_titlebar(node: Node) -> Control:
	for c in node.get_children():
		if c is Control and c.is_in_group("hud_titlebar"):
			return c
		var found := _find_titlebar(c)
		if found != null:
			return found
	return null

# Mémorise/restaure l'ancrage défini dans la scène (pour F6 = réinitialiser).
func _capture_layout(c: Control) -> Dictionary:
	return {
		"al": c.anchor_left, "at": c.anchor_top, "ar": c.anchor_right, "ab": c.anchor_bottom,
		"ol": c.offset_left, "ot": c.offset_top, "ore": c.offset_right, "ob": c.offset_bottom,
		"gh": c.grow_horizontal, "gv": c.grow_vertical,
	}

func _restore_layout(c: Control, d: Dictionary) -> void:
	c.anchor_left = d["al"]; c.anchor_top = d["at"]; c.anchor_right = d["ar"]; c.anchor_bottom = d["ab"]
	c.offset_left = d["ol"]; c.offset_top = d["ot"]; c.offset_right = d["ore"]; c.offset_bottom = d["ob"]
	c.grow_horizontal = d["gh"]; c.grow_vertical = d["gv"]

# (Helpers de construction de panneaux retirés : le HUD est désormais une scène,
# voir scenes/hud.tscn. Le placement par défaut vient de la scène, pas du code.)

func _swatch(color: Color) -> ColorRect:
	var sw := ColorRect.new()
	sw.color = color
	sw.custom_minimum_size = Vector2(16, 16)
	return sw

func _connect_signals() -> void:
	for p in state.players:
		p.resources_changed.connect(func(_id): update())
		p.buildings_changed.connect(func(_id): update())
		p.cards_changed.connect(func(_id): update())
		p.effects_changed.connect(func(_id): update())
		p.custom_data_changed.connect(func(_id, _k): update())
	board.vertex_changed.connect(func(_k): update())
	board.edge_changed.connect(func(_k): update())
	state.status_changed.connect(func(): update())

func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()

func update() -> void:
	if state == null:
		return
	_refresh_resources()
	_refresh_players()
	_refresh_build()
	_refresh_turn_actions()
	_refresh_card_actions()
	_refresh_cards()
	_refresh_log()
	# Seuls les boutons captent la souris; tout le reste laisse passer les clics
	# vers le plateau 3D (sinon le HUD bloque la pose de bâtiments).
	_make_passthrough(self)

func _make_passthrough(node: Node) -> void:
	if node is Button:
		return  # les boutons restent cliquables
	if node == _log_scroll:
		return  # le menu déroulant capte la souris (scroll) -> ne pas le rendre passthrough
	if node is Control and (node.is_in_group("hud_titlebar") or node.is_in_group("hud_resize")):
		return  # barre de titre / poignée de redim: gardent la souris
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_make_passthrough(c)

# === PANNEAUX DÉPLAÇABLES (barre de titre de la scène, position retenue) ===
# Positionnement libre (ancré en haut-gauche, grandit vers le contenu).
func _set_free_pos(panel: Control, pos: Vector2) -> void:
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 0.0; panel.anchor_bottom = 0.0
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.offset_left = pos.x
	panel.offset_top = pos.y

func _on_titlebar_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var panel: Control = _windows[id]["panel"]
		var gp: Vector2 = panel.global_position
		_set_free_pos(panel, gp)  # fige la position visuelle courante
		_drag_panel = panel
		_drag_id = id
		_drag_grab = gp - get_global_mouse_position()
		accept_event()

func _input(event: InputEvent) -> void:
	if _resize_panel != null:
		if event is InputEventMouseMotion:
			var m: Vector2 = get_global_mouse_position()
			var sx: float = (m.x - _resize_origin.x) / maxf(40.0, _resize_base.x)
			var sy: float = (m.y - _resize_origin.y) / maxf(40.0, _resize_base.y)
			var s: float = clampf(maxf(sx, sy), 0.6, 2.5)
			_resize_panel.scale = Vector2(s, s)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_layout.set_value("scale", _resize_id, _resize_panel.scale.x)
			_save_window_pos(_resize_id, Vector2(_resize_panel.offset_left, _resize_panel.offset_top))
			_resize_panel = null
			_resize_id = ""
			get_viewport().set_input_as_handled()
		return
	if _drag_panel == null:
		return
	if event is InputEventMouseMotion:
		var p: Vector2 = get_global_mouse_position() + _drag_grab
		var maxp: Vector2 = get_viewport_rect().size - _drag_panel.size
		p.x = clampf(p.x, 0.0, maxf(0.0, maxp.x))
		p.y = clampf(p.y, 0.0, maxf(0.0, maxp.y))
		_set_free_pos(_drag_panel, p)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_save_window_pos(_drag_id, Vector2(_drag_panel.offset_left, _drag_panel.offset_top))
		_drag_panel = null
		_drag_id = ""
		get_viewport().set_input_as_handled()

func _save_window_pos(id: String, pos: Vector2) -> void:
	_layout.set_value("layout", id, pos)
	_layout.save(LAYOUT_PATH)

# === REDIMENSIONNEMENT PAR PANNEAU (poignée bas-droite, comme une fenêtre OS) ===
# Petite poignée ajoutée en bas-droite du panneau (dans son VBox "V").
func _add_resize_grip(win: Control, id: String) -> void:
	var v := win.get_node_or_null("V")
	if v == null:
		return
	var grip := ColorRect.new()
	grip.color = Color(1, 1, 1, 0.45)
	grip.custom_minimum_size = Vector2(14, 14)
	grip.size_flags_horizontal = Control.SIZE_SHRINK_END
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.tooltip_text = "Glisser pour redimensionner"
	grip.add_to_group("hud_resize")
	grip.gui_input.connect(_on_grip_input.bind(id))
	v.add_child(grip)

func _on_grip_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var panel: Control = _windows[id]["panel"]
		var gp: Vector2 = panel.global_position
		_set_free_pos(panel, gp)         # fige le coin haut-gauche
		panel.pivot_offset = Vector2.ZERO  # le panneau grandit vers le bas-droite
		_resize_panel = panel
		_resize_id = id
		_resize_base = panel.size
		_resize_origin = gp
		accept_event()

# Réinitialise position ET taille de chaque panneau à l'origine (touches F1 / F6).
func reset_layout() -> void:
	for id in _windows:
		var p: Control = _windows[id]["panel"]
		_restore_layout(p, _windows[id]["default"])
		p.scale = Vector2.ONE
		p.pivot_offset = Vector2.ZERO
	_layout.clear()
	_layout.save(LAYOUT_PATH)

# === HAUT-GAUCHE: ressources du joueur courant ===
func _refresh_resources() -> void:
	_clear(_res_box)
	var p := _view_player()
	var header := Label.new()
	header.text = "%s — %s" % [p.label(), state.phase_label()]
	header.modulate = p.color
	_res_box.add_child(header)
	if GameConfig.is_multiplayer:
		var turn := Label.new()
		turn.text = "Tour : %s%s" % [state.current_player().label(), "  (à toi)" if _net_my_turn() else ""]
		_res_box.add_child(turn)
	var mode := Label.new()
	mode.text = "Mode: %s" % state.mode_label()
	_res_box.add_child(mode)
	for res_id in registry.resources:
		if registry.resources[res_id].get("is_desert", false):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var icon := registry.get_resource_icon(res_id)
		if icon != null:
			var tr := TextureRect.new()
			tr.texture = icon
			tr.custom_minimum_size = Vector2(20, 20)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(tr)
		else:
			row.add_child(_swatch(registry.get_resource_color(res_id)))  # repli: carré de couleur
		var lbl := Label.new()
		lbl.text = "%s : %d" % [registry.resources[res_id]["name"], int(p.resources.get(res_id, 0))]
		row.add_child(lbl)
		_res_box.add_child(row)

# === HAUT-DROIT: joueurs, scores, échange, banque ===
func _refresh_players() -> void:
	_clear(_players_box)
	var threshold := registry.victory_threshold
	for pl in state.players:
		var pts := registry.compute_victory_points(pl)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(_swatch(pl.color))
		var btn := Button.new()
		var me := "  (toi)" if pl.id == _view_player().id else ""
		btn.text = "%s : %d/%d%s" % [pl.label(), pts, threshold, me]
		btn.pressed.connect(_on_select_player.bind(pl.id))
		row.add_child(btn)
		_players_box.add_child(row)
	if registry.actions.has("bank_trade"):
		var bank := Button.new()
		bank.text = "Banque"
		bank.pressed.connect(_trigger_action.bind("bank_trade"))
		_players_box.add_child(bank)
	if registry.actions.has("propose_trade"):
		var ta := Button.new()
		ta.text = "Échanger à tous"
		ta.tooltip_text = "Proposer un échange à tous les autres joueurs en même temps."
		ta.disabled = not _net_my_turn() or not registry.actions["propose_trade"].can_trigger()
		ta.pressed.connect(_trigger_action.bind("propose_trade"))
		_players_box.add_child(ta)
	# Trophées: récompenses à PV détenues (plus grande armée, plus longue route,
	# ou tout effet de mod). Générique: lit les effets des joueurs.
	_add_trophies()
	# Détail (provenance des points) du joueur sélectionné
	if _selected_breakdown >= 0 and _selected_breakdown < state.players.size():
		_players_box.add_child(_build_breakdown(_selected_breakdown))

func _add_trophies() -> void:
	var rows: Array = []
	for pl in state.players:
		for e in pl.effects:
			if e.victory_points != 0:
				rows.append("%s : %s (+%d)" % [e.display_name, pl.label(), e.victory_points])
	if rows.is_empty():
		return
	_players_box.add_child(HSeparator.new())
	var title := Label.new()
	title.text = "Trophées :"
	_players_box.add_child(title)
	for r in rows:
		var lbl := Label.new()
		lbl.text = "  " + r
		_players_box.add_child(lbl)

# Clic sur un joueur: affiche/masque la provenance de ses points.
func _on_select_player(id: int) -> void:
	_selected_breakdown = -1 if _selected_breakdown == id else id
	update()

func _build_breakdown(id: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_child(HSeparator.new())
	var pl: Player = state.players[id]
	var title := Label.new()
	title.text = "Points de %s : %d" % [pl.label(), registry.compute_victory_points(pl)]
	title.modulate = pl.color
	box.add_child(title)
	var entries := registry.compute_victory_breakdown(pl)
	if entries.is_empty():
		var none := Label.new()
		none.text = "  (aucun point)"
		box.add_child(none)
	for e in entries:
		var lbl := Label.new()
		lbl.text = "  %s ×%d : %d" % [e["name"], int(e["count"]), int(e["points"])]
		box.add_child(lbl)
	if id != state.current_player_index:
		var trade := Button.new()
		trade.text = "Échanger avec %s" % state.players[id].label()
		trade.disabled = not _net_my_turn()
		trade.pressed.connect(_on_trade_with.bind(id))
		box.add_child(trade)
	return box

# === BAS: actions groupées (Construire / Tour / Cartes) ===
# Chaque bouton porte un tooltip CONSTRUIT À PARTIR DES DONNÉES DU MOD.
func _refresh_build() -> void:
	_clear(_build_box)
	for a in _actions_in_category("build"):
		_build_box.add_child(_make_action_button(a))

func _refresh_turn_actions() -> void:
	_clear(_actions_box)
	for a in _actions_in_category("game"):
		_actions_box.add_child(_make_action_button(a))

func _refresh_card_actions() -> void:
	_clear(_card_actions_box)
	for a in _actions_in_category("cards"):
		_card_actions_box.add_child(_make_action_button(a))

# Actions visibles d'une catégorie (filtre cachées / différées-réseau).
func _actions_in_category(cat: String) -> Array:
	var out: Array = []
	for a in registry.actions.values():
		if a.category != cat or a.id in _HIDDEN_ACTIONS:
			continue
		if GameConfig.is_multiplayer and a.id in _MP_DEFERRED:
			continue
		out.append(a)
	return out

func _make_action_button(a: GameAction) -> Button:
	var btn := Button.new()
	btn.text = a.label
	btn.disabled = not a.can_trigger() or not _net_my_turn()
	btn.tooltip_text = _action_tooltip(a)
	btn.pressed.connect(_on_action.bind(a))
	return btn

# === TOOLTIPS — toutes les infos viennent des mods (BuildingType / GameAction / DevelopmentCard) ===
func _action_tooltip(a: GameAction) -> String:
	if a.building_id != "":
		var bt: BuildingType = registry.get_building(a.building_id)
		if bt != null:
			return _building_tooltip(bt)
	var lines: Array = []
	if a.tooltip != "":
		lines.append(a.tooltip)
	if not a.cost.is_empty():
		lines.append("Coût : " + _format_cost(a.cost))
	return "\n".join(lines)

func _building_tooltip(bt: BuildingType) -> String:
	var lines: Array = [bt.display_name]
	if bt.description != "":
		lines.append(bt.description)
	if not bt.cost.is_empty():
		lines.append("Coût : " + _format_cost(bt.cost))
	if bt.victory_points != 0:
		lines.append("Points de victoire : %d" % bt.victory_points)
	var prod := bt.get_production_amount()
	if prod > 0:
		lines.append("Production : ×%d" % prod)
	return "\n".join(lines)

func _card_tooltip(card: DevelopmentCard) -> String:
	var lines: Array = [card.display_name]
	if card.description != "":
		lines.append(card.description)
	if card.victory_points != 0:
		lines.append("Points de victoire : %d" % card.victory_points)
	return "\n".join(lines)

func _format_cost(cost: Dictionary) -> String:
	var parts: Array = []
	for res in cost:
		var rname: String = res
		if registry.resources.has(res):
			rname = registry.resources[res].get("name", res)
		parts.append("%d %s" % [int(cost[res]), rname])
	return ", ".join(parts)

# === BAS: main de cartes du joueur courant ===
func _refresh_cards() -> void:
	_clear(_cards_box)
	var p := _view_player()
	if p.cards.is_empty():
		var empty := Label.new()
		empty.text = "(aucune carte)"
		_cards_box.add_child(empty)
		return
	var groups: Dictionary = {}
	for card in p.cards:
		if groups.has(card.id):
			groups[card.id]["count"] += 1
		else:
			groups[card.id] = {"card": card, "count": 1}
	for id in groups:
		var g = groups[id]
		var card: DevelopmentCard = g["card"]
		var btn := Button.new()
		btn.text = "%s (x%d)" % [card.display_name, g["count"]]
		btn.tooltip_text = _card_tooltip(card)
		btn.disabled = card.is_passive or not _net_my_turn()
		btn.pressed.connect(_on_play_card.bind(card))
		_cards_box.add_child(btn)

# === HAUT-CENTRE: journal (bouton repliable + menu scrollable) ===
func _toggle_log() -> void:
	_log_open = not _log_open
	_log_scroll.visible = _log_open
	_refresh_log()

func _refresh_log() -> void:
	if _log_button == null:
		return
	var lines: Array = []
	if _main != null:
		lines = _main.game_log
	_log_button.text = "📜 Journal (%d) %s" % [lines.size(), "▲" if _log_open else "▼"]
	if not _log_open:
		return  # menu fermé: rien à reconstruire
	_clear(_log_box)
	if lines.is_empty():
		var none := Label.new()
		none.text = "(rien pour l'instant)"
		_log_box.add_child(none)
		return
	# Plus récent en haut (pas besoin de scroller pour voir le dernier événement).
	for i in range(lines.size() - 1, -1, -1):
		var lab := Label.new()
		lab.text = str(lines[i])
		_log_box.add_child(lab)

# === HANDLERS ===
func _on_trade_with(target_id: int) -> void:
	if not _net_my_turn():
		return
	if GameConfig.is_multiplayer:
		if _main != null:
			_main.submit_command({"t": "trade_with", "target_id": target_id})
	else:
		if _busy():
			return
		registry.emit(ClassicCatanMod.EVT_REQUEST_TRADE_WITH, {"target_id": target_id})

func _on_play_card(card: DevelopmentCard) -> void:
	if not _net_my_turn():
		return
	if GameConfig.is_multiplayer:
		if _main != null:
			_main.submit_command({"t": "play_card", "card_id": card.id})
	else:
		if _busy():
			return
		registry.emit(ClassicCatanMod.EVT_REQUEST_PLAY_CARD, {"card": card})

func _on_action(a: GameAction) -> void:
	if registry.ui != null and registry.ui.is_any_panel_open():
		return
	if not _net_my_turn():
		return
	if GameConfig.is_multiplayer:
		if _main != null:
			_main.submit_command({"t": "action", "id": a.id})
	else:
		if not a.can_trigger():
			return
		a.callback.call()
	update()

func _trigger_action(id: String) -> void:
	if registry.ui != null and registry.ui.is_any_panel_open():
		return
	if not _net_my_turn():
		return
	if GameConfig.is_multiplayer:
		if _main != null:
			_main.submit_command({"t": "action", "id": id})
	else:
		var a: GameAction = registry.actions.get(id)
		if a == null or not a.can_trigger():
			return
		a.callback.call()
	update()

func _busy() -> bool:
	if registry.ui != null and registry.ui.is_any_panel_open():
		return true
	return state.phase != GameState.Phase.PLAY or state.is_busy()
