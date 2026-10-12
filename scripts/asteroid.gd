extends RigidBody2D

const BREAK_EFFECT := preload("res://scenes/asteroid_break.tscn")
const Impact := preload("res://scripts/impact.gd")

# impact is the change in velocity along the contact normal
const HIT_MIN := 90.0
const HIT_COOLDOWN := 0.15

const GOLD := Color(1.0, 0.82, 0.3)

var prev_velocity := Vector2.ZERO
var hit_timer := 0.0
# set by the spawner before the asteroid enters the tree
var golden := false
# 0 = nobody yet / single player, 1 and 2 = the player who last pushed it
var last_pusher := 0
var base_color := Color.WHITE
var flash_tween: Tween

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	var random_force_x = get_random_force(100.0)
	var random_force_y = get_random_force()
	
	var my_vector := Vector2(random_force_x, random_force_y)
	
	if golden:
		_setup_golden()
		# golden ones drift quickly, so they are worth chasing
		my_vector *= 2.4

	apply_impulse(my_vector)

	angular_velocity = randf_range(-3.0, 3.0)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	hit_timer -= state.step
	if hit_timer <= 0.0:
		for i in state.get_contact_count():
			var collider := state.get_contact_collider_object(i) as Node
			if collider == null:
				continue
			var impact := absf((state.linear_velocity - prev_velocity).dot(state.get_contact_local_normal(i)))
			if impact >= HIT_MIN:
				hit_timer = HIT_COOLDOWN
				_on_hit(collider, state.get_contact_collider_position(i), impact)
				break
	prev_velocity = state.linear_velocity


func _on_hit(collider: Node, world_pos: Vector2, impact: float) -> void:
	var strength := clampf(impact / 500.0, 0.2, 1.0)
	_flash(strength)

	# remember who is responsible for this asteroid: a ship that touched it, or the asteroid that hit it
	if collider.is_in_group("player"):
		last_pusher = collider.player_index
	elif collider.is_in_group("asteroids") and collider.last_pusher > 0 and last_pusher == 0:
		last_pusher = collider.last_pusher

	# when two asteroids collide both report it, so only one makes the sound and chips
	var hit_asteroid := collider.is_in_group("asteroids")
	if hit_asteroid and get_instance_id() > collider.get_instance_id():
		return

	if collider.is_in_group("map_bounds"):
		Impact.wall_hit(get_parent(), world_pos, strength * 0.6)
	else:
		Impact.bump(get_parent(), world_pos, strength)
	if strength > 0.5:
		Impact.chips(get_parent(), world_pos, sprite.texture, 2 + int(2.0 * strength))


# the ship's pulse blast hit this asteroid: a spin kick and a flash
func pulse_hit(strength: float, pusher := 0) -> void:
	if pusher > 0:
		last_pusher = pusher
	angular_velocity += randf_range(-5.0, 5.0) * strength
	_flash(0.5 + 0.5 * strength)


# brighten and pop the sprite, then settle back
func _flash(strength: float) -> void:
	if flash_tween:
		flash_tween.kill()
	sprite.modulate = base_color * (1.0 + 0.9 * strength)
	sprite.scale = Vector2.ONE * (1.0 + 0.12 * strength)
	flash_tween = create_tween().set_parallel(true)
	flash_tween.tween_property(sprite, "modulate", base_color, 0.2)
	flash_tween.tween_property(sprite, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# suck_to: if set, the pieces stream toward that world point instead of scattering
func break_apart(piece_count := 12, suck_to := Vector2.INF) -> void:
	var burst: CPUParticles2D = BREAK_EFFECT.instantiate()
	burst.texture = sprite.texture
	burst.amount = piece_count
	# draw above the collection zone's glow and rings, which would otherwise hide the pieces
	burst.z_index = 60
	if golden:
		burst.color = GOLD
	if suck_to != Vector2.INF:
		var to_target := suck_to - global_position
		burst.direction = to_target.normalized()
		burst.spread = 35.0
		burst.lifetime = 0.45
		var speed := to_target.length() / burst.lifetime
		burst.initial_velocity_min = speed * 0.7
		burst.initial_velocity_max = speed * 1.1
	burst.finished.connect(burst.queue_free)
	get_parent().add_child(burst)
	burst.global_position = global_position
	burst.emitting = true
	queue_free()


# golden asteroid: gold tint, a shimmer, a trail of sparkles, lighter so it is easier to knock around
func _setup_golden() -> void:
	add_to_group("golden")
	base_color = GOLD
	sprite.modulate = base_color
	mass = 0.6

	# the sprite brightens and dims slowly
	var shimmer := create_tween().set_loops()
	shimmer.tween_property(sprite, "self_modulate", Color(1.3, 1.2, 0.9), 0.5).set_trans(Tween.TRANS_SINE)
	shimmer.tween_property(sprite, "self_modulate", Color(1.0, 1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE)

	# sparkles left behind in the world as it drifts
	var sparkles := CPUParticles2D.new()
	sparkles.amount = 16
	sparkles.lifetime = 0.9
	sparkles.local_coords = false
	sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	sparkles.emission_sphere_radius = 38.0
	sparkles.direction = Vector2.ZERO
	sparkles.spread = 180.0
	sparkles.gravity = Vector2.ZERO
	sparkles.initial_velocity_min = 5.0
	sparkles.initial_velocity_max = 30.0
	sparkles.scale_amount_min = 4.0
	sparkles.scale_amount_max = 8.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	fade.set_color(1, Color(1.0, 0.8, 0.2, 0.0))
	sparkles.color_ramp = fade
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	sparkles.scale_amount_curve = shrink
	sparkles.show_behind_parent = true
	add_child(sparkles)


func get_random_force(force_range := 50.0) -> float:
	return randf_range(-force_range, force_range)
