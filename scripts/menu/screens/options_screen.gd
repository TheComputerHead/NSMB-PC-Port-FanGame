extends MenuScreen
## Options: window, graphics, frame rate, interface size, volumes and a way to the controls.


func back_target() -> String:
	return "main"


func _leave() -> void:
	Settings.save()
	root.go("main")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		GameAudio.ui_back()
		_leave()


func _ready() -> void:
	super()
	var box := column(0.05, 10)
	box.add_child(MenuStyle.label("Options", 40))

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.1, 0.3, 0.6)
	style.set_corner_radius_all(18)
	style.set_border_width_all(3)
	style.border_color = Color.WHITE
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	box.add_child(panel)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 8)
	panel.add_child(grid)

	var first := _choice(grid, "Display mode", Settings.DISPLAY_NAMES, Settings.display_mode, func(i: int) -> void:
		Settings.display_mode = i
		Settings.apply_display(get_viewport()))
	_choice(grid, "Anti-aliasing", ["Off", "2x", "4x", "8x"], Settings.msaa, func(i: int) -> void:
		Settings.msaa = i
		Settings.apply(get_viewport()))

	var smoothing := CheckButton.new()
	smoothing.button_pressed = Settings.texture_smoothing
	smoothing.toggled.connect(func(on: bool) -> void:
		Settings.texture_smoothing = on
		Settings.apply(get_viewport()))
	_row(grid, "Texture smoothing", smoothing)

	_choice(grid, "Frame rate limit", Settings.FPS_NAMES, Settings.fps_limit, func(i: int) -> void:
		Settings.fps_limit = i
		Settings.apply_performance())
	_choice(grid, "V-Sync", Settings.VSYNC_NAMES, Settings.vsync, func(i: int) -> void:
		Settings.vsync = i
		Settings.apply_performance())
	_choice(grid, "Interface size", Settings.UI_SCALE_NAMES, Settings.ui_scale, func(i: int) -> void:
		Settings.ui_scale = i
		Settings.apply_ui_scale(get_viewport()))

	_row(grid, "Volume", _slider(Settings.master_volume, func(v: float) -> void:
		Settings.master_volume = v
		Settings.apply(get_viewport())))
	_row(grid, "Music", _slider(Settings.music_volume, func(v: float) -> void:
		Settings.music_volume = v
		Settings.apply(get_viewport())))
	var sfx := _slider(Settings.sfx_volume, func(v: float) -> void:
		Settings.sfx_volume = v
		Settings.apply(get_viewport()))
	_row(grid, "Sound effects", sfx)
	# Let go of the slider: play a sample sound so the level can be judged.
	sfx.drag_ended.connect(func(_changed: bool) -> void: GameAudio.ui_decide())

	var upkeep := HBoxContainer.new()
	upkeep.alignment = BoxContainer.ALIGNMENT_CENTER
	upkeep.add_theme_constant_override("separation", 16)
	var rebuild := MenuStyle.button("Rebuild images", 20, Vector2(240, 44), "blue")
	rebuild.tooltip_text = "Deletes the pictures built from your ROM; they are made again right away."
	rebuild.pressed.connect(_rebuild_images)
	var other_rom := MenuStyle.button("Use another ROM", 20, Vector2(240, 44), "red")
	other_rom.tooltip_text = "Forgets the current ROM's data and asks for a ROM again. Your saves are kept."
	var confirm_text := "Sure? Click again"
	other_rom.pressed.connect(func() -> void:
		if other_rom.text != confirm_text:
			other_rom.text = confirm_text
			return
		_forget_rom())
	upkeep.add_child(rebuild)
	upkeep.add_child(other_rom)
	box.add_child(upkeep)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	var controls := MenuStyle.button("Controls", 24, Vector2(240, 52), "green")
	controls.pressed.connect(func() -> void:
		Settings.save()
		root.go("controls"))
	var back := MenuStyle.button("Back", 24, Vector2(240, 52), "grey")
	back.pressed.connect(_leave)
	buttons.add_child(controls)
	buttons.add_child(back)
	box.add_child(buttons)
	first.grab_focus.call_deferred()


## Deletes the pictures built from the ROM (backgrounds, font) and reloads the menu,
## which makes them again.
func _rebuild_images() -> void:
	Settings.save()
	_remove_dir("user://assets/ui")
	get_tree().change_scene_to_file("res://scenes/menu_root.tscn")


## Drops everything taken from the ROM, then goes back to the ROM picker. Saves and
## settings are not touched.
func _forget_rom() -> void:
	Settings.save()
	_remove_dir("user://assets")
	get_tree().change_scene_to_file("res://scenes/rom_select.tscn")


static func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_dir(path + "/" + sub)
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)


## A row with a label on the left and a drop-down list on the right.
func _choice(grid: GridContainer, text: String, names: Array, selected: int, on_select: Callable) -> OptionButton:
	var list := OptionButton.new()
	for item in names:
		list.add_item(item)
	list.selected = selected
	list.item_selected.connect(on_select)
	_row(grid, text, list)
	return list


func _row(grid: GridContainer, text: String, control: Control) -> void:
	var label := MenuStyle.label(text, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	grid.add_child(label)
	control.size_flags_horizontal = Control.SIZE_SHRINK_END
	grid.add_child(control)


func _slider(value: float, on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.custom_minimum_size = Vector2(260, 24)
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.value_changed.connect(on_change)
	return s
