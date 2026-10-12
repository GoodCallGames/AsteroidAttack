extends Control

# When only a few asteroids remain, mark where they are:
#   off-screen asteroids get an edge badge with an arrow pointing toward them
#   on-screen asteroids get a pulsing ring so they're easy to spot
# Drawn in screen space, so it lives inside the HUD CanvasLayer.

const ICON := preload("res://assets/textures/asteroid_grey.png")
const MINT := Color(0.5, 1.0, 0.8)

@export var show_at_or_below := 5
@export var edge_margin := 56.0
# larger top margin keeps badges clear of the HUD panel
@export var top_margin := 130.0
@export var badge_radius := 24.0
# asteroids farther than this from the ship get the faintest badge
@export var far_distance := 2500.0

var remaining := 999
var level_over := false
var strength := 0.0 # 0..1, fades and scales the indicators in and out
var time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var area := get_tree().get_first_node_in_group("collection_area")
	if area:
		area.progress_changed.connect(func(left: int, _total: int): remaining = left)
		if area.total > 0:
			remaining = area.total - area.collected
	var manager := get_tree().get_first_node_in_group("level_manager")
	if manager:
		manager.ended.connect(func(_won: bool): level_over = true)


func _process(delta: float) -> void:
	time += delta
	var active := remaining <= show_at_or_below and remaining > 0 and not level_over
	strength = move_toward(strength, 1.0 if active else 0.0, delta * 3.0)
	visible = strength > 0.0
	if visible:
		queue_redraw()


func _draw() -> void:
	var view_size := get_viewport_rect().size
	var to_screen := get_viewport().get_canvas_transform()
	var zoom := to_screen.get_scale().x
	var inner := Rect2(
		Vector2(edge_margin, top_margin),
		view_size - Vector2(edge_margin * 2.0, top_margin + edge_margin))
	var inner_center := inner.position + inner.size / 2.0
	var player := get_tree().get_first_node_in_group("player") as Node2D

	for node in get_tree().get_nodes_in_group("asteroids"):
		var asteroid := node as Node2D
		if asteroid == null or asteroid.is_queued_for_deletion():
			continue
		var screen_pos := to_screen * asteroid.global_position
		var phase := float(asteroid.get_instance_id() % 7)

		if inner.has_point(screen_pos):
			_draw_ring(screen_pos, zoom, phase)
			continue

		# project onto the inner rectangle along the line from its centre
		var offset := screen_pos - inner_center
		var half := inner.size / 2.0
		var t := minf(half.x / maxf(absf(offset.x), 0.001), half.y / maxf(absf(offset.y), 0.001))
		var closeness := 0.0
		if player:
			closeness = clampf(1.0 - player.global_position.distance_to(asteroid.global_position) / far_distance, 0.0, 1.0)
		_draw_badge(inner_center + offset * t, offset.normalized(), lerpf(0.55, 1.0, closeness), phase)


func _draw_ring(center: Vector2, zoom: float, phase: float) -> void:
	var radius := 66.0 * zoom * (1.0 + 0.1 * sin(time * 4.0 + phase))
	draw_arc(center, radius, 0.0, TAU, 48, Color(MINT, 0.65 * strength), 3.0, true)


func _draw_badge(pos: Vector2, dir: Vector2, alpha: float, phase: float) -> void:
	var a := alpha * strength
	var radius := badge_radius * strength * (1.0 + 0.07 * sin(time * 5.0 + phase))
	var color := Color(MINT, a)

	draw_circle(pos, radius, Color(0.08, 0.09, 0.13, 0.78 * strength))
	draw_arc(pos, radius, 0.0, TAU, 40, color, 3.0, true)
	var icon_size := Vector2.ONE * radius * 1.25
	draw_texture_rect(ICON, Rect2(pos - icon_size / 2.0, icon_size), false, Color(1, 1, 1, a))

	# arrow just outside the badge, pointing toward the asteroid
	var perp := dir.orthogonal()
	var base := pos + dir * (radius + 4.0)
	var tip := pos + dir * (radius + 4.0 + 16.0 * strength)
	draw_colored_polygon(PackedVector2Array([tip, base + perp * 10.0 * strength, base - perp * 10.0 * strength]), color)
