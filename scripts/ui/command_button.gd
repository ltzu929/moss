## 指令按钮组件 - 显示单个MOSS指令按钮
## 负责按钮状态更新和点击响应
class_name CommandButton
extends Button

# ============================================================
# 区域一：信号定义
# ============================================================

## 按钮被点击时发出，携带指令数据
signal command_pressed(cmd: CommandData)

# ============================================================
# 区域二：状态变量
# ============================================================

## 关联的指令数据
var command_data: CommandData = null

## 引用main_os的冷却字典（由main_os设置）
var cooldowns_ref: Dictionary = {}

## 当前算力值（由main_os设置）
var current_cpu: int = 0

## 当前能源值（由main_os设置）
var current_energy: int = 0

## 是否有选中板块（由main_os设置）
var has_selected_sector: bool = false

# ============================================================
# 区域三：生命周期函数
# ============================================================

func _ready() -> void:
	if command_data != null:
		text = command_data.command_name
		update_state()

# ============================================================
# 区域四：状态更新
# ============================================================

## 更新按钮可用状态和tooltip
func update_state() -> void:
	if command_data == null:
		return

	# 检查选中状态
	if not has_selected_sector:
		disabled = true
		tooltip_text = "请先选择板块"
		return

	# 检查冷却
	var cooldown: int = cooldowns_ref.get(command_data.command_name, 0)
	if cooldown > 0:
		disabled = true
		tooltip_text = "冷却中（剩余%d年）" % cooldown
		return

	# 检查算力
	if current_cpu < command_data.cpu_cost:
		disabled = true
		tooltip_text = "算力不足（需要%d）" % command_data.cpu_cost
		return

	# 检查能源
	if current_energy < command_data.energy_cost:
		disabled = true
		tooltip_text = "能源不足（需要%d）" % command_data.energy_cost
		return

	# 可用状态
	disabled = false
	if command_data.energy_cost > 0:
		tooltip_text = "消耗: %d算力 %d能源" % [command_data.cpu_cost, command_data.energy_cost]
	else:
		tooltip_text = "消耗: %d算力" % command_data.cpu_cost

# ============================================================
# 区域五：点击响应
# ============================================================

func _pressed() -> void:
	if command_data != null and not disabled:
		command_pressed.emit(command_data)

# ============================================================
# 区域六：配置函数
# ============================================================

## 设置指令数据（创建时调用）
func setup(cmd: CommandData) -> void:
	command_data = cmd
	text = cmd.command_name