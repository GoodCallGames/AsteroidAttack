extends Control

# Player setup screen, shown over the main menu after PLAY.
#   Player 1 is always in. Player 2 joins with Enter (or Start on a controller).
#   Each player browses ship colours with left / right, freely: what one player is looking at never shows on the other's
#   panel. A colour only becomes unavailable once its player LOCKS IN (presses ready). If the other player was previewing
#   that same colour they are moved on to the next free one, and a ready that comes too late is refused.
#   Two ships can therefore never end up the same colour.
#   When everyone who joined is ready (Space / Enter / A), the game starts.
#   Pressing down moves a selection onto the BACK and START buttons, so they work from a controller too
#   (left / right to choose, the confirm button to press, up or B to go back to the colours). START starts straight away.
#
# It reads the keyboard and controllers directly, so two players can use it at once.

signal start_requested(player_count: int)
signal back_requested

const START_DELAY := 0.8

@onready var slots: Array[Node] = [%Slot1, %Slot2]
@onready var back_button: Button = %Back
@onready var start_button: Button = %Start
@onready var hint: Label = %Hint
@onready var tick: AudioStreamPlayer = %Tick

var joined := [true, false]
var colors := [0, 1]
var ready_state := [false, false]
var start_in := -1.0
var stick_direction := {} # per controller, so one push of the stick changes the colour once
var starting := false
# a short message shown in a player's status line ("P1 TOOK IT"), and how long it still has to show
var notices := ["", ""]
var notice_time := [0.0, 0.0]
# when each player was last moved off a colour they were on (by the other player locking in)
var last_bump_ms := [-10000, -10000]
# a ready press this soon after being moved was aimed at the old colour, so it is ignored
const BUMP_GRACE_MS := 450
# the selection can sit on the BACK / START buttons instead of the player panels
var in_buttons := false
var button_index := 1 # 0 = BACK, 1 = START
var normal_styles := {}


func _ready() -> void:
	tick.bus = "SFX"
	InputHints.changed.connect(_on_hints_changed)
	slots[0].setup(1)
	slots[1].setup(2)
	slots[0].swatch_pressed.connect(func(index: int): _pick_color(0, index))
	slots[1].swatch_pressed.connect(func(index: int): _pick_color(1, index))
	normal_styles[back_button] = back_button.get_theme_stylebox("normal")
	normal_styles[start_button] = start_button.get_theme_stylebox("normal")
	back_button.pressed.connect(func(): back_requested.emit())
	start_button.pressed.connect(_begin)
	Input.joy_connection_changed.connect(func(_device: int, _connected: bool): _refresh())


func open() -> void:
	# start from the colours used last time, making sure they differ
	colors = [Session.player_colors[0], Session.player_colors[1]]
	if colors[0] == colors[1]:
		colors[1] = _first_free_color(colors[0])
	joined = [true, false]
	ready_state = [false, false]
	start_in = -1.0
	starting = false
	stick_direction.clear()
	in_buttons = false
	notices = ["", ""]
	notice_time = [0.0, 0.0]
	_update_buttons()
	hint.text = _hint_text()
	visible = true
	_refresh()


func _process(delta: float) -> void:
	for i in 2:
		if notice_time[i] > 0.0:
			notice_time[i] -= delta
			if notice_time[i] <= 0.0:
				_refresh()
	if start_in < 0.0 or starting:
		return
	start_in -= delta
	hint.text = "STARTING..."
	if start_in <= 0.0:
		_begin()


# ---------- input ----------

func _input(event: InputEvent) -> void:
	if not visible or starting:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _handle_key(event.physical_keycode):
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		if _handle_pad_button(event.device, event.button_index):
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion and (event.axis == JOY_AXIS_LEFT_X or event.axis == JOY_AXIS_LEFT_Y):
		_handle_stick(event.device, event.axis, event.axis_value)


func _handle_key(code: Key) -> bool:
	# before player 2 joins, the arrow keys drive player 1 as well
	var arrows := 1 if joined[1] else 0
	match code:
		KEY_ESCAPE:
			back_requested.emit()
		KEY_A:
			_navigate(0, Vector2i.LEFT)
		KEY_D:
			_navigate(0, Vector2i.RIGHT)
		KEY_W:
			_navigate(0, Vector2i.UP)
		KEY_S:
			_navigate(0, Vector2i.DOWN)
		KEY_LEFT:
			_navigate(arrows, Vector2i.LEFT)
		KEY_RIGHT:
			_navigate(arrows, Vector2i.RIGHT)
		KEY_UP:
			_navigate(arrows, Vector2i.UP)
		KEY_DOWN:
			_navigate(arrows, Vector2i.DOWN)
		KEY_SPACE:
			_confirm(0)
		KEY_ENTER, KEY_KP_ENTER:
			_confirm(1)
		KEY_BACKSPACE:
			_leave()
		_:
			return false
	return true


func _handle_pad_button(device: int, button: int) -> bool:
	var who := _player_for_pad(device)
	if who < 0:
		return false
	match button:
		JOY_BUTTON_DPAD_LEFT:
			_navigate(who, Vector2i.LEFT)
		JOY_BUTTON_DPAD_RIGHT:
			_navigate(who, Vector2i.RIGHT)
		JOY_BUTTON_DPAD_UP:
			_navigate(who, Vector2i.UP)
		JOY_BUTTON_DPAD_DOWN:
			_navigate(who, Vector2i.DOWN)
		JOY_BUTTON_A, JOY_BUTTON_X:
			_confirm(who)
		JOY_BUTTON_START:
			if not joined[1]:
				_join()
		JOY_BUTTON_B:
			if in_buttons:
				_leave_buttons()
			elif who == 1 and joined[1]:
				_leave()
			else:
				back_requested.emit()
		_:
			return false
	return true


func _handle_stick(device: int, axis: int, value: float) -> void:
	var who := _player_for_pad(device)
	if who < 0:
		return
	var key := device * 10 + axis
	var direction := 0 if absf(value) < 0.55 else int(signf(value))
	if direction != stick_direction.get(key, 0):
		stick_direction[key] = direction
		if direction != 0:
			_navigate(who, Vector2i(direction, 0) if axis == JOY_AXIS_LEFT_X else Vector2i(0, direction))


# one step of navigation from a player: on the panels it changes colour or heads for the buttons,
# on the buttons it chooses between them or goes back up
func _navigate(who: int, direction: Vector2i) -> void:
	if in_buttons:
		if direction == Vector2i.LEFT:
			_move_button(-1)
		elif direction == Vector2i.RIGHT:
			_move_button(1)
		elif direction == Vector2i.UP:
			_leave_buttons()
		return
	if direction == Vector2i.LEFT:
		_change_color(who, -1)
	elif direction == Vector2i.RIGHT:
		_change_color(who, 1)
	elif direction == Vector2i.DOWN:
		_enter_buttons()


# the confirm key or button: press the selected button, or join / ready up
func _confirm(who: int) -> void:
	if in_buttons:
		_press_button()
	elif who == 1 and not joined[1]:
		_join()
	else:
		_toggle_ready(who)


# ---------- the BACK / START buttons ----------

func _enter_buttons() -> void:
	in_buttons = true
	button_index = 1
	tick.pitch_scale = 1.2
	tick.play()
	_update_buttons()


func _leave_buttons() -> void:
	in_buttons = false
	tick.pitch_scale = 0.9
	tick.play()
	_update_buttons()


func _move_button(step: int) -> void:
	button_index = wrapi(button_index + step, 0, 2)
	tick.pitch_scale = 1.1
	tick.play()
	_update_buttons()


func _press_button() -> void:
	var button: Button = [back_button, start_button][button_index]
	button.pressed.emit()


# show which button is selected: it takes the hover look and grows a little
func _update_buttons() -> void:
	var buttons: Array[Button] = [back_button, start_button]
	for i in 2:
		var selected := in_buttons and i == button_index
		var button := buttons[i]
		button.add_theme_stylebox_override("normal", button.get_theme_stylebox("hover") if selected else normal_styles[button])
		button.pivot_offset = button.size / 2.0
		button.scale = Vector2.ONE * (1.1 if selected else 1.0)
	if start_in < 0.0:
		hint.text = _hint_text()


# which player a controller belongs to (see Session.setup_coop_inputs for the same rules in the game itself)
func _player_for_pad(device: int) -> int:
	var pads := Input.get_connected_joypads()
	if pads.size() >= 2:
		if device == pads[0]:
			return 0
		return 1 if device == pads[1] else -1
	if pads.size() == 1:
		# a single controller plays as player 1 until player 2 joins, then it becomes player 2's
		return 1 if joined[1] else 0
	return -1


# ---------- actions ----------

# the colour the other player has locked in (pressed ready on), or -1. Only a locked colour is unavailable.
func _taken_for(player: int) -> int:
	var other := 1 - player
	return colors[other] if (joined[other] and ready_state[other]) else -1


# the next colour from `from`, in a direction, that is not locked by the other player
func _next_free_color(player: int, from: int, step: int) -> int:
	var taken := _taken_for(player)
	var index := from
	for _i in Session.COLORS.size():
		index = wrapi(index + step, 0, Session.COLORS.size())
		if index != taken:
			return index
	return from


func _notice(player: int, text: String) -> void:
	notices[player] = text
	notice_time[player] = 1.6
	last_bump_ms[player] = Time.get_ticks_msec()


func _join() -> void:
	if joined[1]:
		return
	joined[1] = true
	ready_state[1] = false
	# player 1 may already have locked in the colour player 2 would start on
	if colors[1] == _taken_for(1):
		colors[1] = _next_free_color(1, colors[1], 1)
	_cancel_countdown()
	UiSound.confirm()
	_refresh()


func _leave() -> void:
	if not joined[1]:
		return
	joined[1] = false
	ready_state[1] = false
	tick.pitch_scale = 0.8
	tick.play()
	# if player 1 was already ready, they are now the only one left, so the game can start
	_update_countdown()
	_refresh()


# ready = lock in. Pressing it again unlocks, which frees the colour for the other player.
func _toggle_ready(player: int) -> void:
	if not joined[player]:
		return
	var other := 1 - player
	if ready_state[player]:
		ready_state[player] = false
		UiSound.confirm()
	else:
		# a press that comes right after this player was moved off a colour was meant for the colour they had been
		# looking at, not the new one, so it must not lock the new one in
		if Time.get_ticks_msec() - last_bump_ms[player] < BUMP_GRACE_MS:
			tick.pitch_scale = 0.7
			tick.play()
			return
		# locking in: the colour must still be free. If the other player locked it first (even a moment earlier),
		# this player is refused and moved on to the next free colour.
		if colors[player] == _taken_for(player):
			colors[player] = _next_free_color(player, colors[player], 1)
			_notice(player, "COLOUR TAKEN")
			tick.pitch_scale = 0.7
			tick.play()
			_refresh()
			return
		ready_state[player] = true
		UiSound.confirm()
		# the other player was previewing the same colour: move them on
		if joined[other] and not ready_state[other] and colors[other] == colors[player]:
			colors[other] = _next_free_color(other, colors[other], 1)
			_notice(other, "P%d TOOK IT" % (player + 1))
	_update_countdown()
	_refresh()


# everyone who joined is ready: count down to the start; otherwise stop any countdown
func _update_countdown() -> void:
	var all_ready := true
	for i in 2:
		if joined[i] and not ready_state[i]:
			all_ready = false
	if all_ready:
		start_in = START_DELAY
	else:
		_cancel_countdown()


# browse to the next colour; locked while ready. The other player's choice never matters unless they locked in.
func _change_color(player: int, step: int) -> void:
	if not joined[player] or ready_state[player]:
		return
	var index := _next_free_color(player, colors[player], step)
	if index != colors[player]:
		colors[player] = index
		tick.pitch_scale = 1.0 + 0.04 * index
		tick.play()
		_refresh()


func _pick_color(player: int, index: int) -> void:
	if not joined[player] or ready_state[player]:
		return
	if index == _taken_for(player):
		return
	colors[player] = index
	tick.pitch_scale = 1.0 + 0.04 * index
	tick.play()
	_refresh()


func _first_free_color(taken: int) -> int:
	for i in Session.COLORS.size():
		if i != taken:
			return i
	return 0


func _cancel_countdown() -> void:
	start_in = -1.0
	hint.text = _hint_text()


func _begin() -> void:
	if starting:
		return
	starting = true
	_resolve_duplicates()
	Session.player_colors = colors.duplicate()
	UiSound.confirm()
	start_requested.emit(2 if joined[1] else 1)


# the START button can start the game before anyone locked in. If both ships are still on the same colour,
# the player who has not locked in (or player 2) is moved to the next one.
func _resolve_duplicates() -> void:
	if not joined[1] or colors[0] != colors[1]:
		return
	var mover := 0 if (ready_state[1] and not ready_state[0]) else 1
	colors[mover] = (colors[mover] + 1) % Session.COLORS.size()


# where the START button is, as a fraction of the screen, for the transition to close on
func start_center() -> Vector2:
	var centre := start_button.global_position + start_button.size / 2.0
	return centre / get_viewport_rect().size


# ---------- display ----------

func _refresh() -> void:
	var pads := Input.get_connected_joypads().size()
	for player in 2:
		var slot = slots[player]
		if not joined[player]:
			slot.show_waiting("PRESS %s\nTO JOIN" % InputHints.join_hint())
			continue
		var who := _who(player)
		var status := "LOCKED IN!" if ready_state[player] else "PRESS %s TO LOCK IN" % InputHints.pulse_hint(who)
		if notice_time[player] > 0.0:
			status = notices[player]
		slot.show_joined(colors[player], _taken_for(player), ready_state[player], _device_text(player, pads), status)


# the player number the input hints know this slot by: before player 2 joins, player 1 can use any device
func _who(player: int) -> int:
	return 0 if (player == 0 and not joined[1]) else player + 1


func _device_text(player: int, pads: int) -> String:
	if InputHints.is_pad(_who(player)):
		return "CONTROLLER" if pads < 2 else "CONTROLLER %d" % (player + 1)
	if player == 0:
		return "WASD / ARROWS + SPACE" if not joined[1] else "WASD + SPACE"
	return "ARROWS + ENTER"


func _hint_text() -> String:
	if in_buttons:
		if InputHints.is_pad():
			return "LEFT / RIGHT  choose     %s  select     UP  back to colours" % InputHints.south()
		return "A / D  choose     SPACE / ENTER  select     W / UP  back to colours"
	if InputHints.is_pad():
		return "D-PAD  colour     %s  ready     DOWN  buttons     %s  back" % [InputHints.south(), InputHints.east()]
	return "LEFT / RIGHT  colour     SPACE / ENTER  ready     DOWN  buttons     ESC  back"


func _on_hints_changed() -> void:
	if not visible:
		return
	_refresh()
	if start_in < 0.0:
		hint.text = _hint_text()
