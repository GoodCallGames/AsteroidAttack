extends PanelContainer

# One player's panel on the setup screen: their ship in the chosen colour, the colour swatches
# (the other player's colour is greyed out), and their ready state. Or an invitation to join.

signal swatch_pressed(color_index: int)

@onready var content: VBoxContainer = %Content
@onready var header: Label = %Header
@onready var device: Label = %Device
@onready var ship_holder: Control = %ShipHolder
@onready var ship: TextureRect = %Ship
@onready var color_name: Label = %ColorName
@onready var swatch_box: HBoxContainer = %Swatches
@onready var status: Label = %Status
@onready var join_prompt: Label = %JoinPrompt

var swatches: Array[Button] = []
var time := 0.0
var phase := 0.0
var joined := true
var accent := Color.WHITE
var player_number := 1

const BOLD_FONT := preload("res://assets/fonts/PixeloidSans-Bold.otf")


func _ready() -> void:
	for i in Session.COLORS.size():
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(38, 38)
		# the setup screen is driven by the players' own controls, not by UI focus
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.pressed.connect(func(): swatch_pressed.emit(i))
		swatch_box.add_child(swatch)
		swatches.append(swatch)


func setup(number: int) -> void:
	player_number = number
	header.text = "PLAYER %d" % number
	phase = number * 1.7


func _process(delta: float) -> void:
	time += delta
	# the ship floats and sways
	var rest := Vector2((ship_holder.size.x - ship.size.x) / 2.0, 4.0)
	ship.position = rest + Vector2(0.0, sin(time * 2.0 + phase) * 6.0)
	ship.rotation = sin(time * 1.3 + phase) * 0.06

	if not joined:
		# the join prompt gently pulses
		join_prompt.modulate.a = 0.65 + 0.35 * sin(time * 3.0)


func show_joined(color_index: int, other_color_index: int, is_ready: bool, device_text: String, status_text: String) -> void:
	joined = true
	content.visible = true
	join_prompt.visible = false

	var entry: Dictionary = Session.COLORS[color_index]
	accent = entry.accent
	ship.texture = entry.texture
	color_name.text = entry.name
	color_name.add_theme_color_override("font_color", accent)
	header.add_theme_color_override("font_color", accent)
	device.text = device_text

	status.text = status_text
	status.add_theme_color_override("font_color", accent if is_ready else Color(0.72, 0.88, 0.82))
	add_theme_stylebox_override("panel", _panel_style(accent if is_ready else Color(0.5, 1.0, 0.8, 0.5), is_ready))

	for i in swatches.size():
		_style_swatch(swatches[i], Session.COLORS[i].accent, i == color_index, i == other_color_index, is_ready)


func show_waiting(prompt_text: String) -> void:
	joined = false
	content.visible = false
	join_prompt.visible = true
	join_prompt.text = prompt_text
	add_theme_stylebox_override("panel", _panel_style(Color(0.5, 1.0, 0.8, 0.25), false))


func _panel_style(border: Color, glow: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = get_theme_stylebox("panel", "PanelContainer").duplicate()
	style.bg_color = Color(0.08, 0.09, 0.13, 0.88)
	style.border_color = border
	style.border_width_left = 5 if glow else 3
	style.border_width_top = 5 if glow else 3
	style.border_width_right = 5 if glow else 3
	style.border_width_bottom = 5 if glow else 3
	for corner in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(corner, 24)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 20.0
	return style


# selected: white ring.
# taken: the other player has this colour. It is shown as an empty socket in that colour, tagged with their
# number, so it reads as "P2 has this" and not as if this player's own colours had changed.
func _style_swatch(swatch: Button, color: Color, selected: bool, taken: bool, locked: bool) -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(19)
	style.set_border_width_all(4)
	if taken:
		style.bg_color = Color(0.1, 0.12, 0.17)
		style.border_color = Color(color, 0.7)
	else:
		style.bg_color = color
		style.border_color = Color.WHITE if selected else Color(1, 1, 1, 0)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		swatch.add_theme_stylebox_override(state, style)

	# the tag: "P1" or "P2", in the colour the other player picked
	swatch.text = "P%d" % (3 - player_number) if taken else ""
	swatch.add_theme_font_override("font", BOLD_FONT)
	swatch.add_theme_font_size_override("font_size", 14)
	swatch.add_theme_color_override("font_disabled_color", color)

	swatch.disabled = taken or locked
	swatch.modulate.a = 1.0 if (taken or selected or not locked) else 0.55
	swatch.tooltip_text = "TAKEN BY PLAYER %d" % (3 - player_number) if taken else ""
