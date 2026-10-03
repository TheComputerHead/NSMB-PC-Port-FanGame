class_name QuiltPanel
extends Control
## The original's touch-screen backdrop: cream quilted bricks, with a green title bar on top.

const BASE := Color("e8dedb")
const BAR := Color("38aa78")

var bar_height := 60.0
var bar_color := BAR
var _title: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	_title = MenuStyle.plain_label("", 22, Color.WHITE)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_title)
	resized.connect(_layout)
	_layout()


func set_title(text: String) -> void:
	_title.text = text


func set_bar_color(color: Color) -> void:
	bar_color = color
	queue_redraw()


func _layout() -> void:
	if _title:
		_title.position = Vector2(0, 0)
		_title.size = Vector2(size.x, bar_height)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BASE)
	# Staggered bricks with a faint variation in tone.
	var brick := Vector2(size.x / 6.0, size.y / 11.0)
	var rows := int(ceil(size.y / brick.y)) + 1
	for row in rows:
		var offset := -brick.x * 0.5 if row % 2 == 1 else 0.0
		var x := offset
		var col := 0
		while x < size.x:
			var tone := 0.97 + 0.04 * fposmod(sin((row * 7 + col * 13) * 12.9898) * 43758.5453, 1.0)
			var rect := Rect2(x, row * brick.y, brick.x, brick.y)
			draw_rect(rect, BASE * Color(tone, tone, tone))
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2)), Color(1, 1, 1, 0.35))
			draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 2), Vector2(rect.size.x, 2)), Color(0.6, 0.55, 0.55, 0.22))
			draw_rect(Rect2(rect.position + Vector2(rect.size.x - 2, 0), Vector2(2, rect.size.y)), Color(0.6, 0.55, 0.55, 0.15))
			x += brick.x
			col += 1
	draw_rect(Rect2(0, 0, size.x, bar_height), bar_color)
	draw_rect(Rect2(0, bar_height - 3, size.x, 3), bar_color.darkened(0.2))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.12), false, 3.0)
