class_name StatIcon
extends Control
## Small drawn icons for the file card's statistics.

const OUTLINE := Color("5a3c00")

var kind := "coin"


func _init(icon_kind: String = "coin", icon_size: float = 24.0) -> void:
	kind = icon_kind
	custom_minimum_size = Vector2(icon_size, icon_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size / 2.0
	match kind:
		"coin":
			draw_circle(c, s * 0.46, OUTLINE)
			draw_circle(c, s * 0.40, Color("ffd726"))
			draw_rect(Rect2(c.x - s * 0.07, c.y - s * 0.22, s * 0.14, s * 0.44), Color("e09a00"))
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2.0 + i * PI / 5.0
				pts.append(c + Vector2(cos(a), sin(a)) * (s * 0.5 if i % 2 == 0 else s * 0.22))
			draw_colored_polygon(pts, Color("ffd726"))
			pts.append(pts[0])
			draw_polyline(pts, Color("c01818"), 2.0)
		"life":
			# a 1-UP style mushroom
			draw_circle(c + Vector2(0, -s * 0.08), s * 0.42, Color("38b848"))
			draw_rect(Rect2(c.x - s * 0.28, c.y + s * 0.05, s * 0.56, s * 0.38), Color("f5e6c8"))
			draw_circle(c + Vector2(0, -s * 0.12), s * 0.14, Color.WHITE)
			draw_circle(c + Vector2(-s * 0.24, -s * 0.02), s * 0.09, Color.WHITE)
			draw_circle(c + Vector2(s * 0.24, -s * 0.02), s * 0.09, Color.WHITE)
		"world":
			draw_circle(c, s * 0.46, Color("1a5fb4"))
			draw_circle(c + Vector2(-s * 0.12, -s * 0.08), s * 0.18, Color("38b848"))
			draw_circle(c + Vector2(s * 0.16, s * 0.14), s * 0.14, Color("38b848"))
			draw_arc(c, s * 0.46, 0, TAU, 24, Color.WHITE, 2.0)
		"clock":
			draw_circle(c, s * 0.46, Color.WHITE)
			draw_arc(c, s * 0.46, 0, TAU, 24, Color("2a2a30"), 2.0)
			draw_line(c, c + Vector2(0, -s * 0.30), Color("2a2a30"), 2.0)
			draw_line(c, c + Vector2(s * 0.22, 0), Color("2a2a30"), 2.0)
		"calendar":
			draw_rect(Rect2(c.x - s * 0.44, c.y - s * 0.40, s * 0.88, s * 0.84), Color.WHITE)
			draw_rect(Rect2(c.x - s * 0.44, c.y - s * 0.40, s * 0.88, s * 0.24), Color("d02020"))
			for i in 3:
				draw_rect(Rect2(c.x - s * 0.30 + i * s * 0.24, c.y + s * 0.04, s * 0.14, s * 0.14), Color("2a2a30"))
