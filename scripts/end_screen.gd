extends CanvasLayer

# Win / lose panel with a restart button. Shown after the level manager's finished signal.

const LevelManager := preload("res://scripts/level_manager.gd")

const MINT := Color(0.5, 1.0, 0.8)
const PINK := Color(1.0, 0.45, 0.55)

@onready var dim: ColorRect = %Dim
@onready var panel: PanelContainer = %Panel
@onready var title: Label = %Title
@onready var details: Label = %Details
@onready var play_again: Button = %PlayAgain
@onready var main_menu_button: Button = %MainMenu
@onready var lose_sound: AudioStreamPlayer = %LoseSound
@onready var hint: Label = $Center/Panel/VBox/Hint

var can_restart := false


func _ready() -> void:
	visible = false
	lose_sound.bus = "SFX"
	InputHints.changed.connect(_update_hint)
	_update_hint()
	play_again.pressed.connect(_restart)
	main_menu_button.pressed.connect(_main_menu)
	var manager := get_tree().get_first_node_in_group("level_manager")
	if manager == null:
		return
	manager.finished.connect(_on_finished)


func _unhandled_input(event: InputEvent) -> void:
	if not can_restart:
		return
	# "restart" is an input action (R, Enter, or the A button on a controller).
	# Enter and A also activate the focused button, so when another button has focus (like MAIN MENU)
	# they must not trigger the shortcut as well; R still restarts from anywhere.
	if event.is_action_pressed("restart"):
		var focused := get_viewport().gui_get_focus_owner()
		if event.is_action_pressed("ui_accept") and focused is Button and focused != play_again:
			return
		_restart()


func _on_finished(won: bool, stats: Dictionary) -> void:
	if won:
		title.text = "LEVEL COMPLETE!"
		title.add_theme_color_override("font_color", MINT)
		details.text = "Time: %s\nTime left: %s" % [
			LevelManager.format_time(stats.time_used),
			LevelManager.format_time(stats.time_left)]
		details.text += _coop_line(stats)
	else:
		title.text = "TIME'S UP!"
		title.add_theme_color_override("font_color", PINK)
		details.text = "Collected %d of %d" % [stats.collected, stats.total]
		details.text += _coop_line(stats)
		# the game over sound plays as the screen appears
		lose_sound.play()

	visible = true
	dim.modulate.a = 0.0
	panel.modulate.a = 0.0
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2(0.8, 0.8)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(dim, "modulate:a", 1.0, 0.5)
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	# a short grace period so a key held from play doesn't skip the screen
	await get_tree().create_timer(0.6).timeout
	can_restart = true
	play_again.grab_focus()


# in a two-player game, who pushed how many in
func _coop_line(stats: Dictionary) -> String:
	if Session.player_count < 2 or not stats.has("scores"):
		return ""
	var scores: Dictionary = stats.scores
	return "\n\nP1  %d    |    P2  %d" % [scores.get(1, 0), scores.get(2, 0)]


func _restart() -> void:
	if not can_restart:
		return
	can_restart = false
	# played here (not on the button) so Enter, R and A make the sound too
	UiSound.confirm()
	Transition.reload_scene()


func _main_menu() -> void:
	if not can_restart:
		return
	can_restart = false
	UiSound.confirm()
	Music.stop(0.5)
	Transition.change_scene("res://scenes/main_menu.tscn")


func _update_hint() -> void:
	hint.text = ("or press %s" % InputHints.south()) if InputHints.is_pad() else "or press ENTER or R"
