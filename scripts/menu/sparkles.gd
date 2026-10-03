class_name Sparkles
extends Control
## Little four-point stars that twinkle on top of the logo.

var area := Rect2()          # where sparkles may appear (set by the menu each frame)

var _items: Array[Dictionary] = []
var _timer := 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0 and area.size.x > 80.0:
		_timer = randf_range(0.1, 0.32)
		_items.append({
			"pos": area.position + Vector2(randf() * area.size.x, randf() * area.size.y * 0.9),
			"age": 0.0,
			"life": randf_range(0.5, 0.9),
			"size": randf_range(7.0, 16.0),
		})
	for item in _items:
		item.age += delta
	_items = _items.filter(func(i: Dictionary) -> bool: return i.age < i.life)
	queue_redraw()


func _draw() -> void:
	for item in _items:
		var t: float = item.age / item.life
		var r: float = item.size * sin(PI * t)
		_star(item.pos, r * 1.35, Color(1.0, 0.9, 0.3, 0.55))
		_star(item.pos, r, Color(1, 1, 1, 0.95))


## A pinched four-point star.
func _star(center: Vector2, radius: float, color: Color) -> void:
	if radius < 0.5:
		return
	var points := PackedVector2Array()
	for i in 8:
		var angle := i * PI / 4.0
		var r := radius if i % 2 == 0 else radius * 0.22
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, color)


## A burst of sparkles all over the area at once.
func burst(count: int) -> void:
	for i in count:
		_items.append({
			"pos": area.position + Vector2(randf() * area.size.x, randf() * area.size.y),
			"age": -randf() * 0.35,
			"life": randf_range(0.55, 1.0),
			"size": randf_range(10.0, 22.0),
		})
