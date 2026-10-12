extends Control

# Title screen: animated space backdrop, title, and PLAY / SETTINGS / QUIT.

const GAME_SCENE := "res://scenes/game.tscn"
const PULSE_RING := preload("res://scripts/pulse_ring.gd")
const ASTEROID_TEXTURE := preload("res://assets/textures/asteroid_grey.png")
const MENU_MUSIC := preload("res://assets/audio/main-menu-bg-music.mp3")

@export var drifter_count := 12

@onready var world: Node2D = %World
@onready var drifters: Node2D = %Drifters
@onready var ufo: Sprite2D = %Ufo
@onready var title_top: Label = %TitleTop
@onready var title_bottom: Label = %TitleBottom
@onready var tagline: Label = %Tagline
@onready var buttons: VBoxContainer = %Buttons
@onready var play_button: Button = %Play
@onready var settings_button: Button = %Settings
@onready var quit_button: Button = %Quit
@onready var fade: ColorRect = %Fade
@onready var settings_menu: CanvasLayer = $SettingsMenu
@onready var setup: Control = $PlayerSetup
@onready var margin: MarginContainer = $Margin
@onready var menu_hint: Label = $Hint

var time := 0.0
var ufo_base := Vector2.ZERO
var ring_timer := 0.0
var starting := false
var drift_data: Array[Dictionary] = []


func _ready() -> void:
	UiSound.wire(self)
	ufo_base = ufo.position
	quit_button.visible = not OS.has_feature("web")

	play_button.pressed.connect(_open_setup)
	setup.start_requested.connect(_start_game)
	setup.back_requested.connect(_close_setup)
	settings_button.pressed.connect(_open_settings)
	quit_button.pressed.connect(func(): get_tree().quit())
	settings_menu.closed.connect(_on_settings_closed)
	resized.connect(_center_world)
	InputHints.changed.connect(_update_hint)
	_update_hint()

	_center_world()
	_spawn_drifters()
	_play_intro()
	play_button.grab_focus()
	# fades in; if it is already playing (e.g. coming back from settings) it carries on
	Music.play(MENU_MUSIC, 1.5)


func _process(delta: float) -> void:
	time += delta

	# the saucer hovers and sways
	ufo.position = ufo_base + Vector2(sin(time * 0.7) * 14.0, sin(time * 1.6) * 12.0)
	ufo.rotation = sin(time * 1.1) * 0.06

	# energy pulses beneath it, like the ones it leaves in the game
	ring_timer -= delta
	if ring_timer <= 0.0:
		ring_timer = 0.55
		_spawn_ring(ufo.position + Vector2(0, 70))

	_move_drifters(delta)


func _center_world() -> void:
	world.position = size / 2.0


func _spawn_ring(pos: Vector2) -> void:
	var ring := Node2D.new()
	ring.set_script(PULSE_RING)
	ring.radius = 26.0
	ring.line_width = 3.0
	ring.end_scale = 3.5
	ring.duration = 0.9
	world.add_child(ring)
	ring.position = pos
	# draw it just behind the saucer
	world.move_child(ring, ufo.get_index())


# --- drifting asteroids in the background ---

func _spawn_drifters() -> void:
	for i in drifter_count:
		var sprite := Sprite2D.new()
		sprite.texture = ASTEROID_TEXTURE
		var s := randf_range(0.5, 1.4)
		sprite.scale = Vector2.ONE * s
		sprite.modulate = Color(1, 1, 1, randf_range(0.35, 0.7))
		sprite.position = Vector2(randf_range(-900, 900), randf_range(-520, 520))
		sprite.rotation = randf() * TAU
		drifters.add_child(sprite)
		drift_data.append({
			"velocity": Vector2.from_angle(randf() * TAU) * randf_range(8.0, 28.0),
			"spin": randf_range(-0.5, 0.5),
		})


func _move_drifters(delta: float) -> void:
	var half := size / 2.0 + Vector2(120, 120)
	for i in drifters.get_child_count():
		var sprite: Sprite2D = drifters.get_child(i)
		var d := drift_data[i]
		sprite.position += d.velocity * delta
		sprite.rotation += d.spin * delta
		# wrap around so the field never empties
		if sprite.position.x > half.x:
			sprite.position.x = -half.x
		elif sprite.position.x < -half.x:
			sprite.position.x = half.x
		if sprite.position.y > half.y:
			sprite.position.y = -half.y
		elif sprite.position.y < -half.y:
			sprite.position.y = half.y


# --- intro animation ---

func _play_intro() -> void:
	var items: Array[Control] = [title_top, title_bottom, tagline]
	for item in items:
		item.modulate.a = 0.0
	buttons.modulate.a = 0.0

	# arriving through a scene transition already reveals the screen, so only fade in on a cold start
	if Transition.busy:
		fade.color.a = 0.0
	else:
		create_tween().tween_property(fade, "color:a", 0.0, 0.6)
	# let the layout settle first so pivots are right
	await get_tree().process_frame
	var tween := create_tween().set_parallel(true)
	for i in items.size():
		var item := items[i]
		item.pivot_offset = Vector2(0, item.size.y / 2.0)
		item.scale = Vector2(1.12, 1.12)
		var delay := 0.25 + 0.18 * i
		tween.tween_property(item, "modulate:a", 1.0, 0.45).set_delay(delay)
		tween.tween_property(item, "scale", Vector2.ONE, 0.6).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(buttons, "modulate:a", 1.0, 0.5).set_delay(0.85)


# --- buttons ---

func _start_game(players: int) -> void:
	if starting:
		return
	starting = true
	Session.player_count = players
	# the music fades out as the iris closes on the PLAY button, then the level opens
	Music.stop(0.5)
	# the iris closes on the setup screen's START button
	Transition.change_scene(GAME_SCENE, setup.start_center())


func _open_setup() -> void:
	margin.visible = false
	menu_hint.visible = false
	setup.open()


func _close_setup() -> void:
	setup.visible = false
	margin.visible = true
	menu_hint.visible = true
	play_button.grab_focus()


func _open_settings() -> void:
	margin.visible = false
	settings_menu.open()


func _on_settings_closed() -> void:
	margin.visible = true
	settings_button.grab_focus()


func _update_hint() -> void:
	menu_hint.text = "%s to choose   |   %s to select" % [_sentence(InputHints.navigate_hint()), _sentence(InputHints.confirm_hint())]


# "ARROW KEYS" -> "Arrow keys", "D-PAD" -> "D-pad"
func _sentence(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1).to_lower()
