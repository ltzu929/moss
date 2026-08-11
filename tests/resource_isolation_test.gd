## 运行态 Resource 隔离测试
extends "res://tests/support/moss_test_case.gd"

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")



func _ready() -> void:
	var sector_template := load("res://data/sector_asia.tres") as SectorData
	var command_template := load("res://data/commands/command_takeover.tres") as CommandData
	var template_order := sector_template.order
	var template_cpu_cost := command_template.cpu_cost

	var first := MAIN_SCENE.instantiate()
	var second := MAIN_SCENE.instantiate()
	add_child(first)
	add_child(second)
	await get_tree().process_frame
	first.get_node("Timer").stop()
	second.get_node("Timer").stop()

	var first_workspace := first.get_node("MainLayout/StrategicWorkspace") as StrategicWorkspace
	var second_workspace := second.get_node("MainLayout/StrategicWorkspace") as StrategicWorkspace
	var first_sector := first_workspace.get_sector_by_region_id("asia")
	var second_sector := second_workspace.get_sector_by_region_id("asia")
	_assert_true(first_sector.data_card != second_sector.data_card, "两个主场景不得共享区域运行态")
	first_sector.data_card.order = 1
	_assert_eq(second_sector.data_card.order, template_order, "修改一个场景不得污染另一个区域")
	_assert_eq(sector_template.order, template_order, "修改运行态不得污染区域 .tres 模板")

	var first_command: CommandData = first._get_command_by_id("takeover")
	var second_command: CommandData = second._get_command_by_id("takeover")
	_assert_true(first_command != second_command, "两个主场景不得共享指令运行态")
	first_command.cpu_cost = 1
	_assert_eq(second_command.cpu_cost, template_cpu_cost, "修改一个场景不得污染另一个指令")
	_assert_eq(command_template.cpu_cost, template_cpu_cost, "修改运行态不得污染指令 .tres 模板")

	print("[MOSS-RESOURCE-ISOLATION] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)
