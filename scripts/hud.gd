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
var _movers: Array = []  # un WindowMover (drag + redim + sauvegarde) par panneau du HUD
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
	_log_button.pressed.connect(_toggle_log)
	for win in get_tree().get_nodes_in_group("hud_window"):
		if not is_ancestor_of(win):
			continue
		var mover := WindowMover.new()
		win.add_child(mover)
		mover.setup(win, _find_titlebar(win), win.name)  # drag (barre titre) + redim + sauvegarde
		_movers.append(mover)

func _find_titlebar(node: Node) -> Control:
	for c in node.get_children():
		if c is Control and c.is_in_group("hud_titlebar"):
			return c
		var found := _find_titlebar(c)
		if found != null:
			return found
	return null


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

# === PANNEAUX DÉPLAÇABLES / REDIMENSIONNABLES ===
# La logique (drag par la barre de titre, redim par la poignée bas-droite,
# sauvegarde de la position/taille) est déléguée à WindowMover (core/window_mover.gd),
# partagé avec les pop-ups. Ici on ne garde que la réinitialisation globale.

# Réinitialise position ET taille de tous les panneaux à l'origine (touches F1 / F6).
func reset_layout() -> void:
	for m in _movers:
		m.reset_visual()
	WindowMover.forget_all()  # efface les positions sauvegardées (HUD + pop-ups)

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
