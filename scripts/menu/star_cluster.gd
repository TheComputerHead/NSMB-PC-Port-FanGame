class_name StarCluster
extends Control
## Three stars in a pyramid beside a file, filled according to the Star Coins found.

var filled := 0   # 0..3


func _draw() -> void:
	var s := minf(size.x, size.y)
	var r := s * 0.26
	var centers := [Vector2(size.x * 0.5, s * 0.28), Vector2(size.x * 0.27, s * 0.72), Vector2(size.x * 0.73, s * 0.72)]
	for i in 3:
		_star(centers[i], r, i < filled)


func _star(center: Vector2, radius: float, on: bool) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var rr := radius if i % 2 == 0 else radius * 0.45
		points.append(center + Vector2(cos(a), sin(a)) * rr)
	var fill := Color("ffd726") if on else Color("c9b8b0")
	var edge := Color("c01818") if on else Color("8d7f79")
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, edge, maxf(radius * 0.18, 2.0))
