extends CanvasLayer

# Autoload ("Transition"): animated iris wipe used for every scene change.
#   Transition.change_scene(path, close_center, open_center)
#   Transition.reload_scene()
# Centres are 0..1 of the screen. The iris closes on close_center, the scene swaps while the screen is covered,
# then it opens from open_center. It runs in "Always" mode so it works from the paused menu too.

const IRIS_SHADER := preload("res://shaders/iris_transition.gdshader")

const CLOSE_TIME := 0.5
const HOLD_TIME := 0.12
const OPEN_TIME := 0.65

var busy := false

var rect: ColorRect
var material: ShaderMaterial


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	material = ShaderMaterial.new()
	material.shader = IRIS_SHADER
	rect = ColorRect.new()
	rect.material = material
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	add_child(rect)

	get_viewport().size_changed.connect(_update_size)
	_update_size()


func change_scene(path: String, close_center := Vector2(0.5, 0.5), open_center := Vector2(0.5, 0.5)) -> void:
	if busy:
		return
	await _cover(close_center)
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
	await _reveal(open_center)


func reload_scene(close_center := Vector2(0.5, 0.5), open_center := Vector2(0.5, 0.5)) -> void:
	if busy:
		return
	await _cover(close_center)
	get_tree().paused = false
	get_tree().reload_current_scene()
	await _reveal(open_center)


func _cover(center: Vector2) -> void:
	busy = true
	_update_size()
	material.set_shader_parameter("center", center)
	material.set_shader_parameter("progress", 0.0)
	rect.visible = true
	# block clicks while the screen is changing
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	await _animate(0.0, 1.0, CLOSE_TIME, Tween.EASE_IN)


func _reveal(center: Vector2) -> void:
	# the new scene is loaded at the end of the frame the change was requested; give it a moment to build
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(HOLD_TIME, true).timeout
	material.set_shader_parameter("center", center)
	await _animate(1.0, 0.0, OPEN_TIME, Tween.EASE_OUT)
	rect.visible = false
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	busy = false


func _animate(from: float, to: float, duration: float, ease_type: Tween.EaseType) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(ease_type)
	tween.tween_method(func(v: float): material.set_shader_parameter("progress", v), from, to, duration)
	await tween.finished


func _update_size() -> void:
	material.set_shader_parameter("screen_size", get_viewport().get_visible_rect().size)
