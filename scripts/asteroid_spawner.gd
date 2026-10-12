extends Node2D

const ASTEROID_SCENE := preload("res://scenes/asteroid.tscn")

@export var min_count := 15
@export var max_count := 40
# play area is a circle of radius ~1500 centred on the origin (see MapBounds)
@export var spawn_radius := 1400.0
# keep asteroids out of the collection area (radius ~152) so they don't spawn pre-collected
@export var safe_radius := 250.0
# asteroids need breathing room, otherwise physics bodies spawn overlapping
@export var min_spacing := 120.0
# about this share of the asteroids are golden (bonus time), at least one and no more than max_golden
@export var golden_fraction := 0.12
@export var max_golden := 4


func _ready() -> void:
	var count := randi_range(min_count, max_count)
	var positions: Array[Vector2] = []
	var attempts := 0

	while positions.size() < count and attempts < count * 20:
		attempts += 1
		var pos := _random_point_in_ring()
		if _is_far_enough(pos, positions):
			positions.append(pos)

	var golden_count := clampi(roundi(positions.size() * golden_fraction), 1, max_golden)
	var order := range(positions.size())
	order.shuffle()
	var golden_indices := order.slice(0, golden_count)

	for i in positions.size():
		var pos := positions[i]
		var asteroid := ASTEROID_SCENE.instantiate()
		asteroid.golden = i in golden_indices
		asteroid.position = pos
		asteroid.rotation = randf() * TAU
		add_child(asteroid)


func _random_point_in_ring() -> Vector2:
	# sqrt gives a uniform distribution over the area instead of clustering at the centre
	var r := sqrt(randf_range(safe_radius * safe_radius, spawn_radius * spawn_radius))
	return Vector2.from_angle(randf() * TAU) * r


func _is_far_enough(pos: Vector2, existing: Array[Vector2]) -> bool:
	for other in existing:
		if pos.distance_to(other) < min_spacing:
			return false
	return true
