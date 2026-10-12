extends Node

# Autoload ("UiSound"): plays the confirm sound when a menu choice is made.
# Runs in "Always" mode so it still works while the game is paused, and it lives across scene reloads
# so the sound isn't cut off by Restart.
#
# UiSound.wire(some_menu_node) hooks up every button in that subtree:
#   buttons play the sound when pressed
#   dropdowns play it when an option is chosen (not when the list merely opens)

const CONFIRM := preload("res://assets/audio/select.mp3")

@export var volume_db := 0.0

var player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	player.stream = CONFIRM
	player.bus = "SFX"
	player.volume_db = volume_db
	add_child(player)


func confirm() -> void:
	player.play(0.2)


func wire(root: Node) -> void:
	for child in root.get_children():
		if child is OptionButton:
			child.item_selected.connect(func(_index: int): confirm())
		elif child is Button:
			child.pressed.connect(confirm)
		wire(child)
