# MOSS指令系统实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 MOSS 指令系统，让玩家能主动选择板块并执行算力分配、系统接管指令。

**Architecture:** 数据驱动设计，CommandData Resource类 + .tres配置文件，通过信号连接板块选中与指令执行。

**Tech Stack:** Godot 4.x GDScript，使用 MCP Godot 工具创建场景节点。

---

## 文件结构总览

| 操作 | 文件路径 | 职责 |
|------|----------|------|
| 创建 | `scripts/resources/command_data.gd` | 指令数据类定义 |
| 创建 | `data/commands/command_allocate.tres` | 算力分配指令配置 |
| 创建 | `data/commands/command_takeover.tres` | 系统接管指令配置 |
| 修改 | `scripts/resources/sector_info.gd` | 添加选中状态和信号 |
| 修改 | `scripts/systems/main_os.gd` | 指令系统核心逻辑 |
| 创建 | `scripts/ui/command_button.gd` | 指令按钮脚本 |
| 创建 | `scripts/ui/allocate_popup.gd` | 算力分配选择弹窗 |
| 创建 | `scenes/command_button.tscn` | 指令按钮场景 |
| 创建 | `scenes/allocate_popup.tscn` | 选择弹窗场景 |
| 修改 | `scenes/main_os.tscn` | 添加指令按钮容器 |

---

### Task 1: 创建 CommandData 数据类

**Files:**
- Create: `scripts/resources/command_data.gd`

- [ ] **Step 1: 创建命令数据目录**

```bash
mkdir -p "e:/GameProiect/moss/data/commands"
```

- [ ] **Step 2: 编写 CommandData 类**

```gdscript
## 指令数据类 - 定义MOSS可执行的指令配置
## 继承Resource，支持在编辑器中通过.tres文件配置
class_name CommandData
extends Resource

# ============================================================
# 区域一：基础信息
# ============================================================

@export_group("基础信息")
## 指令名称，用于冷却字典的键和UI显示
@export var command_name: String = "指令名称"
## 指令描述，用于tooltip提示
@export var description: String = "指令描述"

# ============================================================
# 区域二：消耗配置
# ============================================================

@export_group("消耗")
## 算力消耗值
@export var cpu_cost: int = 0
## 能源消耗值
@export var energy_cost: int = 0

# ============================================================
# 区域三：效果配置
# ============================================================

@export_group("效果")
## 秩序值变化量（正数增加，负数减少）
@export var order_delta: int = 0
## 希望值变化量
@export var hope_delta: int = 0
## 控制权变化量
@export var authority_delta: int = 0

# ============================================================
# 区域四：冷却配置
# ============================================================

@export_group("冷却")
## 冷却年数，执行后需等待的年份
@export var cooldown_years: int = 3

# ============================================================
# 区域五：辅助属性
# ============================================================

## 是否为算力分配类型（需要弹出选择窗口）
@export var is_allocate_type: bool = false
```

- [ ] **Step 3: 提交代码**

```bash
git add scripts/resources/command_data.gd
git commit -m "$(cat <<'EOF'
feat: 添加CommandData指令数据类

定义指令的消耗、效果和冷却配置，支持数据驱动设计。

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 创建指令配置文件

**Files:**
- Create: `data/commands/command_allocate.tres`
- Create: `data/commands/command_takeover.tres`

- [ ] **Step 1: 创建算力分配配置文件**

```gdscript
[gd_resource type="CommandData" format=3 uid="uid://c_allocate_cmd"]

[resource]
command_name = "算力分配"
description = "调配算力资源，提升板块稳定性"
cpu_cost = 20
energy_cost = 0
order_delta = 15
hope_delta = 15
authority_delta = 0
cooldown_years = 3
is_allocate_type = true
```

- [ ] **Step 2: 创建系统接管配置文件**

```gdscript
[gd_resource type="CommandData" format=3 uid="uid://c_takeover_cmd"]

[resource]
command_name = "系统接管"
description = "深度介入板块管理，提升MOSS控制权"
cpu_cost = 30
energy_cost = 20
order_delta = 0
hope_delta = 0
authority_delta = 10
cooldown_years = 5
is_allocate_type = false
```

注：Godot的.tres文件需要通过编辑器创建才能生成正确的UID。这里提供内容参考，实际需要在编辑器中创建Resource文件并填入数值。

- [ ] **Step 3: 提交配置文件**

```bash
git add data/commands/
git commit -m "$(cat <<'EOF'
feat: 添加算力分配和系统接管指令配置

数值可在编辑器中调整：算力分配消耗20算力冷却3年，系统接管消耗30算力20能源冷却5年。

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: 修改 sector_info.gd 添加选中功能

**Files:**
- Modify: `scripts/resources/sector_info.gd`

- [ ] **Step 1: 添加选中状态信号和变量**

在现有代码基础上添加：

```gdscript
class_name SectorInfo
extends Panel

# ============================================================
# 区域一：导出变量
# ============================================================

## 数据卡插槽
@export var data_card: SectorData

# ============================================================
# 区域二：信号定义
# ============================================================

## 板块被点击时发出，用于选中状态
signal sector_clicked(sector: SectorInfo)

# ============================================================
# 区域三：状态变量
# ============================================================

## 是否被选中
var is_selected: bool = false

## 选中时的边框颜色
const SELECTED_COLOR: Color = Color(0.0, 1.0, 0.533, 1.0)  # #00FF88

## 默认边框颜色
const DEFAULT_COLOR: Color = Color(0.5, 0.5, 0.5, 1.0)

# ============================================================
# 区域四：节点引用
# ============================================================

@onready var title_label = $TitleLabel
@onready var order_bar = %OrderBar
@onready var hope_bar = %HopeBar
@onready var authority_bar = %AuthorityBar

func _ready():
	if data_card != null:
		update_display()
	# 设置默认边框颜色
	self.modulate = DEFAULT_COLOR

# ============================================================
# 区域五：显示更新
# ============================================================

func update_display():
	title_label.text = data_card.region_name
	order_bar.value = data_card.order
	hope_bar.value = data_card.hope
	authority_bar.value = data_card.authority

# ============================================================
# 区域六：选中状态管理
# ============================================================

## 设置选中状态
## 参数: value - true为选中，false为取消选中
func set_selected(value: bool) -> void:
	is_selected = value
	if is_selected:
		self.modulate = SELECTED_COLOR
	else:
		self.modulate = DEFAULT_COLOR

# ============================================================
# 区域七：点击响应
# ============================================================

## 面板被点击时发出信号
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			sector_clicked.emit(self)
```

- [ ] **Step 2: 提交代码**

```bash
git add scripts/resources/sector_info.gd
git commit -m "$(cat <<'EOF'
feat: 板块添加选中状态和点击信号

点击板块发出sector_clicked信号，选中时边框高亮显示。

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: 修改 main_os.gd 添加状态变量和加载函数

**Files:**
- Modify: `scripts/systems/main_os.gd`

- [ ] **Step 1: 添加指令系统状态变量**

在区域二（游戏状态变量）后添加新区域：

```gdscript
# ============================================================
# 区域三：指令系统状态
# ============================================================

## 当前选中的板块
var selected_sector: SectorInfo = null

## 各指令冷却剩余年数 {"算力分配": 0, "系统接管": 2}
var command_cooldowns: Dictionary = {}

## 可用指令列表（从磁盘加载）
var available_commands: Array[CommandData] = []
```

- [ ] **Step 2: 添加指令加载函数**

在 `_ready()` 函数中添加指令加载调用：

```gdscript
func _ready() -> void:
	# 初始化事件列表
	all_events.clear()
	load_events_from_disk()
	
	# 初始化指令列表
	available_commands.clear()
	load_commands_from_disk()
```

在区域五后添加区域六：

```gdscript
# ============================================================
# 区域六：指令加载系统
# ============================================================

## 从硬盘目录加载所有指令资源文件
## 自动扫描 res://data/commands/ 下的 .tres 文件
func load_commands_from_disk() -> void:
	var path := "res://data/commands/"
	var dir := DirAccess.open(path)
	
	if not dir:
		push_warning("指令目录不存在: " + path)
		return
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var cmd := load(path + file_name)
			
			if cmd is CommandData:
				available_commands.append(cmd)
				# 初始化冷却状态为0
				command_cooldowns[cmd.command_name] = 0
		
		file_name = dir.get_next()
```

- [ ] **Step 3: 提交代码**

```bash
git add scripts/systems/main_os.gd
git commit -m "$(cat <<'EOF'
feat: main_os添加指令系统状态变量和加载函数

添加selected_sector、command_cooldowns、available_commands状态，从磁盘加载CommandData配置。

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: 添加板块选中管理函数

**Files:**
- Modify: `scripts/systems/main_os.gd`

- [ ] **Step 1: 添加选中管理区域**

在区域六后添加区域七：

```gdscript
# ============================================================
# 区域七：板块选中管理
# ============================================================

## 设置选中板块
## 参数: sector - 被点击的板块节点
func select_sector(sector: SectorInfo) -> void:
	# 取消之前的选中
	if selected_sector != null:
		selected_sector.set_selected(false)
	
	# 设置新选中
	selected_sector = sector
	selected_sector.set_selected(true)

## 取消选中状态
func deselect_sector() -> void:
	if selected_sector != null:
		selected_sector.set_selected(false)
		selected_sector = null

## 板块点击回调 - 连接到SectorInfo的sector_clicked信号
func _on_sector_clicked(sector: SectorInfo) -> void:
	select_sector(sector)
```

- [ ] **Step 2: 提交代码**

```bash
git add scripts/systems/main_os.gd
git commit -m "$(cat <<'EOF'
feat: 添加板块选中管理函数

select_sector/deselect_sector管理选中状态，_on_sector_clicked响应板块点击信号。

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: 添加冷却系统

**Files:**
- Modify: `scripts/systems/main_os.gd`

- [ ] **Step 1: 添加冷却更新函数**

在区域七后添加区域八：

```gdscript
# ============================================================
# 区域八：冷却系统
# ============================================================

## 每年更新冷却状态
## 减少所有指令的冷却计数（最小为0）
func update_cooldowns() -> void:
	for cmd_name in command_cooldowns.keys():
		if command_cooldowns[cmd_name] > 0:
			command_cooldowns[cmd_name] -= 1

## 检查指令是否可用（冷却、资源、选中状态）
## 参数: cmd - 指令数据
## 返回: true表示可执行
func is_command_available(cmd: CommandData) -> bool:
	# 检查选中状态
	if selected_sector == null:
		return false
	
	# 检查冷却
	if command_cooldowns.get(cmd.command_name, 0) > 0:
		return false
	
	# 检查算力
	if current_cpu < cmd.cpu_cost:
		return false
	
	# 检查能源
	if current_energy < cmd.energy_cost:
		return false
	
	return true

## 获取指令不可用的原因（用于tooltip）
## 参数: cmd - 指令数据
## 返回: 不可用原因字符串，可用时返回空字符串
func get_command_unavailable_reason(cmd: CommandData) -> String:
	if selected_sector == null:
		return "请先选择板块"
	
	var cooldown := command_cooldowns.get(cmd.command_name, 0)
	if cooldown > 0:
		return "冷却中（剩余%d年）" % cooldown
	
	if current_cpu < cmd.cpu_cost:
		return "算力不足（需要%d）" % cmd.cpu_cost
	
	if current_energy < cmd.energy_cost:
		return "能源不足（需要%d）" % cmd.energy_cost
	
	return ""
```

- [ ] **Step 2: 在时间推进中调用冷却更新**

修改 `_on_timer_timeout()` 函数，在时间推进部分添加：

```gdscript
# === 第二步：时间推进 ===
current_year += 1
current_energy += 10  # 每年能源自然恢复
current_cpu += 5      # 每年算力恢复5点
current_cpu = mini(current_cpu, 100)  # 算力上限100
update_cooldowns()    # 更新指令冷却
update_global_resource_ui()
```

- [ ] **Step 3: 提交代码**

```bash
git add scripts/systems/main_os.gd
git commit -m "$(cat <<'EOF'
feat: 添加指令冷却系统和算力恢复

每年更新冷却计数、恢复5点算力，is_command_available检查执行条件。

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: 添加指令执行函数

**Files:**
- Modify: `scripts/systems/main_os.gd`

- [ ] **Step 1: 添加指令执行区域**

在区域八后添加区域九：

```gdscript
# ============================================================
# 区域九：指令执行系统
# ============================================================

## 执行指令
## 参数: cmd - 指令数据
## 返回: true表示执行成功
func execute_command(cmd: CommandData) -> bool:
	if not is_command_available(cmd):
		return false
	
	# 消耗资源
	current_cpu -= cmd.cpu_cost
	current_energy -= cmd.energy_cost
	
	# 启动冷却
	command_cooldowns[cmd.command_name] = cmd.cooldown_years
	
	# 刷新资源UI
	update_global_resource_ui()
	
	return true

## 应用指令效果到选中板块
## 参数: cmd - 指令数据
##       effect_type - 对于算力分配，"order"或"hope"
func apply_command_effect(cmd: CommandData, effect_type: String = "") -> void:
	if selected_sector == null:
		return
	
	# 应用效果
	if cmd.is_allocate_type:
		# 算力分配根据选择决定效果
		if effect_type == "order":
			selected_sector.data_card.order += cmd.order_delta
		elif effect_type == "hope":
			selected_sector.data_card.hope += cmd.hope_delta
	else:
		# 其他指令直接应用所有效果
		selected_sector.data_card.order += cmd.order_delta
		selected_sector.data_card.hope += cmd.hope_delta
		selected_sector.data_card.authority += cmd.authority_delta
	
	# 限制数值范围
	selected_sector.data_card.clamp_values()
	
	# 刷新板块显示
	selected_sector.update_display()

## 指令按钮点击回调
## 参数: cmd - 指令数据
func _on_command_button_pressed(cmd: CommandData) -> void:
	if not is_command_available(cmd):
		return
	
	if cmd.is_allocate_type:
		# 算力分配需要弹出选择窗口
		$Timer.stop()
		%AllocatePopup.popup_allocate(cmd, selected_sector.data_card.region_name)
		var choice: String = await %AllocatePopup.choice_selected
		if choice != "":
			execute_command(cmd)
			apply_command_effect(cmd, choice)
		$Timer.start()
	else:
		# 其他指令直接执行
		execute_command(cmd)
		apply_command_effect(cmd)
```

- [ ] **Step 2: 提交代码**

```bash
git add scripts/systems/main_os.gd
git commit -m "$(cat <<'EOF'
feat: 添加指令执行和效果应用函数

execute_command处理资源消耗和冷却，apply_command_effect修改板块数据。

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: 创建 command_button.gd 脚本

**Files:**
- Create: `scripts/ui/command_button.gd`

- [ ] **Step 1: 编写指令按钮脚本**

```gdscript
## 指令按钮组件 - 显示单个MOSS指令按钮
## 负责按钮状态更新和点击响应
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
# 区域三：生命周期
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
	var cooldown := cooldowns_ref.get(command_data.command_name, 0)
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
	tooltip_text = "消耗: %d算力 %d能源" % [command_data.cpu_cost, command_data.energy_cost]

# ============================================================
# 区域五：点击响应
# ============================================================

func _on_pressed() -> void:
	if command_data != null and not disabled:
		command_pressed.emit(command_data)

# ============================================================
# 区域六：配置函数
# ============================================================

## 设置指令数据（创建时调用）
func setup(cmd: CommandData) -> void:
	command_data = cmd
	text = cmd.command_name
```

- [ ] **Step 2: 提交代码**

```bash
git add scripts/ui/command_button.gd
git commit -m "$(cat <<'EOF'
feat: 创建command_button指令按钮组件

根据选中状态、冷却、资源更新按钮状态和tooltip。

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: 创建 allocate_popup.gd 脚本

**Files:**
- Create: `scripts/ui/allocate_popup.gd`

- [ ] **Step 1: 编写算力分配选择弹窗脚本**

```gdscript
## 算力分配选择弹窗 - 让玩家选择提升秩序或希望
extends PanelContainer

# ============================================================
# 区域一：信号定义
# ============================================================

## 玩家选择后发出，"order"表示秩序，"hope"表示希望，空字符串表示取消
signal choice_selected(choice: String)

# ============================================================
# 区域二：生命周期
# ============================================================

func _ready() -> void:
	hide()

# ============================================================
# 区域三：弹窗显示
# ============================================================

## 显示算力分配选择弹窗
## 参数: cmd - 指令数据
##       region_name - 目标板块名称
func popup_allocate(cmd: CommandData, region_name: String) -> void:
	%AllocateTitle.text = "算力分配 - " + region_name
	%AllocateDesc.text = cmd.description + "\n请选择要提升的属性："
	
	%OrderButton.text = "提升秩序 (+%d)" % cmd.order_delta
	%HopeButton.text = "提升希望 (+%d)" % cmd.hope_delta
	
	show()

# ============================================================
# 区域四：按钮回调
# ============================================================

func _on_order_button_pressed() -> void:
	choice_selected.emit("order")
	hide()

func _on_hope_button_pressed() -> void:
	choice_selected.emit("hope")
	hide()

func _on_cancel_button_pressed() -> void:
	choice_selected.emit("")
	hide()
```

- [ ] **Step 2: 提交代码**

```bash
git add scripts/ui/allocate_popup.gd
git commit -m "$(cat <<'EOF'
feat: 创建allocate_popup算力分配选择弹窗

玩家选择提升秩序或希望，发出choice_selected信号。

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: 创建场景文件（通过MCP Godot工具）

**Files:**
- Create: `scenes/command_button.tscn`
- Create: `scenes/allocate_popup.tscn`
- Modify: `scenes/main_os.tscn`

注：场景文件需要通过Godot编辑器或MCP工具创建，避免手动编辑tscn。

- [ ] **Step 1: 使用MCP创建command_button场景**

使用Godot MCP工具创建Button节点场景：

```json
// 调用 mcp__godot__create_scene
{
  "projectPath": "e:/GameProiect/moss",
  "scenePath": "scenes/command_button.tscn",
  "rootNodeType": "Button"
}
```

然后保存并绑定脚本：

```json
// 调用 mcp__godot__save_scene
{
  "projectPath": "e:/GameProiect/moss",
  "scenePath": "scenes/command_button.tscn"
}
```

- [ ] **Step 2: 使用MCP创建allocate_popup场景**

```json
// 调用 mcp__godot__create_scene
{
  "projectPath": "e:/GameProiect/moss",
  "scenePath": "scenes/allocate_popup.tscn",
  "rootNodeType": "PanelContainer"
}
```

添加子节点：
- Label (标题) -> unique name: AllocateTitle
- Label (描述) -> unique name: AllocateDesc
- VBoxContainer -> unique name: ButtonContainer
  - Button (秩序) -> unique name: OrderButton
  - Button (希望) -> unique name: HopeButton
  - Button (取消) -> unique name: CancelButton

- [ ] **Step 3: 修改main_os场景添加指令按钮容器**

在main_os.tscn中添加：
- HBoxContainer -> unique name: CommandButtonContainer
- 实例化2个command_button场景

连接信号：
- SectorInfo的sector_clicked -> main_os._on_sector_clicked
- CommandButton的command_pressed -> main_os._on_command_button_pressed
- 实例化allocate_popup场景 -> unique name: AllocatePopup

- [ ] **Step 4: 提交场景文件**

```bash
git add scenes/
git commit -m "$(cat <<'EOF'
feat: 创建指令按钮和选择弹窗场景

command_button.tscn和allocate_popup.tscn，集成到main_os主界面。

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: 连接信号和初始化指令按钮

**Files:**
- Modify: `scripts/systems/main_os.gd`

- [ ] **Step 1: 在_ready中连接板块点击信号**

修改 `_ready()` 函数：

```gdscript
func _ready() -> void:
	# 初始化事件列表
	all_events.clear()
	load_events_from_disk()
	
	# 初始化指令列表
	available_commands.clear()
	load_commands_from_disk()
	
	# 连接所有板块的点击信号
	var sectors := %SectorInfoContainer.get_children()
	for sector in sectors:
		if sector.get("sector_clicked") != null:
			sector.sector_clicked.connect(_on_sector_clicked)
	
	# 初始化指令按钮
	setup_command_buttons()
```

- [ ] **Step 2: 添加指令按钮初始化函数**

在区域九后添加区域十：

```gdscript
# ============================================================
# 区域十：指令按钮初始化
# ============================================================

## 初始化指令按钮容器中的所有按钮
func setup_command_buttons() -> void:
	var button_container := %CommandButtonContainer
	
	if button_container == null:
		push_error("找不到CommandButtonContainer")
		return
	
	# 清空现有按钮
	for child in button_container.get_children():
		child.queue_free()
	
	# 为每个指令创建按钮
	for cmd in available_commands:
		var button_scene := load("res://scenes/command_button.tscn")
		var button := button_scene.instantiate()
		
		# 配置按钮
		button.setup(cmd)
		button.cooldowns_ref = command_cooldowns
		
		# 连接点击信号
		button.command_pressed.connect(_on_command_button_pressed)
		
		# 添加到容器
		button_container.add_child(button)
```

- [ ] **Step 3: 在时间推进中更新按钮状态**

在 `_on_timer_timeout()` 的UI更新部分添加：

```gdscript
# === 第四步：更新UI ===
update_global_resource_ui()
update_command_buttons()
```

添加按钮更新函数：

```gdscript
## 更新所有指令按钮状态
func update_command_buttons() -> void:
	var button_container := %CommandButtonContainer
	
	if button_container == null:
		return
	
	for button in button_container.get_children():
		if button.get("update_state") != null:
			# 更新按钮的状态变量
			button.current_cpu = current_cpu
			button.current_energy = current_energy
			button.has_selected_sector = (selected_sector != null)
			button.update_state()
```

- [ ] **Step 4: 提交代码**

```bash
git add scripts/systems/main_os.gd
git commit -m "$(cat <<'EOF'
feat: 连接板块信号和初始化指令按钮

setup_command_buttons创建按钮，update_command_buttons每年刷新状态。

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: 测试完整流程

**Files:**
- 无新增文件，运行测试

- [ ] **Step 1: 运行项目测试基本功能**

```bash
# 使用MCP运行项目
mcp__godot__run_project(projectPath: "e:/GameProiect/moss")
```

测试清单：
1. 点击板块是否高亮选中
2. 点击另一板块是否切换选中
3. 未选中板块时指令按钮是否disabled
4. 选中板块后指令按钮是否可用
5. 点击"算力分配"是否弹出选择窗口
6. 选择秩序/希望后板块数值是否更新
7. 执行后算力是否减少
8. 冷却是否生效（按钮disabled）
9. 年份推进后冷却是否减少
10. 算力是否每年恢复5点

- [ ] **Step 2: 检查调试输出**

```bash
mcp__godot__get_debug_output()
```

- [ ] **Step 3: 最终提交**

```bash
git status
git add -A
git commit -m "$(cat <<'EOF'
feat: 完成MOSS指令系统（阶段二）

实现算力分配和系统接管两个指令：
- 数据驱动设计，CommandData类+配置文件
- 板块选中状态，点击高亮显示
- 冷却机制，独立冷却计数
- Tooltip提示，显示不可用原因
- 算力每年恢复5点

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## 自检清单

**1. Spec覆盖检查：**
- [x] CommandData类 → Task 1
- [x] 指令配置文件 → Task 2
- [x] 板块选中状态 → Task 3
- [x] 状态变量和加载 → Task 4
- [x] 选中管理函数 → Task 5
- [x] 冷却系统 → Task 6
- [x] 指令执行 → Task 7
- [x] command_button组件 → Task 8
- [x] allocate_popup弹窗 → Task 9
- [x] 场景创建 → Task 10
- [x] 信号连接 → Task 11
- [x] 测试 → Task 12

**2. Placeholder检查：**
- 无TBD/TODO
- 所有代码步骤有完整代码
- 无"类似Task N"引用

**3. 类型一致性检查：**
- CommandData属性名一致
- signal sector_clicked(sector: Panel) vs SectorInfo类型 → 已修正为sector_clicked(sector: SectorInfo)需在sector_info.gd中修正
- 信号参数类型一致