extends Node

# Runs the level clock and decides win or lose.
#   ended     - fires the moment the level is decided (stop the player, stop urgency effects)
#   finished  - fires a moment later, once the finale has played, to show the end screen

signal time_changed(seconds_left: float)
signal ended(won: bool)
# seconds were added to the clock (a golden asteroid)
signal time_bonus(seconds: float)
# the clock was frozen or thawed (a TIME FREEZE power)
signal time_frozen(frozen: bool)
signal finished(won: bool, stats: Dictionary)

# base time and time per asteroid are trimmed because golden asteroids give time back
@export var base_time := 25.0
@export var seconds_per_asteroid := 4.0
# bonus seconds for each golden asteroid collected
@export var golden_bonus := 6.0
# two ships collect faster, so a co-op level gets this share of the single-player time
@export var coop_time_scale := 0.8
# for testing: anything above 0 replaces the calculated time limit (e.g. 8 to test the ending quickly)
@export var debug_time_limit := 0.0
@export var win_screen_delay := 1.6
@export var lose_screen_delay := 1.0

var time_limit := 0.0
var freeze_left := 0.0
var time_left := 0.0
var running := false
var done := false
var total := 0
var remaining := 0


# in-game music. It ends at 122.46 s (the file has silence after that), and the loop crossfades the end into the start.
const GAME_MUSIC := preload("res://assets/audio/bg-2.mp3")
const GAME_MUSIC_END := 122.46
const GAME_MUSIC_CROSSFADE := 2.5
const GAME_MUSIC_DB := -12.0


func _ready() -> void:
	Music.play(GAME_MUSIC, 2.0, GAME_MUSIC_DB, GAME_MUSIC_END, GAME_MUSIC_CROSSFADE)
	var area := get_tree().get_first_node_in_group("collection_area")
	if area == null:
		return
	area.progress_changed.connect(_on_progress)
	area.golden_collected.connect(func(): add_time(golden_bonus))
	if area.total > 0:
		_on_progress(area.total - area.collected, area.total)


# Debug shortcuts (only in debug builds, so they are not in an exported game):
#   F9  - jump the clock to 10 seconds left, to test the last-seconds build-up and the lose screen
#   F10 - collect every asteroid at once, to test the win screen
func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not event is InputEventKey or not event.pressed or event.echo or done:
		return
	if event.keycode == KEY_F9 and running:
		time_left = minf(time_left, 10.0)
		time_changed.emit(time_left)
	elif event.keycode == KEY_F8:
		# drop a random power orb near the ships, to try them out
		var spawner := get_tree().get_first_node_in_group("power_spawner")
		if spawner:
			spawner.spawn(true)
	elif event.keycode == KEY_F10 and running:
		var area := get_tree().get_first_node_in_group("collection_area")
		for asteroid in get_tree().get_nodes_in_group("asteroids"):
			if not asteroid.is_queued_for_deletion():
				area._on_body_entered(asteroid)


func _process(delta: float) -> void:
	# hold the clock until the scene transition has finished revealing the level
	if not running or Transition.busy:
		return
	# a frozen clock holds still
	if freeze_left > 0.0:
		freeze_left -= delta
		if freeze_left <= 0.0:
			freeze_left = 0.0
			time_frozen.emit(false)
		return
	time_left = maxf(time_left - delta, 0.0)
	time_changed.emit(time_left)
	if time_left <= 0.0:
		_finish(false)


# who pushed how many asteroids in, copied from the collection area
func scores_now() -> Dictionary:
	var area := get_tree().get_first_node_in_group("collection_area")
	return area.scores.duplicate() if area and "scores" in area else {}


func freeze_time(seconds: float) -> void:
	if not running:
		return
	var was_frozen := freeze_left > 0.0
	freeze_left = maxf(freeze_left, seconds)
	if not was_frozen:
		time_frozen.emit(true)


func add_time(seconds: float) -> void:
	if not running:
		return
	time_left += seconds
	# the limit grows too, so "time used" on the win screen stays correct
	time_limit += seconds
	time_changed.emit(time_left)
	time_bonus.emit(seconds)


func _on_progress(new_remaining: int, new_total: int) -> void:
	if done:
		return
	total = new_total
	remaining = new_remaining

	# the first report tells us how many asteroids spawned, which sets the time limit
	if not running and time_limit == 0.0 and total > 0:
		var calculated := base_time + seconds_per_asteroid * total
		if Session.player_count > 1:
			calculated *= coop_time_scale
		time_limit = debug_time_limit if debug_time_limit > 0.0 else calculated
		time_left = time_limit
		running = true
		time_changed.emit(time_left)

	if running and remaining <= 0:
		_finish(true)


func _finish(won: bool) -> void:
	running = false
	done = true
	if freeze_left > 0.0:
		freeze_left = 0.0
		time_frozen.emit(false)

	for player in get_tree().get_nodes_in_group("player"):
		player.controls_enabled = false
	if not won:
		# no collecting after time is up
		var area := get_tree().get_first_node_in_group("collection_area")
		if area:
			area.set_deferred("monitoring", false)

	var stats := {
		"time_limit": time_limit,
		"time_left": time_left,
		"time_used": time_limit - time_left,
		"collected": total - remaining,
		"total": total,
		"scores": scores_now(),
	}
	# time up: the music fades out before the game over sound; a win just lets it sit lower under the finale
	if won:
		Music.set_intensity(0.0, 0.8)
		Music.duck(-8.0, 0.8)
	else:
		Music.stop(0.8)
	ended.emit(won)
	await get_tree().create_timer(win_screen_delay if won else lose_screen_delay).timeout
	finished.emit(won, stats)


static func format_time(seconds: float) -> String:
	var whole := ceili(seconds)
	return "%d:%02d" % [floori(whole / 60.0), whole % 60]
