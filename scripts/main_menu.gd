extends Control

# Menu: solo, héberger, rejoindre, salon. UI construite en code.

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _player_spin: SpinBox
var _map_spin: SpinBox
var _mod_list: VBoxContainer
var _connect_box: VBoxContainer
var _lobby_box: VBoxContainer
var _lobby_list: VBoxContainer
var _start_btn: Button
var _status: Label

var _mods: Dictionary = {}        # id -> GameMod
var _enabled: Dictionary = {}     # id -> bool
var _checkboxes: Dictionary = {}  # id -> CheckBox

func _ready() -> void:
	GameConfig.is_multiplayer = false
	Net.leave()  # coupe une éventuelle connexion précédente
	_build()
	Net.lobby_changed.connect(_refresh_lobby)
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_failed)
	Net.disconnected.connect(_on_disconnected)

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for m in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + m, 30)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = "CATAN 2"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	# --- Écran connexion ---
	_connect_box = VBoxContainer.new()
	_connect_box.add_theme_constant_override("separation", 8)
	root.add_child(_connect_box)

	var name_row := HBoxContainer.new()
	name_row.add_child(_label("Pseudo :"))
	_name_edit = LineEdit.new()
	_name_edit.text = "Joueur"
	_name_edit.custom_minimum_size = Vector2(170, 0)
	name_row.add_child(_name_edit)
	_connect_box.add_child(name_row)

	_connect_box.add_child(_label("Mods :"))
	_mod_list = VBoxContainer.new()
	_connect_box.add_child(_mod_list)
	_build_mod_list()

	var pc_row := HBoxContainer.new()
	pc_row.add_child(_label("Joueurs (solo) :"))
	_player_spin = SpinBox.new()
	_player_spin.min_value = 2
	_player_spin.max_value = 10
	_player_spin.value = clampi(GameConfig.player_count, 2, 10)
	pc_row.add_child(_player_spin)
	_connect_box.add_child(pc_row)

	var ms_row := HBoxContainer.new()
	ms_row.add_child(_label("Taille de la map :"))
	_map_spin = SpinBox.new()
	_map_spin.min_value = 2
	_map_spin.max_value = 6
	_map_spin.value = clampi(GameConfig.map_size, 2, 6)
	ms_row.add_child(_map_spin)
	_connect_box.add_child(ms_row)

	_connect_box.add_child(_button("Jouer en solo", _on_solo))
	_connect_box.add_child(HSeparator.new())
	_connect_box.add_child(_button("Héberger une partie", _on_host))

	var join_row := HBoxContainer.new()
	join_row.add_child(_label("IP :"))
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(150, 0)
	join_row.add_child(_ip_edit)
	join_row.add_child(_button("Rejoindre", _on_join))
	_connect_box.add_child(join_row)

	_connect_box.add_child(_button("Quitter", func(): get_tree().quit()))

	# --- Écran salon ---
	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 8)
	_lobby_box.visible = false
	root.add_child(_lobby_box)

	var lt := Label.new()
	lt.text = "Salon"
	lt.add_theme_font_size_override("font_size", 24)
	_lobby_box.add_child(lt)
	_lobby_box.add_child(_label("Joueurs connectés :"))
	_lobby_list = VBoxContainer.new()
	_lobby_box.add_child(_lobby_list)
	_start_btn = _button("Lancer la partie", _on_start)
	_lobby_box.add_child(_start_btn)
	_lobby_box.add_child(_button("Quitter le salon", _on_leave))

	_status = Label.new()
	_status.modulate = Color(1, 0.85, 0.4)
	root.add_child(_status)

func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l

func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	return b

# === MODS ===

func _build_mod_list() -> void:
	for mod in ModCatalog.create_all():
		_mods[mod.mod_id] = mod
		_enabled[mod.mod_id] = mod.mod_id in GameConfig.enabled_mod_ids
	_enforce_slot_exclusivity()  # au cas où la config pré-active 2 fournisseurs du même slot
	# Arbre par dépendance: un mod s'affiche INDENTÉ sous celui dont il dépend
	# (ex: vanilla_robber sous classic_catan).
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
	cb.text = "%s — %s" % [_mods[id].mod_name, _mods[id].description]
	if not _mods[id].provides.is_empty():
		cb.tooltip_text = "Fournit: %s (un seul mod par slot à la fois)" % ", ".join(_mods[id].provides)
	cb.button_pressed = _enabled[id]
	cb.toggled.connect(_on_mod_toggled.bind(id))
	row.add_child(cb)
	_mod_list.add_child(row)
	_checkboxes[id] = cb
	for child in children.get(id, []):
		_render_mod_node(child, depth + 1, children, rendered)

func _on_mod_toggled(pressed: bool, id: String) -> void:
	_enabled[id] = pressed
	if pressed:
		_enable_deps(id)
		_disable_slot_rivals(id)  # exclusion mutuelle: activer une map désactive l'autre
	else:
		_disable_dependents(id)
	for cid in _checkboxes:
		_checkboxes[cid].set_pressed_no_signal(_enabled[cid])

# Désactive tout autre mod activé qui fournit un même slot à fournisseur unique.
func _disable_slot_rivals(id: String) -> void:
	for slot in _mods[id].provides:
		for other in _mods:
			if other != id and _enabled[other] and slot in _mods[other].provides:
				_enabled[other] = false
				_disable_dependents(other)  # coupe aussi ce qui dépendait du rival

# Au build: si plusieurs mods activés fournissent le même slot, garde le premier.
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

# === ACTIONS ===

func _set_status(t: String) -> void:
	_status.text = t

func _on_solo() -> void:
	GameConfig.is_multiplayer = false
	GameConfig.player_count = int(_player_spin.value)
	GameConfig.map_size = int(_map_spin.value)
	GameConfig.enabled_mod_ids = _enabled_ids()
	GameConfig.game_seed = randi()
	GameConfig.local_player_index = 0
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_host() -> void:
	Net.my_name = _name_edit.text
	if Net.host():
		_show_lobby()
		_set_status("Tu héberges. En attente de joueurs…")
	else:
		_set_status("Impossible d'héberger (port occupé ?).")

func _on_join() -> void:
	Net.my_name = _name_edit.text
	if Net.join(_ip_edit.text):
		_set_status("Connexion à %s…" % _ip_edit.text)
	else:
		_set_status("Adresse invalide.")

func _on_connected() -> void:
	_show_lobby()
	_set_status("Connecté à l'hôte.")

func _on_failed() -> void:
	_set_status("Connexion échouée.")
	_show_connect()

func _on_disconnected() -> void:
	_set_status("Déconnecté de l'hôte.")
	_show_connect()

func _on_leave() -> void:
	Net.leave()
	_show_connect()
	_set_status("")

func _on_start() -> void:
	if Net.players.size() < 2:
		_set_status("Il faut au moins 2 joueurs pour lancer.")
		return
	Net.start_game(_enabled_ids(), int(_map_spin.value))

# === ÉCRANS ===

func _show_lobby() -> void:
	_connect_box.visible = false
	_lobby_box.visible = true
	_refresh_lobby()

func _show_connect() -> void:
	_connect_box.visible = true
	_lobby_box.visible = false

func _refresh_lobby() -> void:
	if _lobby_list == null:
		return
	for c in _lobby_list.get_children():
		c.queue_free()
	var ids := Net.players.keys()
	ids.sort()
	for i in ids.size():
		var id = ids[i]
		var lbl := Label.new()
		var tag := "  (hôte)" if id == 1 else ""
		lbl.text = "J%d : %s%s" % [i, Net.players[id].get("name", "?"), tag]
		_lobby_list.add_child(lbl)
	_start_btn.visible = Net.is_host
	_start_btn.disabled = Net.players.size() < 2
