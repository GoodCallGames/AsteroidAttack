extends CanvasLayer

# Settings screen opened from the pause menu. Reads and writes the Settings autoload.
# Display changes (window mode, resolution) ask for confirmation and revert after a countdown
# so a bad choice can't leave the player stuck on an unusable screen.

signal closed

const CONFIRM_SECONDS := 10.0
const SHAKE_VALUES := [1.0, 0.5, 0.0]

@onready var panel: PanelContainer = %Panel
@onready var window_mode: OptionButton = %WindowMode
@onready var resolution: OptionButton = %Resolution
@onready var vsync: OptionButton = %VSync
@onready var max_fps: OptionButton = %MaxFps
@onready var volume: HSlider = %Volume
@onready var volume_value: Label = %VolumeValue
@onready var music_volume: HSlider = %MusicVolume
@onready var music_value: Label = %MusicValue
@onready var sfx_volume: HSlider = %SfxVolume
@onready var sfx_value: Label = %SfxValue
@onready var shake: OptionButton = %Shake
@onready var back: Button = %Back
@onready var confirm_layer: ColorRect = %ConfirmLayer
@onready var countdown: Label = %Countdown
@onready var keep: Button = %Keep
@onready var revert: Button = %Revert
@onready var preview: AudioStreamPlayer = %Preview

var resolutions: Array[Vector2i] = []
var confirming := false
var confirm_left := 0.0
var confirm_snapshot := {}
var refreshing := false


func _ready() -> void:
	visible = false
	_populate()

	window_mode.item_selected.connect(_on_window_mode)
	resolution.item_selected.connect(_on_resolution)
	vsync.item_selected.connect(_on_vsync)
	max_fps.item_selected.connect(_on_max_fps)
	volume.value_changed.connect(_on_volume)
	music_volume.value_changed.connect(_on_music_volume)
	sfx_volume.value_changed.connect(_on_sfx_volume)
	shake.item_selected.connect(_on_shake)
	back.pressed.connect(close)
	keep.pressed.connect(_keep_display)
	revert.pressed.connect(_revert_display)


func _process(delta: float) -> void:
	if not confirming:
		return
	confirm_left -= delta
	countdown.text = "Reverting in %d" % ceili(maxf(confirm_left, 0.0))
	if confirm_left <= 0.0:
		_revert_display()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	# B / Esc backs out of the confirmation (reverting) or closes the screen
	if confirming:
		_revert_display()
	else:
		close()
	get_viewport().set_input_as_handled()


func open() -> void:
	_refresh()
	visible = true
	window_mode.grab_focus()


func close() -> void:
	Settings.save_settings()
	visible = false
	closed.emit()


func _populate() -> void:
	for text in ["Windowed", "Borderless Fullscreen", "Fullscreen (Exclusive)"]:
		window_mode.add_item(text)
	for text in ["Off", "On", "Adaptive"]:
		vsync.add_item(text)
	for fps in Settings.FPS_OPTIONS:
		max_fps.add_item("Unlimited" if fps == 0 else "%d" % fps)
	for text in ["Full", "Reduced", "Off"]:
		shake.add_item(text)

	resolutions = Settings.available_resolutions()
	for res in resolutions:
		resolution.add_item("%d x %d" % [res.x, res.y])


# show the values currently held by the Settings autoload without triggering change handlers
func _refresh() -> void:
	refreshing = true
	window_mode.select(Settings.window_mode)
	var res_index := resolutions.find(Settings.resolution)
	resolution.select(maxi(res_index, 0))
	vsync.select(Settings.vsync)
	max_fps.select(maxi(Settings.FPS_OPTIONS.find(Settings.max_fps), 0))
	volume.set_value_no_signal(roundf(Settings.volume * 100.0))
	volume_value.text = "%d%%" % int(roundf(Settings.volume * 100.0))
	music_volume.set_value_no_signal(roundf(Settings.music_volume * 100.0))
	music_value.text = "%d%%" % int(roundf(Settings.music_volume * 100.0))
	sfx_volume.set_value_no_signal(roundf(Settings.sfx_volume * 100.0))
	sfx_value.text = "%d%%" % int(roundf(Settings.sfx_volume * 100.0))
	shake.select(_nearest_shake_index(Settings.screen_shake))
	resolution.disabled = Settings.window_mode != Settings.WindowMode.WINDOWED
	refreshing = false


func _nearest_shake_index(value: float) -> int:
	var best := 0
	for i in SHAKE_VALUES.size():
		if absf(SHAKE_VALUES[i] - value) < absf(SHAKE_VALUES[best] - value):
			best = i
	return best


# --- display (needs confirmation) ---

func _on_window_mode(index: int) -> void:
	_change_display(func(): Settings.window_mode = index as Settings.WindowMode)


func _on_resolution(index: int) -> void:
	_change_display(func(): Settings.resolution = resolutions[index])


func _change_display(change: Callable) -> void:
	if refreshing:
		return
	# keep the oldest snapshot if the player changes again while a confirmation is pending
	var before := Settings.snapshot()
	change.call()
	Settings.apply_display()
	resolution.disabled = Settings.window_mode != Settings.WindowMode.WINDOWED
	_start_confirm(before)


func _start_confirm(before: Dictionary) -> void:
	if not confirming:
		confirm_snapshot = before
	confirming = true
	confirm_left = CONFIRM_SECONDS
	confirm_layer.visible = true
	panel.process_mode = Node.PROCESS_MODE_DISABLED
	keep.grab_focus()


func _keep_display() -> void:
	_end_confirm()
	Settings.save_settings()
	window_mode.grab_focus()


func _revert_display() -> void:
	_end_confirm()
	Settings.restore(confirm_snapshot)
	_refresh()
	window_mode.grab_focus()


func _end_confirm() -> void:
	confirming = false
	confirm_layer.visible = false
	panel.process_mode = Node.PROCESS_MODE_INHERIT


# --- everything else applies immediately ---

func _on_vsync(index: int) -> void:
	if refreshing:
		return
	Settings.vsync = index as Settings.VSync
	Settings.apply_vsync()


func _on_max_fps(index: int) -> void:
	if refreshing:
		return
	Settings.max_fps = Settings.FPS_OPTIONS[index]
	Settings.apply_fps()


func _on_volume(value: float) -> void:
	if refreshing:
		return
	Settings.volume = value / 100.0
	Settings.apply_volume()
	volume_value.text = "%d%%" % int(value)
	# the master preview goes through Master so it follows the whole mix
	preview.bus = Settings.BUS_MASTER
	preview.play()


func _on_shake(index: int) -> void:
	if refreshing:
		return
	Settings.screen_shake = SHAKE_VALUES[index]


func _on_music_volume(value: float) -> void:
	if refreshing:
		return
	Settings.music_volume = value / 100.0
	Settings.apply_volume()
	music_value.text = "%d%%" % int(value)


func _on_sfx_volume(value: float) -> void:
	if refreshing:
		return
	Settings.sfx_volume = value / 100.0
	Settings.apply_volume()
	sfx_value.text = "%d%%" % int(value)
	# the blip goes through the SFX bus so you hear what the slider controls
	preview.bus = Settings.BUS_SFX
	preview.play()
