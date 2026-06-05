extends Node

# Couche réseau (autoload "Net"). Modèle P2P à hôte autoritaire via ENet.
# Phase 1: connexion, salon, et lancement synchronisé (seed + mods + assignation).

signal lobby_changed
signal connected
signal connection_failed
signal disconnected

const DEFAULT_PORT := 24545
const MAX_PLAYERS := 10

var my_name := "Joueur"
var is_host := false
# peer_id -> {"name": String}
var players: Dictionary = {}

# Réf au noeud main (défini au lancement) pour les panneaux réseau.
var game: Node = null
var _panel_results: Dictionary = {}
var _req_counter := 0

func _ready() -> void:
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

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_host = false
	players.clear()

# === SIGNAUX RÉSEAU ===

func _on_peer_connected(_id: int) -> void:
	pass  # le client va s'enregistrer via _register

func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	if is_host:
		_sync_lobby.rpc(players)
	lobby_changed.emit()

func _on_connected_to_server() -> void:
	_register.rpc_id(1, my_name)
	connected.emit()

func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()

func _on_server_disconnected() -> void:
	leave()
	disconnected.emit()

# === LOBBY (RPC) ===

@rpc("any_peer", "reliable")
func _register(pname: String) -> void:
	if not is_host:
		return
	players[multiplayer.get_remote_sender_id()] = {"name": pname}
	_sync_lobby.rpc(players)
	lobby_changed.emit()

@rpc("authority", "reliable")
func _sync_lobby(p: Dictionary) -> void:
	players = p
	lobby_changed.emit()

# === LANCEMENT SYNCHRONISÉ ===

func start_game(enabled_mods: Array, map_size: int) -> void:
	if not is_host:
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
	_launch.rpc(s, ids.size(), mapping, enabled_mods, map_size, names)

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
	_show_panel_rpc.rpc_id(peer, req, panel_id, raw, player_index)
	while not _panel_results.has(req):
		await game.get_tree().process_frame
	var r = _panel_results[req]
	_panel_results.erase(req)
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

@rpc("authority", "reliable")
func _show_panel_rpc(req: int, panel_id: String, raw: Dictionary, player_index: int) -> void:
	var result = await game.registry.ui.show_panel(panel_id, _reconstruct(panel_id, raw, player_index))
	_panel_response.rpc_id(1, req, result)

@rpc("any_peer", "reliable")
func _panel_response(req: int, result: Variant) -> void:
	_panel_results[req] = result

@rpc("authority", "reliable", "call_local")
func _launch(s: int, count: int, mapping: Dictionary, mods: Array, map_size: int, names: Array) -> void:
	GameConfig.is_multiplayer = true
	GameConfig.game_seed = s
	GameConfig.player_count = count
	GameConfig.enabled_mod_ids = mods
	GameConfig.map_size = map_size
	GameConfig.player_names = names
	GameConfig.peer_to_player = mapping
	GameConfig.local_player_index = int(mapping.get(multiplayer.get_unique_id(), 0))
	get_tree().change_scene_to_file("res://scenes/main.tscn")
