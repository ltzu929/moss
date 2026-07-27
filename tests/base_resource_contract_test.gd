## 基础资源与主场景装配契约
## 验证六个区域和两条基础指令使用真实 .tres，并以独立运行态装配进主场景
extends Node

const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")
const SECTOR_SPECS: Dictionary = {
	"SectorInfoAsia": ["res://data/sector_asia.tres", "亚洲"],
	"SectorInfoNa": ["res://data/sector_na.tres", "北美"],
	"SectorInfoEurope": ["res://data/sector_europe.tres", "欧洲"],
	"SectorInfoAfrica": ["res://data/sector_africa.tres", "非洲"],
	"SectorInfoOceania": ["res://data/sector_oceania.tres", "大洋洲"],
	"SectorInfoSouthAmerica": ["res://data/sector_south_america.tres", "南美"],
}
const COMMAND_SPECS: Dictionary = {
	"allocate": {
		"path": "res://data/commands/command_allocate.tres",
		"name": "算力分配",
		"cpu_cost": 20,
		"energy_cost": 0,
		"order_delta": 15,
		"hope_delta": 15,
		"authority_delta": 0,
		"cooldown_years": 3,
		"is_allocate_type": true,
	},
	"takeover": {
		"path": "res://data/commands/command_takeover.tres",
		"name": "系统接管",
		"cpu_cost": 30,
		"energy_cost": 20,
		"order_delta": 0,
		"hope_delta": 0,
		"authority_delta": 10,
		"cooldown_years": 5,
		"is_allocate_type": false,
	},
}

var _failed: int = 0


func _ready() -> void:
	var main_os := MAIN_SCENE.instantiate()
	add_child(main_os)
	await get_tree().process_frame
	main_os.get_node("Timer").stop()

	_assert_sector_contracts(main_os)
	_assert_command_contracts(main_os)

	print("[MOSS-BASE-RESOURCES] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_sector_contracts(main_os: Control) -> void:
	var sector_container := main_os.get_node_or_null("%SectorInfoContainer") as GridContainer
	_assert_true(sector_container != null, "主场景应装配区域卡片容器")
	if sector_container == null:
		return

	var expected_node_names: Array[String] = []
	for node_name in SECTOR_SPECS:
		expected_node_names.append(str(node_name))
	expected_node_names.sort()

	var actual_node_names: Array[String] = []
	for child in sector_container.get_children():
		_assert_true(child is SectorInfo, "区域容器子节点必须全部为 SectorInfo：%s" % child.name)
		actual_node_names.append(str(child.name))
	actual_node_names.sort()
	_assert_eq(sector_container.get_child_count(), 6, "区域容器应恰好装配六张区域卡")
	_assert_eq(actual_node_names, expected_node_names, "区域容器子节点集合应与资源契约完全一致")

	var actual_names: Array[String] = []
	for node_name in SECTOR_SPECS:
		var spec: Array = SECTOR_SPECS[node_name]
		var resource_path: String = spec[0]
		var expected_name: String = spec[1]
		var template := load(resource_path) as SectorData
		_assert_true(template != null, "区域资源应能加载：%s" % resource_path)
		if template == null:
			continue

		_assert_eq(template.region_name, expected_name, "%s 应使用约定区域名" % resource_path)
		_assert_true(not template.description.is_empty(), "%s 描述不得为空" % resource_path)
		_assert_between(template.order, 0, 100, "%s 秩序应在 0 到 100" % resource_path)
		_assert_between(template.hope, 0, 100, "%s 希望应在 0 到 100" % resource_path)
		_assert_between(template.authority, 0, 100, "%s 控制权应在 0 到 100" % resource_path)
		_assert_true(template.population > 0, "%s 人口应为正数" % resource_path)
		actual_names.append(template.region_name)

		var sector_info := main_os.get_node_or_null("%" + node_name) as SectorInfo
		_assert_true(sector_info != null, "主场景应装配区域节点：%%%s" % node_name)
		if sector_info == null:
			continue
		_assert_true(
			sector_info.get_parent() == sector_container,
			"%s 必须直接装配在 %%SectorInfoContainer 下" % node_name
		)
		_assert_true(sector_info.data_card != template, "%s 运行态不得复用 .tres 模板" % expected_name)
		_assert_sector_values_equal(
			sector_info.data_card,
			template,
			"%s 主场景运行态应复制真实资源" % expected_name
		)

	var unique_names := {}
	for region_name in actual_names:
		unique_names[region_name] = true
	_assert_eq(actual_names.size(), 6, "应加载六个区域资源")
	_assert_eq(unique_names.size(), 6, "六个区域名称不得重复")


func _assert_command_contracts(main_os: Control) -> void:
	var command_files := DirAccess.get_files_at("res://data/commands/")
	var tres_count := 0
	for file_name in command_files:
		if file_name.ends_with(".tres"):
			tres_count += 1
	_assert_eq(tres_count, COMMAND_SPECS.size(), "基础指令目录应只包含两条已登记指令")
	_assert_eq(main_os.available_commands.size(), COMMAND_SPECS.size(), "主场景应加载两条基础指令")

	for command_id in COMMAND_SPECS:
		var spec: Dictionary = COMMAND_SPECS[command_id]
		var resource_path := str(spec["path"])
		var template := load(resource_path) as CommandData
		_assert_true(template != null, "指令资源应能加载：%s" % resource_path)
		if template == null:
			continue

		_assert_command_values(template, command_id, spec, "真实资源")
		var runtime_command: CommandData = main_os._get_command_by_id(command_id)
		_assert_true(runtime_command != null, "主场景应按稳定 ID 加载指令：%s" % command_id)
		if runtime_command == null:
			continue
		_assert_true(runtime_command != template, "%s 运行态不得复用 .tres 模板" % command_id)
		_assert_command_values(runtime_command, command_id, spec, "主场景运行态")
		_assert_true(main_os.command_cooldowns.has(command_id), "%s 应创建运行态冷却键" % command_id)
		_assert_eq(main_os.command_cooldowns.get(command_id), 0, "%s 初始冷却应为 0" % command_id)


func _assert_command_values(
	command: CommandData,
	command_id: String,
	spec: Dictionary,
	source_name: String
) -> void:
	var prefix := "%s %s" % [source_name, command_id]
	_assert_eq(command.command_id, command_id, "%s 稳定 ID 应匹配" % prefix)
	_assert_eq(command.command_name, spec["name"], "%s 名称应匹配数值设计" % prefix)
	_assert_eq(command.cpu_cost, spec["cpu_cost"], "%s 算力消耗应匹配数值设计" % prefix)
	_assert_eq(command.energy_cost, spec["energy_cost"], "%s 能源消耗应匹配数值设计" % prefix)
	_assert_eq(command.order_delta, spec["order_delta"], "%s 秩序效果应匹配数值设计" % prefix)
	_assert_eq(command.hope_delta, spec["hope_delta"], "%s 希望效果应匹配数值设计" % prefix)
	_assert_eq(
		command.authority_delta,
		spec["authority_delta"],
		"%s 控制权效果应匹配数值设计" % prefix
	)
	_assert_eq(
		command.cooldown_years,
		spec["cooldown_years"],
		"%s 基础冷却应匹配数值设计" % prefix
	)
	_assert_eq(
		command.is_allocate_type,
		spec["is_allocate_type"],
		"%s 指令类型应匹配" % prefix
	)


func _assert_sector_values_equal(
	actual: SectorData,
	expected: SectorData,
	message: String
) -> void:
	_assert_true(actual != null, "%s，运行态资源不得为空" % message)
	if actual == null:
		return
	_assert_eq(actual.region_name, expected.region_name, "%s：区域名" % message)
	_assert_eq(actual.description, expected.description, "%s：描述" % message)
	_assert_eq(actual.order, expected.order, "%s：秩序" % message)
	_assert_eq(actual.hope, expected.hope, "%s：希望" % message)
	_assert_eq(actual.authority, expected.authority, "%s：控制权" % message)
	_assert_eq(actual.population, expected.population, "%s：人口" % message)
	_assert_eq(actual.is_locked, expected.is_locked, "%s：封锁状态" % message)


func _assert_between(actual: int, minimum: int, maximum: int, message: String) -> void:
	_assert_true(
		actual >= minimum and actual <= maximum,
		"%s（范围=%d..%d，实际=%d）" % [message, minimum, maximum, actual]
	)


func _assert_true(value: bool, message: String) -> void:
	if value:
		print("[ OK ] " + message)
		return
	_failed += 1
	push_error("[FAIL] " + message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_assert_true(
		actual == expected,
		"%s（期望=%s，实际=%s）" % [message, str(expected), str(actual)]
	)
