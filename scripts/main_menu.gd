extends Control

@onready var player_spin: SpinBox = $Panel/Margin/VBox/PlayerRow/PlayerSpin
@onready var mod_list: VBoxContainer = $Panel/Margin/VBox/ModList
@onready var start_button: Button = $Panel/Margin/VBox/Buttons/StartButton
@onready var quit_button: Button = $Panel/Margin/VBox/Buttons/QuitButton

var _mods: Dictionary = {}        # id -> GameMod
var _enabled: Dictionary = {}     # id -> bool
var _checkboxes: Dictionary = {}  # id -> CheckBox

func _ready() -> void:
	player_spin.min_value = 2
	player_spin.max_value = 4
	player_spin.value = GameConfig.player_count
	start_button.pressed.connect(_on_start)
	quit_button.pressed.connect(_on_quit)
	_build_mod_list()

func _build_mod_list() -> void:
	for mod in ModCatalog.create_all():
		_mods[mod.mod_id] = mod
		_enabled[mod.mod_id] = mod.mod_id in GameConfig.enabled_mod_ids
	for id in _mods:
		var mod = _mods[id]
		var cb := CheckBox.new()
		cb.text = "%s — %s" % [mod.mod_name, mod.description]
		cb.button_pressed = _enabled[id]
		cb.toggled.connect(_on_mod_toggled.bind(id))
		mod_list.add_child(cb)
		_checkboxes[id] = cb

# Garde la sélection cohérente: activer un mod active ses dépendances,
# désactiver un mod désactive ceux qui en dépendent.
func _on_mod_toggled(pressed: bool, id: String) -> void:
	_enabled[id] = pressed
	if pressed:
		_enable_deps(id)
	else:
		_disable_dependents(id)
	_refresh_checkboxes()

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

func _refresh_checkboxes() -> void:
	for id in _checkboxes:
		_checkboxes[id].set_pressed_no_signal(_enabled[id])

func _on_start() -> void:
	GameConfig.player_count = int(player_spin.value)
	var ids: Array = []
	for id in _enabled:
		if _enabled[id]:
			ids.append(id)
	GameConfig.enabled_mod_ids = ids
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_quit() -> void:
	get_tree().quit()
