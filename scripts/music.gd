extends Node

# Autoload ("Music"): plays one music track at a time, with fades, optional seamless crossfade looping and ducking.
# It lives across scene changes, so a track can fade out while the screen transition covers the old scene.
#
#   Music.play(stream, fade_in, volume_db)                          simple looping track (uses the stream's own loop)
#   Music.play(stream, fade_in, volume_db, loop_end, crossfade)     loops by crossfading the end into the start;
#                                                                    loop_end is where the music actually ends (seconds),
#                                                                    so silence at the end of the file is skipped
#   Music.stop(fade_out)
#   Music.duck(db, time)                                            temporarily turn the music down (0 to restore)
#   Music.set_intensity(0..1, time)                                 build-up: speeds the track up a little and swells it
#   Music.pulse()                                                   a quick dip, so a sound effect (like the timer tick) cuts through
#
# The "Music" audio bus (settings slider) scales everything here.

var players: Array[AudioStreamPlayer] = []
var gains := [0.0, 0.0]        # per-player fade level, 0..1
var gain_tweens: Array = [null, null]
var active := 0                # which player is the current one

var current: AudioStream
var base_db := -9.0
var duck_db := 0.0
var duck_tween: Tween

# build-up: at full intensity the track runs a little faster and a little louder
const MAX_PITCH := 1.07
const INTENSITY_DB := 2.0
var intensity := 0.0
var intensity_tween: Tween
var pulse_db := 0.0
var pulse_tween: Tween

var loop_end := 0.0
var loop_crossfade := 0.0
var crossfading := false
var fading_out := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		players.append(p)


func _process(_delta: float) -> void:
	# volume = track level + duck + this player's fade
	var pitch := lerpf(1.0, MAX_PITCH, intensity)
	for i in 2:
		players[i].pitch_scale = pitch
		players[i].volume_db = base_db + duck_db + pulse_db + intensity * INTENSITY_DB + (linear_to_db(gains[i]) if gains[i] > 0.001 else -80.0)

	# time to start the next pass of a crossfade-looped track?
	if loop_crossfade > 0.0 and not crossfading and not fading_out:
		var p := players[active]
		if p.playing and p.get_playback_position() >= loop_end - loop_crossfade:
			_start_crossfade()


func play(stream: AudioStream, fade_in := 1.5, volume_db := -9.0, loop_end_seconds := 0.0, crossfade_seconds := 0.0) -> void:
	# already playing this track and not on its way out: let it carry on, just un-duck
	if players[active].playing and current == stream and gains[active] > 0.05 and not fading_out:
		duck(0.0, 0.4)
		set_intensity(0.0, 0.6)
		return

	_stop_all_immediately()
	current = stream
	base_db = volume_db
	loop_end = loop_end_seconds
	loop_crossfade = crossfade_seconds
	crossfading = false
	fading_out = false
	duck_db = 0.0
	intensity = 0.0
	pulse_db = 0.0

	if stream is AudioStreamMP3:
		# crossfade-looped tracks loop in code; the rest use the stream's own loop
		stream.loop = crossfade_seconds <= 0.0
	active = 0
	players[0].stream = stream
	players[0].play()
	_fade_gain(0, 1.0, fade_in)


func stop(fade_out := 0.6) -> void:
	if not (players[0].playing or players[1].playing):
		return
	fading_out = true
	for i in 2:
		if players[i].playing:
			_fade_gain(i, 0.0, fade_out)
	get_tree().create_timer(fade_out + 0.05, true).timeout.connect(func():
		# only stop if nothing new has started in the meantime
		if fading_out:
			_stop_all_immediately()
			current = null
			fading_out = false)


func duck(db: float, time := 0.4) -> void:
	if duck_tween:
		duck_tween.kill()
	duck_tween = create_tween()
	duck_tween.tween_property(self, "duck_db", db, time).set_trans(Tween.TRANS_SINE)


func set_intensity(value: float, time := 1.0) -> void:
	if intensity_tween:
		intensity_tween.kill()
	intensity_tween = create_tween()
	intensity_tween.tween_property(self, "intensity", clampf(value, 0.0, 1.0), time).set_trans(Tween.TRANS_SINE)


# a quick dip and recovery, timed with something like the timer tick
func pulse(db := -4.0, time := 0.25) -> void:
	if pulse_tween:
		pulse_tween.kill()
	pulse_db = db
	pulse_tween = create_tween()
	pulse_tween.tween_property(self, "pulse_db", 0.0, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _start_crossfade() -> void:
	crossfading = true
	var old := active
	var next := 1 - active
	players[next].stream = current
	players[next].play()
	gains[next] = 0.0
	_fade_gain(next, 1.0, loop_crossfade)
	_fade_gain(old, 0.0, loop_crossfade)
	active = next
	# the old pass is silent by now; stop it and allow the next crossfade
	get_tree().create_timer(loop_crossfade + 0.1, true).timeout.connect(func():
		if not fading_out:
			players[old].stop()
		crossfading = false)


func _fade_gain(slot: int, target: float, seconds: float) -> void:
	if gain_tweens[slot]:
		gain_tweens[slot].kill()
	var tween := create_tween()
	var from: float = gains[slot]
	tween.tween_method(func(v: float): gains[slot] = v, from, target, maxf(seconds, 0.01)).set_trans(Tween.TRANS_SINE)
	gain_tweens[slot] = tween


func _stop_all_immediately() -> void:
	for i in 2:
		if gain_tweens[i]:
			gain_tweens[i].kill()
		gains[i] = 0.0
		players[i].stop()
