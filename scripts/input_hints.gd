extends Node

# Autoload ("InputHints"): knows whether each player is using the keyboard or a controller, and words the
# on-screen instructions to match. Screens listen to `changed` and rebuild their hint text.
#
#   InputHints.kind_for(0)    the most recently used device (menus and single player)
#   InputHints.kind_for(1/2)  that co-op player's own device (their keys, or their controller)
#   InputHints.pulse_hint(p), move_hint(p), confirm_hint(), back_hint(), pause_hint(), navigate_hint(), join_hint()
#
# Controller buttons are named for the kind of controller (A / CROSS / B), using the name it reports.

signal changed

enum Kind { KEYBOARD, GAMEPAD }

var last := Kind.KEYBOARD
var last_pad := -1
var player_kind := {1: Kind.KEYBOARD, 2: Kind.KEYBOARD}
# a player only gets their own device once they have actually used it; until then the controller assignment decides
var player_touched := {1: false, 2: false}

const P1_KEYS := [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SPACE]
const P2_KEYS := [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_ENTER, KEY_KP_ENTER]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# the window sees every event before any node does, even ones a menu later marks as handled
	get_window().window_input.connect(_on_window_input)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		last_pad = pads[0]


func _on_window_input(event: InputEvent) -> void:
	var new_kind := -1
	var player := 0
	if event is InputEventKey and event.pressed:
		new_kind = Kind.KEYBOARD
		var code: int = event.physical_keycode
		if code in P1_KEYS:
			player = 1
		elif code in P2_KEYS:
			player = 2
	elif event is InputEventMouseButton and event.pressed:
		new_kind = Kind.KEYBOARD
	elif event is InputEventJoypadButton and event.pressed:
		new_kind = Kind.GAMEPAD
		last_pad = event.device
		player = _player_for_pad(event.device)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		new_kind = Kind.GAMEPAD
		last_pad = event.device
		player = _player_for_pad(event.device)
	if new_kind < 0:
		return

	var did_change := new_kind != last
	last = new_kind
	if player > 0 and (not player_touched[player] or player_kind[player] != new_kind):
		player_touched[player] = true
		player_kind[player] = new_kind
		did_change = true
	if did_change:
		changed.emit()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		last_pad = device
	elif device == last_pad:
		var pads := Input.get_connected_joypads()
		last_pad = pads[0] if not pads.is_empty() else -1
		if pads.is_empty():
			last = Kind.KEYBOARD
	changed.emit()


# a new co-op game starts: forget what players used before, so the controller assignment decides again
func reset_players() -> void:
	player_touched = {1: false, 2: false}
	changed.emit()


# same assignment rules as Session.setup_coop_inputs
func _player_for_pad(device: int) -> int:
	var pads := Input.get_connected_joypads()
	if pads.size() >= 2:
		if device == pads[0]:
			return 1
		return 2 if device == pads[1] else 0
	return 2 if pads.size() == 1 else 0


func kind_for(player := 0) -> int:
	if player == 0:
		return last
	if player_touched[player]:
		return player_kind[player]
	# nothing pressed yet: a player with a controller assigned is assumed to use it
	var pads := Input.get_connected_joypads().size()
	var has_pad := pads >= 2 if player == 1 else pads >= 1
	return Kind.GAMEPAD if has_pad else Kind.KEYBOARD


func is_pad(player := 0) -> bool:
	return kind_for(player) == Kind.GAMEPAD


# ---------- controller naming ----------

func pad_style() -> String:
	var device := last_pad
	if device < 0:
		var pads := Input.get_connected_joypads()
		if pads.is_empty():
			return "xbox"
		device = pads[0]
	var joy_name := Input.get_joy_name(device).to_lower()
	if "ps" in joy_name or "playstation" in joy_name or "sony" in joy_name or "dualsense" in joy_name or "dualshock" in joy_name:
		return "playstation"
	if "nintendo" in joy_name or "switch" in joy_name or "joy-con" in joy_name:
		return "nintendo"
	return "xbox"


# the bottom face button (accept / pulse)
func south() -> String:
	match pad_style():
		"playstation":
			return "CROSS"
		"nintendo":
			return "B"
	return "A"


# the right face button (back)
func east() -> String:
	match pad_style():
		"playstation":
			return "CIRCLE"
		"nintendo":
			return "A"
	return "B"


func start_name() -> String:
	match pad_style():
		"playstation":
			return "OPTIONS"
		"nintendo":
			return "+"
	return "START"


# ---------- hint words ----------

func move_hint(player := 0) -> String:
	if is_pad(player):
		return "LEFT STICK"
	match player:
		1:
			return "WASD"
		2:
			return "ARROWS"
	return "WASD OR ARROWS"


func pulse_hint(player := 0) -> String:
	if is_pad(player):
		return south()
	return "ENTER" if player == 2 else "SPACE"


func confirm_hint() -> String:
	return south() if is_pad() else "ENTER"


func back_hint() -> String:
	return east() if is_pad() else "ESC"


func pause_hint() -> String:
	return start_name() if is_pad() else "ESC OR P"


func navigate_hint() -> String:
	return "D-PAD" if is_pad() else "ARROW KEYS"


func join_hint() -> String:
	return start_name() if is_pad() else "ENTER"
