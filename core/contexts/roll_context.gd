class_name RollContext
extends RefCounted

var state: GameState
var board: Board
var roller_id: int = -1

# Le résultat du lancer. -1 = pas encore défini, les hooks dice_roll l'écrivent.
var result: int = -1

# Si true, after_dice_rolled n'émet pas la production
var cancel_production: bool = false
