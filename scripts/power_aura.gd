extends Node2D

# Ring around a ship that has a power: a faint full circle, and a bright arc that shrinks as the power runs out.

var color := Color.WHITE
var fraction := 1.0
var time := 0.0


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 1.0 + 0.04 * sin(time * 6.0)
	var radius := 92.0 * pulse
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, 0.18), 10.0, true)
	if fraction > 0.01:
		draw_arc(Vector2.ZERO, radius, -PI / 2.0, -PI / 2.0 + TAU * fraction, 48, Color(color, 0.95), 6.0, true)
