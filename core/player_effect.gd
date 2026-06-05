class_name PlayerEffect
extends RefCounted

# Identité
var id: String = ""                # ex: "longest_road", "largest_army", "trophy_x"
var source_mod: String = ""        # mod_id qui l'a créé
var display_name: String = ""
var description: String = ""

# Score
var victory_points: int = 0

# Données spécifiques (ex: pour longest_road: la longueur)
var data: Dictionary = {}
