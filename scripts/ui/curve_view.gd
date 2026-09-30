class_name CurveView
extends Control
## Visualises the transmitter response curve for one axis.

var axis_cfg: Dictionary = {}

func _init() -> void:
	custom_minimum_size = Vector2(180, 180)

func set_cfg(c: Dictionary) -> void:
	axis_cfg = c
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0, 0, 0, 0.35))
	var c := r.get_center()
	draw_line(Vector2(r.position.x, c.y), Vector2(r.end.x, c.y), Color(1, 1, 1, 0.15), 1.0)
	draw_line(Vector2(c.x, r.position.y), Vector2(c.x, r.end.y), Color(1, 1, 1, 0.15), 1.0)
	draw_line(r.position + Vector2(0, r.size.y), r.position + Vector2(r.size.x, 0), Color(1, 1, 1, 0.12), 1.0)
	var pts := PackedVector2Array()
	for i in 81:
		var x := -1.0 + i / 40.0
		var y := Transmitter.shape(x, axis_cfg)
		pts.append(Vector2(c.x + x * r.size.x * 0.5, c.y - y * r.size.y * 0.5))
	draw_polyline(pts, UITheme.ACCENT, 3.0, true)
