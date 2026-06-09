extends Node
## Audio global (autoload "UISound") :
##  - crée les bus UI / SFX / Notification / Musique, tous routés vers MASTER
##    (Master garde le volume général ; Settings.master_volume agit dessus).
##  - joue les sons d'UI (clic + survol) sur TOUS les boutons (BaseButton) automatiquement,
##    présents OU à venir (menu, HUD, panneaux), via le bus "UI".
##
## Répartition des bus :
##   UI            -> sons d'interface (ce fichier)
##   SFX           -> sons de placement (buildPop, place_robber)
##   Notification  -> son "à toi de jouer" (core/turn_audio.gd)
##   Musique       -> réservé (plus tard)

const UI_BUS := "UI"
const BUSES := ["UI", "SFX", "Notification", "Musique"]

var _click: AudioStreamPlayer
var _hover: AudioStreamPlayer

func _ready() -> void:
	_ensure_buses()
	_click = _make_player("res://ui/sounds/UI_click.mp3", UI_BUS, -8.0)
	_hover = _make_player("res://ui/sounds/UI_hover.mp3", UI_BUS, -16.0)
	get_tree().node_added.connect(_on_node_added)
	# Filet : câble aussi les boutons DÉJÀ dans l'arbre au lancement (au cas où certains
	# seraient entrés avant la connexion de node_added) -> menu, ses sous-panneaux, etc.
	_wire_existing.call_deferred()

# Crée les bus manquants, chacun envoyé vers Master.
func _ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")

func _make_player(path: String, bus: String, vol: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		p.stream = load(path)
	p.bus = bus
	p.volume_db = vol
	add_child(p)
	return p

# Câble clic + survol sur chaque BaseButton qui entre dans l'arbre.
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		if not node.pressed.is_connected(_play_click):
			node.pressed.connect(_play_click)
		if not node.mouse_entered.is_connected(_play_hover):
			node.mouse_entered.connect(_play_hover)

# Parcourt l'arbre courant pour câbler les BaseButton déjà présents (filet de démarrage).
func _wire_existing() -> void:
	_wire_recursive(get_tree().root)

func _wire_recursive(node: Node) -> void:
	_on_node_added(node)
	for c in node.get_children():
		_wire_recursive(c)

func _play_click() -> void:
	if _click != null and _click.stream != null:
		_click.play()

func _play_hover() -> void:
	if _hover != null and _hover.stream != null:
		_hover.play()
