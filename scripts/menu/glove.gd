class_name Glove
extends Control
## A white glove pointing to the right, bobbing, to show the highlighted file.

const OUTLINE := Color("1a1a22")

var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var bob := sin(_time * 7.0) * size.x * 0.05
	draw_set_transform(Vector2(bob, 0))
	_shapes(size.y * 0.07, OUTLINE)
	_shapes(0.0, Color.WHITE)
	# A little shading along the bottom of the fingers.
	draw_circle(Vector2(size.x * 0.44, size.y * 0.70), size.y * 0.10, Color(0.78, 0.8, 0.88))


## The glove as a few round shapes; `grow` fattens them (used for the outline).
func _shapes(grow: float, color: Color) -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0 - grow, h * 0.30 - grow, w * 0.16 + grow * 2.0, h * 0.44 + grow * 2.0), color)   # cuff
	draw_circle(Vector2(w * 0.40, h * 0.52), h * 0.30 + grow, color)                                  # palm
	draw_circle(Vector2(w * 0.41, h * 0.24), h * 0.13 + grow, color)                                  # thumb
	draw_rect(Rect2(w * 0.40, h * 0.37 - grow, w * 0.50 + grow, h * 0.20 + grow * 2.0), color)         # index finger
	draw_circle(Vector2(w * 0.90, h * 0.47), h * 0.10 + grow, color)                                  # fingertip
	for i in 3:
		draw_circle(Vector2(w * (0.30 + 0.10 * i), h * 0.72), h * 0.11 + grow, color)                 # curled fingers
