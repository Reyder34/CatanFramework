extends PanelContainer

# Panneau PERSISTANT des dés (non bloquant).
# Affiché/maj via UIRegistry.show_persistent() après chaque lancer.
# WindowMover ajouté par UIRegistry._make_movable() — ne pas en créer un ici.

const DIE := preload("res://modules/classic_catan/panels_scripts/die_face.gd")

var _d1: Control
var _d2: Control
var _total: Label

func _ready() -> void:
	theme = load("res://ui/theme.tres")
	custom_minimum_size = Vector2(240, 0)
	_total = get_node_or_null("Content/Margin/DiceRow/Total")
	_ensure_built()


func _ensure_built() -> void:
	# Laisse passer les clics vers le plateau 3D (titre + poignée restent actifs, posés
	# en STOP par WindowMover après coup).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var content := get_node_or_null("Content")
	if content != null:
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _total == null:
		_total = get_node_or_null("Content/Margin/DiceRow/Total")
	if _total != null:
		_total.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _d1 != null:
		return
	var row: HBoxContainer = get_node_or_null("Content/Margin/DiceRow")
	if row == null:
		return
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Ordre voulu : _d1(0), Plus(1), _d2(2), Eq(3), Total(4)
	_d1 = _make_die()
	row.add_child(_d1)
	row.move_child(_d1, 0)
	_d2 = _make_die()
	row.add_child(_d2)
	row.move_child(_d2, 2)


func _make_die() -> Control:
	var d := Control.new()
	d.set_script(DIE)
	d.custom_minimum_size = Vector2(60, 60)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


# Contrat des panneaux persistants : appelée à l'affichage et à chaque mise à jour.
func update_panel(params: Dictionary) -> void:
	_ensure_built()
	var a := int(params.get("d1", 0))
	var b := int(params.get("d2", 0))
	if _d1 != null:
		_d1.set_value(a)
	if _d2 != null:
		_d2.set_value(b)
	if _total != null:
		_total.text = str(a + b)
