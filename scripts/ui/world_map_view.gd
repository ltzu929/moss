class_name WorldMapView
extends Control

signal region_selected(region_name: String)

const MossTheme := preload("res://scripts/ui/moss_ui_theme.gd")

var _regions: Dictionary = {}
var _label_positions: Dictionary = {}
var _connections: Array[Array] = []
var _region_states: Dictionary = {}
var _selected_region: String = ""
var _hovered_region: String = ""
var _scan_progress: float = 0.0


func _ready() -> void:
	unique_name_in_owner = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_map_geometry()
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_scan_progress = fmod(_scan_progress + delta * 0.075, 1.0)
	queue_redraw()


func set_region_states(states: Dictionary) -> void:
	_region_states = states.duplicate(true)
	queue_redraw()


func set_selected_region(region_name: String) -> void:
	_selected_region = region_name
	queue_redraw()


func get_region_names() -> Array[String]:
	var result: Array[String] = []
	for region_name in _regions.keys():
		result.append(str(region_name))
	return result


func _build_map_geometry() -> void:
	_regions = {
		"北美": PackedVector2Array([
			Vector2(0.07, 0.24), Vector2(0.13, 0.12), Vector2(0.27, 0.14),
			Vector2(0.33, 0.25), Vector2(0.27, 0.39), Vector2(0.14, 0.36),
		]),
		"南美": PackedVector2Array([
			Vector2(0.27, 0.43), Vector2(0.35, 0.47), Vector2(0.38, 0.61),
			Vector2(0.33, 0.84), Vector2(0.26, 0.68), Vector2(0.24, 0.52),
		]),
		"联合政府": PackedVector2Array([
			Vector2(0.43, 0.20), Vector2(0.55, 0.18), Vector2(0.59, 0.29),
			Vector2(0.53, 0.37), Vector2(0.45, 0.32),
		]),
		"非洲": PackedVector2Array([
			Vector2(0.45, 0.39), Vector2(0.57, 0.38), Vector2(0.61, 0.52),
			Vector2(0.55, 0.73), Vector2(0.47, 0.63), Vector2(0.42, 0.49),
		]),
		"俄罗斯": PackedVector2Array([
			Vector2(0.54, 0.12), Vector2(0.76, 0.11), Vector2(0.83, 0.20),
			Vector2(0.76, 0.31), Vector2(0.59, 0.29),
		]),
		"亚洲": PackedVector2Array([
			Vector2(0.60, 0.32), Vector2(0.79, 0.30), Vector2(0.88, 0.43),
			Vector2(0.82, 0.59), Vector2(0.69, 0.58), Vector2(0.58, 0.46),
		]),
		"大洋洲": PackedVector2Array([
			Vector2(0.78, 0.63), Vector2(0.90, 0.62), Vector2(0.94, 0.74),
			Vector2(0.86, 0.82), Vector2(0.77, 0.75),
		]),
	}
	_label_positions = {
		"北美": Vector2(0.18, 0.25),
		"南美": Vector2(0.31, 0.60),
		"联合政府": Vector2(0.50, 0.26),
		"非洲": Vector2(0.51, 0.51),
		"俄罗斯": Vector2(0.68, 0.20),
		"亚洲": Vector2(0.73, 0.43),
		"大洋洲": Vector2(0.85, 0.70),
	}
	_connections = [
		["北美", "联合政府"],
		["北美", "南美"],
		["联合政府", "非洲"],
		["联合政府", "俄罗斯"],
		["俄罗斯", "亚洲"],
		["非洲", "亚洲"],
		["亚洲", "大洋洲"],
	]


func _draw() -> void:
	var map_rect := Rect2(Vector2.ZERO, size)
	draw_rect(map_rect, Color(0.008, 0.022, 0.035, 1.0), true)
	_draw_grid()
	_draw_connections()

	for region_name in _regions.keys():
		_draw_region(str(region_name))

	var scan_y := size.y * _scan_progress
	draw_line(
		Vector2(0.0, scan_y),
		Vector2(size.x, scan_y),
		Color(0.30, 0.78, 0.82, 0.10),
		1.0
	)
	draw_rect(map_rect, MossTheme.BORDER, false, 1.0)


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


func _draw_connections() -> void:
	for connection in _connections:
		var from_position := _normalized_to_local(_label_positions[connection[0]])
		var to_position := _normalized_to_local(_label_positions[connection[1]])
		draw_dashed_line(
			from_position,
			to_position,
			Color(0.25, 0.65, 0.72, 0.34),
			1.0,
			8.0
		)


func _draw_region(region_name: String) -> void:
	var polygon := _local_polygon(_regions[region_name])
	var state: Dictionary = _region_states.get(region_name, {})
	var authority := int(state.get("authority", 50))
	var fill_color := Color(0.08, 0.18, 0.24, 0.70)
	var line_color := Color(0.28, 0.48, 0.59, 0.88)

	if authority < 20:
		fill_color = Color(0.26, 0.055, 0.06, 0.68)
		line_color = MossTheme.DANGER
	elif authority < 40:
		fill_color = Color(0.09, 0.14, 0.18, 0.76)

	if region_name == _hovered_region:
		fill_color = fill_color.lightened(0.10)
		line_color = MossTheme.ACCENT_CYAN

	if region_name == _selected_region:
		fill_color = Color(0.24, 0.20, 0.10, 0.64)
		line_color = MossTheme.ACCENT_GOLD

	draw_colored_polygon(polygon, fill_color)
	draw_polyline(polygon, line_color, 1.5, true)
	draw_line(polygon[polygon.size() - 1], polygon[0], line_color, 1.5, true)

	var label_position := _normalized_to_local(_label_positions[region_name])
	draw_circle(label_position, 4.0, line_color)
	draw_circle(label_position, 9.0, Color(line_color, 0.16), false, 1.0)

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
		MossTheme.TEXT_PRIMARY
	)


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
			if region_name != "":
				region_selected.emit(region_name)
				accept_event()


func _region_at_position(local_position: Vector2) -> String:
	for region_name in _regions.keys():
		var polygon := _local_polygon(_regions[region_name])
		if Geometry2D.is_point_in_polygon(local_position, polygon):
			return str(region_name)
	return ""


func _local_polygon(normalized_polygon: PackedVector2Array) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for point in normalized_polygon:
		polygon.append(_normalized_to_local(point))
	return polygon


func _normalized_to_local(point: Vector2) -> Vector2:
	return Vector2(point.x * size.x, point.y * size.y)
