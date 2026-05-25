class_name VictoryContext
extends RefCounted

var state: GameState
var board: Board
var player_id: int = -1

# Modifiable par les hooks compute_victory_points
var points: int = 0

# Pour victory_check: seuil et joueur vainqueur (à écrire si gagné)
var threshold: int = 10
var winner: int = -1  # -1 = pas encore de vainqueur
