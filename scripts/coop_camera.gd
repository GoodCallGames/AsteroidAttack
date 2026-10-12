extends Camera2D

# Shared camera for co-op: sits between the players and zooms out as they move apart,
# so both ships are always on screen. Limits match the single-player camera.

@export var max_zoom := 0.6     # same as the single-player camera, used when the players are close
@export var min_zoom := 0.38    # farthest it will zoom out
@export var margin := 520.0     # world pixels of breathing room around the ships
@export var zoom_speed := 3.0

var target_zoom := 0.6


func _init() -> void:
	# set before the camera enters the tree, so Godot does not have to override it for physics interpolation
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


func _ready() -> void:
	limit_left = -1650
	limit_top = -1650
	limit_right = 1650
	limit_bottom = 1650
	limit_smoothed = true
	position_smoothing_enabled = true
	position_smoothing_speed = 10.0
	zoom = Vector2.ONE * max_zoom
	target_zoom = max_zoom
	# start centred on the players instead of gliding in from the origin
	global_position = _midpoint()
	reset_smoothing()


func _physics_process(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	global_position = _midpoint()

	# the largest spread, compared with how much of the screen each axis can show
	var view := get_viewport_rect().size
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for p in players:
		min_pos = min_pos.min(p.global_position)
		max_pos = max_pos.max(p.global_position)
	var spread := max_pos - min_pos
	var needed_zoom := minf(view.x / (spread.x + 2.0 * margin), view.y / (spread.y + 2.0 * margin))
	target_zoom = clampf(needed_zoom, min_zoom, max_zoom)
	var z := lerpf(zoom.x, target_zoom, clampf(zoom_speed * delta, 0.0, 1.0))
	zoom = Vector2.ONE * z


func _midpoint() -> Vector2:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return global_position
	var sum := Vector2.ZERO
	for p in players:
		sum += p.global_position
	return sum / players.size()
