extends PanelContainer

# Panneau PERSISTANT des dés (non bloquant). Affiché/maj par UIRegistry.show_persistent()
# après chaque lancer. Les valeurs viennent d'un marqueur plateau synchronisé -> tous les
# joueurs voient les mêmes dés en multijoueur.

const DIE := preload("res://modules/classic_catan/panels_scripts/die_face.gd")

var _d1: Control
var _d2: Control
var _total: Label

func _ready() -> void:
	_ensure_built()

func _ensure_built() -> void:
	# Laisse passer les clics vers le plateau 3D (titre + poignée restent actifs, posés
	# en STOP par WindowMover après coup).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var content := get_node_or_null("Content")
	if content != null:
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _total == null:
		_total = get_node_or_null("Content/Total")
	if _total != null:
		_total.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _d1 != null:
		return
	var row: HBoxContainer = get_node_or_null("Content/DiceRow")
	if row == null:
		return
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_d1 = _make_die()
	_d2 = _make_die()
	row.add_child(_d1)
	row.add_child(_d2)

func _make_die() -> Control:
	var d := Control.new()
	d.set_script(DIE)
	d.custom_minimum_size = Vector2(56, 56)
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
		_total.text = "Total : %d" % (a + b)
