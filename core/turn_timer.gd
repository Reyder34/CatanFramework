class_name TurnTimer
extends Node

# Timer de tour (CORE). Décompte le temps du joueur courant et, à l'expiration, émet
# l'event générique "turn_timeout" -> un mod (ex: classic_catan) le traduit en fin de
# tour. Le core ne connaît pas la notion de "passer son tour" : il signale juste la fin.
#
# - Actif uniquement pendant un TOUR DE JEU normal (phase PLAY, hors sous-phase).
# - EN PAUSE quand une pop-up est ouverte (locale OU panneau réseau en attente, via
#   UIRegistry.is_any_panel_open()).
# - N'émet le timeout que sur le pair AUTORITAIRE (host/solo) -> action une seule fois.
# - UI persistante core (déplaçable/redimensionnable comme les autres panneaux).

const PANEL := "turn_timer"

var _state: GameState
var _registry: GameRegistry
var _authoritative := true
var _duration := 0.0
var _remaining := 0.0
var _last_index := -1
var _fired := false
var _last_shown := -999

func setup(state: GameState, registry: GameRegistry, seconds: int, authoritative: bool) -> void:
	_state = state
	_registry = registry
	_duration = float(seconds)
	_authoritative = authoritative
	if _duration <= 0.0:
		return  # 0 = timer désactivé
	if _registry.ui != null:
		_registry.ui.register_panel(PANEL, preload("res://core/turn_timer_panel.tscn"))
	_state.status_changed.connect(_on_status_changed)
	_reset()
	set_process(true)

func _on_status_changed() -> void:
	if _state.current_player_index != _last_index:
		_reset()

func _reset() -> void:
	_last_index = _state.current_player_index
	_remaining = _duration
	_fired = false

# Actif: tour de jeu normal, hors sous-phase (voleur…) et hors pop-up.
func _active() -> bool:
	return _state.phase == GameState.Phase.PLAY \
		and _state.sub_phase == "" \
		and _registry.ui != null \
		and not _registry.ui.is_any_panel_open()

func _process(delta: float) -> void:
	if _duration <= 0.0:
		return
	if _active() and not _fired:
		_remaining = maxf(0.0, _remaining - delta)
		if _remaining <= 0.0:
			_fired = true
			if _authoritative:
				_registry.emit("turn_timeout", {"state": _state, "player": _state.current_player_index})
	_show()

func _show() -> void:
	if _registry.ui == null:
		return
	var secs := int(ceil(_remaining))
	if secs == _last_shown:
		return
	_last_shown = secs
	_registry.ui.show_persistent(PANEL, {"seconds": secs})
