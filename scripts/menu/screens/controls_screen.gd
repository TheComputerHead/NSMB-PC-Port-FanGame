extends MenuScreen
## Controls: each action has a keyboard key and a gamepad button the player can change.
## Click a binding, then press the new key or button (Escape cancels).

var _key_buttons := {}
var _pad_buttons := {}
var _waiting_action := ""
var _waiting_pad := false
var _hint: Label


func back_target() -> String:
	return "options"


func help_items() -> Array:
	return [
		{"kind": "move", "text": "Move"},
		{"kind": "accept", "text": "Change"},
		{"kind": "back", "text": "Back"},
	]


func _leave() -> void:
	Settings.save()
	root.go("options")


func _ready() -> void:
	super()
	var box := column(0.03, 6)
	box.add_child(MenuStyle.label("Controls", 34))

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.1, 0.3, 0.6)
	style.set_corner_radius_all(18)
	style.set_border_width_all(3)
	style.border_color = Color.WHITE
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	box.add_child(panel)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 3)
	panel.add_child(grid)
	grid.add_child(MenuStyle.label("Action", 20, Color.WHITE))
	grid.add_child(MenuStyle.label("Keyboard", 20, Color.WHITE))
	grid.add_child(MenuStyle.label("Gamepad", 20, Color.WHITE))

	var first: Button = null
	for a: Dictionary in InputConfig.ACTIONS:
		var name_label := MenuStyle.label(a.label, 20, Color.WHITE)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.custom_minimum_size = Vector2(250, 0)
		grid.add_child(name_label)
		var key_button := MenuStyle.button("", 20, Vector2(170, 36), "green")
		var pad_button := MenuStyle.button("", 20, Vector2(130, 36), "blue")
		key_button.pressed.connect(_start_waiting.bind(a.id, false))
		pad_button.pressed.connect(_start_waiting.bind(a.id, true))
		grid.add_child(key_button)
		grid.add_child(pad_button)
		_key_buttons[a.id] = key_button
		_pad_buttons[a.id] = pad_button
		if first == null:
			first = key_button
	_refresh()

	_hint = MenuStyle.label("", 22, Color.WHITE)
	box.add_child(_hint)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	var reset := MenuStyle.button("Defaults", 22, Vector2(240, 44), "blue")
	reset.pressed.connect(func() -> void:
		InputConfig.reset_defaults()
		_refresh())
	var back := MenuStyle.button("Back", 22, Vector2(240, 44), "grey")
	back.pressed.connect(_leave)
	buttons.add_child(reset)
	buttons.add_child(back)
	box.add_child(buttons)
	first.grab_focus.call_deferred()


func _refresh() -> void:
	for a: Dictionary in InputConfig.ACTIONS:
		(_key_buttons[a.id] as Button).text = InputConfig.key_name(a.id)
		(_pad_buttons[a.id] as Button).text = InputConfig.pad_name(a.id)


func _start_waiting(action: String, pad: bool) -> void:
	_waiting_action = action
	_waiting_pad = pad
	_hint.text = "Press a %s for this action (Esc to cancel)" % ("gamepad button" if pad else "key")


func _input(event: InputEvent) -> void:
	if _waiting_action == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.physical_keycode != KEY_ESCAPE and not _waiting_pad:
			InputConfig.set_key(_waiting_action, event.physical_keycode)
		_finish_waiting()
	elif event is InputEventJoypadButton and event.pressed and _waiting_pad:
		get_viewport().set_input_as_handled()
		InputConfig.set_pad(_waiting_action, event.button_index)
		_finish_waiting()


func _finish_waiting() -> void:
	_waiting_action = ""
	_hint.text = ""
	_refresh()
	# The Escape that cancelled must not also leave the screen.
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _waiting_action != "":
		return
	super(event)
