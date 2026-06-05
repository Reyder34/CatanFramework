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

var _res_box: VBoxContainer
var _players_box: VBoxContainer
var _actions_box: HBoxContainer
var _cards_box: HBoxContainer
var _log_box: VBoxContainer
var _log_button: Button
var _log_scroll: ScrollContainer
var _log_open: bool = false
var _selected_breakdown: int = -1  # joueur dont on affiche le détail des points (-1 = aucun)
var _main: Node = null  # main (pour router les actions en réseau)

# Actions à panneaux/cartes désactivées en réseau (Phase 2b).
const _MP_DEFERRED := ["propose_trade", "show_dev_cards"]

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
	_build()
	_connect_signals()
	update()

func _build() -> void:
	# Haut-gauche: ressources
	var tl := _make_panel()
	_anchor_corner(tl, "top_left")
	_res_box = _titled_box(tl, "Ressources")
	# Haut-droit: joueurs + banque
	var tr := _make_panel()
	_anchor_corner(tr, "top_right")
	_players_box = _titled_box(tr, "Joueurs")
	# Bas-centre: actions + main
	var bottom := _make_panel()
	_anchor_corner(bottom, "bottom_center")
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	bottom.add_child(vb)
	vb.add_child(_title("Actions"))
	_actions_box = HBoxContainer.new()
	_actions_box.add_theme_constant_override("separation", 6)
	vb.add_child(_actions_box)
	vb.add_child(_title("Ma main"))
	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 6)
	vb.add_child(_cards_box)
	# Haut-centre: bouton "Journal" qui ouvre/ferme un menu déroulant scrollable
	# (évite de surcharger l'écran). Rempli par les events "game_log".
	var tc := _make_panel()
	_anchor_corner(tc, "top_center")
	var log_vb := VBoxContainer.new()
	tc.add_child(log_vb)
	_log_button = Button.new()
	_log_button.pressed.connect(_toggle_log)
	log_vb.add_child(_log_button)
	_log_scroll = ScrollContainer.new()
	_log_scroll.custom_minimum_size = Vector2(260, 160)
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_scroll.visible = false
	log_vb.add_child(_log_scroll)
	_log_box = VBoxContainer.new()
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_scroll.add_child(_log_box)

func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	add_child(panel)
	return panel

# Ancre un Control (qui se dimensionne à son contenu) dans un coin du HUD.
func _anchor_corner(c: Control, where: String) -> void:
	match where:
		"top_left":
			c.anchor_left = 0.0; c.anchor_right = 0.0
			c.anchor_top = 0.0; c.anchor_bottom = 0.0
			c.grow_horizontal = Control.GROW_DIRECTION_END
			c.grow_vertical = Control.GROW_DIRECTION_END
			c.offset_left = 8.0; c.offset_top = 8.0
		"top_right":
			c.anchor_left = 1.0; c.anchor_right = 1.0
			c.anchor_top = 0.0; c.anchor_bottom = 0.0
			c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			c.grow_vertical = Control.GROW_DIRECTION_END
			c.offset_right = -8.0; c.offset_top = 8.0
		"bottom_center":
			c.anchor_left = 0.5; c.anchor_right = 0.5
			c.anchor_top = 1.0; c.anchor_bottom = 1.0
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
			c.offset_bottom = -8.0
		"top_center":
			c.anchor_left = 0.5; c.anchor_right = 0.5
			c.anchor_top = 0.0; c.anchor_bottom = 0.0
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
			c.grow_vertical = Control.GROW_DIRECTION_END
			c.offset_top = 8.0

func _titled_box(panel: PanelContainer, title: String) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	vb.add_child(_title(title))
	var content := VBoxContainer.new()
	vb.add_child(content)
	return content

func _title(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	return lbl

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
	_refresh_actions()
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
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_make_passthrough(c)

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
		row.add_child(_swatch(registry.get_resource_color(res_id)))
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

# === BAS: barre d'actions (depuis les actions déclarées par les mods) ===
func _refresh_actions() -> void:
	_clear(_actions_box)
	for a in registry.actions.values():
		if a.category == "debug" or a.id in _HIDDEN_ACTIONS:
			continue
		if GameConfig.is_multiplayer and a.id in _MP_DEFERRED:
			continue
		var btn := Button.new()
		btn.text = a.label
		btn.disabled = not a.can_trigger() or not _net_my_turn()
		btn.pressed.connect(_on_action.bind(a))
		_actions_box.add_child(btn)

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
