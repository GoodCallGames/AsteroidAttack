extends Node

# Autoload ("Session"): what kind of game is being played, who is playing, and their ship colours.
#
#   Session.player_count = 2 before loading the game scene makes it a local co-op game.
#   Session.player_colors = [color for P1, color for P2] are indexes into Session.COLORS, chosen on the setup screen.
#   Session.setup_coop_inputs() builds the p1_* and p2_* actions for the controllers that are connected:
#     P1: WASD + Space (pulse)       and the first controller, if two are connected
#     P2: Arrow keys + Enter (pulse) and a controller (the only one, or the second of two)
#   One player can always play on the keyboard, so two people can share a keyboard, or one keyboard plus one
#   controller, or two controllers.

var player_count := 1
# index into COLORS for player 1 and player 2; no two players ever share one
var player_colors := [0, 1]

const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "pulse"]

# the ship colours a player can pick. accent is used for their thruster, rings and HUD meter.
const COLORS := [
	{"name": "MINT", "texture": preload("res://assets/textures/green_ship.png"), "accent": Color(0.5, 1.0, 0.75)},
	{"name": "CORAL", "texture": preload("res://assets/textures/coral_ship.png"), "accent": Color(1.0, 0.65, 0.42)},
	{"name": "SKY", "texture": preload("res://assets/textures/sky_ship.png"), "accent": Color(0.45, 0.8, 1.0)},
	{"name": "PINK", "texture": preload("res://assets/textures/pink_ship.png"), "accent": Color(1.0, 0.55, 0.78)},
	{"name": "LIME", "texture": preload("res://assets/textures/lime_ship.png"), "accent": Color(0.75, 1.0, 0.4)},
	{"name": "ORCHID", "texture": preload("res://assets/textures/orchid_ship.png"), "accent": Color(0.8, 0.6, 1.0)},
]


# the colour entry (name, texture, accent) for player 1 or 2
func color_of(player: int) -> Dictionary:
	return COLORS[player_colors[clampi(player, 1, 2) - 1]]


func accent_of(player: int) -> Color:
	return color_of(player).accent


func setup_coop_inputs() -> void:
	var pads := Input.get_connected_joypads()
	var p1_pad := -1
	var p2_pad := -1
	if pads.size() >= 2:
		p1_pad = pads[0]
		p2_pad = pads[1]
	elif pads.size() == 1:
		# one controller: it is player two's, and player one plays on the keyboard
		p2_pad = pads[0]

	_build_player_actions(1, [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SPACE], p1_pad)
	_build_player_actions(2, [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_ENTER], p2_pad)
	InputHints.reset_players()


func _build_player_actions(index: int, keys: Array, pad: int) -> void:
	for i in ACTIONS.size():
		var action := "p%d_%s" % [index, ACTIONS[i]]
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, 0.2)
		InputMap.action_add_event(action, _key(keys[i]))
		# keypad enter also fires P2's pulse
		if index == 2 and ACTIONS[i] == "pulse":
			InputMap.action_add_event(action, _key(KEY_KP_ENTER))

		if pad < 0:
			continue
		match ACTIONS[i]:
			"move_left":
				InputMap.action_add_event(action, _axis(JOY_AXIS_LEFT_X, -1.0, pad))
				InputMap.action_add_event(action, _button(JOY_BUTTON_DPAD_LEFT, pad))
			"move_right":
				InputMap.action_add_event(action, _axis(JOY_AXIS_LEFT_X, 1.0, pad))
				InputMap.action_add_event(action, _button(JOY_BUTTON_DPAD_RIGHT, pad))
			"move_up":
				InputMap.action_add_event(action, _axis(JOY_AXIS_LEFT_Y, -1.0, pad))
				InputMap.action_add_event(action, _button(JOY_BUTTON_DPAD_UP, pad))
			"move_down":
				InputMap.action_add_event(action, _axis(JOY_AXIS_LEFT_Y, 1.0, pad))
				InputMap.action_add_event(action, _button(JOY_BUTTON_DPAD_DOWN, pad))
			"pulse":
				InputMap.action_add_event(action, _button(JOY_BUTTON_A, pad))
				InputMap.action_add_event(action, _button(JOY_BUTTON_X, pad))


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


func _axis(axis: JoyAxis, value: float, device: int) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	event.device = device
	return event


func _button(button: JoyButton, device: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.device = device
	return event
