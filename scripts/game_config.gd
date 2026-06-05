class_name GameConfig
extends RefCounted

# Configuration choisie dans le menu, lue par la scène de jeu.
# Les `static var` persistent entre les changements de scène.
static var player_count: int = 4
static var enabled_mod_ids: Array = ["classic_catan", "vanilla_robber"]
static var map_size: int = 2  # rayon hex du plateau (réglé au lobby), lu par les générateurs
static var player_names: Array = []  # index joueur -> pseudo (réseau); vide en solo

# Multijoueur
static var is_multiplayer: bool = false
static var game_seed: int = 0          # 0 = aléatoire; sinon plateau déterministe (réseau)
static var local_player_index: int = 0  # quel joueur ce peer contrôle
static var peer_to_player: Dictionary = {}  # peer_id -> index joueur (réseau)
