class_name HelpBar
extends HBoxContainer
## The line at the bottom that tells which button does what, with the keys shown for the
## device being used: keyboard names, or the gamepad symbols of the game's own font.

const KEYBOARD := {
	"accept": "Enter", "back": "Esc", "move": "↑↓", "left_right": "←→", "erase": "Del",
}
# U+E000.. are the button symbols of the game's font (A, B, X, Y, L, R, D-pad).
const GAMEPAD := {
	"accept": "", "back": "", "move": "", "left_right": "", "erase": "",
}


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 34)


## `items` is a list of {kind, text}; `device` is "keyboard" or "pad".
func set_items(device: String, items: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var names: Dictionary = GAMEPAD if device == "pad" else KEYBOARD
	for item: Dictionary in items:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 10)
		pair.mouse_filter = MOUSE_FILTER_IGNORE
		pair.add_child(MenuStyle.label(names.get(item.kind, item.kind), 22, MenuStyle.YELLOW))
		pair.add_child(MenuStyle.label(item.text, 22, Color.WHITE))
		add_child(pair)
