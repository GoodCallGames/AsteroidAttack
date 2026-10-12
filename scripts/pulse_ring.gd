extends Node2D

# Expanding, fading energy ring. Frees itself when finished.

@export var radius := 14.4
@export var line_width := 2.4
@export var color := Color(0.5, 1.0, 0.75, 0.5)
@export var end_scale := 3.0
@export var duration := 0.6


func _ready() -> void:
	scale = Vector2(0.4, 0.4)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE * end_scale, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate:a", 0.0, duration)
	tween.chain().tween_callback(queue_free)


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, color, line_width, true)
