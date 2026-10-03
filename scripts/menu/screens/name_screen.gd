extends MenuScreen
## Name entry for a new file: an on-screen keyboard that works with the gamepad, and
## ordinary typing on the keyboard. The name is shown on the file and its preview.

const ROWS := ["ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZ0123", "456789.-!?"]

var _text := ""
var _field: Label
var _time := 0.0


func back_target() -> String:
	return "character"


func help_items() -> Array:
	return [
		{"kind": "move", "text": "Move"},
		{"kind": "accept", "text": "Type"},
		{"kind": "back", "text": "Back"},
	]


func _ready() -> void:
	super()
	var box := column(0.04, 10)
	box.add_child(PipeStyle.header("Enter your name!", 30, Vector2(640, 52)))

	var field_box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f2e8e4")
	style.set_corner_radius_all(10)
	style.set_border_width_all(4)
	style.border_color = Color("38aa78")
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	field_box.add_theme_stylebox_override("panel", style)
	field_box.custom_minimum_size = Vector2(640, 64)
	_field = MenuStyle.plain_label("", 30, Color("2a2a30"))
	_field.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	field_box.add_child(_field)
	box.add_child(field_box)

	var grid := GridContainer.new()
	grid.columns = ROWS[0].length()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	var first: PanelButton = null
	for row: String in ROWS:
		for ch in row:
			var key := PanelButton.new()
			key.font_size = 24
			key.setup("green", [ch] as Array[String], Vector2(60, 50))
			key.pressed.connect(_type.bind(ch))
			grid.add_child(key)
			if first == null:
				first = key

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)
	var space := PanelButton.new()
	space.font_size = 22
	space.setup("blue", ["Space"] as Array[String], Vector2(160, 50))
	space.pressed.connect(_type.bind(" "))
	var delete := PanelButton.new()
	delete.font_size = 22
	delete.setup("red", ["Delete"] as Array[String], Vector2(160, 50))
	delete.pressed.connect(_delete)
	var ok := PanelButton.new()
	ok.font_size = 22
	ok.setup("orange", ["OK"] as Array[String], Vector2(160, 50))
	ok.pressed.connect(_finish)
	actions.add_child(space)
	actions.add_child(delete)
	actions.add_child(ok)
	_update_field()
	first.grab_focus.call_deferred()


func _process(delta: float) -> void:
	_time += delta
	_update_field()


func _update_field() -> void:
	var cursor := "_" if fmod(_time, 1.0) < 0.55 and _text.length() < SaveData.NAME_MAX else " "
	_field.text = _text + cursor if _text != "" else "Type your name" if fmod(_time, 1.0) < 0.55 else ""


func _type(ch: String) -> void:
	if _text.length() < SaveData.NAME_MAX:
		_text += ch


func _delete() -> void:
	_text = _text.left(_text.length() - 1)


## Creates the file with this name; the file screen then shows it.
func _finish() -> void:
	var player_name := _text.strip_edges()
	if player_name == "":
		player_name = root.pending_character.capitalize()
	SaveData.create(root.current_slot, root.pending_character, player_name)
	Settings.last_slot = root.current_slot
	Settings.save()
	root.toast("%s is ready! The game itself is not available yet." % player_name)
	root.go("file")


## Typing on a real keyboard.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_BACKSPACE:
		get_viewport().set_input_as_handled()
		_delete()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		get_viewport().set_input_as_handled()
		_finish()
	elif event.keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		_type(" ")
	elif event.unicode >= 33 and event.unicode < 127:
		get_viewport().set_input_as_handled()
		_type(char(event.unicode))
