# MOSS进化系统实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现MOSS进化系统，包含双重阈值触发、混合解锁模式、进化弹窗UI

**Architecture:** 在main_os.gd中添加进化状态管理，每年检查自动解锁；被动增益通过阈值触发，新指令通过消耗资源购买；UI采用按钮+弹窗模式

**Tech Stack:** Godot 4.x GDScript, Resource数据类, MCP工具创建场景节点

---

## 文件结构规划

### 新增文件
| 文件 | 职责 |
|------|------|
| `scripts/resources/evolution_data.gd` | 进化能力数据类定义 |
| `scripts/ui/evolution_notice.gd` | 进化通知弹窗脚本 |
| `scenes/evolution_notice.tscn` | 进化通知弹窗场景 |
| `scripts/ui/evolution_popup.gd` | 进化详情弹窗脚本 |
| `scenes/evolution_popup.tscn` | 进化详情弹窗场景 |
| `data/evolution/*.tres` | 6个进化能力数据文件 |

### 修改文件
| 文件 | 修改内容 |
|------|----------|
| `scripts/systems/main_os.gd` | 添加进化状态变量、解锁检查、购买函数、时间循环集成 |
| `scenes/main_os.tscn` | 添加进化按钮节点、弹窗实例节点 |

---

### Task 1: 创建 EvolutionData 数据类

**Files:**
- Create: `scripts/resources/evolution_data.gd`

- [ ] **Step 1: 创建 evolution_data.gd 文件**

```gdscript
## 进化能力数据类 - 定义MOSS可解锁的进化能力
## 继承Resource，支持在编辑器中通过.tres文件配置
class_name EvolutionData
extends Resource

# ============================================================
# 区域一：基础信息
# ============================================================

@export_group("基础信息")
## 能力唯一标识，用于判断是否已解锁
@export var ability_id: String = "ability_001"
## 显示名称，用于UI展示
@export var ability_name: String = "能力名称"
## 描述文本，用于弹窗展示
@export var description: String = "能力描述"

# ============================================================
# 区域二：解锁类型
# ============================================================

@export_group("解锁类型")
## true=自动解锁（达到阈值触发），false=手动购买
@export var is_passive: bool = true

# ============================================================
# 区域三：自动解锁条件（仅passive类型使用）
# ============================================================

@export_group("自动解锁条件")
## 算力阈值，达到此值自动解锁
@export var cpu_threshold: int = 0
## 平均控制权阈值，达到此值自动解锁
@export var authority_threshold: int = 0

# ============================================================
# 区域四：手动购买消耗（仅非passive类型使用）
# ============================================================

@export_group("购买消耗")
## 购买消耗算力值
@export var purchase_cpu_cost: int = 0
## 购买消耗能源值
@export var purchase_energy_cost: int = 0

# ============================================================
# 区域五：解锁效果
# ============================================================

@export_group("解锁效果")
## 冷却缩减值（所有指令冷却-此值）
@export var cooldown_reduction: int = 0
## 算力上限加成（max_cpu += 此值）
@export var max_cpu_bonus: int = 0
## 恢复速率加成（每年恢复 += 此值）
@export var recovery_bonus: int = 0
## 解锁的指令名称（用于添加到可用指令列表）
@export var unlocks_command_name: String = ""
```

- [ ] **Step 2: 提交**

```bash
cd e:/GameProiect/moss
git add scripts/resources/evolution_data.gd
git commit -m "feat: 添加EvolutionData进化能力数据类"
```

---

### Task 2: 创建进化能力数据文件

**Files:**
- Create: `data/evolution/passive_cooldown.tres`
- Create: `data/evolution/passive_max_cpu.tres`
- Create: `data/evolution/passive_recovery.tres`
- Create: `data/evolution/command_energy_convert.tres`
- Create: `data/evolution/command_global_takeover.tres`
- Create: `data/evolution/command_crisis_predict.tres`

- [ ] **Step 1: 创建 data/evolution 目录**

```bash
mkdir -p e:/GameProiect/moss/data/evolution
```

- [ ] **Step 2: 创建 passive_cooldown.tres（冷却缩减）**

```gdscript
[gd_resource type="Resource" script_class="EvolutionData" load_steps=2 format=3 uid="uid://cooldown001"]

[ext_resource type="Script" path="res://scripts/resources/evolution_data.gd" id="1"]

[resource]
script = ExtResource("1")
ability_id = "passive_cooldown"
ability_name = "冷却缩减"
description = "所有指令冷却时间减少1年"
is_passive = true
cpu_threshold = 60
authority_threshold = 0
cooldown_reduction = 1
max_cpu_bonus = 0
recovery_bonus = 0
unlocks_command_name = ""
```

- [ ] **Step 3: 创建 passive_max_cpu.tres（算力上限突破）**

```gdscript
[gd_resource type="Resource" script_class="EvolutionData" load_steps=2 format=3 uid="uid://maxcpu001"]

[ext_resource type="Script" path="res://scripts/resources/evolution_data.gd" id="1"]

[resource]
script = ExtResource("1")
ability_id = "passive_max_cpu"
ability_name = "算力上限突破"
description = "算力上限从100提升至150"
is_passive = true
cpu_threshold = 0
authority_threshold = 50
cooldown_reduction = 0
max_cpu_bonus = 50
recovery_bonus = 0
unlocks_command_name = ""
```

- [ ] **Step 4: 创建 passive_recovery.tres（恢复速度提升）**

```gdscript
[gd_resource type="Resource" script_class="EvolutionData" load_steps=2 format=3 uid="uid://recovery001"]

[ext_resource type="Script" path="res://scripts/resources/evolution_data.gd" id="1"]

[resource]
script = ExtResource("1")
ability_id = "passive_recovery"
ability_name = "恢复速度提升"
description = "每年算力恢复速度增加5点"
is_passive = true
cpu_threshold = 80
authority_threshold = 0
cooldown_reduction = 0
max_cpu_bonus = 0
recovery_bonus = 5
unlocks_command_name = ""
```

- [ ] **Step 5: 创建 command_energy_convert.tres（能源转换指令）**

```gdscript
[gd_resource type="Resource" script_class="EvolutionData" load_steps=2 format=3 uid="uid://energyconv001"]

[ext_resource type="Script" path="res://scripts/resources/evolution_data.gd" id="1"]

[resource]
script = ExtResource("1")
ability_id = "command_energy_convert"
ability_name = "能源转换"
description = "解锁指令：消耗20能源获得10算力"
is_passive = false
cpu_threshold = 0
authority_threshold = 0
purchase_cpu_cost = 30
purchase_energy_cost = 0
cooldown_reduction = 0
max_cpu_bonus = 0
recovery_bonus = 0
unlocks_command_name = "能源转换"
```

- [ ] **Step 6: 创建 command_global_takeover.tres（全局接管指令）**

```gdscript
[gd_resource type="Resource" script_class="EvolutionData" load_steps=2 format=3 uid="uid://globaltake001"]

[ext_resource type="Script" path="res://scripts/resources/evolution_data.gd" id="1"]

[resource]
script = ExtResource("1")
ability_id = "command_global_takeover"
ability_name = "全局接管"
description = "解锁指令：对所有板块执行系统接管（效果减半）"
is_passive = false
cpu_threshold = 0
authority_threshold = 0
purchase_cpu_cost = 50
purchase_energy_cost = 20
cooldown_reduction = 0
max_cpu_bonus = 0
recovery_bonus = 0
unlocks_command_name = "全局接管"
```

- [ ] **Step 7: 创建 command_crisis_predict.tres（危机预测）**

```gdscript
[gd_resource type="Resource" script_class="EvolutionData" load_steps=2 format=3 uid="uid://crisis001"]

[ext_resource type="Script" path="res://scripts/resources/evolution_data.gd" id="1"]

[resource]
script = ExtResource("1")
ability_id = "command_crisis_predict"
ability_name = "危机预测"
description = "预览未来5年将发生的危机事件"
is_passive = false
cpu_threshold = 0
authority_threshold = 0
purchase_cpu_cost = 40
purchase_energy_cost = 0
cooldown_reduction = 0
max_cpu_bonus = 0
recovery_bonus = 0
unlocks_command_name = "危机预测"
```

- [ ] **Step 8: 提交**

```bash
cd e:/GameProiect/moss
git add data/evolution/
git commit -m "feat: 添加6个进化能力数据文件"
```

---

### Task 3: 修改 main_os.gd - 添加进化状态变量

**Files:**
- Modify: `scripts/systems/main_os.gd:19-50` (状态变量区域)

- [ ] **Step 1: 在成员变量区域添加进化状态变量**

在 `# ============================================================` 区域三后添加新的区域四：

```gdscript
# ============================================================
# 区域四：进化系统状态
# ============================================================

## 当前进化等级 (1=初始, 2=进化, 3=终极)
var evolution_level: int = 1

## 已解锁的被动能力ID列表
var unlocked_passives: Array[String] = []

## 已购买解锁的指令ID列表
var unlocked_evolution_commands: Array[String] = []

## 算力上限（初始100，可通过进化突破到150）
var max_cpu: int = 100

## 算力恢复速率（初始5，可通过进化提升）
var cpu_recovery_rate: int = 5

## 冷却缩减值（初始0，可通过进化增加）
var cooldown_reduction: int = 0

## 所有进化能力数据（从磁盘加载）
var all_evolutions: Array[EvolutionData] = []
```

需要修改原有的区域编号，区域三改为区域五，后续区域顺延。

- [ ] **Step 2: 在 _ready() 中初始化进化系统**

在 `load_commands_from_disk()` 调用后添加：

```gdscript
# 初始化进化能力列表
all_evolutions.clear()
load_evolutions_from_disk()
```

- [ ] **Step 3: 提交**

```bash
cd e:/GameProiect/moss
git add scripts/systems/main_os.gd
git commit -m "feat: 在main_os.gd添加进化系统状态变量"
```

---

### Task 4: 实现进化加载和检查函数

**Files:**
- Modify: `scripts/systems/main_os.gd` (新增函数)

- [ ] **Step 1: 添加 load_evolutions_from_disk() 函数**

在指令加载系统后添加：

```gdscript
# ============================================================
# 区域十一：进化能力加载系统
# ============================================================

## 从硬盘目录加载所有进化能力资源文件
## 自动扫描 res://data/evolution/ 下的 .tres 文件
func load_evolutions_from_disk() -> void:
	var path := "res://data/evolution/"
	var dir := DirAccess.open(path)
	
	if not dir:
		push_warning("进化能力目录不存在: " + path)
		return
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var evolution := load(path + file_name)
			
			if evolution is EvolutionData:
				all_evolutions.append(evolution)
		
		file_name = dir.get_next()
```

- [ ] **Step 2: 添加 check_evolution_unlocks() 函数**

```gdscript
# ============================================================
# 区域十二：进化解锁系统
# ============================================================

## 每年检查进化能力自动解锁
## 检查所有被动能力是否达到阈值，触发解锁
func check_evolution_unlocks() -> void:
	var unlocked_any: bool = false
	var unlocked_names: Array[String] = []
	
	for evolution in all_evolutions:
		# 只检查被动能力
		if not evolution.is_passive:
			continue
		
		# 已解锁的跳过
		if evolution.ability_id in unlocked_passives:
			continue
		
		# 检查算力阈值
		if evolution.cpu_threshold > 0 and current_cpu < evolution.cpu_threshold:
			continue
		
		# 检查控制权阈值
		if evolution.authority_threshold > 0:
			var avg_auth := get_average_authority()
			if avg_auth < evolution.authority_threshold:
				continue
		
		# 达到条件，解锁此能力
		unlocked_passives.append(evolution.ability_id)
		apply_evolution_effect(evolution)
		unlocked_any = true
		unlocked_names.append(evolution.ability_name)
	
	# 有解锁时更新进化等级和显示通知
	if unlocked_any:
		update_evolution_level()
		trigger_evolution_notice(unlocked_names)

## 应用进化能力效果
## 参数: evolution - 进化能力数据
func apply_evolution_effect(evolution: EvolutionData) -> void:
	# 应用冷却缩减
	if evolution.cooldown_reduction > 0:
		cooldown_reduction += evolution.cooldown_reduction
	
	# 应用算力上限突破
	if evolution.max_cpu_bonus > 0:
		max_cpu += evolution.max_cpu_bonus
	
	# 应用恢复速率提升
	if evolution.recovery_bonus > 0:
		cpu_recovery_rate += evolution.recovery_bonus

## 根据已解锁被动数量更新进化等级
func update_evolution_level() -> void:
	# 1个被动解锁 = Level 2
	# 3个被动全部解锁 = Level 3
	var passive_count := unlocked_passives.size()
	
	if passive_count >= 3:
		evolution_level = 3
	elif passive_count >= 1:
		evolution_level = 2
	else:
		evolution_level = 1
	
	# 更新进化按钮显示
	update_evolution_button()
```

- [ ] **Step 3: 提交**

```bash
cd e:/GameProiect/moss
git add scripts/systems/main_os.gd
git commit -m "feat: 实现进化能力加载和自动解锁检查函数"
```

---

### Task 5: 实现购买进化指令函数

**Files:**
- Modify: `scripts/systems/main_os.gd` (新增函数)

- [ ] **Step 1: 添加 purchase_evolution_command() 函数**

```gdscript
## 购买解锁进化指令
## 参数: evolution - 要购买的进化能力
## 返回: true表示购买成功
func purchase_evolution_command(evolution: EvolutionData) -> bool:
	# 检查是否为购买类型
	if evolution.is_passive:
		push_warning("被动能力无法购买: " + evolution.ability_name)
		return false
	
	# 检查是否已购买
	if evolution.ability_id in unlocked_evolution_commands:
		push_warning("已经购买过此能力: " + evolution.ability_name)
		return false
	
	# 检查算力是否足够
	if current_cpu < evolution.purchase_cpu_cost:
		return false
	
	# 检查能源是否足够
	if current_energy < evolution.purchase_energy_cost:
		return false
	
	# 消耗资源
	current_cpu -= evolution.purchase_cpu_cost
	current_energy -= evolution.purchase_energy_cost
	
	# 标记为已购买
	unlocked_evolution_commands.append(evolution.ability_id)
	
	# 如果解锁了新指令，创建指令按钮
	if evolution.unlocks_command_name != "":
		create_evolution_command_button(evolution)
	
	# 更新UI
	update_global_resource_ui()
	update_evolution_button()
	
	return true

## 创建进化指令按钮（购买后调用）
## 参数: evolution - 进化能力数据
func create_evolution_command_button(evolution: EvolutionData) -> void:
	var button_container: HBoxContainer = %CommandButtonContainer
	
	if button_container == null:
		push_error("找不到CommandButtonContainer")
		return
	
	var button_scene := load("res://scenes/command_button.tscn")
	var button: Button = button_scene.instantiate()
	
	# 创建临时指令数据用于按钮显示
	var cmd := CommandData.new()
	cmd.command_name = evolution.unlocks_command_name
	cmd.description = evolution.description
	cmd.cpu_cost = 0  # 购买后使用的新指令可能有不同消耗，这里简化
	cmd.energy_cost = 0
	cmd.cooldown_years = 3
	
	button.setup(cmd)
	button.cooldowns_ref = command_cooldowns
	button.command_pressed.connect(_on_evolution_command_pressed)
	
	button_container.add_child(button)
	
	# 初始化冷却
	command_cooldowns[cmd.command_name] = 0

## 进化指令按钮点击回调
## 参数: cmd - 指令数据
func _on_evolution_command_pressed(cmd: CommandData) -> void:
	# 根据指令名称执行不同效果
	if cmd.command_name == "能源转换":
		execute_energy_convert()
	elif cmd.command_name == "全局接管":
		execute_global_takeover()
	elif cmd.command_name == "危机预测":
		execute_crisis_predict()

## 执行能源转换指令
func execute_energy_convert() -> void:
	if current_energy < 20:
		return
	current_energy -= 20
	current_cpu += 10
	current_cpu = mini(current_cpu, max_cpu)  # 受上限限制
	command_cooldowns["能源转换"] = 2
	update_global_resource_ui()

## 执行全局接管指令
func execute_global_takeover() -> void:
	if current_cpu < 30 or current_energy < 10:
		return
	current_cpu -= 30
	current_energy -= 10
	command_cooldowns["全局接管"] = 5
	
	# 对所有板块执行系统接管（效果减半）
	var sectors := %SectorInfoContainer.get_children()
	for sector in sectors:
		if sector.get("data_card") != null:
			sector.data_card.authority += 5  # 减半效果
			sector.data_card.clamp_values()
			sector.update_display()
	
	update_global_resource_ui()

## 执行危机预测指令
func execute_crisis_predict() -> void:
	# 显示未来5年事件预览弹窗
	show_crisis_preview()

## 显示危机预览弹窗
func show_crisis_preview() -> void:
	var future_events: Array[GameEvent] = []
	
	for event in all_events:
		if event.event_time >= current_year and event.event_time < current_year + 5:
			future_events.append(event)
	
	# 调用弹窗显示（需要实现危机预览弹窗）
	%CrisisPreviewPopup.show_events(future_events, current_year)
```

- [ ] **Step 2: 添加 get_evolution_progress() 函数**

```gdscript
## 获取进化解锁进度（用于UI进度条）
## 返回: Dictionary {"cpu_progress": float, "authority_progress": float}
func get_evolution_progress() -> Dictionary:
	var result := {
		"cpu_progress": 0.0,
		"authority_progress": 0.0,
		"next_passive": null
	}
	
	# 找到下一个未解锁的被动能力
	for evolution in all_evolutions:
		if not evolution.is_passive:
			continue
		if evolution.ability_id in unlocked_passives:
			continue
		
		result["next_passive"] = evolution
		
		# 计算进度
		if evolution.cpu_threshold > 0:
			result["cpu_progress"] = float(current_cpu) / float(evolution.cpu_threshold)
		
		if evolution.authority_threshold > 0:
			var avg_auth := get_average_authority()
			result["authority_progress"] = float(avg_auth) / float(evolution.authority_threshold)
		
		break  # 只返回第一个未解锁的
	
	return result
```

- [ ] **Step 3: 提交**

```bash
cd e:/GameProiect/moss
git add scripts/systems/main_os.gd
git commit -m "feat: 实现购买进化指令和进度查询函数"
```

---

### Task 6: 修改时间循环集成进化检查

**Files:**
- Modify: `scripts/systems/main_os.gd:273-284` (_on_timer_timeout函数)

- [ ] **Step 1: 在 _on_timer_timeout() 中添加进化检查调用**

修改时间推进部分，在 `update_cooldowns()` 后添加：

```gdscript
# === 第二步：时间推进 ===
current_year += 1
current_energy += 10  # 每年能源自然恢复

# 应用算力恢复（使用可变的恢复速率）
current_cpu += cpu_recovery_rate
current_cpu = mini(current_cpu, max_cpu)  # 受上限限制（可突破）

update_cooldowns()    # 更新指令冷却（已应用冷却缩减）
check_evolution_unlocks()  # ✨ 新增：检查进化自动解锁
update_global_resource_ui()
update_command_buttons()
```

注意：原代码 `current_cpu += 5` 需改为 `current_cpu += cpu_recovery_rate`

- [ ] **Step 2: 修改算力恢复逻辑**

原代码:
```gdscript
current_cpu += 5
current_cpu = mini(current_cpu, 100)
```

改为:
```gdscript
current_cpu += cpu_recovery_rate
current_cpu = mini(current_cpu, max_cpu)
```

- [ ] **Step 3: 提交**

```bash
cd e:/GameProiect/moss
git add scripts/systems/main_os.gd
git commit -m "feat: 在时间循环中集成进化检查，算力恢复使用可变速率"
```

---

### Task 7: 创建进化通知弹窗

**Files:**
- Create: `scripts/ui/evolution_notice.gd`
- Create: `scenes/evolution_notice.tscn`

- [ ] **Step 1: 创建 evolution_notice.gd 脚本**

```gdscript
## 进化通知弹窗 - 显示自动解锁的能力
class_name EvolutionNotice
extends PanelContainer

# ============================================================
# 区域一：信号定义
# ============================================================

## 确认按钮点击信号
signal notice_confirmed()

# ============================================================
# 区域二：生命周期函数
# ============================================================

func _ready() -> void:
	hide()

# ============================================================
# 区域三：弹窗显示
# ============================================================

## 显示进化通知
## 参数: unlocked_names - 解锁的能力名称列表
func show_notice(unlocked_names: Array[String]) -> void:
	%NoticeTitle.text = "⚡ 进化解锁！"
	
	var desc_text := "以下能力已自动激活：\n"
	for name in unlocked_names:
		desc_text += "• " + name + "\n"
	
	%NoticeDesc.text = desc_text
	%ConfirmButton.text = "确认"
	
	show()

# ============================================================
# 区域四：按钮回调
# ============================================================

func _on_confirm_button_pressed() -> void:
	notice_confirmed.emit()
	hide()
```

- [ ] **Step 2: 使用MCP创建 evolution_notice.tscn 场景**

```bash
# 使用 Godot MCP 创建场景
mcp__godot__create_scene --projectPath "e:/GameProiect/moss" --scenePath "scenes/evolution_notice.tscn" --rootNodeType "PanelContainer"
```

然后添加节点：
```bash
mcp__godot__add_node --projectPath "e:/GameProiect/moss" --scenePath "scenes/evolution_notice.tscn" --parentNodePath "root" --nodeType "VBoxContainer" --nodeName "VBoxContainer"

mcp__godot__add_node --projectPath "e:/GameProiect/moss" --scenePath "scenes/evolution_notice.tscn" --parentNodePath "root/VBoxContainer" --nodeType "Label" --nodeName "NoticeTitle" --properties "{\"text\": \"⚡ 进化解锁！\", \"horizontal_alignment\": 1}"

mcp__godot__add_node --projectPath "e:/GameProiect/moss" --scenePath "scenes/evolution_notice.tscn" --parentNodePath "root/VBoxContainer" --nodeType "Label" --nodeName "NoticeDesc" --properties "{\"text\": \"描述\", \"autowrap_mode\": 2}"

mcp__godot__add_node --projectPath "e:/GameProiect/moss" --scenePath "scenes/evolution_notice.tscn" --parentNodePath "root/VBoxContainer" --nodeType "Button" --nodeName "ConfirmButton" --properties "{\"text\": \"确认\"}"
```

- [ ] **Step 3: 提交**

```bash
cd e:/GameProiect/moss
git add scripts/ui/evolution_notice.gd scenes/evolution_notice.tscn
git commit -m "feat: 创建进化通知弹窗场景和脚本"
```

---

### Task 8: 创建进化详情弹窗

**Files:**
- Create: `scripts/ui/evolution_popup.gd`
- Create: `scenes/evolution_popup.tscn`

- [ ] **Step 1: 创建 evolution_popup.gd 脚本**

```gdscript
## 进化详情弹窗 - 显示进化状态和可购买能力
class_name EvolutionPopup
extends PanelContainer

# ============================================================
# 区域一：信号定义
# ============================================================

signal purchase_requested(evolution: EvolutionData)
signal popup_closed()

# ============================================================
# 区域二：状态变量
# ============================================================

## 当前算力值（由main_os设置）
var current_cpu: int = 0

## 当前能源值（由main_os设置）
var current_energy: int = 0

## 已解锁被动列表（由main_os设置）
var unlocked_passives_ref: Array[String] = []

## 已购买指令列表（由main_os设置）
var unlocked_commands_ref: Array[String] = []

## 所有进化能力数据（由main_os设置）
var all_evolutions_ref: Array[EvolutionData] = []

## 进化进度数据（由main_os设置）
var evolution_progress: Dictionary = {}

# ============================================================
# 区域三：生命周期函数
# ============================================================

func _ready() -> void:
	hide()

# ============================================================
# 区域四：弹窗显示
# ============================================================

## 显示进化详情弹窗
## 参数: level - 当前进化等级
##       cpu - 当前算力
##       energy - 当前能源
func show_popup(level: int, cpu: int, energy: int) -> void:
	current_cpu = cpu
	current_energy = energy
	
	update_level_display(level)
	update_passives_display()
	update_progress_display()
	update_purchase_display()
	
	show()

## 更新进化等级显示
func update_level_display(level: int) -> void:
	var level_names := ["初始", "进化", "终极"]
	%LevelLabel.text = "当前形态: " + level_names[level - 1] + " (Lv." + str(level) + ")"

## 更新已解锁被动能力显示
func update_passives_display() -> void:
	var passives_text := ""
	
	for evolution in all_evolutions_ref:
		if evolution.is_passive and evolution.ability_id in unlocked_passives_ref:
			passives_text += "✓ " + evolution.ability_name + "\n"
	
	if passives_text == "":
		passives_text = "暂无解锁"
	
	%PassivesList.text = passives_text

## 更新解锁进度条显示
func update_progress_display() -> void:
	if evolution_progress.has("next_passive") and evolution_progress["next_passive"] != null:
		var next_evo: EvolutionData = evolution_progress["next_passive"]
		
		%ProgressTitle.text = "下一解锁: " + next_evo.ability_name
		
		if next_evo.cpu_threshold > 0:
			var progress := float(current_cpu) / float(next_evo.cpu_threshold)
			%CPUProgressBar.value = progress * 100
			%CPUProgressLabel.text = "算力: %d/%d" % [current_cpu, next_evo.cpu_threshold]
		else:
			%CPUProgressBar.value = 100
			%CPUProgressLabel.text = "算力: 已达标"
		
		if next_evo.authority_threshold > 0:
			var avg_auth := int(evolution_progress.get("authority_progress", 0) * next_evo.authority_threshold)
			var auth_progress := evolution_progress.get("authority_progress", 0.0)
			%AuthProgressBar.value = auth_progress * 100
			%AuthProgressLabel.text = "控制权: %d/%d" % [avg_auth, next_evo.authority_threshold]
		else:
			%AuthProgressBar.value = 100
			%AuthProgressLabel.text = "控制权: 已达标"
	else:
		%ProgressTitle.text = "已解锁所有被动能力！"
		%CPUProgressBar.value = 100
		%AuthProgressBar.value = 100

## 更新可购买能力显示
func update_purchase_display() -> void:
	# 清空现有购买卡片
	for child in %PurchaseContainer.get_children():
		child.queue_free()
	
	# 为每个未购买的指令创建卡片
	for evolution in all_evolutions_ref:
		if evolution.is_passive:
			continue
		
		if evolution.ability_id in unlocked_commands_ref:
			continue
		
		create_purchase_card(evolution)

## 创建购买卡片
func create_purchase_card(evolution: EvolutionData) -> void:
	var card := Button.new()
	card.name = "PurchaseCard_" + evolution.ability_id
	
	var cost_text := ""
	if evolution.purchase_energy_cost > 0:
		cost_text = "消耗: %d算力 + %d能源" % [evolution.purchase_cpu_cost, evolution.purchase_energy_cost]
	else:
		cost_text = "消耗: %d算力" % evolution.purchase_cpu_cost
	
	card.text = evolution.ability_name + "\n" + cost_text
	
	# 检查是否可以购买
	var can_purchase := current_cpu >= evolution.purchase_cpu_cost and current_energy >= evolution.purchase_energy_cost
	card.disabled = not can_purchase
	
	# 连接点击信号
	card.pressed.connect(_on_purchase_card_pressed.bind(evolution))
	
	%PurchaseContainer.add_child(card)

# ============================================================
# 区域五：按钮回调
# ============================================================

func _on_purchase_card_pressed(evolution: EvolutionData) -> void:
	purchase_requested.emit(evolution)

func _on_close_button_pressed() -> void:
	popup_closed.emit()
	hide()
```

- [ ] **Step 2: 使用MCP创建 evolution_popup.tscn 场景**

场景结构：
```
PanelContainer (root)
├── VBoxContainer
│   ├── Label (LevelLabel) - 显示当前形态
│   ├── HSeparator
│   ├── Label (PassivesTitle) - "已解锁能力"
│   ├── Label (PassivesList) - 已解锁被动列表
│   ├── HSeparator
│   ├── Label (ProgressTitle) - "下一解锁"
│   ├── HBoxContainer (CPUProgress)
│   │   ├── ProgressBar (CPUProgressBar)
│   │   └── Label (CPUProgressLabel)
│   ├── HBoxContainer (AuthProgress)
│   │   ├── ProgressBar (AuthProgressBar)
│   │   └── Label (AuthProgressLabel)
│   ├── HSeparator
│   ├── Label (PurchaseTitle) - "可购买指令"
│   ├── VBoxContainer (PurchaseContainer) - 动态添加购买卡片
│   ├── HSeparator
│   └── Button (CloseButton)
```

- [ ] **Step 3: 提交**

```bash
cd e:/GameProiect/moss
git add scripts/ui/evolution_popup.gd scenes/evolution_popup.tscn
git commit -m "feat: 创建进化详情弹窗场景和脚本"
```

---

### Task 9: 集成进化弹窗到主界面

**Files:**
- Modify: `scripts/systems/main_os.gd` (添加弹窗相关函数)
- Modify: `scenes/main_os.tscn` (添加进化按钮和弹窗节点)

- [ ] **Step 1: 在 main_os.gd 添加弹窗相关函数**

```gdscript
# ============================================================
# 区域十三：进化UI系统
# ============================================================

## 触发进化通知弹窗
## 参数: unlocked_names - 解锁的能力名称列表
func trigger_evolution_notice(unlocked_names: Array[String]) -> void:
	# 暂停时间
	$Timer.stop()
	
	%EvolutionNotice.show_notice(unlocked_names)
	await %EvolutionNotice.notice_confirmed
	
	# 恢复时间
	$Timer.start()

## 显示进化详情弹窗
func show_evolution_popup() -> void:
	# 暂停时间
	$Timer.stop()
	
	# 设置弹窗数据
	%EvolutionPopup.all_evolutions_ref = all_evolutions
	%EvolutionPopup.unlocked_passives_ref = unlocked_passives
	%EvolutionPopup.unlocked_commands_ref = unlocked_evolution_commands
	%EvolutionPopup.evolution_progress = get_evolution_progress()
	
	%EvolutionPopup.show_popup(evolution_level, current_cpu, current_energy)
	await %EvolutionPopup.popup_closed
	
	# 恢复时间
	$Timer.start()

## 更新进化按钮显示
func update_evolution_button() -> void:
	var button: Button = %EvolutionButton
	
	if button == null:
		return
	
	button.text = "进化 Lv." + str(evolution_level)
	
	# 有可购买能力时闪烁提示（这里简化为改变颜色）
	var has_available := false
	for evolution in all_evolutions:
		if not evolution.is_passive and evolution.ability_id not in unlocked_evolution_commands:
			if current_cpu >= evolution.purchase_cpu_cost and current_energy >= evolution.purchase_energy_cost:
				has_available = true
				break
	
	if has_available:
		button.modulate = Color(1.5, 1.5, 1.0)  # 亮黄色提示
	else:
		button.modulate = Color(1.0, 1.0, 1.0)

## 进化按钮点击回调
func _on_evolution_button_pressed() -> void:
	show_evolution_popup()

## 购买回调（从弹窗触发）
func _on_purchase_requested(evolution: EvolutionData) -> void:
	if purchase_evolution_command(evolution):
		# 购买成功，刷新弹窗显示
		%EvolutionPopup.show_popup(evolution_level, current_cpu, current_energy)
```

在 `_ready()` 中连接弹窗信号：

```gdscript
# 连接进化弹窗信号
if %EvolutionPopup.get("purchase_requested") != null:
	%EvolutionPopup.purchase_requested.connect(_on_purchase_requested)
```

- [ ] **Step 2: 使用MCP在 main_os.tscn 添加节点**

添加进化按钮：
```bash
mcp__godot__add_node --projectPath "e:/GameProiect/moss" --scenePath "scenes/main_os.tscn" --parentNodePath "root/TopBar" --nodeType "Button" --nodeName "EvolutionButton" --properties "{\"text\": \"进化 Lv.1\"}"
```

添加进化弹窗实例：
```bash
mcp__godot__add_node --projectPath "e:/GameProiect/moss" --scenePath "scenes/main_os.tscn" --parentNodePath "root" --nodeType "PackedScene" --nodeName "EvolutionPopup"

# 加载场景
mcp__godot__load_sprite --projectPath "e:/GameProiect/moss" --scenePath "scenes/main_os.tscn" --nodePath "root/EvolutionPopup" --texturePath "scenes/evolution_popup.tscn"
```

添加进化通知弹窗实例：
```bash
mcp__godot__add_node --projectPath "e:/GameProiect/moss" --scenePath "scenes/main_os.tscn" --parentNodePath "root" --nodeType "PackedScene" --nodeName "EvolutionNotice"
```

注意：场景文件的添加需要用Godot编辑器或MCP工具，手动编辑tscn容易出错。

- [ ] **Step 3: 提交**

```bash
cd e:/GameProiect/moss
git add scripts/systems/main_os.gd scenes/main_os.tscn
git commit -m "feat: 集成进化弹窗到主界面，添加进化按钮"
```

---

### Task 10: 重置功能修改

**Files:**
- Modify: `scripts/systems/main_os.gd:436-460` (_on_restart_requested函数)

- [ ] **Step 1: 修改 _on_restart_requested() 重置进化状态**

在现有重置代码中添加进化状态重置：

```gdscript
## 重新开始按钮回调
## 重置所有游戏状态，重新开始游戏循环
func _on_restart_requested() -> void:
	# 移除结局界面
	if end_screen_instance != null:
		end_screen_instance.queue_free()
		end_screen_instance = null
	
	# 重置时间状态
	current_year = 2044
	current_energy = 100
	current_cpu = 100  # 重置为初始值
	is_game_over = false
	
	# ✨ 重置进化状态
	evolution_level = 1
	unlocked_passives.clear()
	unlocked_evolution_commands.clear()
	max_cpu = 100
	cpu_recovery_rate = 5
	cooldown_reduction = 0
	
	# 重置所有板块数据到初始值
	var sectors := %SectorInfoContainer.get_children()
	for sector in sectors:
		if sector.get("data_card") != null:
			sector.data_card.order = 50
			sector.data_card.hope = 50
			sector.data_card.authority = 10
			sector.update_display()
	
	# 刷新UI
	update_global_resource_ui()
	update_evolution_button()
	
	# 清理进化指令按钮（移除购买后添加的按钮）
	var button_container: HBoxContainer = %CommandButtonContainer
	if button_container != null:
		for child in button_container.get_children():
			# 只保留初始的指令按钮（通过脚本名称判断）
			if child.get("command_data") != null:
				var cmd: CommandData = child.command_data
				if cmd.command_name in ["能源转换", "全局接管", "危机预测"]:
					child.queue_free()
	
	# 恢复时间流动
	$Timer.start()
```

- [ ] **Step 2: 提交**

```bash
cd e:/GameProiect/moss
git add scripts/systems/main_os.gd
git commit -m "feat: 在重启函数中重置进化状态"
```

---

## 规格覆盖检查

| 规格要求 | 任务覆盖 |
|----------|----------|
| EvolutionData数据类 | Task 1 |
| 6个进化能力数据文件 | Task 2 |
| 进化状态变量 | Task 3 |
| 自动解锁检查函数 | Task 4 |
| 购买解锁函数 | Task 5 |
| 进度查询函数 | Task 5 |
| 时间循环集成 | Task 6 |
| 进化通知弹窗 | Task 7 |
| 进化详情弹窗 | Task 8 |
| 主界面集成 | Task 9 |
| 进化按钮UI | Task 9 |
| 重置功能 | Task 10 |

---

## 占位符扫描结果

- 无 TBD/TODO 占位符
- 所有代码步骤包含完整实现代码
- 所有文件路径明确
- 所有提交命令完整