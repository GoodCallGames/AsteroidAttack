extends RefCounted

# Shared collision effects, used by the ship and the asteroids:
#   bump()      - asteroid thud, random pitch, louder for harder hits
#   chips()     - a few small fragments knocked off an asteroid
#   wall_hit()  - barrier collision sound, sparks, and a ripple along the map boundary
# Use with: const Impact := preload("res://scripts/impact.gd")

const BUMP_SOUND := preload("res://assets/audio/asteroid-thud-trimmed.wav")
const BARRIER_SOUND := preload("res://assets/audio/barrier-collision-trimmed.wav")
const PULSE_SOUND := preload("res://assets/audio/pulse-blast.wav")
const POWER_PICKUP_SOUND := preload("res://assets/audio/power-pickup.wav")
const POWER_END_SOUND := preload("res://assets/audio/power-end.wav")
const PULSE_RING := preload("res://scripts/pulse_ring.gd")
const WALL_SPARK := preload("res://scenes/wall_spark.tscn")
const CHIP_EFFECT := preload("res://scenes/asteroid_break.tscn")

static var _ripple_tween: Tween


# strength is 0..1
static func bump(parent: Node, world_pos: Vector2, strength: float, stream: AudioStream = BUMP_SOUND, pitch := 1.0) -> void:
	var sound := AudioStreamPlayer2D.new()
	sound.stream = stream
	sound.bus = "SFX"
	sound.pitch_scale = randf_range(0.9, 1.1) * pitch
	sound.volume_db = linear_to_db(lerpf(0.25, 1.0, strength))
	sound.finished.connect(sound.queue_free)
	parent.add_child(sound)
	sound.global_position = world_pos
	sound.play()


static func chips(parent: Node, world_pos: Vector2, texture: Texture2D, count: int) -> void:
	var burst: CPUParticles2D = CHIP_EFFECT.instantiate()
	burst.texture = texture
	burst.amount = count
	# a small knock, not a full break: slower and shorter-lived than the destroy burst
	burst.initial_velocity_min = 40.0
	burst.initial_velocity_max = 130.0
	burst.lifetime = 0.5
	burst.finished.connect(burst.queue_free)
	parent.add_child(burst)
	burst.global_position = world_pos
	burst.emitting = true


# sparks fly back toward the arena centre (the origin); the boundary ripples at the hit point
static func wall_hit(parent: Node, world_pos: Vector2, strength: float) -> void:
	var sparks: CPUParticles2D = WALL_SPARK.instantiate()
	sparks.direction = -world_pos.normalized()
	sparks.amount = int(8 + 12 * strength)
	sparks.finished.connect(sparks.queue_free)
	parent.add_child(sparks)
	sparks.global_position = world_pos
	sparks.emitting = true

	bump(parent, world_pos, strength, BARRIER_SOUND)
	_play_wall_ripple(parent.get_tree(), world_pos, strength)


static func _play_wall_ripple(tree: SceneTree, world_pos: Vector2, strength: float) -> void:
	var atmosphere := tree.get_first_node_in_group("atmosphere") as CanvasItem
	if atmosphere == null:
		return
	var mat := atmosphere.material as ShaderMaterial
	mat.set_shader_parameter("hit_pos", world_pos)
	mat.set_shader_parameter("hit_strength", strength)
	if _ripple_tween and _ripple_tween.is_valid():
		_ripple_tween.kill()
	_ripple_tween = tree.create_tween()
	_ripple_tween.tween_method(func(v: float): mat.set_shader_parameter("hit_progress", v), 0.0, 1.0, 1.1)


# the ship's pulse blast: two rings racing out to the blast radius, a ring of sparks, and the thump
static func pulse_blast(parent: Node, world_pos: Vector2, radius: float, colors := [Color(0.85, 0.5, 1.0), Color(0.5, 1.0, 0.8)]) -> void:
	for i in 2:
		var ring := Node2D.new()
		ring.set_script(PULSE_RING)
		ring.radius = 30.0
		ring.line_width = 2.0 if i == 0 else 1.2
		ring.color = Color(colors[i], 0.85 if i == 0 else 0.6)
		ring.end_scale = radius / 30.0 * (1.0 if i == 0 else 0.7)
		ring.duration = 0.45 if i == 0 else 0.35
		ring.z_index = 99
		parent.add_child(ring)
		ring.global_position = world_pos

	var sparks := _spark_burst(colors[0])
	sparks.spread = 180.0
	sparks.direction = Vector2.UP
	sparks.amount = 36
	sparks.initial_velocity_min = 260.0
	sparks.initial_velocity_max = 620.0
	sparks.finished.connect(sparks.queue_free)
	parent.add_child(sparks)
	sparks.global_position = world_pos
	sparks.emitting = true

	bump(parent, world_pos, 1.0, PULSE_SOUND)


# two ships colliding: a lighter "bonk" than an asteroid hit, a quick ring in both ships' colours, and a puff of sparks
static func ship_bump(parent: Node, world_pos: Vector2, strength: float, color_a: Color, color_b: Color) -> void:
	bump(parent, world_pos, strength, BUMP_SOUND, 1.4)

	var ring := Node2D.new()
	ring.set_script(PULSE_RING)
	ring.radius = 20.0
	ring.line_width = 2.5
	ring.color = Color(color_a.lerp(color_b, 0.5), 0.8)
	ring.end_scale = 2.5 + 2.0 * strength
	ring.duration = 0.35
	ring.z_index = 99
	parent.add_child(ring)
	ring.global_position = world_pos

	var sparks := _spark_burst(color_a.lerp(color_b, 0.5))
	sparks.spread = 180.0
	sparks.direction = Vector2.UP
	sparks.amount = int(8 + 10 * strength)
	sparks.finished.connect(sparks.queue_free)
	parent.add_child(sparks)
	sparks.global_position = world_pos
	sparks.emitting = true


# a spark burst whose colours fade from a light tint of the given colour to transparent
static func _spark_burst(color: Color) -> CPUParticles2D:
	var sparks: CPUParticles2D = WALL_SPARK.instantiate()
	var ramp: Gradient = sparks.color_ramp.duplicate()
	ramp.set_color(0, color.lightened(0.6))
	ramp.set_color(1, Color(color, 0.0))
	sparks.color_ramp = ramp
	return sparks


# a ship grabs a power orb: a ring and sparks in the power's colour, and the pickup chime
static func pickup_burst(parent: Node, world_pos: Vector2, color: Color) -> void:
	var ring := Node2D.new()
	ring.set_script(PULSE_RING)
	ring.radius = 30.0
	ring.line_width = 3.0
	ring.color = Color(color, 0.9)
	ring.end_scale = 6.0
	ring.duration = 0.5
	ring.z_index = 99
	parent.add_child(ring)
	ring.global_position = world_pos

	var sparks := _spark_burst(color)
	sparks.spread = 180.0
	sparks.direction = Vector2.UP
	sparks.amount = 26
	sparks.initial_velocity_min = 200.0
	sparks.initial_velocity_max = 460.0
	sparks.finished.connect(sparks.queue_free)
	parent.add_child(sparks)
	sparks.global_position = world_pos
	sparks.emitting = true

	bump(parent, world_pos, 1.0, POWER_PICKUP_SOUND)


static func power_end(parent: Node, world_pos: Vector2) -> void:
	bump(parent, world_pos, 0.7, POWER_END_SOUND)
