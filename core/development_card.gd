class_name DevelopmentCard
extends RefCounted

# Identité
var id: String = ""
var display_name: String = ""
var description: String = ""
var image: String = ""

# Comportement
var victory_points: int = 0     # cartes PV cachées
var is_passive: bool = false    # vrai pour les cartes PV (pas besoin de "jouer")

# === À surcharger ===

# Peut-elle être jouée maintenant?
# bought_this_turn: vrai si la carte vient d'être achetée
func is_playable(state: GameState, player: Player, bought_this_turn: bool) -> bool:
	if is_passive:
		return false  # jamais "jouée" manuellement
	if bought_this_turn:
		return false  # règle officielle: pas le tour de l'achat
	return state.phase == GameState.Phase.PLAY \
		and not state.is_busy()

# Effet de la carte. Renvoie true si la carte a été consommée.
# (peut renvoyer false si l'utilisateur a annulé pendant un await)
func on_play(state: GameState, board: Board, registry: GameRegistry, player: Player) -> bool:
	return true
