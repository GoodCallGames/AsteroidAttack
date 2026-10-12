extends Node

# Drops a power orb on the map every so often. At most `max_active` at once, never two of the same kind,
# and never close to the collection zone, a ship, or another orb. Stops when the level ends.

const PICKUP_SCENE := preload("res://scenes/power_pickup.tscn")
const Powers := preload("res://scripts/powers.gd")

@export var first_delay := 7.0
@export var interval_min := 14.0
@export var interval_max := 20.0
@export var max_active := 2
@export var min_radius := 320.0   # keep clear of the collection zone at the centre
@export var max_radius := 1250.0  # the wall is at about 1500
@export var keep_clear := 320.0   # distance from ships and other orbs

var timer := 0.0
var level_over := false


func _ready() -> void:
	add_to_group("power_spawner")
	timer = first_delay
	var manager := get_tree().get_first_node_in_group("level_manager")
	if manager:
		manager.ended.connect(func(_won: bool): level_over = true)


func _process(delta: float) -> void:
	if level_over or Transition.busy:
		return
	timer -= delta
	if timer <= 0.0:
		timer = randf_range(interval_min, interval_max)
		spawn()


func active_pickups() -> Array:
	return get_tree().get_nodes_in_group("power_pickups").filter(func(p): return not p.is_queued_for_deletion() and not p.taken)


# returns the new orb, or null if there was no room or too many are out already
func spawn(ignore_limit := false) -> Node:
	var active := active_pickups()
	if active.size() >= max_active and not ignore_limit:
		return null
	# a power that is not already on the map
	var on_map := active.map(func(p): return p.type)
	var choices := range(Powers.DATA.size()).filter(func(t): return not (t in on_map))
	if choices.is_empty():
		choices = range(Powers.DATA.size())
	var spot := _find_spot(active)
	if spot == Vector2.INF:
		return null
	var pickup := PICKUP_SCENE.instantiate()
	pickup.type = choices.pick_random()
	pickup.position = spot
	get_parent().add_child(pickup)
	return pickup


func _find_spot(active: Array) -> Vector2:
	var players := get_tree().get_nodes_in_group("player")
	for attempt in 40:
		var radius := sqrt(randf_range(min_radius * min_radius, max_radius * max_radius))
		var spot := Vector2.from_angle(randf() * TAU) * radius
		var clear := true
		for p in players:
			if p.global_position.distance_to(spot) < keep_clear:
				clear = false
		for pickup in active:
			if pickup.global_position.distance_to(spot) < keep_clear:
				clear = false
		if clear:
			return spot
	return Vector2.INF
