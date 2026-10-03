class_name PanelButton
extends Button
## A flat button like the ones on the original's touch screen: coloured body, light top
## edge, dark bottom edge, drop shadow and small rivets in the corners. Bright when
## highlighted, dark otherwise. One text, or two (a split panel like "File 1 | World 8").

# body, light edge, dark edge
const PALETTES := {
	"green": {
		"bright": [Color("4cc41f"), Color("8fe55c"), Color("2c8a14")],
		"dim": [Color("1f7a30"), Color("2f9a47"), Color("125a22")],
	},
	"blue": {
		"bright": [Color("3f6fd0"), Color("7aa2ee"), Color("22408f")],
		"dim": [Color("2c4f93"), Color("4068b4"), Color("1a3366")],
	},
	"red": {
		"bright": [Color("d8261f"), Color("f27458"), Color("8e0f0f")],
		"dim": [Color("8c1414"), Color("aa2828"), Color("5c0a0a")],
	},
	"orange": {
		"bright": [Color("f5920c"), Color("ffc866"), Color("a85a00")],
		"dim": [Color("e07c08"), Color("f0a040"), Color("8a4a00")],
	},
}
const TEXT_DIM := Color("cfcfcf")

var palette := "green"
var parts: Array[String] = []
var split := 0.5
var arrow := false           # draw a "go back" arrow instead of a text
var font_size := 26

var _labels: Array[Label] = []


func setup(palette_name: String, texts: Array[String], size_hint: Vector2) -> void:
	palette = palette_name
	parts = texts
	custom_minimum_size = size_hint
	focus_mode = Control.FOCUS_ALL
	flat = true
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for text in texts:
		var label := MenuStyle.label(text, font_size, TEXT_DIM)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		_labels.append(label)
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	mouse_entered.connect(func() -> void: if focus_mode != Control.FOCUS_NONE: grab_focus())
	focus_entered.connect(func() -> void: GameAudio.ui_cursor())
	pressed.connect(func() -> void: GameAudio.ui_decide())
	resized.connect(_layout)


func _ready() -> void:
	_layout()


func set_texts(texts: Array[String]) -> void:
	parts = texts
	for i in _labels.size():
		_labels[i].text = texts[i] if i < texts.size() else ""
	_layout()


func _highlighted() -> bool:
	return has_focus()


func _refresh() -> void:
	var color := MenuStyle.YELLOW if _highlighted() else TEXT_DIM
	for label in _labels:
		label.add_theme_color_override("font_color", color)
	queue_redraw()


func _layout() -> void:
	var count := _labels.size()
	for i in count:
		var label := _labels[i]
		var width := size.x / count if count == 1 else (size.x * split if i == 0 else size.x * (1.0 - split))
		var left := 0.0 if i == 0 else size.x * split
		label.size = Vector2(width, size.y - 6.0)
		label.position = Vector2(left, 0)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	queue_redraw()


func _draw() -> void:
	var colors: Array = PALETTES[palette]["bright" if _highlighted() else "dim"]
	var body: Color = colors[0]
	var light: Color = colors[1]
	var dark: Color = colors[2]
	var w := size.x
	var h := size.y - 5.0                    # the shadow takes the last few pixels
	var unit := maxf(h / 28.0, 1.0)         # one "game pixel" of the original

	draw_rect(Rect2(3, 5, w, h), Color(0, 0, 0, 0.45))              # drop shadow
	draw_rect(Rect2(0, 0, w, h), body)
	draw_rect(Rect2(0, 0, w, unit * 1.5), light)                    # light top edge
	draw_rect(Rect2(0, h - unit * 2.0, w, unit * 2.0), dark)        # dark bottom edge
	draw_rect(Rect2(0, 0, unit, h), light.darkened(0.15))           # left edge
	draw_rect(Rect2(w - unit, 0, unit, h), dark)                    # right edge
	if parts.size() == 2:
		draw_rect(Rect2(w * split - unit * 0.5, unit * 3.0, unit, h - unit * 6.0), dark)
	# Rivets in the four corners.
	var inset := unit * 3.5
	var rivet := unit * 1.8
	for p in [Vector2(inset, inset), Vector2(w - inset, inset), Vector2(inset, h - inset), Vector2(w - inset, h - inset)]:
		draw_rect(Rect2(p - Vector2.ONE * rivet / 2.0, Vector2.ONE * rivet), light)
		draw_rect(Rect2(p + Vector2.ONE * rivet / 4.0, Vector2.ONE * rivet / 2.0), dark)
	if arrow:
		_draw_arrow(Vector2(w / 2.0, h / 2.0), minf(w, h) * 0.3)


## The red curved "back" arrow of the original's return button.
func _draw_arrow(center: Vector2, radius: float) -> void:
	var red := Color("d01010")
	var edge := Color("500808")
	var points := PackedVector2Array()
	for i in 11:
		var a := lerpf(-PI * 0.15, PI * 1.05, i / 10.0)
		points.append(center + Vector2(cos(a), -sin(a)) * radius)
	draw_polyline(points, edge, radius * 0.7)
	draw_polyline(points, red, radius * 0.45)
	var tip := points[points.size() - 1]
	var head := PackedVector2Array([
		tip + Vector2(-radius * 0.65, -radius * 0.1),
		tip + Vector2(radius * 0.65, -radius * 0.1),
		tip + Vector2(0, radius * 0.8),
	])
	draw_colored_polygon(head, edge)
	var inner := PackedVector2Array([
		tip + Vector2(-radius * 0.42, -radius * 0.05),
		tip + Vector2(radius * 0.42, -radius * 0.05),
		tip + Vector2(0, radius * 0.55),
	])
	draw_colored_polygon(inner, red)
