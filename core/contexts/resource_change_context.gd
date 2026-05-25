class_name ResourceChangeContext
extends RefCounted

var state: GameState
var player_id: int = -1
var resource_id: String = ""
var delta: int = 0  # positif = ajout, négatif = retrait
var cancelled: bool = false
var reason: String = ""  # "production", "trade", "robber", etc.
