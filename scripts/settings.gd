extends Node

# Autoload ("Settings"): holds the player's settings, saves them to user://settings.cfg and applies them.
# Godot can't set a monitor's refresh rate, so "refresh rate" here is VSync plus an FPS cap.

const SAVE_PATH := "user://settings.cfg"

# audio buses: music and effects each feed Master, so Master scales everything
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

enum WindowMode { WINDOWED, BORDERLESS, EXCLUSIVE }
enum VSync { OFF, ON, ADAPTIVE }

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

# 0 means unlimited
const FPS_OPTIONS: Array[int] = [0, 60]

var window_mode := WindowMode.WINDOWED
var resolution := Vector2i(1280, 720)
var vsync := VSync.ON
var max_fps := 0
var volume := 1.0 # master, 0..1
var music_volume := 1.0
var sfx_volume := 1.0
var screen_shake := 1.0 # 1 full, 0.5 reduced, 0 off


func _ready() -> void:
	# the buses have to exist before any scene creates a player that uses them
	_ensure_bus(BUS_MUSIC)
	_ensure_bus(BUS_SFX)
	# only touch the window if the player has saved settings; otherwise keep the project defaults
	if load_settings():
		apply_all()
	else:
		apply_volume()


# resolutions that fit on the monitor the game is running on
func available_resolutions() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var result: Array[Vector2i] = []
	for res in RESOLUTIONS:
		if res.x <= screen.x and res.y <= screen.y:
			result.append(res)
	if result.is_empty():
		result.append(RESOLUTIONS[0])
	return result


func snapshot() -> Dictionary:
	return {
		"window_mode": window_mode,
		"resolution": resolution,
		"vsync": vsync,
		"max_fps": max_fps,
		"volume": volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"screen_shake": screen_shake,
	}


func restore(data: Dictionary) -> void:
	window_mode = data.window_mode
	resolution = data.resolution
	vsync = data.vsync
	max_fps = data.max_fps
	volume = data.volume
	music_volume = data.music_volume
	sfx_volume = data.sfx_volume
	screen_shake = data.screen_shake
	apply_all()


func apply_all() -> void:
	apply_display()
	apply_vsync()
	apply_fps()
	apply_volume()


func apply_display() -> void:
	var window := get_window()
	match window_mode:
		WindowMode.WINDOWED:
			window.mode = Window.MODE_WINDOWED
			window.size = resolution
			# changing mode and size in the same frame can lose the position, so centre afterwards
			_center_window.call_deferred()
		WindowMode.BORDERLESS:
			window.mode = Window.MODE_FULLSCREEN
		WindowMode.EXCLUSIVE:
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN


func _center_window() -> void:
	var window := get_window()
	if window.mode != Window.MODE_WINDOWED:
		return
	var screen := DisplayServer.window_get_current_screen()
	var origin := DisplayServer.screen_get_position(screen)
	var size := DisplayServer.screen_get_size(screen)
	window.position = origin + Vector2i(Vector2(size - window.size) / 2.0)


func apply_vsync() -> void:
	match vsync:
		VSync.OFF:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		VSync.ON:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		VSync.ADAPTIVE:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)


func apply_fps() -> void:
	Engine.max_fps = max_fps


func apply_volume() -> void:
	_set_bus_volume(BUS_MASTER, volume)
	_set_bus_volume(BUS_MUSIC, music_volume)
	_set_bus_volume(BUS_SFX, sfx_volume)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return
	AudioServer.set_bus_volume_db(bus, -80.0 if linear <= 0.001 else linear_to_db(linear))


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, BUS_MASTER)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "window_mode", window_mode)
	config.set_value("display", "resolution", resolution)
	config.set_value("display", "vsync", vsync)
	config.set_value("display", "max_fps", max_fps)
	config.set_value("audio", "volume", volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("gameplay", "screen_shake", screen_shake)
	config.save(SAVE_PATH)


# returns true if a settings file was found
func load_settings() -> bool:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return false
	window_mode = config.get_value("display", "window_mode", window_mode)
	resolution = config.get_value("display", "resolution", resolution)
	vsync = config.get_value("display", "vsync", vsync)
	max_fps = config.get_value("display", "max_fps", max_fps)
	volume = config.get_value("audio", "volume", volume)
	music_volume = config.get_value("audio", "music_volume", music_volume)
	sfx_volume = config.get_value("audio", "sfx_volume", sfx_volume)
	screen_shake = config.get_value("gameplay", "screen_shake", screen_shake)
	return true
