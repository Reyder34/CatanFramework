extends Node3D

var registry: GameRegistry
var state: GameState
var board: Board
var board_view: BoardView
var hud: GameHud

var loaded_mods: Array = []
var _snapshot_dirty := false  # réseau (hôte): un changement à diffuser
var _authority_lost := false  # réseau: l'autorité a quitté (évite un double retour menu)
var game_log: Array = []  # derniers événements (dés, actions...), synchronisé en réseau

const OPTIONS_MENU := preload("res://scenes/options_menu.tscn")
var _sun: DirectionalLight3D = null   # soleil : arc est->ouest, intensité ~ hauteur, ombres mobiles
var _moon: DirectionalLight3D = null  # lune : faible lumière blanche la nuit
var _env: Environment = null          # ambiance (remplissage) modulée jour/nuit
var _sky_mat: ShaderMaterial = null   # matériau du ciel (fige cycle_duration si jour/nuit off)
var _clean_view := false  # F12 : masque HUD + labels 3D pour les screenshots

func _ready() -> void:
	# Seed partagée (réseau) -> plateau + ports identiques chez tous les joueurs.
	if GameConfig.game_seed != 0:
		seed(GameConfig.game_seed)
	registry = GameRegistry.new()
	registry.setup_ui($UI/HUD)
	$UI/HUD.theme = load("res://ui/theme.tres")  # thème partagé -> tous les pop-ups héritent
	registry.events.subscribe("flash_tile", _flash_tile_handler, 0, "core")
	registry.events.subscribe("game_log", _on_game_log, 0, "core")
	
	# Chargement des mods activés (le ModLoader résout l'ordre des dépendances + conflits)
	_load_mods()
	
	# Taille de la map choisie au lobby (hors core): pilote board_radius, que les
	# générateurs lisent. Override le défaut posé par les mods.
	registry.set_board_radius(GameConfig.map_size)

	# Création de l'état après chargement (le registry est rempli)
	board = Board.new()
	board_view = BoardView.new(registry, board)
	board_view.on_tile_click = _on_tile_clicked
	board_view.on_vertex_click = _on_vertex_clicked
	board_view.on_edge_click = _on_edge_clicked
	board_view.generate(self)
	
	state = GameState.new(registry, GameConfig.player_count)

	# Pseudo des joueurs (réseau): index -> nom (sinon "J<id>" via Player.label()).
	for i in state.players.size():
		if i < GameConfig.player_names.size() and str(GameConfig.player_names[i]) != "":
			state.players[i].display_name = str(GameConfig.player_names[i])

	# Ressources de départ (0 par défaut; un mod peut en distribuer via l'event game_start).
	for p in state.players:
		for res_id in registry.resources:
			if not registry.resources[res_id].get("is_desert", false):
				p.resources[res_id] = 0	
	
	registry.emit("game_start", {
		"state": state,
		"board": board,
		"registry": registry,
		"board_view": board_view,
	})

	hud = preload("res://scenes/hud.tscn").instantiate()
	$UI/HUD.add_child(hud)
	hud.setup(state, registry, board, self)

	# Son "à toi de jouer" (core): -1 en solo (chaque tour), sinon le joueur local.
	var turn_audio := TurnAudio.new()
	add_child(turn_audio)
	turn_audio.setup(state, GameConfig.local_player_index if GameConfig.is_multiplayer else -1)

	# Timer de tour (core, réglé au lobby/solo ; 0 = off). À l'expiration -> "turn_timeout".
	var turn_timer := TurnTimer.new()
	add_child(turn_timer)
	turn_timer.setup(state, registry, GameConfig.turn_timer, _authoritative())
	# À l'expiration du tour : on annule les pop-ups optionnelles (échange/banque) en cours.
	registry.on("turn_timeout", _on_turn_timeout_cancel, 0)

	# Réseau: panneaux + diffusion d'état (hôte) sur tout changement.
	Net.game = self
	if GameConfig.is_multiplayer and _authoritative():
		_connect_broadcast_signals()

	# Reprise de partie (autorité) : applique le snapshot chargé, puis il sera diffusé.
	if _authoritative() and not GameConfig.resume_snapshot.is_empty():
		_apply_snapshot(_snapshot_from_json(GameConfig.resume_snapshot))
		GameConfig.resume_snapshot = {}
		_snapshot_dirty = true

	print("Jeu prêt. Mods chargés: ", registry._origin.size(), " entrées dans le registry")

	# Éclairage jour/nuit : cycle long en jeu (10 min jour + 10 min nuit), puis collecte des lampes.
	DayNight.cycle_seconds = 1200.0
	_collect_lights()
	Settings.graphics_changed.connect(_apply_graphics)
	_apply_graphics()
	# On intercepte la fermeture (Alt+F4 / croix) pour proposer la sauvegarde à l'hôte.
	get_tree().set_auto_accept_quit(false)
	# Au chargement en multi (lancement OU rejoin), un client demande l'état complet à l'autorité.
	# INDISPENSABLE au RETOUR : le revenant repart d'un plateau initial -> ce resync le rattrape.
	# Différé pour que la scène + le réseau soient prêts ; silencieux pour ne pas spammer le journal.
	if GameConfig.is_multiplayer and not _authoritative():
		_request_resync.call_deferred(true)
	Music.set_context("game")  # bascule sur les playlists jour/nuit

func _load_mods() -> void:
	# Mods choisis dans le menu (GameConfig), + expansion des dépendances par sécurité.
	var catalog: Array = ModCatalog.create_all()
	var by_id: Dictionary = {}
	for m in catalog:
		by_id[m.mod_id] = m
	var enabled: Dictionary = {}
	for id in GameConfig.enabled_mod_ids:
		_mark_with_deps(id, by_id, enabled)
	var to_load: Array = []
	for m in catalog:
		if enabled.has(m.mod_id):
			to_load.append(m)
	# Le ModLoader résout l'ordre (depends_on) et vérifie les conflits.
	loaded_mods = ModLoader.load_mods(registry, to_load)

func _mark_with_deps(id: String, by_id: Dictionary, enabled: Dictionary) -> void:
	if not by_id.has(id) or enabled.has(id):
		return
	enabled[id] = true
	for dep in by_id[id].depends_on:
		_mark_with_deps(dep, by_id, enabled)
	


# === ENTRÉES UTILISATEUR ===

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_M:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	if event.keycode == KEY_F5:
		_request_resync()  # anti-désync: l'hôte re-diffuse l'état complet à tous
		return
	if event.keycode == KEY_F1 or event.keycode == KEY_F6:
		if hud != null:
			hud.reset_layout()  # réinitialise position + taille de l'UI
		return
	if event.keycode == KEY_F12:
		_toggle_clean_view()  # masque HUD + numéros/ratios pour les screenshots
		return
	# Échap : menu d'options, accessible à tout moment.
	# Exception : si un mode construction est actif, Échap l'annule d'abord (cancel_build, même touche).
	if event.keycode == KEY_ESCAPE and not event.echo:
		if has_node("OptionsMenu"):
			return  # overlay déjà ouvert : il gère lui-même sa fermeture
		if state.build_mode_id == "":
			var opt := OPTIONS_MENU.instantiate()
			add_child(opt)
			opt.set_game(self)  # affiche le bouton "Quitter la partie"
			get_viewport().set_input_as_handled()
			return
		# sinon : laisser l'action cancel_build s'exécuter (flux normal ci-dessous)
	if state.phase == GameState.Phase.GAME_OVER:
		return
	if not _can_local_act():
		return
	var action: GameAction = registry.find_action_by_hotkey(event.keycode)
	if action == null:
		return
	if GameConfig.is_multiplayer and action.id in MP_DEFERRED_ACTIONS:
		return
	if not action.can_trigger():
		return
	submit_command({"t": "action", "id": action.id})
	hud.update()


# === CLICS ===

func _on_tile_clicked(_cam, event, _pos, _norm, _idx, tile: StaticBody3D) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if state.phase == GameState.Phase.GAME_OVER or not _can_local_act():
		return
	submit_command({"t": "click", "target": "tile", "key": "", "coords": tile.get_meta("coords")})
	hud.update()

func _on_vertex_clicked(_cam, event, _pos, _norm, _idx, body: StaticBody3D) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if state.phase == GameState.Phase.GAME_OVER or not _can_local_act():
		return
	submit_command({"t": "click", "target": "vertex", "key": body.get_meta("key"), "coords": Vector2.ZERO})
	hud.update()

func _on_edge_clicked(_cam, event, _pos, _norm, _idx, body: StaticBody3D) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if state.phase == GameState.Phase.GAME_OVER or not _can_local_act():
		return
	submit_command({"t": "click", "target": "edge", "key": body.get_meta("key"), "coords": Vector2.ZERO})
	hud.update()

# === MULTIJOUEUR (Phase 2a: clics + actions hors panneaux) ===

# Actions différées en réseau (panneaux/cartes) -> Phase 2b.
const MP_DEFERRED_ACTIONS := ["show_dev_cards", "debug_hello"]

func _authoritative() -> bool:
	# Autorité = ce pair fait tourner la logique. En direct, l'hôte (pair 1) EST le serveur ;
	# en mode relais, l'autorité est un client distinct du serveur (authority_peer_id != 1).
	return not GameConfig.is_multiplayer or multiplayer.get_unique_id() == GameConfig.authority_peer_id

# Le joueur local peut-il agir maintenant (son tour, pas de panneau ouvert) ?
func _can_local_act() -> bool:
	if registry.ui != null and registry.ui.is_any_panel_open():
		return false
	if not GameConfig.is_multiplayer:
		return true
	return state.current_player_index == GameConfig.local_player_index

# Solo/hôte: applique direct (+ diffuse). Client: envoie la commande à l'hôte.
func submit_command(cmd: Dictionary) -> void:
	if _authoritative():
		var by := GameConfig.local_player_index if GameConfig.is_multiplayer else state.current_player_index
		_apply_command(cmd, by)
	else:
		_net_command.rpc_id(GameConfig.authority_peer_id, cmd)

@rpc("any_peer", "reliable")
func _net_command(cmd: Dictionary) -> void:
	if not _authoritative():
		return
	var by := int(GameConfig.peer_to_player.get(multiplayer.get_remote_sender_id(), -1))
	_apply_command(cmd, by)
	if hud != null:
		hud.update()  # l'hôte rafraîchit son affichage après une action d'un client

# Anti-désync (touche F5): force l'hôte à re-diffuser l'état complet à tous.
# N'importe qui peut le déclencher: si client, on demande à l'hôte de rediffuser.
func _request_resync(silent := false) -> void:
	if not GameConfig.is_multiplayer:
		return
	if _authoritative():
		_do_resync(silent)
	else:
		_ask_resync.rpc_id(GameConfig.authority_peer_id, silent)

@rpc("any_peer", "reliable")
func _ask_resync(silent := false) -> void:
	if _authoritative():
		_do_resync(silent)

func _do_resync(silent := false) -> void:
	if not silent:
		registry.emit("game_log", {"text": "🔄 Resynchronisation"})
	_snapshot_dirty = true
	if hud != null:
		hud.update()

# Appelé par Net quand l'autorité (ou le relais) tombe : on termine proprement et on rentre au menu.
func on_authority_lost() -> void:
	if _authority_lost:
		return  # déjà géré (peut être notifié 2x : _authority_left + peer_disconnected)
	_authority_lost = true
	if state != null:
		state.phase = GameState.Phase.GAME_OVER
	registry.emit("game_log", {"text": "⚠️ L'hôte a quitté. Partie terminée."})
	if hud != null:
		hud.update()
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# === QUITTER LA PARTIE / FERMETURE DE LA FENÊTRE ===

# Bouton "Quitter la partie" du menu d'options (Échap). Client (non-autorité) : on quitte vers le
# menu (on pourra REVENIR via Rejoindre, même pseudo). Hôte/solo : confirmation de sauvegarde.
func request_quit_to_menu() -> void:
	if _authoritative():
		_show_quit_confirmation(false)  # -> menu après (ou sans) sauvegarde
	else:
		_leave_to_menu()

# Alt+F4 / croix de la fenêtre (set_auto_accept_quit(false) en _ready -> on intercepte).
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if _authoritative():
		_show_quit_confirmation(true)   # proposer la sauvegarde, puis fermer l'appli
	else:
		Net.leave()
		get_tree().quit()

func _leave_to_menu() -> void:
	Net.leave()  # client : se déconnecte (l'hôte continue) ; hôte : ferme le serveur (fin de partie)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# Confirmation pour l'autorité : sauvegarder ou non avant de quitter.
# quit_app = true -> fermer l'appli (Alt+F4) ; false -> revenir au menu.
func _show_quit_confirmation(quit_app: bool) -> void:
	if has_node("QuitDialog"):
		return
	var dlg := ConfirmationDialog.new()
	dlg.name = "QuitDialog"
	dlg.title = "Quitter la partie"
	dlg.dialog_text = "Sauvegarder la partie avant de quitter ?"
	dlg.ok_button_text = "💾 Sauvegarder et quitter"
	dlg.add_button("Quitter sans sauvegarder", false, "no_save")
	dlg.get_cancel_button().text = "Annuler"
	dlg.confirmed.connect(func() -> void:
		_do_save_game()
		_finish_quit(quit_app))
	dlg.custom_action.connect(func(action: StringName) -> void:
		if action == "no_save":
			dlg.hide()
			_finish_quit(quit_app))
	dlg.canceled.connect(dlg.queue_free)
	dlg.close_requested.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

func _do_save_game() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	save_game("partie_" + stamp)

func _finish_quit(quit_app: bool) -> void:
	if quit_app:
		Net.leave()
		get_tree().quit()
	else:
		_leave_to_menu()

# Expiration du timer (émise sur l'autorité uniquement) : on annule les pop-ups optionnelles
# (échange/banque) ouvertes ici ET chez chaque client, pour ne pas laisser un échange traîner.
func _on_turn_timeout_cancel(_ctx) -> void:
	broadcast_cancel_modals()

# Ferme les pop-ups modales ouvertes ICI et chez TOUS les clients. Appelé par l'autorité :
# à l'expiration du timer, ou quand un échange est conclu (le 1er accepteur ferme l'UI de tous).
func broadcast_cancel_modals() -> void:
	if registry.ui != null:
		registry.ui.cancel_open_modals()
	if not GameConfig.is_multiplayer:
		return
	var me := multiplayer.get_unique_id()
	for pid in GameConfig.peer_to_player:
		if int(pid) != me:
			_net_cancel_modals.rpc_id(int(pid))

@rpc("any_peer", "reliable")
func _net_cancel_modals() -> void:
	if multiplayer.get_remote_sender_id() != GameConfig.authority_peer_id:
		return
	if registry.ui != null:
		registry.ui.cancel_open_modals()

func _apply_command(cmd: Dictionary, by: int) -> void:
	if not _authoritative():
		return
	if by != state.current_player_index:  # seul le joueur courant agit
		return
	match cmd.get("t", ""):
		"click":
			_do_click(cmd, by)
		"action":
			_do_action(cmd.get("id", ""))
		"trade_with":
			registry.emit(ClassicCatanMod.EVT_REQUEST_TRADE_WITH, {"target_id": int(cmd.get("target_id", -1))})
		"play_card":
			_do_play_card(by, cmd.get("card_id", ""))
	_snapshot_dirty = true

func _do_play_card(by: int, card_id: String) -> void:
	var pl: Player = state.players[by]
	for c in pl.cards:
		if c.id == card_id:
			registry.emit(ClassicCatanMod.EVT_REQUEST_PLAY_CARD, {"card": c})
			return

func _do_click(cmd: Dictionary, by: int) -> void:
	var ctx := ClickContext.new()
	ctx.state = state
	ctx.board = board
	ctx.player_id = by
	match cmd.get("target", ""):
		"tile":
			ctx.target_coords = cmd.get("coords", Vector2.ZERO)
			registry.emit("tile_clicked", ctx)
		"vertex":
			ctx.target_key = cmd.get("key", "")
			registry.emit("vertex_clicked", ctx)
		"edge":
			ctx.target_key = cmd.get("key", "")
			registry.emit("edge_clicked", ctx)

func _do_action(id: String) -> void:
	if GameConfig.is_multiplayer and id in MP_DEFERRED_ACTIONS:
		return
	var action: GameAction = registry.actions.get(id)
	if action == null or not action.can_trigger():
		return
	action.callback.call()

# Snapshot d'état diffusé par l'hôte; les clients l'appliquent (affichage).
func _build_snapshot() -> Dictionary:
	var pdata: Array = []
	for p in state.players:
		var effs: Array = []
		for e in p.effects:
			effs.append({"id": e.id, "name": e.display_name, "vp": e.victory_points})
		# custom_data filtré aux types de base (sérialisable; ex: flag "dés lancés").
		var cd: Dictionary = {}
		for k in p.custom_data:
			var v = p.custom_data[k]
			if v is int or v is float or v is bool or v is String:
				cd[k] = v
		var cards_data: Array = []
		for c in p.cards:
			cards_data.append({"id": c.id, "name": c.display_name, "vp": c.victory_points, "passive": c.is_passive})
		pdata.append({"resources": p.resources.duplicate(), "effects": effs, "custom_data": cd, "cards": cards_data})
	return {
		"vertex_state": board.vertex_state.duplicate(true),
		"edge_state": board.edge_state.duplicate(true),
		"markers": board.tile_markers.duplicate(),
		"current_player": state.current_player_index,
		"phase": state.phase,
		"sub_phase": state.sub_phase,
		"winner": state.winner_index,
		"build_mode": state.build_mode_id,
		"players": pdata,
		"log": game_log.duplicate(),
	}

# === SAUVEGARDE / REPRISE ===
# L'autorité écrit l'état complet (méta + snapshot) dans user://saves/<slot>.json.
func save_game(slot: String) -> bool:
	DirAccess.make_dir_recursive_absolute(GameConfig.SAVES_DIR)
	var data := {
		"meta": {
			"mods": GameConfig.enabled_mod_ids,
			"map_size": GameConfig.map_size,
			"seed": GameConfig.game_seed,
			"timer": GameConfig.turn_timer,
			"names": GameConfig.player_names,
			"turn": state.current_player_index,
		},
		"snapshot": _snapshot_to_json(_build_snapshot()),
	}
	var f := FileAccess.open("%s/%s.json" % [GameConfig.SAVES_DIR, slot], FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	registry.emit("game_log", {"text": "💾 Partie sauvegardée : %s" % slot})
	return true

# JSON ne connaît pas Vector2 -> marqueurs en [x, y] (et inversement au chargement).
func _snapshot_to_json(snap: Dictionary) -> Dictionary:
	var s := snap.duplicate()
	var m := {}
	for id in snap.get("markers", {}):
		var v: Vector2 = snap["markers"][id]
		m[id] = [v.x, v.y]
	s["markers"] = m
	return s

func _snapshot_from_json(j: Dictionary) -> Dictionary:
	var s := j.duplicate(true)
	var m := {}
	for id in j.get("markers", {}):
		var a = j["markers"][id]
		m[id] = Vector2(float(a[0]), float(a[1]))
	s["markers"] = m
	# JSON ramène les entiers en float -> on réentier les champs indexés/sensibles.
	for key in s.get("vertex_state", {}):
		s["vertex_state"][key]["owner"] = int(s["vertex_state"][key]["owner"])
	for key in s.get("edge_state", {}):
		s["edge_state"][key]["owner"] = int(s["edge_state"][key]["owner"])
	for pd in s.get("players", []):
		var r := {}
		for res in pd.get("resources", {}):
			r[res] = int(pd["resources"][res])
		pd["resources"] = r
	return s

# any_peer (et non "authority") car en mode relais l'autorité est un CLIENT, pas le serveur.
# On n'accepte donc un snapshot QUE s'il vient bien du pair autorité.
@rpc("any_peer", "reliable")
func _net_snapshot(snap: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != GameConfig.authority_peer_id:
		return
	_apply_snapshot(snap)

func _apply_snapshot(snap: Dictionary) -> void:
	# Incrémental: ne rafraîchir QUE les cases changées (sinon on ré-instancie tous les
	# modèles 3D de bâtiments + re-rend les 126 sommets/arêtes à CHAQUE snapshot -> gros
	# à-coups pendant les actions).
	var new_v: Dictionary = snap["vertex_state"]
	var new_e: Dictionary = snap["edge_state"]
	var new_m: Dictionary = snap["markers"]
	var changed_v := _diff_keys(board.vertex_state, new_v)
	var changed_e := _diff_keys(board.edge_state, new_e)
	var changed_m := _diff_keys(board.tile_markers, new_m)
	board.vertex_state = new_v
	board.edge_state = new_e
	board.tile_markers = new_m
	for key in changed_v:
		board_view._refresh_vertex(key)
	for key in changed_e:
		board_view._refresh_edge(key)
	for mid in changed_m:
		board.marker_changed.emit(mid, board.tile_markers.get(mid, Vector2.INF))
	state.current_player_index = snap["current_player"]
	state.build_mode_id = snap["build_mode"]
	state.winner_index = snap["winner"]
	state.phase = snap["phase"]
	state.sub_phase = snap["sub_phase"]
	for i in state.players.size():
		var pd: Dictionary = snap["players"][i]
		var p: Player = state.players[i]
		var res_changed: bool = p.resources != pd["resources"]
		p.resources = pd["resources"]
		if res_changed:
			p.resources_changed.emit(p.id)
		for k in pd.get("custom_data", {}):
			p.custom_data[k] = pd["custom_data"][k]
		_rebuild_buildings(p)
		_rebuild_effects(p, pd["effects"])
		_rebuild_cards(p, pd.get("cards", []))
	game_log = snap.get("log", [])
	if hud != null:
		hud.update()

# Clés dont la valeur a changé (ajout / suppression / modif) entre deux dictionnaires.
func _diff_keys(old: Dictionary, new: Dictionary) -> Array:
	var out: Dictionary = {}
	for k in old:
		if not new.has(k) or new[k] != old[k]:
			out[k] = true
	for k in new:
		if not old.has(k) or old[k] != new[k]:
			out[k] = true
	return out.keys()

# Reconstruit player.buildings depuis l'état du board (pour les PV/affichage côté client).
func _rebuild_buildings(p: Player) -> void:
	p.buildings.clear()
	for key in board.vertex_state:
		if int(board.vertex_state[key].get("owner", -1)) == p.id:
			var t: String = board.vertex_state[key].get("type", "")
			p.buildings.append(PlacedBuilding.new(registry.get_building(t), key, "vertex"))
	for key in board.edge_state:
		if int(board.edge_state[key].get("owner", -1)) == p.id:
			var t: String = board.edge_state[key].get("type", "")
			p.buildings.append(PlacedBuilding.new(registry.get_building(t), key, "edge"))
	p.buildings_changed.emit(p.id)

func _rebuild_effects(p: Player, effects_data: Array) -> void:
	p.effects.clear()
	for e in effects_data:
		var eff := PlayerEffect.new()
		eff.id = e["id"]
		eff.display_name = e["name"]
		eff.victory_points = int(e["vp"])
		p.effects.append(eff)
	p.effects_changed.emit(p.id)

# Reconstruit la main (cartes) en stubs pour l'affichage + les PV. Jouer une carte
# se fait par id -> l'hôte joue la vraie carte (qui a le comportement on_play).
func _rebuild_cards(p: Player, cards_data: Array) -> void:
	p.cards.clear()
	for c in cards_data:
		var card := DevelopmentCard.new()
		card.id = c["id"]
		card.display_name = c["name"]
		card.victory_points = int(c["vp"])
		card.is_passive = c["passive"]
		p.cards.append(card)
	p.cards_changed.emit(p.id)

func _connect_broadcast_signals() -> void:
	for p in state.players:
		p.resources_changed.connect(func(_i): _snapshot_dirty = true)
		p.buildings_changed.connect(func(_i): _snapshot_dirty = true)
		p.effects_changed.connect(func(_i): _snapshot_dirty = true)
		p.custom_data_changed.connect(func(_i, _k): _snapshot_dirty = true)
	board.vertex_changed.connect(func(_k): _snapshot_dirty = true)
	board.edge_changed.connect(func(_k): _snapshot_dirty = true)
	board.marker_changed.connect(func(_m, _c): _snapshot_dirty = true)
	state.status_changed.connect(func(): _snapshot_dirty = true)

func _process(_delta: float) -> void:
	_apply_day_night()
	if _snapshot_dirty and GameConfig.is_multiplayer and _authoritative():
		_snapshot_dirty = false
		_send_snapshot_to_clients(_build_snapshot())

# Éclairage jour/nuit (cycle global DayNight) : module énergie + couleur des lampes du plateau.
func _collect_lights() -> void:
	_sun = get_node_or_null("Sun") as DirectionalLight3D
	_moon = get_node_or_null("Moon") as DirectionalLight3D
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null:
		_env = we.environment
	var sky_rect := get_node_or_null("Sky/ColorRect") as ColorRect
	if sky_rect != null:
		_sky_mat = sky_rect.material as ShaderMaterial

func _apply_day_night() -> void:
	# Soleil : on l'oriente selon l'arc du cycle (ombres qui balayent est-ouest), intensité + couleur.
	if _sun != null:
		var dir: Vector3 = DayNight.sun_direction
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.BACK
		_sun.look_at(_sun.global_position + dir, up)
		_sun.light_energy = DayNight.sun_energy
		_sun.light_color = DayNight.sun_color
		_sun.visible = DayNight.sun_energy > 0.001  # éteint sous l'horizon
	# Lune : faible lumière blanche la nuit.
	if _moon != null:
		_moon.light_energy = DayNight.moon_energy
		_moon.visible = DayNight.moon_energy > 0.001
	# Ambiance : remplissage clair le jour, sombre bleuté la nuit (évite le noir total).
	if _env != null:
		_env.ambient_light_color = DayNight.ambient_color
		_env.ambient_light_energy = DayNight.ambient_energy

# Réglages graphiques (preset + cycle jour/nuit). Au démarrage et sur Settings.graphics_changed.
func _apply_graphics() -> void:
	Settings.apply_world(_env, _sun, get_viewport())
	if _sky_mat != null:
		# Cycle jour/nuit off -> ciel figé à midi (cycle_duration énorme).
		var cd := 1200.0 if Settings.day_night_enabled else 1.0e9
		_sky_mat.set_shader_parameter("cycle_duration", cd)

# F12 : mode "screenshot" — masque le HUD (2D) + tous les Label3D (numéros de tuiles, ratios de ports).
func _toggle_clean_view() -> void:
	_clean_view = not _clean_view
	$UI.visible = not _clean_view
	_set_labels_3d_visible(self, not _clean_view)

func _set_labels_3d_visible(node: Node, vis: bool) -> void:
	for child in node.get_children():
		if child is Label3D:
			child.visible = vis
		_set_labels_3d_visible(child, vis)

# Envoi CIBLÉ à chaque joueur (sauf soi) plutôt qu'un rpc() global : en mode relais le
# serveur n'est pas un joueur, il ne doit jamais recevoir de RPC de jeu (il relaie seulement).
func _send_snapshot_to_clients(snap: Dictionary) -> void:
	var me := multiplayer.get_unique_id()
	for pid in GameConfig.peer_to_player:
		if int(pid) != me:
			_net_snapshot.rpc_id(int(pid), snap)

func _flash_tile_handler(ctx: Dictionary) -> void:
	var coords: Vector2 = ctx.get("coords", Vector2.ZERO)
	var tile: Node = board_view.tile_nodes.get(coords)
	if tile == null:
		return
	# Flash robuste pour l'hexagone procédural ET les tuiles 3D (.glb). On superpose un
	# overlay blanc translucide sur tous les MeshInstance3D, puis on le retire (sans
	# toucher au matériau d'origine). Les tuiles à modèle n'ont PAS de material_override
	# -> l'ancienne version (mesh_inst.material_override.albedo_color) plantait dessus.
	var meshes := _collect_mesh_instances(tile)
	var overlay := StandardMaterial3D.new()
	overlay.albedo_color = Color(1, 1, 1, 0.75)
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mi in meshes:
		mi.material_overlay = overlay
	await get_tree().create_timer(0.4).timeout
	for mi in meshes:
		if is_instance_valid(mi):
			mi.material_overlay = null

# Tous les MeshInstance3D sous un nœud (récursif) : flashe une tuile quel que soit son
# rendu (cylindre procédural ou modèle 3D avec décor).
func _collect_mesh_instances(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_collect_mesh_instances(c))
	return out

# Journal: un mod émet "game_log" {text}. On garde les derniers messages et on les
# synchronise (snapshot) pour que tous les joueurs voient le même journal.
func _on_game_log(ctx) -> void:
	var text := ""
	if ctx is Dictionary:
		text = str(ctx.get("text", ""))
	else:
		text = str(ctx)
	if text == "":
		return
	game_log.append(text)
	while game_log.size() > 30:
		game_log.pop_front()
	if _authoritative():
		_snapshot_dirty = true
	if hud != null:
		hud.update()
