extends RigidBody2D

const PULSE_RING := preload("res://scripts/pulse_ring.gd")
const Impact := preload("res://scripts/impact.gd")
const Powers := preload("res://scripts/powers.gd")
const PowerAura := preload("res://scripts/power_aura.gd")

# 0 = single player (uses the normal input actions), 1 and 2 = co-op (uses the p1_* / p2_* actions)
var player_index := 0
var accent := Color(0.5, 1.0, 0.75)

var move_force := 1500.0
var controls_enabled := true
var exhaust_offset := 40.0
var ring_interval := 0.12
var ring_timer := 0.0

# ship hum: a seamless loop that runs silently and fades in while thrusting, rising in pitch with speed
var hum_volume := 0.45
var hum_fade_in := 0.12
var hum_fade_out := 0.35
var hum_min_pitch := 0.9
var hum_max_pitch := 1.3
var hum_full_speed := 700.0
var is_thrusting := false

# temporary power from a pickup (see powers.gd). -1 = none.
var power := -1
var power_time_left := 0.0
var power_duration := 1.0
var base_move_force := 1500.0
var base_pulse_cooldown := 1.8
var base_mass := 1.0
var aura: Node2D

# pulse blast: a shockwave that shoves nearby asteroids away
var pulse_radius := 520.0
var pulse_force := 540.0
var pulse_recoil := 220.0         # most the ship is kicked back
var pulse_recoil_share := 0.25   # share of the pushed impulse that comes back
var pulse_cooldown := 1.8
# how strongly a pulse shoves the other ship, compared with an asteroid (friendly fire)
var pulse_ship_share := 0.6
var pulse_timer := 0.0
# 0..1, read by the HUD
var pulse_charge := 1.0

# wall hit feedback
var wall_hit_min_speed := 120.0
var wall_hit_cooldown := 0.25
var wall_hit_timer := 0.0
var prev_velocity := Vector2.ZERO
var shake_tween: Tween
var squash_tween: Tween

@onready var sparkles: CPUParticles2D = $Trail
@onready var camera: Camera2D = $Camera2D
@onready var ship: Sprite2D = $Ship
@onready var thrust_sound: AudioStreamPlayer = $ThrustSound


func _ready() -> void:
	base_move_force = move_force
	base_pulse_cooldown = pulse_cooldown
	base_mass = mass
	thrust_sound.bus = "SFX"
	thrust_sound.volume_linear = 0.0
	thrust_sound.pitch_scale = hum_min_pitch
	thrust_sound.play()


func _process(delta: float) -> void:
	if power >= 0:
		power_time_left -= delta
		if aura:
			aura.fraction = clampf(power_time_left / power_duration, 0.0, 1.0)
		if power_time_left <= 0.0:
			_end_power()
	if pulse_timer > 0.0:
		pulse_timer = maxf(pulse_timer - delta, 0.0)
		pulse_charge = 1.0 - pulse_timer / pulse_cooldown
	var target := hum_volume if is_thrusting else 0.0
	var fade_time := hum_fade_in if is_thrusting else hum_fade_out
	thrust_sound.volume_linear = move_toward(thrust_sound.volume_linear, target, hum_volume / fade_time * delta)
	var speed_t := clampf(linear_velocity.length() / hum_full_speed, 0.0, 1.0)
	thrust_sound.pitch_scale = lerpf(thrust_sound.pitch_scale, lerpf(hum_min_pitch, hum_max_pitch, speed_t), 6.0 * delta)


# ---------- powers ----------

# take a power: it replaces any power the ship already has
func grant_power(type: int) -> void:
	if power >= 0:
		_end_power(false)
	power = type
	power_duration = Powers.power_duration(type)
	power_time_left = power_duration
	_apply_power_stats()

	aura = Node2D.new()
	aura.set_script(PowerAura)
	aura.color = Powers.power_color(type)
	aura.z_index = 1
	add_child(aura)

	match type:
		Powers.Type.TURBO:
			# the pulse is ready at once
			pulse_timer = 0.0
			pulse_charge = 1.0
		Powers.Type.FREEZE:
			var manager := get_tree().get_first_node_in_group("level_manager")
			if manager:
				manager.freeze_time(power_duration)
	_flash_ship(1.0)


func _end_power(play_sound := true) -> void:
	if power < 0:
		return
	power = -1
	power_time_left = 0.0
	_apply_power_stats()
	if aura:
		aura.queue_free()
		aura = null
	if play_sound:
		Impact.power_end(get_parent(), global_position)


# thrust, pulse recharge and weight for the current power (all back to normal when there is none)
func _apply_power_stats() -> void:
	move_force = base_move_force
	pulse_cooldown = base_pulse_cooldown
	mass = base_mass
	match power:
		Powers.Type.TURBO:
			move_force = base_move_force * Powers.TURBO_THRUST
			pulse_cooldown = base_pulse_cooldown * Powers.TURBO_PULSE_COOLDOWN
		Powers.Type.HEAVY:
			# heavier, with the thrust raised to match so it still accelerates
			mass = base_mass * Powers.HEAVY_MASS
			move_force = base_move_force * Powers.HEAVY_THRUST


# MAGNET: asteroids close by are drawn toward the ship, and slowed relative to it so they gather instead of orbiting
func _magnet_pull() -> void:
	for node in get_tree().get_nodes_in_group("asteroids"):
		var body := node as RigidBody2D
		if body == null or body.is_queued_for_deletion():
			continue
		var offset := global_position - body.global_position
		var distance := offset.length()
		if distance > Powers.MAGNET_RADIUS or distance < 60.0:
			continue
		var strength := 1.0 - distance / Powers.MAGNET_RADIUS
		body.apply_central_force(offset.normalized() * Powers.MAGNET_FORCE * strength)
		body.apply_central_force(-(body.linear_velocity - linear_velocity) * 2.0 * strength)


# which input action this player listens to: "move_left" alone, or "p2_move_left" in co-op
func _action(action_name: String) -> StringName:
	return StringName(action_name if player_index == 0 else "p%d_%s" % [player_index, action_name])


# the ship's look for a colour from the setup screen: its picture, and the colour of its thrusters and rings
func apply_look(color_index: int) -> void:
	var entry: Dictionary = Session.COLORS[color_index]
	accent = entry.accent
	ship.texture = entry.texture
	var ramp: Gradient = sparkles.color_ramp.duplicate()
	ramp.set_color(0, accent.lightened(0.6))
	ramp.set_color(1, Color(accent, 0.0))
	sparkles.color_ramp = ramp


# called by the level for a co-op game: pick the player's number and engine note
func setup_player(index: int) -> void:
	player_index = index
	apply_look(Session.player_colors[index - 1])
	if index == 2:
		# a slightly higher engine note, so two hums don't blur into one
		hum_min_pitch *= 1.12
		hum_max_pitch *= 1.12


func _pulse_colors() -> Array:
	return [accent, accent.lightened(0.5)]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(_action("pulse")):
		_try_pulse()


func _try_pulse() -> void:
	if not controls_enabled or pulse_timer > 0.0:
		return
	pulse_timer = pulse_cooldown
	pulse_charge = 0.0

	var hit := 0
	var total_impulse := Vector2.ZERO
	for node in get_tree().get_nodes_in_group("asteroids"):
		var body := node as RigidBody2D
		if body == null or body.is_queued_for_deletion():
			continue
		var offset := body.global_position - global_position
		var distance := offset.length()
		if distance > pulse_radius:
			continue
		# strongest up close, still a solid shove at the edge of the blast
		var falloff := 1.0 - distance / pulse_radius
		var direction := offset.normalized() if distance > 1.0 else Vector2.from_angle(randf() * TAU)
		var impulse := direction * pulse_force * (0.4 + 0.6 * falloff)
		body.apply_central_impulse(impulse)
		total_impulse += impulse
		if body.has_method("pulse_hit"):
			body.pulse_hit(0.4 + 0.6 * falloff, player_index)
		hit += 1

	# the blast also shoves the other ship, a bit more gently (a boost for a friend, a nudge for a rival)
	for node in get_tree().get_nodes_in_group("player"):
		var other := node as RigidBody2D
		if other == null or other == self:
			continue
		var gap := other.global_position - global_position
		var gap_distance := gap.length()
		if gap_distance > pulse_radius:
			continue
		var gap_falloff := 1.0 - gap_distance / pulse_radius
		var ship_impulse := gap.normalized() * pulse_force * pulse_ship_share * (0.4 + 0.6 * gap_falloff)
		other.apply_central_impulse(ship_impulse)
		other.pulse_hit(0.4 + 0.6 * gap_falloff)
		# pushing the other ship kicks you back too
		total_impulse += ship_impulse

	# a kick back from everything it pushed, so firing next to a crowd moves you too
	apply_central_impulse((-total_impulse * pulse_recoil_share).limit_length(pulse_recoil))
	Impact.pulse_blast(get_parent(), global_position, pulse_radius, _pulse_colors())
	_shake_camera(6.0 + minf(hit, 8) * 0.8)
	_squash(0.8)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	wall_hit_timer -= state.step
	for i in state.get_contact_count():
		var collider := state.get_contact_collider_object(i) as Node
		if collider == null:
			continue
		# contacts are reported after the bounce, so compare with last frame's velocity
		var impact := absf((state.linear_velocity - prev_velocity).dot(state.get_contact_local_normal(i)))
		if impact >= wall_hit_min_speed and wall_hit_timer <= 0.0:
			wall_hit_timer = wall_hit_cooldown
			var strength := clampf(impact / 600.0, 0.3, 1.0)
			var pos := state.get_contact_collider_position(i)
			if collider.is_in_group("map_bounds"):
				Impact.wall_hit(get_parent(), pos, strength)
				_shake_camera(4.0 + 8.0 * strength)
			elif collider.is_in_group("player"):
				# ship against ship: both ships feel it, but only one of the pair makes the sound and effects
				if get_instance_id() < collider.get_instance_id():
					Impact.ship_bump(get_parent(), pos, strength, accent, collider.accent)
				_shake_camera(3.0 + 6.0 * strength)
				_flash_ship(strength)
			_squash(strength)
		break
	prev_velocity = state.linear_velocity


func _physics_process(delta: float) -> void:
	if power == Powers.Type.MAGNET:
		_magnet_pull()
	var thrust := Vector2.ZERO
	if controls_enabled:
		thrust = Input.get_vector(_action("move_left"), _action("move_right"), _action("move_up"), _action("move_down"))
	var thrusting := thrust != Vector2.ZERO
	is_thrusting = thrusting
	sparkles.emitting = thrusting

	if not thrusting:
		ring_timer = 0.0
		return

	apply_force(thrust * move_force)

	var emit_offset := -thrust * exhaust_offset
	sparkles.position = emit_offset

	ring_timer -= delta
	if ring_timer <= 0.0:
		ring_timer = ring_interval
		_spawn_ring(global_position + emit_offset)


func _spawn_ring(world_pos: Vector2) -> void:
	var ring := Node2D.new()
	ring.set_script(PULSE_RING)
	ring.z_index = 99
	ring.color = Color(accent, 0.5)

	get_parent().add_child(ring)
	ring.global_position = world_pos


func _shake_camera(amount: float) -> void:
	amount *= Settings.screen_shake
	if amount <= 0.0:
		return
	# shake whichever camera is active: the ship's own, or the shared co-op one
	var active_camera := get_viewport().get_camera_2d()
	if active_camera == null:
		return
	if shake_tween:
		shake_tween.kill()
	shake_tween = create_tween()
	for i in 4:
		var falloff := 1.0 - i / 4.0
		var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amount * falloff
		shake_tween.tween_property(active_camera, "offset", offset, 0.035)
	shake_tween.tween_property(active_camera, "offset", Vector2.ZERO, 0.06)


# another ship's pulse hit this ship
func pulse_hit(strength: float, _pusher := 0) -> void:
	_flash_ship(0.6 + 0.4 * strength)
	_squash(0.9)
	_shake_camera(5.0)


# brighten the ship briefly
func _flash_ship(strength: float) -> void:
	var tween := create_tween()
	ship.modulate = Color.WHITE * (1.0 + 0.8 * strength)
	tween.tween_property(ship, "modulate", Color.WHITE, 0.2)


# quick squash-and-recover so the ship feels like it took the hit
func _squash(strength: float) -> void:
	if squash_tween:
		squash_tween.kill()
	squash_tween = create_tween()
	squash_tween.tween_property(ship, "scale", Vector2(1.0 + 0.16 * strength, 1.0 - 0.14 * strength), 0.05)
	squash_tween.tween_property(ship, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
