extends MenuScreen
## Main menu, like the original's "Select a Game" screen: a yellow title bar and warp-pipe
## buttons coming out of the right edge of the window. The pipes slide in with a bounce,
## the selected one pushes forward, and a pressed one is squashed.

const PIPE_WIDTH := 470.0     # visible part of the pipes
const OFF_SCREEN := 80.0      # how far they continue past the window edge
const SLIDE_FROM := 640.0     # how far to the right the pipes start
const PUSH := 26.0            # how far the selected pipe moves left

const LABELS := ["Mario Game", "Mario Vs. Luigi", "Minigames", "Options", "Quit"]
const DESCRIPTIONS := [
	"Pick a save file and play the adventure with Mario or Luigi.",
	"Two-player battles. Coming soon.",
	"A collection of minigames. Coming soon.",
	"Display, sound and controls.",
	"Close the game.",
]

var _column: VBoxContainer
var _items: Array[Control] = []      # header + pipes, in order
var _pipes: Array[Button] = []
var _intro: Array[float] = []        # how far each item is still to the right
var _push: Array[float] = []         # current forward push of each pipe
var _shake: Array[float] = []        # shake strength after a press
var _description: PanelContainer
var _description_label: Label
var _time := 0.0


func _init() -> void:
	mode = "main"


func back_target() -> String:
	return "title"


func _ready() -> void:
	super()
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	add_child(_column)
	var width := PIPE_WIDTH + OFF_SCREEN

	_add_slot(PipeStyle.header("Select a Game", 30, Vector2(width, 52)), Vector2(width, 52))
	for i in LABELS.size():
		var theme := "blue" if i >= 3 else "green"
		var pipe := PipeStyle.button(LABELS[i], theme, 30, Vector2(width, 62))
		_add_slot(pipe, Vector2(width, 62))
		_pipes.append(pipe)
		pipe.focus_entered.connect(_show_description.bind(i))
		pipe.pressed.connect(_press.bind(i))
		pipe.resized.connect(func() -> void: pipe.pivot_offset = pipe.size / 2.0)

	_pipes[0].pressed.connect(func() -> void:
		GameAudio.play_sound("SAR_MENU", "SE_PLY_DOKAN_IN_OUT")   # down the pipe
		root.go("file"))
	_pipes[1].pressed.connect(root.toast.bind("Multiplayer is not available yet."))
	_pipes[2].pressed.connect(root.toast.bind("Minigames are not available yet."))
	_pipes[3].pressed.connect(root.go.bind("options"))
	_pipes[4].pressed.connect(get_tree().quit)

	_build_description()
	for i in _items.size():
		_intro.append(SLIDE_FROM)
		_push.append(0.0)
		_shake.append(0.0)
		var tween := create_tween()
		tween.tween_interval(0.08 * i + 0.1)
		tween.tween_method(_set_intro.bind(i), SLIDE_FROM, 0.0, 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pipes[0].grab_focus.call_deferred()
	resized.connect(_place)
	_place.call_deferred()


## Each item sits in a slot so the column keeps its layout while the item slides.
func _add_slot(item: Control, slot_size: Vector2) -> void:
	var slot := Control.new()
	slot.custom_minimum_size = slot_size
	slot.mouse_filter = MOUSE_FILTER_IGNORE
	slot.add_child(item)
	item.size = slot_size
	slot.resized.connect(func() -> void: item.size = slot.size)
	_column.add_child(slot)
	_items.append(item)


func _build_description() -> void:
	_description = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.08, 0.2, 0.72)
	style.set_corner_radius_all(14)
	style.set_border_width_all(3)
	style.border_color = Color.WHITE
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_description.add_theme_stylebox_override("panel", style)
	_description.mouse_filter = MOUSE_FILTER_IGNORE
	_description_label = MenuStyle.label("", 22, Color.WHITE)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.custom_minimum_size = Vector2(430, 0)
	_description.add_child(_description_label)
	add_child(_description)


func _show_description(index: int) -> void:
	_description_label.text = DESCRIPTIONS[index]
	_description.modulate.a = 0.0
	create_tween().tween_property(_description, "modulate:a", 1.0, 0.18)


func _set_intro(value: float, index: int) -> void:
	_intro[index] = value


## Squash the pressed pipe and make it shake a little.
func _press(index: int) -> void:
	var pipe := _pipes[index]
	_shake[index + 1] = 8.0
	pipe.scale = Vector2(1.03, 0.86)
	create_tween().tween_property(pipe, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_time += delta
	var follow := 1.0 - exp(-delta * 14.0)
	for i in _items.size():
		var item := _items[i]
		var pushed := 0.0
		if i > 0:
			var target := -PUSH if _pipes[i - 1].has_focus() else 0.0
			_push[i] = lerpf(_push[i], target, follow)
			pushed = _push[i]
		_shake[i] = move_toward(_shake[i], 0.0, delta * 40.0)
		item.position.x = _intro[i] + pushed + sin(_time * 80.0) * _shake[i]


## Pipes stick out of the right edge, the description sits at the bottom left.
func _place() -> void:
	_column.size = _column.get_combined_minimum_size()
	_column.position = Vector2(size.x - PIPE_WIDTH, maxf(size.y * 0.21, 80.0))
	_description.position = Vector2(size.x * 0.05, size.y - 190.0)
