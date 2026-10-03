extends MenuScreen
## Save file selection, laid out like the original's touch screen: a title bar, three file
## panels ("Anna | World 8" or "File 3 | New") with stars for the Star Coins found, and Copy /
## Erase / Back buttons. A glove points at the highlighted file and a card on the left
## shows its details. An empty file starts a new game (hero, then name); an existing one
## would continue (the game itself does not exist yet).

enum Mode { NORMAL, COPY_SOURCE, COPY_TARGET, ERASE }

const TITLES := {
	Mode.NORMAL: "Select a file.",
	Mode.COPY_SOURCE: "Copy which file?",
	Mode.COPY_TARGET: "Copy to which file?",
	Mode.ERASE: "Erase which file?",
}
const BAR_COLORS := {
	Mode.NORMAL: Color("38aa78"),
	Mode.COPY_SOURCE: Color("3f6fd0"),
	Mode.COPY_TARGET: Color("3f6fd0"),
	Mode.ERASE: Color("c43030"),
}
const PUSH := 7.0     # how far the highlighted file steps forward, in game pixels

var _mode := Mode.NORMAL
var _copy_from := 0
var _panel: QuiltPanel
var _files: Array[PanelButton] = []
var _stars: Array[StarCluster] = []
var _copy_button: PanelButton
var _erase_button: PanelButton
var _back_button: PanelButton
var _glove: GloveView
var _dialog: Control
var _scale := 2.3

var _base_x: Array[float] = []     # resting x of each file panel
var _slide: Array[float] = []      # how far each file is still to the right (intro)
var _push: Array[float] = []       # current forward step of each file panel

var _card: PanelContainer
var _card_title: Label
var _card_lines: Label
var _card_stats: VBoxContainer
var _card_heads := {}              # character id -> CharacterView
var _card_time := 0.0


func _init() -> void:
	mode = "main"   # same layout as the main menu: logo on the left, screen on the right


func back_target() -> String:
	return "main"


func help_items() -> Array:
	if _dialog or _mode != Mode.NORMAL:
		return [{"kind": "accept", "text": "Select"}, {"kind": "back", "text": "Cancel"}]
	return [
		{"kind": "move", "text": "Move"},
		{"kind": "accept", "text": "Select"},
		{"kind": "erase", "text": "Erase"},
		{"kind": "back", "text": "Back"},
	]


func _ready() -> void:
	super()
	_panel = QuiltPanel.new()
	add_child(_panel)
	for i in SaveData.SLOT_COUNT:
		var file := PanelButton.new()
		file.setup("green", ["File %d" % (i + 1), "New"] as Array[String], Vector2(100, 40))
		file.pressed.connect(_on_file.bind(i))
		file.focus_entered.connect(_show_card.bind(i))
		_panel.add_child(file)
		_files.append(file)
		var stars := StarCluster.new()
		stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(stars)
		_stars.append(stars)
		_base_x.append(0.0)
		_slide.append(0.0)
		_push.append(0.0)
	_copy_button = _make_button("blue", ["Copy"] as Array[String])
	_copy_button.pressed.connect(_set_mode.bind(Mode.COPY_SOURCE))
	_copy_button.focus_entered.connect(_show_note.bind("Copy a file onto another file."))
	_erase_button = _make_button("red", ["Erase"] as Array[String])
	_erase_button.pressed.connect(_set_mode.bind(Mode.ERASE))
	_erase_button.focus_entered.connect(_show_note.bind("Erase a file for good."))
	_back_button = _make_button("orange", [] as Array[String])
	_back_button.arrow = true
	_back_button.pressed.connect(root.go.bind("main"))
	_back_button.focus_entered.connect(_show_note.bind("Back to the main menu."))

	_glove = GloveView.new()
	_glove.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_glove)
	_build_card()

	resized.connect(_layout)
	_layout()
	_refresh()
	var start := clampi(Settings.last_slot - 1, 0, SaveData.SLOT_COUNT - 1)
	_files[start].grab_focus.call_deferred()
	_intro()


func _make_button(palette: String, texts: Array[String]) -> PanelButton:
	var button := PanelButton.new()
	button.setup(palette, texts, Vector2(60, 40))
	_panel.add_child(button)
	return button


## The file panels slide in from the right, one after the other.
func _intro() -> void:
	for i in _files.size():
		_slide[i] = 300.0
		var tween := create_tween()
		tween.tween_interval(0.12 + 0.09 * i)
		tween.tween_method(func(v: float) -> void: _slide[i] = v, 300.0, 0.0, 0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Sizes everything from the panel scale (one "game pixel" of the original = _scale px).
func _layout() -> void:
	_scale = clampf((size.y - 130.0) / 192.0, 1.2, 2.6)
	var s := _scale
	_panel.size = Vector2(256, 192) * s
	_panel.position = Vector2(size.x - _panel.size.x - 34.0, (size.y - _panel.size.y) / 2.0 - 8.0)
	_panel.bar_height = 32.0 * s
	for i in _files.size():
		var y := (40.0 + 40.0 * i) * s
		_base_x[i] = 45.0 * s
		_files[i].position = Vector2(_base_x[i], y)
		_files[i].size = Vector2(167, 28) * s
		_stars[i].position = Vector2(214, 0) * s + Vector2(0, y - 3.0 * s)
		_stars[i].size = Vector2(34, 34) * s
	_copy_button.position = Vector2(16, 158) * s
	_copy_button.size = Vector2(81, 28) * s
	_erase_button.position = Vector2(113, 158) * s
	_erase_button.size = Vector2(80, 28) * s
	_back_button.position = Vector2(223, 158) * s
	_back_button.size = Vector2(28, 28) * s
	_glove.size = Vector2(52, 36) * s
	_card.position = Vector2(size.x * 0.05, size.y * 0.47)
	_panel.queue_redraw()


func _process(delta: float) -> void:
	_card_time += delta
	var follow := 1.0 - exp(-delta * 14.0)
	var focus := get_viewport().gui_get_focus_owner()
	for i in _files.size():
		var target := -PUSH * _scale if focus == _files[i] else 0.0
		_push[i] = lerpf(_push[i], target, follow)
		_files[i].position.x = _base_x[i] + _slide[i] + _push[i]
		_stars[i].position.x = 214.0 * _scale + _slide[i]
	# The glove stands in the margin left of the highlighted file.
	var index := _files.find(focus as PanelButton)
	_glove.visible = index >= 0 and _dialog == null
	if index >= 0:
		var file := _files[index]
		_glove.position = Vector2(file.position.x - _glove.size.x * 0.8,
			file.position.y + (file.size.y - _glove.size.y) / 2.0)


## Texts and stars from the saves.
func _refresh() -> void:
	for i in _files.size():
		var data := SaveData.load_slot(i + 1)
		var left := "File %d" % (i + 1) if data.is_empty() else str(data.name).left(9)
		var right := "New" if data.is_empty() else "World %d" % data.world
		_files[i].set_texts([left, right] as Array[String])
		_stars[i].visible = not data.is_empty()
		_stars[i].filled = 0 if data.is_empty() else clampi(ceili(data.star_coins / 8.0), 0, 3)
		_stars[i].queue_redraw()
	_panel.set_title(TITLES[_mode])
	_panel.set_bar_color(BAR_COLORS[_mode])


func _set_mode(new_mode: Mode) -> void:
	_mode = new_mode
	_panel.set_title(TITLES[_mode])
	_panel.set_bar_color(BAR_COLORS[_mode])
	root.refresh_help()


# --- the details card on the left ----------------------------------------------

func _build_card() -> void:
	_card = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.08, 0.2, 0.74)
	style.set_corner_radius_all(14)
	style.set_border_width_all(3)
	style.border_color = Color.WHITE
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_card.add_theme_stylebox_override("panel", style)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_card.add_child(row)
	var head_box := Control.new()
	head_box.custom_minimum_size = Vector2(130, 130)
	row.add_child(head_box)
	for id in ["mario", "luigi"]:
		var head := CharacterView.new(id, 14.0 if id == "mario" else -14.0, true)
		head.size = Vector2(130, 130)
		head.visible = false
		head_box.add_child(head)
		_card_heads[id] = head
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 4)
	row.add_child(texts)
	_card_title = MenuStyle.label("", 30, MenuStyle.YELLOW)
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	texts.add_child(_card_title)
	_card_stats = VBoxContainer.new()
	_card_stats.add_theme_constant_override("separation", 3)
	texts.add_child(_card_stats)
	_card_lines = MenuStyle.label("", 20, Color.WHITE)
	_card_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_card_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_lines.custom_minimum_size = Vector2(300, 0)
	texts.add_child(_card_lines)


func _show_card(index: int) -> void:
	var data := SaveData.load_slot(index + 1)
	_clear_stats()
	root.set_world(int(data.world) if not data.is_empty() else root.last_world())
	for id in _card_heads:
		_card_heads[id].visible = not data.is_empty() and data.character == id
	if data.is_empty():
		_card_title.text = "File %d" % (index + 1)
		_card_lines.text = "A new adventure!\nPick your hero and a name to begin."
	else:
		_card_title.text = str(data.name)
		_card_lines.text = ""
		_add_stat(_icon("world", 66, 17), SaveData.level_label(data.world, data.level))
		_add_stat(_icon(str(data.character), 24, 24), "x %d" % data.lives)
		_add_stat(_icon("coin", 24, 24), "x %d" % data.coins)
		_add_stat(_icon("star_coin", 24, 24), "x %d" % data.star_coins)
		_add_stat(null, "Time  %s" % SaveData.time_label(data.play_time))
		_add_stat(null, "Played  %s" % SaveData.date_label(data.last_played))
		if Settings.last_slot == index + 1:
			_card_lines.text = "The file you used last"
	_flash_card()


## One line of the card: a picture from the ROM (or nothing) and its text.
func _add_stat(icon: Control, text: String) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(icon.size.x if icon else 0, 24)
	if icon:
		slot.add_child(icon)
	line.add_child(slot)
	var label := MenuStyle.label(text, 20, Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.add_child(label)
	_card_stats.add_child(line)


func _icon(picture: String, width: int, height: int) -> Control:
	var texture := HudIcons.texture(picture)
	if texture == null:
		return null
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size = Vector2(width, height)
	rect.position = Vector2(0, (24 - height) / 2.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _coin() -> Control:
	var view := CoinView.new()
	view.size = Vector2(26, 26)
	view.position = Vector2(0, -1)
	return view


func _clear_stats() -> void:
	for child in _card_stats.get_children():
		_card_stats.remove_child(child)
		child.queue_free()


func _show_note(text: String) -> void:
	_clear_stats()
	for id in _card_heads:
		_card_heads[id].visible = false
	_card_title.text = ""
	_card_lines.text = text
	_flash_card()


func _flash_card() -> void:
	_card.modulate.a = 0.2
	create_tween().tween_property(_card, "modulate:a", 1.0, 0.2)


# --- what the files do ------------------------------------------------------------

func _on_file(index: int) -> void:
	var data := SaveData.load_slot(index + 1)
	match _mode:
		Mode.NORMAL:
			root.current_slot = index + 1
			if data.is_empty():
				root.go("character")
			else:
				Settings.last_slot = index + 1
				Settings.save()
				root.toast("The game itself is not available yet.")
		Mode.COPY_SOURCE:
			if data.is_empty():
				root.toast("That file is empty.")
			else:
				_copy_from = index
				_set_mode(Mode.COPY_TARGET)
		Mode.COPY_TARGET:
			if index == _copy_from:
				root.toast("Choose another file.")
			elif data.is_empty():
				_copy(index)
			else:
				_ask("Overwrite file %d?" % (index + 1), _copy.bind(index))
		Mode.ERASE:
			if data.is_empty():
				root.toast("That file is empty.")
			else:
				_ask("Erase file %d?" % (index + 1), _erase.bind(index))


func _copy(target: int) -> void:
	SaveData.save_slot(target + 1, SaveData.load_slot(_copy_from + 1))
	_set_mode(Mode.NORMAL)
	_refresh()
	_show_card(target)
	root.toast("File %d copied to file %d." % [_copy_from + 1, target + 1])


func _erase(index: int) -> void:
	SaveData.erase(index + 1)
	_set_mode(Mode.NORMAL)
	_refresh()
	_show_card(index)


## A yes/no question over the panel.
func _ask(question: String, on_yes: Callable) -> void:
	_dialog = Control.new()
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(_dialog)
	_dialog.size = _panel.size
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = _panel.size
	_dialog.add_child(dim)
	var s := _scale
	var box := QuiltPanel.new()
	box.bar_height = 0.0
	box.size = Vector2(190, 92) * s
	box.position = (_panel.size - box.size) / 2.0
	_dialog.add_child(box)
	var text := MenuStyle.plain_label(question, 22, Color("2a2a30"))
	text.size = Vector2(box.size.x, 40.0 * s)
	text.position = Vector2(0, 8.0 * s)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(text)
	var yes := PanelButton.new()
	yes.setup("green", ["Yes"] as Array[String], Vector2(60, 40))
	yes.position = Vector2(22, 54) * s
	yes.size = Vector2(66, 28) * s
	var no := PanelButton.new()
	no.setup("red", ["No"] as Array[String], Vector2(60, 40))
	no.position = Vector2(102, 54) * s
	no.size = Vector2(66, 28) * s
	box.add_child(yes)
	box.add_child(no)
	yes.pressed.connect(func() -> void:
		_close_dialog()
		on_yes.call())
	no.pressed.connect(_close_dialog)
	for b in _focusables():
		b.focus_mode = Control.FOCUS_NONE
	root.refresh_help()
	no.grab_focus.call_deferred()


func _focusables() -> Array:
	return _files + [_copy_button, _erase_button, _back_button]


func _close_dialog() -> void:
	if _dialog:
		_dialog.queue_free()
		_dialog = null
	for b in _focusables():
		b.focus_mode = Control.FOCUS_ALL
	root.refresh_help()
	_files[clampi(Settings.last_slot - 1, 0, _files.size() - 1)].grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _dialog or _mode != Mode.NORMAL:
			get_viewport().set_input_as_handled()
			GameAudio.ui_back()
			if _dialog:
				_close_dialog()
			else:
				_set_mode(Mode.NORMAL)
			return
	elif _mode == Mode.NORMAL and not _dialog and _is_erase(event):
		var index := _files.find(get_viewport().gui_get_focus_owner() as PanelButton)
		if index >= 0 and not SaveData.load_slot(index + 1).is_empty():
			get_viewport().set_input_as_handled()
			_ask("Erase file %d?" % (index + 1), _erase.bind(index))
			return
	super(event)


func _is_erase(event: InputEvent) -> bool:
	return (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE) \
		or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y)
