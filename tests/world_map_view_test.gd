## 世界地图遮罩回归测试
## 验证 WorldMapView 的公共接口、遮罩加载和像素级点击区域。
extends Node

const MAP_SIZE := Vector2(1603.0, 1004.0)
const RESIZED_MAP_SIZE := Vector2(1920.0, 1080.0)
const ASIA_MASK_PATH := "res://assets/ui/world-map/mask_asia.png"
const TEST_REGIONS: Array[String] = ["北美", "南美", "非洲", "亚洲", "大洋洲"]
const SITUATION_PATHS: Array[String] = [
	"res://data/situations/emergency_communication_congestion.tres",
	"res://data/situations/regional_power_instability.tres",
	"res://data/situations/underground_life_support_fault.tres",
]

var _failed: int = 0
var _world_map: Control
var _selected_region: String = ""


func _ready() -> void:
	var world_map_script := ResourceLoader.load(
		"res://scripts/ui/world_map_view.gd",
		"GDScript",
		ResourceLoader.CACHE_MODE_IGNORE
	) as GDScript
	_assert_true(world_map_script != null, "WorldMapView 脚本应能强制加载当前磁盘版本")

	_world_map = Control.new()
	_world_map.set_script(world_map_script)
	_world_map.size = MAP_SIZE
	add_child(_world_map)
	await get_tree().process_frame

	_assert_true(_world_map != null, "WorldMapView 应能正常实例化")
	_assert_true(_world_map.has_signal("region_selected"), "应保留 region_selected 信号")
	_assert_true(_world_map.has_method("set_region_states"), "应保留 set_region_states")
	_assert_true(_world_map.has_method("set_selected_region"), "应保留 set_selected_region")
	_assert_true(_world_map.has_method("get_region_names"), "应保留 get_region_names")

	_assert_region_names()
	_assert_situation_targets_have_map_warnings()
	_assert_clear_asset_names()
	_assert_masks_loaded()
	_assert_editor_preview_contract(world_map_script)
	_assert_mask_hit_testing()
	await _assert_resized_map_hit_testing()
	_assert_selection_signal()
	_assert_main_scene_loads()
	await _assert_blank_map_click_deselects_main_scene()

	print("[WORLD-MAP-TEST] 完成，失败断言：%d" % _failed)
	get_tree().quit(_failed)


func _assert_region_names() -> void:
	var names: Array = _world_map.call("get_region_names")
	_assert_eq(names.size(), TEST_REGIONS.size(), "get_region_names 应只返回五个可点击区域")
	for region_name in TEST_REGIONS:
		_assert_true(region_name in names, "应包含可点击区域：%s" % region_name)


func _assert_situation_targets_have_map_warnings() -> void:
	var names: Array = _world_map.call("get_region_names")
	for path in SITUATION_PATHS:
		var data := load(path) as SituationData
		_assert_true(data != null, "地图警示测试应能加载局势：%s" % path)
		if data == null:
			continue
		for region_name in data.eligible_regions:
			var map_region := "亚洲" if region_name == "俄罗斯" else region_name
			_assert_true(
				map_region in names,
				"%s 的合法目标 %s 应能映射到地图警示" % [data.title, region_name]
			)


func _assert_clear_asset_names() -> void:
	_assert_true(FileAccess.file_exists(ASIA_MASK_PATH), "亚洲遮罩应使用清晰文件名 mask_asia.png")


func _assert_masks_loaded() -> void:
	var mask_images_variant: Variant = _world_map.get("_mask_images")
	_assert_true(mask_images_variant is Dictionary, "应缓存遮罩 Image 字典")
	if not mask_images_variant is Dictionary:
		return

	var mask_images: Dictionary = mask_images_variant
	for region_name in TEST_REGIONS:
		var image: Image = mask_images.get(region_name)
		_assert_true(image != null and not image.is_empty(), "%s 遮罩应加载为 Image" % region_name)


func _assert_editor_preview_contract(world_map_script: GDScript) -> void:
	_assert_true(world_map_script.is_tool(), "WorldMapView 应为 @tool 脚本以便编辑器直接绘制")
	for property_name in [
		"north_america_label_position",
		"south_america_label_position",
		"africa_label_position",
		"asia_label_position",
		"oceania_label_position",
	]:
		_assert_true(_world_map.get(property_name) is Vector2, "%s 应作为可调标签坐标导出" % property_name)
	_assert_true(_world_map.has_method("_load_editor_preview_states"), "应提供编辑器预览区域数据加载方法")
	if _world_map.has_method("_load_editor_preview_states"):
		_world_map.call("_load_editor_preview_states")
		var states: Dictionary = _world_map.get("_region_states")
		_assert_eq(states.size(), TEST_REGIONS.size(), "编辑器预览应加载五个区域状态")


func _assert_mask_hit_testing() -> void:
	_assert_region_at(Vector2(860.0, 470.0), "", "透明海洋不应命中区域")
	_assert_region_at(Vector2(358.0, 159.0), "", "欧洲参考层不应命中区域")
	_assert_region_at(Vector2(734.0, 951.0), "", "南极洲参考层不应命中区域")
	_assert_region_at(Vector2(260.0, 455.0), "非洲", "非洲代表点应命中非洲")
	_assert_region_at(Vector2(1195.0, 177.0), "北美", "北美代表点应命中北美")
	_assert_region_at(Vector2(575.0, 255.0), "亚洲", "亚洲代表点应命中亚洲")
	_assert_region_at(Vector2(600.0, 150.0), "亚洲", "俄罗斯所在遮罩应返回亚洲")


func _assert_resized_map_hit_testing() -> void:
	_world_map.size = RESIZED_MAP_SIZE
	await get_tree().process_frame

	var map_rect: Rect2 = _world_map.call("_get_map_rect")
	_assert_true(map_rect.position.x > 0.0, "1920×1080 下地图应水平居中并保留侧边空白")
	_assert_true(is_equal_approx(map_rect.size.y, RESIZED_MAP_SIZE.y), "1920×1080 下地图应按高度等比缩放")
	_assert_eq(
		_world_map.call("_region_at_position", _map_pixel_to_control(Vector2(575.0, 255.0))),
		"亚洲",
		"缩放后亚洲代表点仍应命中亚洲"
	)
	_assert_eq(
		_world_map.call(
			"_region_at_position",
			Vector2(map_rect.position.x - 12.0, map_rect.size.y * 0.5)
		),
		"",
		"缩放留白区不应命中区域"
	)

	_world_map.size = MAP_SIZE
	await get_tree().process_frame


func _assert_selection_signal() -> void:
	_world_map.connect("region_selected", _on_region_selected)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(575.0, 255.0)
	_world_map.call("_gui_input", click)
	_assert_eq(_selected_region, "亚洲", "点击亚洲遮罩应发出 region_selected('亚洲')")

	click.position = Vector2(860.0, 470.0)
	_world_map.call("_gui_input", click)
	_assert_eq(_selected_region, "", "点击地图海洋或空白处应发出空区域用于取消选中")


func _assert_main_scene_loads() -> void:
	var scene := load("res://scenes/main_os.tscn") as PackedScene
	_assert_true(scene != null, "main_os.tscn 应能正常加载")


func _assert_blank_map_click_deselects_main_scene() -> void:
	var scene := load("res://scenes/main_os.tscn") as PackedScene
	if scene == null:
		return

	var main_os := scene.instantiate() as Control
	add_child(main_os)
	await get_tree().process_frame

	if main_os.has_node("Timer"):
		var timer := main_os.get_node("Timer") as Timer
		timer.stop()

	var sectors: Array[Node] = main_os.get_node("%SectorInfoContainer").get_children()
	if sectors.is_empty():
		_assert_true(false, "主场景应存在区域卡片")
		main_os.queue_free()
		return

	var first_sector := sectors[0] as SectorInfo
	if first_sector == null:
		_assert_true(false, "主场景区域卡片应为 SectorInfo")
		main_os.queue_free()
		return

	main_os.call("select_sector", first_sector)
	await get_tree().process_frame
	_assert_eq(
		(main_os.get_node("%RegionNameLabel") as Label).text,
		first_sector.data_card.region_name,
		"主场景测试前应先选中一个区域"
	)

	var world_map := main_os.get_node("%WorldMapView") as WorldMapView
	world_map.region_selected.emit("")
	await get_tree().process_frame
	_assert_eq(
		(main_os.get_node("%RegionNameLabel") as Label).text,
		"未选择区域",
		"中央地图空白点击应取消主场景当前选区"
	)

	main_os.queue_free()


func _on_region_selected(region_name: String) -> void:
	_selected_region = region_name


func _map_pixel_to_control(pixel: Vector2) -> Vector2:
	var map_rect: Rect2 = _world_map.call("_get_map_rect")
	var uv := Vector2(pixel.x / MAP_SIZE.x, pixel.y / MAP_SIZE.y)
	return map_rect.position + Vector2(map_rect.size.x * uv.x, map_rect.size.y * uv.y)


func _assert_region_at(position: Vector2, expected: String, message: String) -> void:
	_assert_eq(_world_map.call("_region_at_position", position), expected, message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		print("[ OK ] " + message)
		return
	_failed += 1
	push_error("[FAIL] %s（期望=%s，实际=%s）" % [message, str(expected), str(actual)])


func _assert_true(value: bool, message: String) -> void:
	_assert_eq(value, true, message)
