extends Node2D

# Root of the level. In a two-player game it adds the second ship and the shared camera.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const COOP_CAMERA := preload("res://scripts/coop_camera.gd")

# where the ships start (the single-player ship starts at (382, 179) in the scene)
const P1_START := Vector2(382, 179)
const P2_START := Vector2(-382, 179)

@onready var gameplay: Node2D = $Gameplay
@onready var player_one: RigidBody2D = $Gameplay/Player


func _ready() -> void:
	# the chosen colour applies in single player too
	player_one.apply_look(Session.player_colors[0])
	if Session.player_count < 2:
		return

	Session.setup_coop_inputs()
	player_one.global_position = P1_START
	player_one.setup_player(1)

	var player_two: RigidBody2D = PLAYER_SCENE.instantiate()
	gameplay.add_child(player_two)
	player_two.global_position = P2_START
	player_two.lock_rotation = true
	player_two.setup_player(2)

	# one camera for both ships; the ships' own cameras are switched off
	var shared_camera := Camera2D.new()
	shared_camera.set_script(COOP_CAMERA)
	add_child(shared_camera)
	shared_camera.make_current()
	player_one.camera.enabled = false
	player_two.camera.enabled = false
