## 指令领域服务
## 负责指令配置、可用性、执行结算和数值效果，不依赖场景树或 UI
class_name CommandSystem
extends RefCounted

# ============================================================
# 常量
# ============================================================

## 稳定指令 ID
const COMMAND_ALLOCATE: String = "allocate"
const COMMAND_TAKEOVER: String = "takeover"
const COMMAND_ENERGY_CONVERT: String = "energy_convert"
const COMMAND_GLOBAL_TAKEOVER: String = "global_takeover"
const COMMAND_TECHNOLOGY_AID: String = "technology_aid"

# ============================================================
# 指令查询
# ============================================================

## 判断稳定指令 ID 是否已经存在于指令列表
func has_command_id(commands: Array[CommandData], command_id: String) -> bool:
	return get_command_by_id(commands, command_id) != null


## 根据稳定指令 ID 查找指令；不存在时返回 null
func get_command_by_id(commands: Array[CommandData], command_id: String) -> CommandData:
	for cmd in commands:
		if cmd.command_id == command_id:
			return cmd
	return null


## 判断算力分配是否已开放综合调度选项
func can_allocate_combined(technology: TechnologySystem) -> bool:
	return technology.has_tag("managed_decision")


## 判断指令执行前是否必须选中目标板块
func command_requires_selected_sector(cmd: CommandData) -> bool:
	return cmd.command_id not in [
		COMMAND_ENERGY_CONVERT,
		COMMAND_GLOBAL_TAKEOVER,
	]

# ============================================================
# 科技指令配置
# ============================================================

## 同步科技解锁的运行时指令，并重置/覆盖指令参数
func refresh_command_configuration(
	commands: Array[CommandData],
	cooldowns: Dictionary,
	technology: TechnologySystem
) -> void:
	_sync_command_unlock(
		commands,
		cooldowns,
		COMMAND_ENERGY_CONVERT,
		technology.has_tag("unlock_energy_convert")
	)
	_sync_command_unlock(
		commands,
		cooldowns,
		COMMAND_GLOBAL_TAKEOVER,
		technology.has_tag("unlock_global_takeover")
	)
	_sync_command_unlock(
		commands,
		cooldowns,
		COMMAND_TECHNOLOGY_AID,
		technology.has_tag("unlock_technology_aid")
	)
	_reset_command_values(commands, technology)


## 按科技解锁状态添加或移除指定运行时指令
func _sync_command_unlock(
	commands: Array[CommandData],
	cooldowns: Dictionary,
	command_id: String,
	should_exist: bool
) -> void:
	if should_exist and not has_command_id(commands, command_id):
		var cmd := _create_technology_command(command_id)
		if cmd != null:
			commands.append(cmd)
			cooldowns[command_id] = 0
	elif not should_exist and has_command_id(commands, command_id):
		for index in range(commands.size() - 1, -1, -1):
			if commands[index].command_id == command_id:
				commands.remove_at(index)
				cooldowns.erase(command_id)


## 根据稳定指令 ID 创建科技解锁的运行时指令数据
func _create_technology_command(command_id: String) -> CommandData:
	var cmd := CommandData.new()
	cmd.command_id = command_id
	match command_id:
		COMMAND_ENERGY_CONVERT:
			cmd.command_name = "能源转换"
			cmd.description = "消耗20能源，将其转换为算力"
			cmd.energy_cost = 20
			cmd.cooldown_years = 2
		COMMAND_GLOBAL_TAKEOVER:
			cmd.command_name = "全局接管"
			cmd.description = "对全部区域执行统一接管"
			cmd.cpu_cost = 30
			cmd.energy_cost = 10
			cmd.cooldown_years = 5
		COMMAND_TECHNOLOGY_AID:
			cmd.command_name = "技术援助"
			cmd.description = "向区域开放技术，提高自治能力并降低MOSS控制"
			cmd.cpu_cost = 20
			cmd.energy_cost = 10
			cmd.order_delta = 10
			cmd.hope_delta = 10
			cmd.authority_delta = -3
			cmd.cooldown_years = 4
		_:
			return null
	return cmd


## 将基础指令恢复为默认数值，再应用科技标签提供的覆盖效果
func _reset_command_values(
	commands: Array[CommandData],
	technology: TechnologySystem
) -> void:
	var allocate := get_command_by_id(commands, COMMAND_ALLOCATE)
	if allocate != null:
		allocate.cpu_cost = 20
		allocate.order_delta = 15
		allocate.hope_delta = 15
		allocate.authority_delta = 0
		allocate.set_meta("combined_enabled", can_allocate_combined(technology))

	var takeover := get_command_by_id(commands, COMMAND_TAKEOVER)
	if takeover != null:
		takeover.cpu_cost = 30
		takeover.energy_cost = 20
		takeover.authority_delta = 10
		takeover.hope_delta = 0
		takeover.cooldown_years = 5
		if technology.has_tag("managed_infrastructure"):
			takeover.cpu_cost = 25
			takeover.energy_cost = 15
			takeover.authority_delta = 15
			takeover.hope_delta = -5
		if technology.has_tag("managed_takeover_cooldown"):
			takeover.cooldown_years = 4
		if technology.has_tag("managed_command_energy_discount"):
			takeover.energy_cost = maxi(0, takeover.energy_cost - 5)
		if technology.has_tag("managed_consensual_core"):
			takeover.authority_delta = 12
			takeover.hope_delta = 0

	var energy_convert := get_command_by_id(commands, COMMAND_ENERGY_CONVERT)
	if energy_convert != null:
		energy_convert.energy_cost = 20
		energy_convert.cooldown_years = 2
		if technology.has_tag("energy_convert_efficiency"):
			energy_convert.energy_cost = 15
			energy_convert.cooldown_years = 1

	var global_takeover := get_command_by_id(commands, COMMAND_GLOBAL_TAKEOVER)
	if global_takeover != null:
		global_takeover.cpu_cost = 30
		global_takeover.energy_cost = 10
		global_takeover.cooldown_years = 5
		if technology.has_tag("managed_command_energy_discount"):
			global_takeover.energy_cost = 5

	var technology_aid := get_command_by_id(commands, COMMAND_TECHNOLOGY_AID)
	if technology_aid != null:
		technology_aid.cpu_cost = 20
		technology_aid.energy_cost = 10
		technology_aid.order_delta = 10
		technology_aid.hope_delta = 10
		technology_aid.authority_delta = -3
		technology_aid.cooldown_years = 4
		if technology.has_tag("human_mutual_aid"):
			technology_aid.cpu_cost = 15
			technology_aid.energy_cost = 5
			technology_aid.order_delta = 12
			technology_aid.hope_delta = 12
			technology_aid.authority_delta = -4
		if technology.has_tag("human_collaborative_core"):
			technology_aid.cpu_cost = 10
			technology_aid.energy_cost = 5
			technology_aid.order_delta = 15
			technology_aid.hope_delta = 15
			technology_aid.authority_delta = -5
			technology_aid.cooldown_years = 2

# ============================================================
# 可用性与执行结算
# ============================================================

## 每月更新冷却状态，最小保持为 0
func update_cooldowns(cooldowns: Dictionary) -> void:
	for command_id in cooldowns.keys():
		if cooldowns[command_id] > 0:
			cooldowns[command_id] -= 1


## 检查指令是否可用
func is_command_available(
	cmd: CommandData,
	current_cpu: int,
	current_energy: int,
	has_selected_sector: bool,
	cooldowns: Dictionary
) -> bool:
	return get_command_unavailable_reason(
		cmd,
		current_cpu,
		current_energy,
		has_selected_sector,
		cooldowns
	).is_empty()


## 获取指令不可用原因；可用时返回空字符串
func get_command_unavailable_reason(
	cmd: CommandData,
	current_cpu: int,
	current_energy: int,
	has_selected_sector: bool,
	cooldowns: Dictionary
) -> String:
	if command_requires_selected_sector(cmd) and not has_selected_sector:
		return "请先选择板块"

	var cooldown: int = cooldowns.get(cmd.command_id, 0)
	if cooldown > 0:
		return "冷却中（剩余%s）" % format_cooldown_months(cooldown)

	if current_cpu < cmd.cpu_cost:
		return "算力不足（需要%d）" % cmd.cpu_cost

	if current_energy < cmd.energy_cost:
		return "能源不足（需要%d）" % cmd.energy_cost

	return ""


## 执行指令结算，返回新资源、冷却和失败原因
func execute_command(
	cmd: CommandData,
	current_cpu: int,
	current_energy: int,
	has_selected_sector: bool,
	cooldown_reduction: int,
	cooldowns: Dictionary
) -> Dictionary:
	var reason := get_command_unavailable_reason(
		cmd,
		current_cpu,
		current_energy,
		has_selected_sector,
		cooldowns
	)
	if not reason.is_empty():
		return {
			"success": false,
			"new_cpu": current_cpu,
			"new_energy": current_energy,
			"applied_cooldown": 0,
			"unavailable_reason": reason,
		}

	var adjusted_cooldown := maxi(0, cmd.cooldown_years - cooldown_reduction) * 12
	cooldowns[cmd.command_id] = adjusted_cooldown
	return {
		"success": true,
		"new_cpu": current_cpu - cmd.cpu_cost,
		"new_energy": current_energy - cmd.energy_cost,
		"applied_cooldown": adjusted_cooldown,
		"unavailable_reason": "",
	}


## 生成指令消耗提示文本
func get_command_cost_text(cmd: CommandData) -> String:
	if cmd.energy_cost > 0:
		return "消耗: %d算力 %d能源" % [cmd.cpu_cost, cmd.energy_cost]
	return "消耗: %d算力" % cmd.cpu_cost


## 将运行态月冷却格式化为玩家可读文本
func format_cooldown_months(cooldown_months: int) -> String:
	var years := floori(float(cooldown_months) / 12.0)
	var months := cooldown_months % 12
	if years > 0 and months > 0:
		return "%d年%d个月" % [years, months]
	if years > 0:
		return "%d年" % years
	return "%d个月" % months

# ============================================================
# 指令效果
# ============================================================

## 应用需要目标区域的指令效果，返回变化日志行
func apply_targeted_command(
	cmd: CommandData,
	sector_data: SectorData,
	effect_type: String,
	has_public_decision: bool,
	combined_enabled: bool
) -> Array[String]:
	var lines: Array[String] = []
	var changed := false

	if cmd.is_allocate_type:
		if effect_type == "order":
			sector_data.order += cmd.order_delta
			_append_signed_change(lines, "秩序", cmd.order_delta)
			changed = true
			if has_public_decision:
				sector_data.hope += 5
				sector_data.authority -= 1
				_append_signed_change(lines, "希望", 5)
				_append_signed_change(lines, "控制权", -1)
		elif effect_type == "hope":
			sector_data.hope += cmd.hope_delta
			_append_signed_change(lines, "希望", cmd.hope_delta)
			changed = true
			if has_public_decision:
				sector_data.order += 5
				sector_data.authority -= 1
				_append_signed_change(lines, "秩序", 5)
				_append_signed_change(lines, "控制权", -1)
		elif effect_type == "combined" and combined_enabled:
			sector_data.order += 10
			sector_data.hope += 10
			sector_data.authority += 2
			_append_signed_change(lines, "秩序", 10)
			_append_signed_change(lines, "希望", 10)
			_append_signed_change(lines, "控制权", 2)
			changed = true
	else:
		sector_data.order += cmd.order_delta
		sector_data.hope += cmd.hope_delta
		sector_data.authority += cmd.authority_delta
		_append_signed_change(lines, "秩序", cmd.order_delta)
		_append_signed_change(lines, "希望", cmd.hope_delta)
		_append_signed_change(lines, "控制权", cmd.authority_delta)
		changed = true

	if changed:
		sector_data.clamp_values()
	return lines


## 应用能源转换效果，返回新算力和实际增长日志
func apply_energy_convert(
	current_cpu: int,
	max_cpu: int,
	technology: TechnologySystem
) -> Dictionary:
	var gain := 15 if technology.has_tag("core_recursive") else 10
	var new_cpu := mini(current_cpu + gain, max_cpu)
	var actual_gain := new_cpu - current_cpu
	var lines: Array[String] = []
	_append_signed_change(lines, "算力", actual_gain)
	return {
		"new_cpu": new_cpu,
		"actual_gain": actual_gain,
		"lines": lines,
	}


## 应用全局接管效果，返回影响区域数量和日志行
func apply_global_takeover(
	sector_data_list: Array[SectorData],
	technology: TechnologySystem
) -> Dictionary:
	var affected_count := 0
	var authority_gain := 5
	var order_gain := 0
	var hope_change := 0
	if technology.has_tag("managed_consensual_core"):
		authority_gain = 6
		order_gain = 3
	elif technology.has_tag("managed_core"):
		authority_gain = 8
		order_gain = 5
		hope_change = -5

	for sector_data in sector_data_list:
		sector_data.authority += authority_gain
		sector_data.order += order_gain
		sector_data.hope += hope_change
		sector_data.clamp_values()
		affected_count += 1

	var lines: Array[String] = [
		"影响板块：全区域（%d）" % affected_count,
		"每个区域 控制权 +%d" % authority_gain,
	]
	if order_gain != 0 or hope_change != 0:
		lines.append("每个区域 秩序 %+d / 希望 %+d" % [order_gain, hope_change])

	return {
		"affected_count": affected_count,
		"lines": lines,
	}


## 将非零变化追加为带符号日志
func _append_signed_change(lines: Array[String], label: String, delta: int) -> void:
	if delta == 0:
		return

	var prefix := "+" if delta > 0 else ""
	lines.append("%s %s%d" % [label, prefix, delta])
