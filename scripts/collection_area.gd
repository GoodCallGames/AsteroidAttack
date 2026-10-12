extends Area2D

# remaining asteroids and the starting total, for the HUD
signal progress_changed(remaining: int, total: int)
# a golden asteroid was collected (the level manager adds bonus time)
signal golden_collected

const PULSE_RING := preload("res://scripts/pulse_ring.gd")

# major pentatonic steps (in semitones) the chime climbs through during a combo
const COMBO_SEMITONES := [0, 2, 4, 7, 9, 12, 14, 16]

# collecting again within this many seconds keeps a combo going
@export var combo_window := 1.2

@onready var collect_sound: AudioStreamPlayer2D = $CollectSound
@onready var glow: Sprite2D = $Glow
@onready var rings: GPUParticles2D = $GPUParticles2D

var total := 0
var collected := 0
# how many each player pushed in (0 = single player / nobody, 1 and 2 = the co-op players)
var scores := {0: 0, 1: 0, 2: 0}
var combo := 0
var combo_timer := 0.0
var flash_tween: Tween
var pop_tween: Tween


func _ready() -> void:
	collect_sound.bus = "SFX" # the chimes copy this bus
	# the spawner adds its asteroids in its own _ready, so count after everything is in the tree
	await get_tree().process_frame
	total = get_tree().get_nodes_in_group("asteroids").size()
	_update_glow()
	progress_changed.emit(total - collected, total)

	# slow breathing so the area never looks static
	var breathe := create_tween().set_loops()
	breathe.tween_property(glow, "scale", Vector2.ONE * 1.95, 1.8).set_trans(Tween.TRANS_SINE)
	breathe.tween_property(glow, "scale", Vector2.ONE * 1.7, 1.8).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	combo_timer -= delta
	if combo_timer <= 0.0:
		combo = 0


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("asteroids"):
		return

	collected += 1
	var pusher: int = body.get("last_pusher") if body.get("last_pusher") != null else 0
	scores[pusher] = scores.get(pusher, 0) + 1
	combo += 1
	combo_timer = combo_window

	var is_golden: bool = body.get("golden") == true
	# the asteroid shatters and the pieces scatter, like any break (golden ones into more pieces)
	body.break_apart(randi_range(12, 16) if is_golden else randi_range(8, 12))
	_play_note(_combo_pitch(combo))
	_pulse(0.6)
	if is_golden:
		_golden_flourish()
		golden_collected.emit()
	_update_glow()
	progress_changed.emit(total - collected, total)

	if total > 0 and collected >= total:
		_celebrate()


# the more you've collected, the brighter the area glows (progress without a HUD)
func _update_glow() -> void:
	var progress := 0.0 if total == 0 else float(collected) / float(total)
	glow.self_modulate.a = lerpf(0.45, 1.0, progress)


func _combo_pitch(step: int) -> float:
	var semis: int = COMBO_SEMITONES[mini(step - 1, COMBO_SEMITONES.size() - 1)]
	return pow(2.0, semis / 12.0)


# one-shot player per note so quick successive chimes overlap and ring out
func _play_note(pitch: float) -> void:
	var note := AudioStreamPlayer2D.new()
	note.stream = collect_sound.stream
	note.volume_db = collect_sound.volume_db
	note.bus = collect_sound.bus
	note.pitch_scale = pitch
	note.finished.connect(note.queue_free)
	add_child(note)
	note.play()


func _pulse(strength: float) -> void:
	_spawn_ring(60.0, 3.2 + strength, 0.7, 0.55 + 0.3 * strength)

	if flash_tween:
		flash_tween.kill()
	glow.modulate = Color.WHITE * (1.0 + 1.4 * strength)
	flash_tween = create_tween()
	flash_tween.tween_property(glow, "modulate", Color.WHITE, 0.4)

	if pop_tween:
		pop_tween.kill()
	rings.scale = Vector2.ONE * (1.0 + 0.1 * strength)
	pop_tween = create_tween()
	pop_tween.tween_property(rings, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# all asteroids collected: a rising chord and a cascade of rings
func _celebrate() -> void:
	var chord := [1.0, 1.26, 1.5]
	for i in chord.size():
		get_tree().create_timer(0.12 * i).timeout.connect(func():
			_play_note(chord[i])
			_spawn_ring(60.0, 4.5 + i, 0.9, 0.8)
			_pulse(1.0))
	get_tree().create_timer(0.5).timeout.connect(func(): _play_note(2.0))


# a sparkling extra chime and a gold ring on top of the normal collect effects
func _golden_flourish() -> void:
	for i in 3:
		get_tree().create_timer(0.07 * (i + 1), true).timeout.connect(func(): _play_note(2.0 * [1.0, 1.26, 1.5][i]))
	_spawn_ring(60.0, 5.0, 0.8, 0.95, Color(1.0, 0.85, 0.3))
	_pulse(1.0)


func _spawn_ring(start_radius: float, scale_to: float, duration: float, alpha: float, color := Color(0.95, 0.57, 1.0)) -> void:
	var ring := Node2D.new()
	ring.set_script(PULSE_RING)
	ring.radius = start_radius
	ring.line_width = 7.0
	ring.color = Color(color, alpha)
	ring.end_scale = scale_to
	ring.duration = duration
	ring.z_index = 5
	add_child(ring)
