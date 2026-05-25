extends PanelContainer

# Signal attendu par l'UIRegistry
signal closed(result: Variant)

var message_label: Label
var ok_button: Button

func _ready() -> void:
	message_label = get_node("Content/MessageLabel")
	ok_button = get_node("Content/OkButton")
	ok_button.pressed.connect(_on_ok)

# Méthode appelée par UIRegistry.show_panel après instanciation
func show_panel(params: Dictionary) -> void:
	if params.has("message"):
		message_label.text = params["message"]

func _on_ok() -> void:
	closed.emit("ok")
