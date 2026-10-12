extends CanvasLayer

# Shows how many asteroids are left to collect. Driven by the collection area's progress_changed signal.

const LevelManager := preload("res://scripts/level_manager.gd")
const Powers := preload("res://scripts/powers.gd")

const MINT := Color(0.5, 1.0, 0.8)
const PURPLE := Color(0.85, 0.45, 1.0)
const RED := Color(1.0, 0.4, 0.5)
const GOLD := Color(1.0, 0.82, 0.3)
const ICE := Color(0.7, 0.95, 1.0)

# the timer turns red, ticks and pulses for this many final seconds
const URGENT_SECONDS := 10

@onready var panel: PanelContainer = %Panel
@onready var count_label: Label = %Count
@onready var caption: Label = %Caption
@onready var bar: ProgressBar = %Bar
@onready var timer_label: Label = %Timer
@onready var urgency: TextureRect = %Urgency
@onready var tick: AudioStreamPlayer = %Tick
@onready var root_control: Control = $Root
@onready var pulse_meter: PanelContainer = %PulseMeter
@onready var pulse_bar: ProgressBar = %PulseBar
@onready var pulse_meter2: PanelContainer = %PulseMeter2
@onready var pulse_bar2: ProgressBar = %PulseBar2
@onready var power_badge: PanelContainer = %PowerBadge
@onready var power_bar: ProgressBar = %PowerBar
@onready var power_badge2: PanelContainer = %PowerBadge2
@onready var power_bar2: ProgressBar = %PowerBar2
@onready var frost: TextureRect = %Frost

var pop_tween: Tween
var bar_tween: Tween
var timer_tween: Tween
var urgency_tween: Tween
var last_remaining := -1
var last_second := -1
var urgent_on := false
var player: Node
var pulse_was_ready := true
var pulse_ready := {}
var badge_power := {}
var frost_tween: Tween


func _ready() -> void:
	tick.bus = "SFX"
	_style_pulse_meter(pulse_meter, pulse_bar, Session.accent_of(1))
	if Session.player_count > 1:
		pulse_meter2.visible = true
		pulse_meter.get_node("Row/Name").text = "P1 PULSE"
		pulse_meter2.get_node("Row/Name").text = "P2 PULSE"
		_style_pulse_meter(pulse_meter2, pulse_bar2, Session.accent_of(2))
	count_label.text = ""
	caption.text = ""
	timer_label.text = ""

	var manager := get_tree().get_first_node_in_group("level_manager")
	if manager:
		manager.time_changed.connect(_on_time_changed)
		manager.ended.connect(_on_ended)
		manager.time_bonus.connect(_on_time_bonus)
		manager.time_frozen.connect(_on_time_frozen)

	var area := get_tree().get_first_node_in_group("collection_area")
	if area == null:
		return
	area.progress_changed.connect(_on_progress)
	if area.total > 0:
		_on_progress(area.total - area.collected, area.total)


func _process(_delta: float) -> void:
	# each ship's pulse meter follows its own recharge
	for node in get_tree().get_nodes_in_group("player"):
		var index: int = node.player_index
		var meter := pulse_meter2 if index == 2 else pulse_meter
		var bar := pulse_bar2 if index == 2 else pulse_bar
		bar.value = node.pulse_charge * 100.0
		var ready: bool = node.pulse_charge >= 1.0
		if ready and not pulse_ready.get(index, true):
			meter.pivot_offset = meter.size / 2.0
			meter.scale = Vector2.ONE * 1.12
			create_tween().tween_property(meter, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		pulse_ready[index] = ready
		meter.modulate.a = 1.0 if ready else 0.7
		_update_power_badge(index, node)


# colour a pulse meter's label and bar to match its player's ship
func _style_pulse_meter(meter: Control, bar: ProgressBar, color: Color) -> void:
	meter.get_node("Row/Name").add_theme_color_override("font_color", color)
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill").duplicate()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)


func _on_time_changed(seconds_left: float) -> void:
	var whole := ceili(seconds_left)
	timer_label.text = LevelManager.format_time(seconds_left)
	# bonus time can lift the clock back out of the last seconds
	if seconds_left > URGENT_SECONDS and urgent_on:
		_clear_urgency()
	if whole == last_second:
		return
	last_second = whole
	if whole <= URGENT_SECONDS and whole > 0:
		urgent_on = true
		_urgent_beat(whole)


func _clear_urgency() -> void:
	urgent_on = false
	timer_label.remove_theme_color_override("font_color")
	if urgency_tween:
		urgency_tween.kill()
	urgency_tween = create_tween()
	urgency_tween.tween_property(urgency, "modulate:a", 0.0, 0.4)
	Music.set_intensity(0.0, 1.0)


# a golden asteroid added time: a gold "+6s" floats up from the clock and the clock flashes gold
func _on_time_bonus(seconds: float) -> void:
	var popup := Label.new()
	popup.text = "+%ds" % int(seconds)
	popup.add_theme_font_override("font", timer_label.get_theme_font("font"))
	popup.add_theme_font_size_override("font_size", 40)
	popup.add_theme_color_override("font_color", GOLD)
	popup.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.0, 0.9))
	popup.add_theme_constant_override("outline_size", 8)
	root_control.add_child(popup)
	popup.global_position = timer_label.global_position + Vector2(timer_label.size.x * 0.5 - 32.0, timer_label.size.y - 6.0)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y + 56.0, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 0.5).set_delay(0.7)
	tween.chain().tween_callback(popup.queue_free)

	if timer_tween:
		timer_tween.kill()
	timer_label.pivot_offset = timer_label.size / 2.0
	timer_label.scale = Vector2.ONE * 1.35
	timer_label.add_theme_color_override("font_color", GOLD)
	timer_tween = create_tween()
	timer_tween.tween_property(timer_label, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# back to the normal colour after the flash, unless the clock is still in its last seconds
	timer_tween.tween_callback(func():
		if not urgent_on:
			timer_label.remove_theme_color_override("font_color")
		else:
			timer_label.add_theme_color_override("font_color", RED))


# once a second in the last seconds: tick, red flash, number pop, edge vignette pulse
func _urgent_beat(whole: int) -> void:
	var closeness := 1.0 - float(whole) / URGENT_SECONDS # 0 at 10s, near 1 at 1s
	tick.pitch_scale = 1.0 + 0.5 * closeness
	tick.play()
	# the music builds with the clock and dips on each tick so the tick cuts through
	Music.set_intensity(closeness, 1.0)
	Music.pulse(-4.0 - 2.0 * closeness)

	timer_label.add_theme_color_override("font_color", RED)
	timer_label.pivot_offset = timer_label.size / 2.0
	timer_label.scale = Vector2.ONE * 1.3
	if timer_tween:
		timer_tween.kill()
	timer_tween = create_tween()
	timer_tween.tween_property(timer_label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	var base := lerpf(0.12, 0.45, closeness)
	urgency.modulate.a = base + 0.2
	if urgency_tween:
		urgency_tween.kill()
	urgency_tween = create_tween()
	urgency_tween.tween_property(urgency, "modulate:a", base, 0.7)


func _on_ended(won: bool) -> void:
	if timer_tween:
		timer_tween.kill()
	if urgency_tween:
		urgency_tween.kill()
	timer_label.scale = Vector2.ONE
	timer_label.add_theme_color_override("font_color", MINT if won else RED)
	urgency_tween = create_tween()
	urgency_tween.tween_property(urgency, "modulate:a", 0.0 if won else 0.45, 0.5)


func _on_progress(remaining: int, total: int) -> void:
	var first_update := last_remaining < 0
	var changed := remaining != last_remaining
	last_remaining = remaining

	count_label.text = str(remaining)
	caption.text = "LEFT" if remaining > 0 else "ALL COLLECTED!"

	bar.max_value = maxi(total, 1)
	if bar_tween:
		bar_tween.kill()
	if first_update:
		bar.value = total - remaining
	else:
		bar_tween = create_tween()
		bar_tween.tween_property(bar, "value", total - remaining, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if changed and not first_update:
		_pop(remaining == 0)


# the number kicks up in size and flashes purple, then settles
func _pop(finished: bool) -> void:
	if pop_tween:
		pop_tween.kill()
	count_label.pivot_offset = count_label.size / 2.0
	count_label.scale = Vector2.ONE * (1.7 if finished else 1.4)
	count_label.modulate = PURPLE
	pop_tween = create_tween().set_parallel(true)
	pop_tween.tween_property(count_label, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	pop_tween.tween_property(count_label, "modulate", MINT if finished else Color.WHITE, 0.4)

	if finished:
		caption.add_theme_color_override("font_color", MINT)


# the badge above a ship's pulse meter shows its power and how long is left
func _update_power_badge(index: int, ship: Node) -> void:
	var badge := power_badge2 if index == 2 else power_badge
	var bar := power_bar2 if index == 2 else power_bar
	if ship.power < 0:
		badge.visible = false
		badge_power[index] = -2
		return
	var color := Powers.power_color(ship.power)
	badge.visible = true
	bar.value = ship.power_time_left / ship.power_duration * 100.0
	if badge_power.get(index, -2) != ship.power:
		badge_power[index] = ship.power
		var label: Label = badge.get_node("Row/Name")
		label.text = Powers.power_name(ship.power)
		label.add_theme_color_override("font_color", color)
		var fill: StyleBoxFlat = bar.get_theme_stylebox("fill").duplicate()
		fill.bg_color = color
		bar.add_theme_stylebox_override("fill", fill)


# TIME FREEZE: frost creeps in from the screen edges, the clock turns icy and the music dips
func _on_time_frozen(frozen: bool) -> void:
	if frost_tween:
		frost_tween.kill()
	frost_tween = create_tween()
	if frozen:
		frost_tween.tween_property(frost, "modulate:a", 1.0, 0.4)
		timer_label.add_theme_color_override("font_color", ICE)
		Music.duck(-7.0, 0.3)
	else:
		frost_tween.tween_property(frost, "modulate:a", 0.0, 0.7)
		if urgent_on:
			timer_label.add_theme_color_override("font_color", RED)
		else:
			timer_label.remove_theme_color_override("font_color")
		Music.duck(0.0, 0.5)
