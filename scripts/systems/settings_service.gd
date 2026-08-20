class_name SettingsService
extends RefCounted

const WINDOWED: String = "windowed"
const FULLSCREEN: String = "fullscreen"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1280, 720),
]

var _settings_path: String


func _init(settings_path: String = "user://settings.cfg") -> void:
	_settings_path = settings_path


func load_settings() -> Dictionary:
	var defaults := _default_settings()
	var config := ConfigFile.new()
	if config.load(_settings_path) != OK:
		return defaults
	var mode := str(config.get_value("display", "mode", defaults["mode"]))
	var width := int(config.get_value("display", "width", defaults["width"]))
	var height := int(config.get_value("display", "height", defaults["height"]))
	var settings := {"mode": mode, "width": width, "height": height}
	return settings if validate_settings(settings) else defaults


func save_settings(settings: Dictionary) -> bool:
	if not validate_settings(settings):
		return false
	var config := ConfigFile.new()
	config.set_value("display", "mode", str(settings["mode"]))
	config.set_value("display", "width", int(settings["width"]))
	config.set_value("display", "height", int(settings["height"]))
	return config.save(_settings_path) == OK


func apply_settings(settings: Dictionary) -> bool:
	if not validate_settings(settings):
		return false
	var mode := str(settings["mode"])
	if mode == FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var size := Vector2i(int(settings["width"]), int(settings["height"]))
		DisplayServer.window_set_size(size)
		var screen := DisplayServer.window_get_current_screen()
		var screen_size := DisplayServer.screen_get_size(screen)
		var screen_position := DisplayServer.screen_get_position(screen)
		DisplayServer.window_set_position(
			screen_position + (screen_size - size) / 2
		)
	return true


func validate_settings(settings: Dictionary) -> bool:
	var mode := str(settings.get("mode", ""))
	if mode not in [WINDOWED, FULLSCREEN]:
		return false
	var size := Vector2i(
		int(settings.get("width", 0)),
		int(settings.get("height", 0))
	)
	return size in RESOLUTIONS


func resolution_index(settings: Dictionary) -> int:
	var size := Vector2i(int(settings.get("width", 0)), int(settings.get("height", 0)))
	var index := RESOLUTIONS.find(size)
	return 0 if index < 0 else index


func _default_settings() -> Dictionary:
	return {
		"mode": (
			FULLSCREEN
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			else WINDOWED
		),
		"width": int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)),
		"height": int(ProjectSettings.get_setting("display/window/size/viewport_height", 1080)),
	}
