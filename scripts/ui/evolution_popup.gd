class_name EvolutionPopup
extends PanelContainer

# ============================================================
# 信号定义
# ============================================================

## 购买请求信号
signal purchase_requested(evolution: EvolutionData)

## 弹窗关闭信号
signal popup_closed()

# ============================================================
# 成员变量
# ============================================================

## 当前算力（从main_os传入）
var current_cpu: int = 0

## 当前能源（从main_os传入）
var current_energy: int = 0

## 已解锁被动能力引用（从main_os传入）
var unlocked_passives_ref: Array[String] = []

## 已解锁指令引用（从main_os传入）
var unlocked_commands_ref: Array[String] = []

## 所有进化能力引用（从main_os传入）
var all_evolutions_ref: Array[EvolutionData] = []

# ============================================================
# 生命周期函数
# ============================================================

func _ready() -> void:
	hide()

# ============================================================
# 公共函数
# ============================================================

## 显示进化弹窗
## 参数: level - 当前进化等级
##       cpu - 当前算力
##       energy - 当前能源
func show_popup(level: int, cpu: int, energy: int) -> void:
	current_cpu = cpu
	current_energy = energy

	# 更新等级显示
	var names := ["初始", "进化", "终极"]
	$VBoxContainer/LevelLabel.text = "形态: " + names[level - 1]

	# 更新被动能力列表
	var txt := ""
	for e in all_evolutions_ref:
		if e.is_passive and e.ability_id in unlocked_passives_ref:
			txt += "✓ " + e.ability_name + "\n"
	if txt == "":
		txt = "暂无"
	$VBoxContainer/PassivesList.text = txt

	# 清空并重建购买按钮列表
	var purchase_container: VBoxContainer = $VBoxContainer/PurchaseContainer
	for c in purchase_container.get_children():
		c.queue_free()

	for e in all_evolutions_ref:
		# 跳过被动能力（自动解锁）
		if e.is_passive:
			continue
		# 跳过已解锁的指令
		if e.ability_id in unlocked_commands_ref:
			continue

		# 创建购买按钮
		var btn := Button.new()
		var cost_parts: Array[String] = []
		if e.purchase_cpu_cost > 0:
			cost_parts.append(str(e.purchase_cpu_cost) + "算力")
		if e.purchase_energy_cost > 0:
			cost_parts.append(str(e.purchase_energy_cost) + "能源")

		var cost_text := "免费"
		if not cost_parts.is_empty():
			cost_text = " / ".join(cost_parts)

		btn.text = "解锁指令：" + e.ability_name + " (" + cost_text + ")"
		btn.disabled = current_cpu < e.purchase_cpu_cost or current_energy < e.purchase_energy_cost
		btn.tooltip_text = e.description
		btn.pressed.connect(func(): purchase_requested.emit(e))
		purchase_container.add_child(btn)

	show()

# ============================================================
# 回调函数
# ============================================================

## 关闭按钮点击回调
func _on_close_pressed() -> void:
	popup_closed.emit()
	hide()
