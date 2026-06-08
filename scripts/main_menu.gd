extends Control

# Menu à 4 écrans distincts :
#   ACCUEIL : Solo / Multijoueur / Quitter
#   SOLO    : toutes les options (mods, joueurs, taille, timer) + Lancer
#   MULTI   : Héberger / Rejoindre
#   SALON   : joueurs + options (l'HÔTE règle, tout le monde voit EN DIRECT) + Lancer
# La même ConfigBox (options) est DÉPLACÉE dans l'écran Solo ou dans le Salon.

@onready var _name_edit: LineEdit = %NameEdit
@onready var _ip_edit: LineEdit = %IpEdit
@onready var _player_spin: SpinBox = %PlayerSpin
@onready var _map_spin: SpinBox = %MapSpin
@onready var _timer_spin: SpinBox = %TimerSpin
@onready var _mod_list: VBoxContainer = %ModList
@onready var _config_box: VBoxContainer = %ConfigBox
@onready var _config_title: Label = %ConfigTitle
@onready var _pc_row: HBoxContainer = %PcRow
@onready var _home_box: VBoxContainer = %HomeBox
@onready var _solo_box: VBoxContainer = %SoloBox
@onready var _solo_slot: VBoxContainer = %SoloConfigSlot
@onready var _multi_box: VBoxContainer = %MultiBox
@onready var _lobby_box: VBoxContainer = %LobbyBox
@onready var _lobby_slot: VBoxContainer = %LobbyConfigSlot
@onready var _lobby_list: VBoxContainer = %LobbyList
@onready var _saves_label: Label = %SavesLabel
@onready var _saves_list: VBoxContainer = %SavesList
@onready var _start_btn: Button = %StartBtn
@onready var _status: Label = %Status
@onready var _relay_form: VBoxContainer = %RelayForm
@onready var _relay_addr: LineEdit = %RelayAddrEdit
@onready var _relay_port: SpinBox = %RelayPortSpin
@onready var _relay_token: LineEdit = %RelayTokenEdit

var _mods: Dictionary = {}        # id -> GameMod
var _enabled: Dictionary = {}     # id -> bool
var _checkboxes: Dictionary = {}  # id -> CheckBox
var _in_lobby := false
var _suppress_push := false       # vrai quand on APPLIQUE une config reçue (pas de re-broadcast)
var _config_published := false    # l'autorité a-t-elle déjà publié sa config initiale au salon ?

func _ready() -> void:
	if Net.is_relay:
		return  # process relais (--relay) : pas de menu, on laisse Net faire serveur
	GameConfig.is_multiplayer = false
	Net.leave()
	get_window().content_scale_factor = 1.0
	if Net.my_name != "":
		_name_edit.text = Net.my_name
	_player_spin.value = clampi(GameConfig.player_count, 2, 10)
	_map_spin.value = clampi(GameConfig.map_size, 2, 6)
	_timer_spin.value = clampi(GameConfig.turn_timer, 0, 600)
	%SoloBtn.pressed.connect(_show_solo)
	%MultiBtn.pressed.connect(_show_multi)
	%QuitBtn.pressed.connect(func() -> void: get_tree().quit())
	%LancerSoloBtn.pressed.connect(_on_solo)
	%RetourSoloBtn.pressed.connect(_show_home)
	%HostBtn.pressed.connect(_on_host)
	%JoinBtn.pressed.connect(_on_join)
	%RelayBtn.pressed.connect(func() -> void: _relay_form.visible = not _relay_form.visible)
	%RelayConnectBtn.pressed.connect(_on_relay_connect)
	%RetourMultiBtn.pressed.connect(_show_home)
	%StartBtn.pressed.connect(_on_start)
	%LeaveBtn.pressed.connect(_on_leave)
	_map_spin.value_changed.connect(_on_config_edited)
	_timer_spin.value_changed.connect(_on_config_edited)
	_build_mod_list()
	_show_home()
	Net.lobby_changed.connect(_refresh_lobby)
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_failed)
	Net.disconnected.connect(_on_disconnected)
	Net.config_changed.connect(_on_config_received)

# === MODS ===

func _build_mod_list() -> void:
	for mod in ModCatalog.create_all():
		_mods[mod.mod_id] = mod
		_enabled[mod.mod_id] = mod.mod_id in GameConfig.enabled_mod_ids
	_enforce_slot_exclusivity()
	var children: Dictionary = {}
	var roots: Array = []
	for id in _mods:
		var parent := ""
		for dep in _mods[id].depends_on:
			if _mods.has(dep):
				parent = dep
				break
		if parent == "":
			roots.append(id)
		else:
			if not children.has(parent):
				children[parent] = []
			children[parent].append(id)
	var rendered: Dictionary = {}
	for root in roots:
		_render_mod_node(root, 0, children, rendered)
	for id in _mods:  # filet de sécurité (cycle / parent hors catalogue)
		if not rendered.has(id):
			_render_mod_node(id, 0, children, rendered)

func _render_mod_node(id: String, depth: int, children: Dictionary, rendered: Dictionary) -> void:
	if rendered.has(id):
		return
	rendered[id] = true
	var row := HBoxContainer.new()
	if depth > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(depth * 26, 0)
		row.add_child(spacer)
	var cb := CheckBox.new()
	cb.text = _mods[id].mod_name           # le nom seul ; la description passe en infobulle
	cb.button_pressed = _enabled[id]
	cb.toggled.connect(_on_mod_toggled.bind(id))
	row.add_child(cb)
	# Pastille "(i)" : description (et slot éventuel) affichés au survol de la souris.
	var info := Label.new()
	info.text = " (i)"
	info.modulate = Color(0.55, 0.75, 1.0)
	info.mouse_filter = Control.MOUSE_FILTER_STOP   # nécessaire pour recevoir le survol -> infobulle
	info.mouse_default_cursor_shape = Control.CURSOR_HELP
	var tip: String = _mods[id].description
	if not _mods[id].provides.is_empty():
		tip += "\n(Fournit : %s — un seul mod par slot à la fois)" % ", ".join(_mods[id].provides)
	info.tooltip_text = tip
	row.add_child(info)
	_mod_list.add_child(row)
	_checkboxes[id] = cb
	for child in children.get(id, []):
		_render_mod_node(child, depth + 1, children, rendered)

func _on_mod_toggled(pressed: bool, id: String) -> void:
	_enabled[id] = pressed
	if pressed:
		_enable_deps(id)
		_disable_slot_rivals(id)
	else:
		_disable_dependents(id)
	for cid in _checkboxes:
		_checkboxes[cid].set_pressed_no_signal(_enabled[cid])
	_push_config_if_host()

func _disable_slot_rivals(id: String) -> void:
	for slot in _mods[id].provides:
		for other in _mods:
			if other != id and _enabled[other] and slot in _mods[other].provides:
				_enabled[other] = false
				_disable_dependents(other)

func _enforce_slot_exclusivity() -> void:
	var taken: Dictionary = {}
	for id in _mods:
		if not _enabled[id]:
			continue
		for slot in _mods[id].provides:
			if taken.has(slot):
				_enabled[id] = false
				break
			taken[slot] = id

func _enable_deps(id: String) -> void:
	for dep in _mods[id].depends_on:
		if _mods.has(dep) and not _enabled[dep]:
			_enabled[dep] = true
			_enable_deps(dep)

func _disable_dependents(id: String) -> void:
	for other in _mods:
		if _enabled[other] and id in _mods[other].depends_on:
			_enabled[other] = false
			_disable_dependents(other)

func _enabled_ids() -> Array:
	var ids: Array = []
	for id in _enabled:
		if _enabled[id]:
			ids.append(id)
	return ids

# === SYNC DE CONFIG (salon) ===

func _push_config_if_host() -> void:
	if _suppress_push:
		return
	if _in_lobby and Net.can_edit_lobby():
		Net.set_lobby_config(_enabled_ids(), int(_map_spin.value), int(_timer_spin.value))

func _on_config_edited(_v: float = 0.0) -> void:
	_push_config_if_host()

func _on_config_received() -> void:
	if Net.am_authority():
		return
	_suppress_push = true
	_map_spin.value = clampi(Net.lobby_map_size, 2, 6)
	_timer_spin.value = clampi(Net.lobby_timer, 0, 600)
	for id in _enabled:
		_enabled[id] = id in Net.lobby_mods
	for cid in _checkboxes:
		_checkboxes[cid].set_pressed_no_signal(_enabled[cid])
	_suppress_push = false

func _set_config_editable(editable: bool) -> void:
	for cid in _checkboxes:
		_checkboxes[cid].disabled = not editable
	_map_spin.editable = editable
	_timer_spin.editable = editable

# === ACTIONS ===

func _set_status(t: String) -> void:
	_status.text = t

func _on_solo() -> void:
	GameConfig.is_multiplayer = false
	GameConfig.player_count = int(_player_spin.value)
	GameConfig.map_size = int(_map_spin.value)
	GameConfig.turn_timer = int(_timer_spin.value)
	GameConfig.enabled_mod_ids = _enabled_ids()
	GameConfig.game_seed = randi()
	GameConfig.local_player_index = 0
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_host() -> void:
	Net.my_name = _name_edit.text
	if Net.host():
		_enter_lobby(true)
		_set_status("Tu héberges. En attente de joueurs…")
	else:
		_set_status("Impossible d'héberger (port occupé ?).")

func _on_join() -> void:
	Net.my_name = _name_edit.text
	if Net.join(_ip_edit.text):
		_set_status("Connexion à %s…" % _ip_edit.text)
	else:
		_set_status("Adresse invalide.")

# Connexion à un serveur-relais distant (token requis ; le 1er connecté devient l'autorité).
func _on_relay_connect() -> void:
	Net.my_name = _name_edit.text
	if Net.join_relay(_relay_addr.text, int(_relay_port.value), _relay_token.text):
		_set_status("Connexion au serveur…")
	else:
		_set_status("Adresse/port invalides.")

func _on_connected() -> void:
	_enter_lobby(false)
	_set_status("Connecté à l'hôte.")

func _on_failed() -> void:
	_set_status("Connexion échouée.")
	_show_multi()

func _on_disconnected() -> void:
	_set_status("Déconnecté de l'hôte.")
	_show_multi()

func _on_leave() -> void:
	Net.leave()
	_set_status("")
	_show_multi()

func _on_start() -> void:
	if Net.players.size() < 2:
		_set_status("Il faut au moins 2 joueurs pour lancer.")
		return
	Net.start_game()

# === ÉCRANS ===

func _hide_all_screens() -> void:
	_home_box.visible = false
	_solo_box.visible = false
	_multi_box.visible = false
	_lobby_box.visible = false

# Déplace la ConfigBox (options) dans l'écran demandé (Solo ou Salon).
func _move_config(slot: Node) -> void:
	if _config_box.get_parent() != slot:
		_config_box.reparent(slot, false)

func _show_home() -> void:
	_in_lobby = false
	_hide_all_screens()
	_home_box.visible = true

func _show_solo() -> void:
	_in_lobby = false
	_hide_all_screens()
	_move_config(_solo_slot)
	_pc_row.visible = true
	_config_title.text = "Options"
	_set_config_editable(true)
	_solo_box.visible = true

func _show_multi() -> void:
	_in_lobby = false
	_hide_all_screens()
	_multi_box.visible = true

func _enter_lobby(_as_host: bool) -> void:
	# _as_host n'est qu'indicatif : en mode relais l'autorité (1er client) n'est connue
	# qu'à réception de _sync_lobby. _refresh_lobby ré-évalue l'autorité à chaque mise à jour.
	_in_lobby = true
	_config_published = false
	_hide_all_screens()
	_move_config(_lobby_slot)
	_pc_row.visible = false  # en multi: nb joueurs = nb connectés
	_lobby_box.visible = true
	_refresh_lobby()

func _refresh_saves_list() -> void:
	for c in _saves_list.get_children():
		c.queue_free()
	for s in GameConfig.list_saves():
		var names: Array = s.get("meta", {}).get("names", [])
		var btn := Button.new()
		btn.text = "%s  (%d joueurs)" % [s["slot"], names.size()]
		btn.pressed.connect(_on_pick_save.bind(s["slot"]))
		_saves_list.add_child(btn)

# Charge une save SI le salon contient exactement les pseudos sauvegardés.
func _on_pick_save(slot: String) -> void:
	var data := GameConfig.load_save(slot)
	if data.is_empty():
		_set_status("Sauvegarde illisible.")
		return
	var meta: Dictionary = data.get("meta", {})
	var saved: Array = (meta.get("names", []) as Array).duplicate()
	var lobby_names: Array = []
	for pid in Net.players:
		lobby_names.append(Net.players[pid].get("name", ""))
	saved.sort()
	lobby_names.sort()
	if saved != lobby_names:
		_set_status("Pour reprendre, il faut EXACTEMENT : %s" % ", ".join(meta.get("names", [])))
		return
	Net.resume_game(data.get("snapshot", {}), meta.get("mods", []), int(meta.get("map_size", 2)),
		int(meta.get("timer", 0)), meta.get("names", []), int(meta.get("seed", 0)))

func _refresh_lobby() -> void:
	if _lobby_list == null or not _in_lobby:
		return
	for c in _lobby_list.get_children():
		c.queue_free()
	var ids := Net.players.keys()
	ids.sort()
	for i in ids.size():
		var id = ids[i]
		var lbl := Label.new()
		var tag := "  (hôte)" if id == Net.authority_peer_id else ""
		lbl.text = "J%d : %s%s" % [i, Net.players[id].get("name", "?"), tag]
		_lobby_list.add_child(lbl)
	# Ré-évalue l'autorité : l'autorité règle les options + voit Lancer/les sauvegardes.
	var auth := Net.am_authority()
	_config_title.text = "Options (tu décides)" if auth else "Options (réglées par l'hôte)"
	_set_config_editable(auth)
	_saves_label.visible = auth
	_saves_list.visible = auth
	if auth and _saves_list.get_child_count() == 0:
		_refresh_saves_list()
	if not auth:
		_on_config_received()         # reflète la config de l'autorité
	elif not _config_published:
		_config_published = true
		_push_config_if_host()        # publie la config initiale une fois reconnu autorité
	_start_btn.visible = auth
	_start_btn.disabled = Net.players.size() < 2
