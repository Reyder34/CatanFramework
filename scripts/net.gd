extends Node

# Couche réseau (autoload "Net"). Modèle P2P à hôte autoritaire via ENet.
# Phase 1: connexion, salon, et lancement synchronisé (seed + mods + assignation).

signal lobby_changed
signal connected
signal connection_failed
signal disconnected
signal config_changed

const DEFAULT_PORT := 24545
const MAX_PLAYERS := 10

var my_name := "Joueur"
var is_host := false
# peer_id -> {"name": String}
var players: Dictionary = {}

# === MODE RELAIS (Phase 2) ===
# Le relais est un process Godot headless qui est le SERVEUR ENet (pair 1) mais ne joue
# pas : il valide un token, suit les pairs, désigne le 1er client comme autorité, et relaie
# les paquets entre clients (server_relay natif). Tout le monde se connecte EN SORTANT.
var is_relay := false          # ce process est le serveur-relais passif (pair 1, ne joue pas)
var is_relay_client := false   # ce process est client d'un relais (présente un token au handshake)
var relay_token := ""          # côté relais : mot de passe attendu
var pending_token := ""        # côté client : token à présenter
var authority_peer_id := 1     # autorité de jeu. Direct = 1 (hôte). Relais : 0 tant qu'aucun client.
var in_game := false           # true après lancement (distingue déconnexion salon vs partie)

# Config du salon (réglée par l'hôte, diffusée à tous les pairs).
var lobby_mods: Array = []
var lobby_map_size: int = 2
var lobby_timer: int = 0

# Réf au noeud main (défini au lancement) pour les panneaux réseau.
var game: Node = null
var _panel_results: Dictionary = {}
var _req_counter := 0

func _ready() -> void:
	# Mode relais : `godot --headless -- --relay <port> <token>` -> ce process devient le
	# serveur-relais passif et ne branche PAS les signaux de jeu (il ne joue pas).
	var uargs := OS.get_cmdline_user_args()
	var ri := uargs.find("--relay")
	if ri >= 0 and ri + 2 < uargs.size():
		_start_relay(int(uargs[ri + 1]), String(uargs[ri + 2]))
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# === HÔTE / CLIENT ===

func host(port := DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	# max_clients = MAX_PLAYERS - 1 (l'hôte est déjà le peer 1) -> 10 joueurs au total.
	if peer.create_server(port, MAX_PLAYERS - 1) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	players = {1: {"name": my_name}}  # l'hôte est le peer 1
	lobby_changed.emit()
	return true

func join(ip: String, port := DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, port) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	return true

# === RELAIS (serveur passif) + AUTH PAR TOKEN ===

# Démarre le serveur-relais : valide le token au handshake, n'a pas de siège joueur.
func _start_relay(port: int, token: String) -> void:
	var sm := multiplayer as SceneMultiplayer
	sm.auth_callback = _relay_auth          # DOIT être réglé AVANT create_server
	sm.auth_timeout = 8.0                    # 3.0 par défaut est court pour un relais distant
	if not sm.peer_authentication_failed.is_connected(_on_auth_failed):
		sm.peer_authentication_failed.connect(_on_auth_failed)
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_PLAYERS) != OK:
		push_error("[relais] impossible d'ouvrir le port %d" % port)
		get_tree().quit()
		return
	multiplayer.multiplayer_peer = peer
	is_host = true
	is_relay = true
	relay_token = token
	authority_peer_id = 0     # aucun joueur encore : le 1er à s'enregistrer devient l'autorité
	players = {}              # le relais (pair 1) n'est PAS un joueur
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[relais] en écoute sur le port ", port)

# Auth côté relais : accepte si le token correspond, sinon coupe avant peer_connected.
func _relay_auth(id: int, data: PackedByteArray) -> void:
	var sm := multiplayer as SceneMultiplayer
	if data.get_string_from_utf8() == relay_token:
		sm.send_auth(id, "ok".to_utf8_buffer())
		sm.complete_auth(id)
	else:
		sm.disconnect_peer(id)

# Auth côté client : confirme la connexion à réception de l'accusé du relais.
func _client_auth(_id: int, data: PackedByteArray) -> void:
	var sm := multiplayer as SceneMultiplayer
	if data.get_string_from_utf8() == "ok":
		sm.complete_auth(_id)

# Le client présente son token quand le relais (pair 1) démarre le handshake.
func _on_authenticating(id: int) -> void:
	(multiplayer as SceneMultiplayer).send_auth(id, pending_token.to_utf8_buffer())

func _on_auth_failed(_id: int) -> void:
	if is_relay:
		return  # le relais a simplement rejeté un mauvais token : rien à faire
	leave()
	connection_failed.emit()  # côté client : mauvais mot de passe / timeout

# Rejoint un relais avec un token (auth bilatérale obligatoire).
func join_relay(ip: String, port: int, token: String) -> bool:
	pending_token = token
	is_relay_client = true
	var sm := multiplayer as SceneMultiplayer
	sm.auth_callback = _client_auth         # AVANT create_client (sinon timeout)
	sm.auth_timeout = 8.0
	if not sm.peer_authenticating.is_connected(_on_authenticating):
		sm.peer_authenticating.connect(_on_authenticating)
	if not sm.peer_authentication_failed.is_connected(_on_auth_failed):
		sm.peer_authentication_failed.connect(_on_auth_failed)
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, port) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	return true

# Suis-je l'autorité de jeu ? Direct : l'hôte. Relais : le client dont l'id == authority_peer_id.
func am_authority() -> bool:
	if is_relay:
		return false
	if is_relay_client:
		return multiplayer.get_unique_id() == authority_peer_id
	return is_host

func can_edit_lobby() -> bool:
	return am_authority()

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	# Réinitialise l'auth pour ne pas casser une partie LAN suivante (sans token).
	var sm := multiplayer as SceneMultiplayer
	if sm != null:
		sm.auth_callback = Callable()
	is_host = false
	is_relay = false
	is_relay_client = false
	relay_token = ""
	pending_token = ""
	authority_peer_id = 1
	in_game = false
	game = null
	players.clear()

# === SIGNAUX RÉSEAU ===

func _on_peer_connected(_id: int) -> void:
	pass  # le client va s'enregistrer via _register

func _on_peer_disconnected(id: int) -> void:
	# PARTIE EN COURS : si l'AUTORITÉ tombe -> fin de partie (reprise via sauvegarde).
	if in_game:
		if id == authority_peer_id:
			if is_relay:
				_authority_left.rpc()          # prévient les clients restants
				_reset_relay_after_game()      # le relais reste en écoute, prêt pour une reprise
			elif game != null:
				game.on_authority_lost()
		return
	# SALON : retire le joueur, ré-élit l'autorité si besoin, re-diffuse.
	players.erase(id)
	if is_host:
		if is_relay and id == authority_peer_id:
			authority_peer_id = 0
			var ids := players.keys()
			ids.sort()
			if not ids.is_empty():
				authority_peer_id = int(ids[0])
		_sync_lobby.rpc(players, authority_peer_id)
	lobby_changed.emit()

# Le relais redevient un salon vide après une partie : nouvelle autorité possible, reprise par save.
func _reset_relay_after_game() -> void:
	players.clear()
	authority_peer_id = 0
	in_game = false
	lobby_mods = []
	lobby_map_size = 2
	lobby_timer = 0

func _on_connected_to_server() -> void:
	_register.rpc_id(1, my_name)
	connected.emit()

func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()

func _on_server_disconnected() -> void:
	# Perte du serveur : soit le relais est tombé, soit (en direct) l'hôte=autorité a quitté.
	var g := game
	leave()
	if g != null:
		g.on_authority_lost()   # on était en partie -> retour menu propre
	else:
		disconnected.emit()

# === LOBBY (RPC) ===

@rpc("any_peer", "reliable")
func _register(pname: String) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	players[sender] = {"name": pname}
	if is_relay and authority_peer_id == 0:
		authority_peer_id = sender  # le 1er client enregistré devient l'autorité
	_sync_lobby.rpc(players, authority_peer_id)
	_sync_config.rpc(lobby_mods, lobby_map_size, lobby_timer)  # le nouveau venu reçoit la config
	lobby_changed.emit()

# authority transporté pour que chaque client sache QUI fait autorité (relais : un client).
@rpc("authority", "reliable")
func _sync_lobby(p: Dictionary, authority := 1) -> void:
	players = p
	authority_peer_id = authority
	lobby_changed.emit()

# === LANCEMENT SYNCHRONISÉ ===

func start_game() -> void:
	if not am_authority():
		return
	var s := randi()
	if s == 0:
		s = 1
	var ids := players.keys()
	ids.sort()
	var mapping := {}  # peer_id -> index joueur
	var names: Array = []  # index joueur -> pseudo
	for i in ids.size():
		mapping[ids[i]] = i
		names.append(players[ids[i]].get("name", ""))
	if is_relay_client:
		# L'autorité-client ne peut pas émettre _launch (@rpc authority) : elle demande au relais.
		_request_launch.rpc_id(1, s, ids.size(), mapping, lobby_mods, lobby_map_size, names, lobby_timer)
	else:
		# Direct : l'hôte est le serveur ET l'autorité ; son id (=1) fait foi.
		_launch.rpc(s, ids.size(), mapping, lobby_mods, lobby_map_size, names, lobby_timer, multiplayer.get_unique_id())

# L'autorité-client demande le lancement ; le relais (pair 1) émet _launch à tous.
@rpc("any_peer", "reliable")
func _request_launch(s: int, count: int, mapping: Dictionary, mods: Array, map_size: int, names: Array, timer: int) -> void:
	if not is_relay:
		return
	if multiplayer.get_remote_sender_id() != authority_peer_id:
		return
	in_game = true
	_launch.rpc(s, count, mapping, mods, map_size, names, timer, authority_peer_id)

# Config du salon: l'hôte la règle, on la diffuse à tous (sync live des cases mods…).
func set_lobby_config(mods: Array, map_size: int, timer: int) -> void:
	if not am_authority():
		return
	lobby_mods = mods
	lobby_map_size = map_size
	lobby_timer = timer
	if is_relay_client:
		_request_set_config.rpc_id(1, mods, map_size, timer)  # le relais re-diffuse
	else:
		_sync_config.rpc(mods, map_size, timer)               # direct : l'hôte=pair 1 diffuse

# L'autorité-client règle la config ; le relais (pair 1) la diffuse à tous.
@rpc("any_peer", "reliable")
func _request_set_config(mods: Array, map_size: int, timer: int) -> void:
	if not is_relay:
		return
	if multiplayer.get_remote_sender_id() != authority_peer_id:
		return
	lobby_mods = mods
	lobby_map_size = map_size
	lobby_timer = timer
	_sync_config.rpc(mods, map_size, timer)

@rpc("authority", "reliable")
func _sync_config(mods: Array, map_size: int, timer: int) -> void:
	lobby_mods = mods
	lobby_map_size = map_size
	lobby_timer = timer
	config_changed.emit()

# Reprise d'une sauvegarde: l'hôte applique le snapshot au boot ; chaque joueur récupère
# SON siège via son pseudo (mapping par nom), et tout le monde rejoue la MÊME seed.
func resume_game(snapshot: Dictionary, mods: Array, map_size: int, timer: int, names: Array, saved_seed: int) -> void:
	if not am_authority():
		return
	var mapping := {}  # peer_id -> index (par pseudo)
	for pid in players:
		var who: String = players[pid].get("name", "")
		var idx: int = names.find(who)
		mapping[pid] = idx if idx >= 0 else 0
	# Le snapshot est posé LOCALEMENT chez l'autorité (jamais transmis au relais) ; appliqué au boot.
	GameConfig.resume_snapshot = snapshot
	if is_relay_client:
		_request_launch.rpc_id(1, saved_seed, names.size(), mapping, mods, map_size, names, timer)
	else:
		_launch.rpc(saved_seed, names.size(), mapping, mods, map_size, names, timer, multiplayer.get_unique_id())

# === PANNEAUX RÉSEAU (Phase 2b) ===
# Affiche un panneau sur le client qui contrôle player_index, attend son résultat.
# En solo (ou si c'est ce peer), affiche localement. raw = params sérialisables;
# les objets (registry, player) sont injectés localement par _reconstruct.
func show_panel_for(player_index: int, panel_id: String, raw: Dictionary) -> Variant:
	if game == null:
		return null
	var is_local := (not GameConfig.is_multiplayer) or (player_index == GameConfig.local_player_index)
	if is_local:
		return await game.registry.ui.show_panel(panel_id, _reconstruct(panel_id, raw, player_index))
	var peer := _player_to_peer(player_index)
	if peer < 0:
		return null
	var req := _req_counter
	_req_counter += 1
	game.registry.ui.note_external_open()  # met le timer de tour en pause (pop-up distante)
	_show_panel_rpc.rpc_id(peer, req, panel_id, raw, player_index)
	while not _panel_results.has(req):
		await game.get_tree().process_frame
	var r = _panel_results[req]
	_panel_results.erase(req)
	game.registry.ui.note_external_close()
	return r

# Affiche plusieurs panneaux EN MÊME TEMPS (un par joueur) et attend TOUS les résultats.
# Séquentiel en solo (un seul écran), parallèle en réseau. requests = [{player_index, panel_id, raw}].
func show_panels_parallel(requests: Array) -> Array:
	var results: Array = []
	results.resize(requests.size())
	if requests.is_empty():
		return results
	if not GameConfig.is_multiplayer:
		for idx in requests.size():
			var r = requests[idx]
			results[idx] = await show_panel_for(r["player_index"], r["panel_id"], r["raw"])
		return results
	var remaining := {"n": requests.size()}
	for idx in requests.size():
		var r = requests[idx]
		_run_one_panel(r["player_index"], r["panel_id"], r["raw"], idx, results, remaining)
	while remaining["n"] > 0:
		await game.get_tree().process_frame
	return results

func _run_one_panel(player_index: int, panel_id: String, raw: Dictionary, idx: int, results: Array, remaining: Dictionary) -> void:
	results[idx] = await show_panel_for(player_index, panel_id, raw)
	remaining["n"] -= 1

func _player_to_peer(player_index: int) -> int:
	for pid in GameConfig.peer_to_player:
		if int(GameConfig.peer_to_player[pid]) == player_index:
			return int(pid)
	return -1

# Reconstruit les params complets (objets locaux) à partir des données sérialisables.
func _reconstruct(panel_id: String, raw: Dictionary, player_index: int) -> Dictionary:
	var p := raw.duplicate()
	p["registry"] = game.registry
	match panel_id:
		"bank_trade", "robber_discard":
			p["player"] = game.state.players[player_index]
		"trade_proposal":
			p["proposer"] = game.state.players[player_index]
		"trade_response":
			p["proposer"] = game.state.players[int(raw.get("proposer_index", 0))]
			p["responder"] = game.state.players[player_index]
		"robber_steal":
			p["players"] = game.state.players
	return p

# any_peer : en mode relais l'autorité (qui ouvre les panneaux distants) est un client.
# On vérifie que l'ordre vient bien de l'autorité avant d'afficher quoi que ce soit.
@rpc("any_peer", "reliable")
func _show_panel_rpc(req: int, panel_id: String, raw: Dictionary, player_index: int) -> void:
	if multiplayer.get_remote_sender_id() != GameConfig.authority_peer_id:
		return
	var result = await game.registry.ui.show_panel(panel_id, _reconstruct(panel_id, raw, player_index))
	_panel_response.rpc_id(GameConfig.authority_peer_id, req, result)

@rpc("any_peer", "reliable")
func _panel_response(req: int, result: Variant) -> void:
	_panel_results[req] = result

# Prévient les clients restants que l'autorité a quitté (relais vivant) -> retour menu propre.
@rpc("authority", "reliable")
func _authority_left() -> void:
	if game != null:
		game.on_authority_lost()
	else:
		disconnected.emit()

@rpc("authority", "reliable", "call_local")
func _launch(s: int, count: int, mapping: Dictionary, mods: Array, map_size: int, names: Array, timer: int, authority: int) -> void:
	if is_relay:
		return  # le relais reste au salon : il ne charge JAMAIS la scène de jeu
	in_game = true
	GameConfig.is_multiplayer = true
	GameConfig.game_seed = s
	GameConfig.player_count = count
	GameConfig.enabled_mod_ids = mods
	GameConfig.map_size = map_size
	GameConfig.player_names = names
	GameConfig.peer_to_player = mapping
	GameConfig.turn_timer = timer
	GameConfig.authority_peer_id = authority  # qui fait tourner la logique (direct: l'hôte=1)
	GameConfig.local_player_index = int(mapping.get(multiplayer.get_unique_id(), 0))
	get_tree().change_scene_to_file("res://scenes/main.tscn")
