## 1920×1080 主界面运行时布局回归测试。
## 必须通过 display 模式运行，确保容器完成真实窗口尺寸下的布局计算。
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const EXPECTED_VIEWPORT_SIZE := Vector2(1920.0, 1080.0)



func _ready() -> void:
	var main_os := MAIN_SCENE.instantiate() as Control
	add_child(main_os)
	await get_tree().process_frame
	await get_tree().process_frame
	(main_os.get_node("Timer") as Timer).stop()

	_assert_runtime_geometry(main_os)
	await _assert_europe_selection_keeps_geometry(main_os)

	main_os.queue_free()
	print("[MOSS-UI-LAYOUT-1080P] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(_failed)


func _assert_runtime_geometry(main_os: Control) -> void:
	var viewport_size := main_os.get_viewport_rect().size
	_assert_true(
		viewport_size.is_equal_approx(EXPECTED_VIEWPORT_SIZE),
		"运行视口应为1920×1080，实际为%s" % viewport_size
	)

	var workspace := main_os.get_node("MainLayout/StrategicWorkspace") as StrategicWorkspace
	var world_map := workspace.get_world_map() as Control
	_assert_true(
		world_map.size.x >= 1300.0 and world_map.size.y >= 620.0,
		"世界地图应占据主要观察面积，实际为%s" % world_map.size
	)

	var main_layout := main_os.get_node("MainLayout") as Control
	var layout_rect := main_layout.get_global_rect()
	_assert_true(
		layout_rect.position.x >= 0.0 and layout_rect.position.y >= 0.0,
		"主布局不应越过视口左上边界，实际为%s" % layout_rect
	)
	_assert_true(
		layout_rect.end.x <= viewport_size.x and layout_rect.end.y <= viewport_size.y,
		"主布局不应越过视口右下边界，实际为%s" % layout_rect
	)


func _assert_europe_selection_keeps_geometry(main_os: Control) -> void:
	var workspace := main_os.get_node("MainLayout/StrategicWorkspace") as StrategicWorkspace
	var world_map := workspace.get_world_map()
	var before_content_rect := workspace.get_content_rect()
	var before_map_rect := workspace.get_world_map_rect()

	world_map.region_selected.emit("europe")
	await get_tree().process_frame
	await get_tree().process_frame

	_assert_true(
		workspace.get_region_name_text() == "欧洲",
		"点击欧洲后应选中欧洲板块"
	)
	_assert_true(
		workspace.get_content_rect().is_equal_approx(before_content_rect),
		"点击欧洲前后中央内容区几何应保持不变"
	)
	_assert_true(
		workspace.get_world_map_rect().is_equal_approx(before_map_rect),
		"点击欧洲前后世界地图几何应保持不变"
	)
	_assert_runtime_geometry(main_os)
