extends SceneTree
func _initialize() -> void:
	var c: Control = Control.new()
	c.set_value(3)
	print("PROBE_DONE")
	quit()
