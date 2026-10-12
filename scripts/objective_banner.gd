extends CanvasLayer

# Objective card shown at the bottom of the screen at the start of a level. It slides up, stays until the player has had time to read it
# and has started moving (or a maximum time passes), then slides away. Replaces the old in-world text.

# stay at least this long, and until the player has thrust for MIN_MOVE_TIME seconds
const MIN_SHOW_TIME := 3.0
const MIN_MOVE_TIME := 1.0
const MAX_SHOW_TIME := 10.0

@onready var panel: PanelContainer = %Panel
@onready var controls: HBoxContainer = $Root/Panel/VBox/Controls
@onready var controls2: HBoxContainer = $Root/Panel/VBox/Controls2
@onready var coop_controls: VBoxContainer = %CoopControls

var elapsed := 0.0
var move_time := 0.0
var dismissing := false
var final_y := 0.0


func _ready() -> void:
	# a two-player game shows both players' controls instead
	if Session.player_count > 1:
		controls.visible = false
		controls2.visible = false
		coop_controls.visible = true
		coop_controls.get_node("P1").add_theme_color_override("font_color", Session.accent_of(1))
		coop_controls.get_node("P2").add_theme_color_override("font_color", Session.accent_of(2))

	InputHints.changed.connect(_refresh_hints)
	_refresh_hints()

	# wait a frame so the panel has its real size, then slide in
	await get_tree().process_frame
	final_y = panel.position.y
	panel.position.y = final_y + 40.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.4).set_delay(0.5)
	tween.tween_property(panel, "position:y", final_y, 0.6).set_delay(0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var manager := get_tree().get_first_node_in_group("level_manager")
	if manager:
		manager.ended.connect(func(_won: bool): _dismiss())


func _process(delta: float) -> void:
	if dismissing:
		return
	elapsed += delta
	for player in get_tree().get_nodes_in_group("player"):
		if player.is_thrusting:
			move_time += delta
			break
	if (elapsed >= MIN_SHOW_TIME and move_time >= MIN_MOVE_TIME) or elapsed >= MAX_SHOW_TIME:
		_dismiss()


func _dismiss() -> void:
	if dismissing:
		return
	dismissing = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_property(panel, "position:y", final_y + 30.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


# word the controls for the device each player is using
func _refresh_hints() -> void:
	if Session.player_count > 1:
		for player in [1, 2]:
			coop_controls.get_node("P%d" % player).text = "P%d   %s to move   |   %s to pulse" % [player, InputHints.move_hint(player), InputHints.pulse_hint(player)]
		# a reminder only makes sense when no controller is plugged in
		var tip := coop_controls.get_node("Hint")
		tip.visible = Input.get_connected_joypads().is_empty()
		return

	var pad := InputHints.is_pad()
	# move row: keyboard shows WASD or ARROWS, a controller shows the stick
	for node_name in ["Cap1", "Or1", "Cap2"]:
		controls.get_node(node_name).visible = not pad
	controls.get_node("Or2").visible = false
	controls.get_node("Cap3").visible = pad
	# pulse row: SPACE on the keyboard, the bottom button on a controller
	controls2.get_node("CapSpace").visible = not pad
	controls2.get_node("OrP").visible = false
	controls2.get_node("CapA").visible = pad
	controls2.get_node("CapA/Label").text = "%s BUTTON" % InputHints.south() if InputHints.south().length() == 1 else InputHints.south()
