class_name TurnAudio
extends AudioStreamPlayer

# Joue un son quand c'est le tour du joueur LOCAL. Le "tour" est un concept du
# core (le core gère tours + points de victoire), donc ce composant vit ici.
#
# local_index = index du joueur local (réseau) ; -1 = jouer à CHAQUE changement
# de tour (mode solo, où tu contrôles tout le monde).
#
# Pour ton propre son: remplace core/sounds/your_turn.wav, OU dépose un
# core/sounds/your_turn.ogg (prioritaire). Le .wav fourni n'est qu'un bip d'exemple.

const SOUND_PATHS := [
	"res://core/sounds/your_turn.ogg",
	"res://core/sounds/your_turn.mp3",
	"res://core/sounds/your_turn.wav",
]

var _state: GameState
var _local_index: int = -1
var _last_index: int = -1

func setup(state: GameState, local_index: int) -> void:
	_state = state
	_local_index = local_index
	stream = _load_sound()
	_last_index = state.current_player_index
	state.status_changed.connect(_on_status_changed)

func _load_sound() -> AudioStream:
	for p in SOUND_PATHS:
		if ResourceLoader.exists(p):
			return load(p)
	return null

func _on_status_changed() -> void:
	# status_changed sert aussi pour phase/sous-phase: ne réagir qu'au vrai
	# changement de joueur courant.
	if _state.current_player_index == _last_index:
		return
	_last_index = _state.current_player_index
	if _state.phase == GameState.Phase.GAME_OVER:
		return
	if stream == null:
		return
	if _local_index < 0 or _state.current_player_index == _local_index:
		play()
