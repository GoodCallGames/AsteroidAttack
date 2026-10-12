extends Area2D

# A power orb floating on the map. Its icon, name and colour show which power it gives before you grab it.
# A ship that flies into it gets the power. It blinks for the last few seconds, then fades away if nobody took it.

const Powers := preload("res://scripts/powers.gd")
const Impact := preload("res://scripts/impact.gd")

const LIFETIME := 24.0
const WARN_TIME := 4.0

# set by the spawner before the orb enters the tree
var type: int = Powers.Type.MAGNET

var age := 0.0
var taken := false
var color := Color.WHITE

@onready var name_label: Label = $Name


func _ready() -> void:
	add_to_group("power_pickups")
	color = Powers.power_color(type)
	name_label.text = Powers.power_name(type)
	name_label.add_theme_color_override("font_color", color)
	name_label.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.1, 0.95))
	name_label.add_theme_constant_override("outline_size", 10)
	body_entered.connect(_on_body_entered)

	# pop in
	scale = Vector2.ZERO
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if taken:
		return
	age += delta
	queue_redraw()
	var remaining := LIFETIME - age
	if remaining < WARN_TIME:
		modulate.a = 0.4 + 0.6 * absf(sin(age * 9.0))
	if remaining <= 0.0:
		_expire()


func _draw() -> void:
	var bob := Vector2(0.0, sin(age * 2.2) * 6.0)
	var pulse := 1.0 + 0.06 * sin(age * 4.0)

	# soft glow
	for i in 4:
		draw_circle(bob, (78.0 - i * 10.0) * pulse, Color(color, 0.06 + 0.03 * i))
	# disc and rim
	draw_circle(bob, 46.0, Color(0.07, 0.08, 0.13, 0.96))
	draw_arc(bob, 46.0, 0.0, TAU, 40, color, 5.0, true)
	# a short arc that circles the orb, so it looks alive
	draw_arc(bob, 60.0 * pulse, age * 2.0, age * 2.0 + 1.5, 16, Color(color, 0.85), 3.5, true)
	Powers.draw_icon(self, type, bob, 40.0)


func _on_body_entered(body: Node2D) -> void:
	if taken or not body.is_in_group("player"):
		return
	taken = true
	body.grant_power(type)
	Impact.pickup_burst(get_parent(), global_position, color)
	queue_free()


func _expire() -> void:
	taken = true
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
