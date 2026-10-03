extends MenuScreen
## Title screen: the logo drops in with a bounce and a burst of sparkles, then a yellow
## "PRESS START" bar slides in from the right and pulses.

const BAR_HEIGHT := 64.0

var _bar: PanelContainer
var _label: Label
var _bar_in := 0.0          # 0 = far to the right, 1 = in place
var _time := 0.0
var _started := false


func _init() -> void:
	mode = "title"


func help_items() -> Array:
	return [{"kind": "accept", "text": "Start"}]


func _ready() -> void:
	super()
	_bar = PipeStyle.header("PRESS START", 36, Vector2(0, BAR_HEIGHT))
	_label = _bar.get_child(0) as Label
	_bar.pivot_offset = Vector2.ZERO
	add_child(_bar)
	_place()
	resized.connect(_place)

	var note := MenuStyle.label("Unofficial fan project. Not affiliated with Nintendo.", 16, Color.WHITE)
	note.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	note.offset_top -= 64
	note.offset_bottom -= 64
	add_child(note)

	# The logo lands first, then the bar slides in.
	root.logo_drop()
	var tween := create_tween()
	tween.tween_interval(0.85)
	tween.tween_callback(root.burst_sparkles.bind(14))
	tween.tween_interval(0.25)
	tween.tween_method(_set_bar, 0.0, 1.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not Settings.intro_seen:
		tween.tween_interval(0.6)
		tween.tween_callback(_welcome)


## First launch only: where the game's data comes from and where the saves are kept.
func _welcome() -> void:
	Settings.intro_seen = true
	Settings.save()
	root.toast("Welcome! All graphics and sounds come from your own ROM.\nYour save files are in %s" %
		ProjectSettings.globalize_path("user://saves"), 8.0)


func _set_bar(value: float) -> void:
	_bar_in = value
	_place()


func _place() -> void:
	_bar.size = Vector2(size.x + 60.0, BAR_HEIGHT)
	_bar.position = Vector2((1.0 - _bar_in) * (size.x + 80.0) - 30.0, size.y - 190.0)


func _process(delta: float) -> void:
	_time += delta
	# The text breathes: it grows and fades a little in time with the music.
	var wave := 0.5 + 0.5 * sin(_time * 4.0)
	_label.modulate.a = lerpf(0.45, 1.0, wave)
	_label.pivot_offset = _label.size / 2.0
	_label.scale = Vector2.ONE * (1.0 + 0.06 * wave)


func _input(event: InputEvent) -> void:
	if _started:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	# While the menu is still opening, a press would be refused by the root and the title
	# screen would believe it had already started: it would never react again.
	if pressed and not root.is_busy():
		_started = true
		get_viewport().set_input_as_handled()
		GameAudio.ui_decide()
		root.burst_sparkles(10)
		root.go("main")
