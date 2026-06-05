class_name GameConfig
extends RefCounted

# Configuration choisie dans le menu, lue par la scène de jeu.
# Les `static var` persistent entre les changements de scène.
static var player_count: int = 4
static var enabled_mod_ids: Array = ["classic_catan", "vanilla_robber"]
