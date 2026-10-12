extends CanvasLayer

# Pause menu. This node's process mode is "Always" so it keeps running while the tree is paused.
# Pause with the "pause" action (Esc, P or Start); the game also pauses if the window loses focus.

@onready var dim: ColorRect = %Dim
@onready var panel: PanelContainer = %Panel
@onready var resume_button: Button = %Resume
@onready var restart_button: Button = %Restart
@onready var settings_button: Button = %Settings
@onready var main_menu_button: Button = %MainMenu
@onready var quit_button: Button = %Quit
@onready var settings_menu: CanvasLayer = $SettingsMenu
@onready var hint: Label = $Center/Panel/VBox/Hint

var show_tween: Tween


func _ready() -> void:
	visible = false
	# confirm sound on every button and dropdown choice, including the settings screen inside this menu
	UiSound.wire(self)
	InputHints.changed.connect(_update_hint)
	_update_hint()
	resume_button.pressed.connect(_resume)
	restart_button.pressed.connect(_restart)
	settings_button.pressed.connect(_open_settings)
	main_menu_button.pressed.connect(_main_menu)
	settings_menu.closed.connect(_on_settings_closed)
	quit_button.pressed.connect(func(): get_tree().quit())


func _unhandled_input(event: InputEvent) -> void:
	# the settings screen handles its own input while it is open
	if settings_menu.visible:
		return
	if event.is_action_pressed("pause"):
		if get_tree().paused:
			_resume()
		elif _can_pause():
			_pause()
		get_viewport().set_input_as_handled()
	elif get_tree().paused and event.is_action_pressed("ui_cancel"):
		# B on a controller also closes the menu
		_resume()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not get_tree().paused and _can_pause():
		_pause()


# no pausing once the level has been won or lost; the end screen takes over
func _can_pause() -> bool:
	var manager := get_tree().get_first_node_in_group("level_manager")
	return manager == null or not manager.done


func _pause() -> void:
	get_tree().paused = true
	Music.duck(-9.0, 0.3)
	visible = true
	dim.modulate.a = 0.0
	panel.modulate.a = 0.0
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2(0.9, 0.9)
	if show_tween:
		show_tween.kill()
	show_tween = create_tween().set_parallel(true)
	show_tween.tween_property(dim, "modulate:a", 1.0, 0.2)
	show_tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	show_tween.tween_property(panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	resume_button.grab_focus()


func _resume() -> void:
	get_tree().paused = false
	Music.duck(0.0, 0.3)
	visible = false


func _restart() -> void:
	# the transition unpauses once the screen is covered
	Transition.reload_scene()


func _open_settings() -> void:
	panel.visible = false
	settings_menu.open()


func _on_settings_closed() -> void:
	panel.visible = true
	settings_button.grab_focus()


func _main_menu() -> void:
	Music.stop(0.5)
	Transition.change_scene("res://scenes/main_menu.tscn")


func _update_hint() -> void:
	hint.text = "%s to resume" % InputHints.pause_hint()
