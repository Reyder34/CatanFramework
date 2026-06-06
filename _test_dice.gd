extends SceneTree

# Test jetable: API d'UI persistante (show/update/hide) + panneau de dés (2 faces + total).

func _initialize() -> void:
	var ok := true
	var ui_layer := Control.new()
	get_root().add_child(ui_layer)
	var reg := GameRegistry.new()
	reg.setup_ui(ui_layer)
	reg.ui.register_panel("dice_panel", load("res://modules/classic_catan/panels/dice_panel.tscn"))

	# 1) création + 1ère mise à jour
	var inst = reg.ui.show_persistent("dice_panel", {"d1": 2, "d2": 5})
	ok = _check(ok, inst != null, "show_persistent crée l'instance")
	ok = _check(ok, inst.has_method("update_panel"), "le panneau a update_panel()")
	var row = inst.get_node("Content/DiceRow")
	ok = _check(ok, row.get_child_count() == 2, "2 faces de dé (n=%d)" % row.get_child_count())
	var f0 = row.get_child(0)
	var f1 = row.get_child(1)
	ok = _check(ok, f0.value == 2 and f1.value == 5, "valeurs dés = 2 et 5 (a=%d,%d)" % [f0.value, f1.value])
	var total = inst.get_node("Content/Total")
	ok = _check(ok, total.text == "Total : 7", "total = 7 (a=%s)" % total.text)

	# 2) idempotent : 2e show = même instance, valeurs mises à jour
	var inst2 = reg.ui.show_persistent("dice_panel", {"d1": 6, "d2": 3})
	ok = _check(ok, inst2 == inst, "2e show_persistent = même instance (pas de doublon)")
	ok = _check(ok, f0.value == 6 and f1.value == 3, "valeurs maj = 6 et 3")
	ok = _check(ok, total.text == "Total : 9", "total maj = 9 (a=%s)" % total.text)

	# 3) update_persistent
	reg.ui.update_persistent("dice_panel", {"d1": 1, "d2": 1})
	ok = _check(ok, total.text == "Total : 2", "update_persistent -> total 2 (a=%s)" % total.text)

	# 4) hide
	reg.ui.hide_persistent("dice_panel")
	ok = _check(ok, reg.ui.get_persistent("dice_panel") == null, "hide_persistent retire le panneau")

	print("ALL OK" if ok else "FAILED")
	quit()

func _check(prev: bool, cond: bool, label: String) -> bool:
	print(("  OK   " if cond else "  FAIL ") + label)
	return prev and cond
