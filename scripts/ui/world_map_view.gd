@tool
class_name WorldMapView
extends Control

signal region_selected(region_name: String)

## MOSS 界面主题工具
const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")
const WORLD_OUTLINE_PATH := "res://assets/ui/world-map/world_outline_gray.png"
const REGION_ORDER := ["北美", "南美", "非洲", "亚洲", "大洋洲"]
const MASK_ALPHA_THRESHOLD := 0.35
const REGION_TEXTURE_PATHS := {
	"北美": "res://assets/ui/world-map/mask_north_america.png",
	"南美": "res://assets/ui/world-map/mask_south_america.png",
	"非洲": "res://assets/ui/world-map/mask_africa.png",
	"亚洲": "res://assets/ui/world-map/mask_asia.png",
	"大洋洲": "res://assets/ui/world-map/mask_oceania.png",
}
const EDITOR_PREVIEW_SECTOR_PATHS := {
	"北美": "res://data/sector_na.tres",
	"南美": "res://data/sector_south_america.tres",
	"非洲": "res://data/sector_africa.tres",
	"亚洲": "res://data/sector_asia.tres",
	"大洋洲": "res://data/sector_oceania.tres",
}

@export_group("编辑器标签位置")
@export var north_america_label_position := Vector2(0.75, 0.23):
	set(value):
		north_america_label_position = value
		if is_inside_tree():
			_sync_label_positions()
@export var south_america_label_position := Vector2(0.90, 0.59):
	set(value):
		south_america_label_position = value
		if is_inside_tree():
			_sync_label_positions()
@export var africa_label_position := Vector2(0.15, 0.47):
	set(value):
		africa_label_position = value
		if is_inside_tree():
			_sync_label_positions()
@export var asia_label_position := Vector2(0.39, 0.31):
	set(value):
		asia_label_position = value
		if is_inside_tree():
			_sync_label_positions()
@export var oceania_label_position := Vector2(0.46, 0.67):
	set(value):
		oceania_label_position = value
		if is_inside_tree():
			_sync_label_positions()

var _label_positions: Dictionary = {}
var _world_outline_texture: Texture2D
var _region_textures: Dictionary = {}
var _mask_images: Dictionary = {}
var _region_states: Dictionary = {}
var _selected_region: String = ""
var _hovered_region: String = ""
var _scan_progress: float = 0.0


func _ready() -> void:
	unique_name_in_owner = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sync_label_positions()
	_load_map_textures()
	_cache_mask_images()
	if Engine.is_editor_hint():
		_load_editor_preview_states()
		_scan_progress = 0.5
		set_process(false)
	else:
		set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_scan_progress = fmod(_scan_progress + delta * 0.075, 1.0)
	queue_redraw()


func _sync_label_positions() -> void:
	_label_positions = {
		"北美": north_america_label_position,
		"南美": south_america_label_position,
		"非洲": africa_label_position,
		"亚洲": asia_label_position,
		"大洋洲": oceania_label_position,
	}
	queue_redraw()


func _load_editor_preview_states() -> void:
	var preview_states: Dictionary = {}
	for region_name in EDITOR_PREVIEW_SECTOR_PATHS:
		var sector := load(EDITOR_PREVIEW_SECTOR_PATHS[region_name]) as SectorData
		if sector == null:
			continue
		preview_states[region_name] = {
			"order": sector.order,
			"hope": sector.hope,
			"authority": sector.authority,
			"population": sector.population,
		}
	_region_states = preview_states
	queue_redraw()


func set_region_states(states: Dictionary) -> void:
	_region_states = states.duplicate(true)
	queue_redraw()


func set_selected_region(region_name: String) -> void:
	_selected_region = _map_region_name(region_name)
	queue_redraw()


func get_region_names() -> Array[String]:
	var result: Array[String] = []
	for region_name in REGION_ORDER:
		result.append(region_name)
	return result


func _load_map_textures() -> void:
	_world_outline_texture = load(WORLD_OUTLINE_PATH) as Texture2D
	if _world_outline_texture == null:
		push_warning("世界地图底图缺失：%s" % WORLD_OUTLINE_PATH)

	_region_textures.clear()
	for region_name in REGION_ORDER:
		var texture_path := str(REGION_TEXTURE_PATHS.get(region_name, ""))
		var texture := load(texture_path) as Texture2D
		if texture == null:
			push_warning("世界地图遮罩缺失：%s" % region_name)
			continue
		_region_textures[region_name] = texture


func _cache_mask_images() -> void:
	_mask_images.clear()
	for region_name in REGION_ORDER:
		var texture: Texture2D = _region_textures.get(region_name)
		if texture == null:
			continue

		var image: Image = texture.get_image()
		if image == null or image.is_empty():
			push_warning("世界地图遮罩无法读取：%s" % region_name)
			continue

		_mask_images[region_name] = image


func _get_map_rect() -> Rect2:
	if _world_outline_texture == null:
		return Rect2(Vector2.ZERO, size)

	var source_size: Vector2 = _world_outline_texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return Rect2(Vector2.ZERO, size)

	var map_scale: float = min(size.x / source_size.x, size.y / source_size.y)
	var draw_size: Vector2 = source_size * map_scale
	var draw_position: Vector2 = (size - draw_size) * 0.5
	return Rect2(draw_position, draw_size)


func _draw() -> void:
	var control_rect := Rect2(Vector2.ZERO, size)
	var map_rect := _get_map_rect()

	draw_rect(control_rect, Color(0.008, 0.022, 0.035, 1.0), true)
	_draw_grid()
	if _world_outline_texture != null:
		draw_texture_rect(
			_world_outline_texture,
			map_rect,
			false,
			Color(1.0, 1.0, 1.0, 0.78)
		)

	for region_name in REGION_ORDER:
		_draw_region(region_name, map_rect)

	for region_name in REGION_ORDER:
		_draw_region_label(region_name, map_rect)

	var scan_y := size.y * _scan_progress
	draw_line(
		Vector2(0.0, scan_y),
		Vector2(size.x, scan_y),
		Color(0.30, 0.78, 0.82, 0.10),
		1.0
	)
	draw_rect(control_rect, MOSS_THEME.BORDER, false, 1.0)


func _draw_grid() -> void:
	var grid_color := Color(0.12, 0.27, 0.34, 0.18)
	var grid_size := 42.0
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), grid_color, 1.0)
		x += grid_size

	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), grid_color, 1.0)
		y += grid_size


func _draw_region(region_name: String, map_rect: Rect2) -> void:
	var texture: Texture2D = _region_textures.get(region_name)
	if texture == null:
		return

	draw_texture_rect(texture, map_rect, false, _region_fill_color(region_name))


func _draw_region_label(region_name: String, map_rect: Rect2) -> void:
	var state: Dictionary = _region_states.get(region_name, {})
	var authority := int(state.get("authority", 50))
	var situation_count := int(state.get("situation_count", 0))
	var label_position := _normalized_to_map(_label_positions[region_name], map_rect)
	var marker_color := _region_marker_color(region_name)

	draw_circle(label_position, 4.0, marker_color)
	draw_circle(label_position, 9.0, Color(marker_color, 0.16), false, 1.0)
	if situation_count > 0:
		draw_circle(label_position, 15.0, Color(1.0, 0.24, 0.20, 0.82), false, 2.0)
		draw_string(
			ThemeDB.fallback_font,
			label_position + Vector2(-4.0, -18.0),
			"!%d" % situation_count,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			13,
			Color(1.0, 0.42, 0.34, 1.0)
		)

	var label_text := region_name
	if not state.is_empty():
		label_text += "  %d%%" % authority
	draw_string(
		ThemeDB.fallback_font,
		label_position + Vector2(10.0, -7.0),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		14,
		MOSS_THEME.TEXT_PRIMARY
	)


func _region_fill_color(region_name: String) -> Color:
	var state: Dictionary = _region_states.get(region_name, {})
	var authority := int(state.get("authority", 50))
	var fill_color := Color(0.075, 0.17, 0.22, 0.66)

	if authority < 20:
		fill_color = Color(0.25, 0.045, 0.055, 0.70)
	elif authority < 40:
		fill_color = Color(0.08, 0.12, 0.16, 0.72)

	if region_name == _hovered_region:
		fill_color = fill_color.lightened(0.12)
		fill_color = fill_color.lerp(Color(0.12, 0.46, 0.50, fill_color.a), 0.28)

	if region_name == _selected_region:
		fill_color = Color(0.28, 0.235, 0.115, 0.72)

	return fill_color


func _region_marker_color(region_name: String) -> Color:
	if region_name == _selected_region:
		return MOSS_THEME.ACCENT_GOLD
	if region_name == _hovered_region:
		return MOSS_THEME.ACCENT_CYAN

	var state: Dictionary = _region_states.get(region_name, {})
	var authority := int(state.get("authority", 50))
	if authority < 20:
		return MOSS_THEME.DANGER
	return Color(0.28, 0.48, 0.59, 0.88)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hovered_region = _region_at_position(event.position)
		mouse_default_cursor_shape = (
			Control.CURSOR_POINTING_HAND
			if _hovered_region != ""
			else Control.CURSOR_ARROW
		)
		queue_redraw()
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var region_name := _region_at_position(event.position)
			region_selected.emit(region_name)
			accept_event()


func _region_at_position(local_position: Vector2) -> String:
	var map_rect := _get_map_rect()
	if not map_rect.has_point(local_position):
		return ""

	var uv := Vector2(
		(local_position.x - map_rect.position.x) / map_rect.size.x,
		(local_position.y - map_rect.position.y) / map_rect.size.y
	)

	for region_name in REGION_ORDER:
		var image: Image = _mask_images.get(region_name)
		if image == null or image.is_empty():
			continue

		var pixel_x := clampi(
			int(floor(uv.x * image.get_width())),
			0,
			image.get_width() - 1
		)
		var pixel_y := clampi(
			int(floor(uv.y * image.get_height())),
			0,
			image.get_height() - 1
		)
		if image.get_pixel(pixel_x, pixel_y).a > MASK_ALPHA_THRESHOLD:
			return region_name

	return ""


func _normalized_to_map(point: Vector2, map_rect: Rect2) -> Vector2:
	return map_rect.position + Vector2(point.x * map_rect.size.x, point.y * map_rect.size.y)


func _map_region_name(region_name: String) -> String:
	if region_name == "俄罗斯":
		return "亚洲"
	return region_name
