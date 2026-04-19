# UI布局优化 v2 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将板块水平排列改为3列网格，添加年份进度条和右侧MOSS状态面板

**Architecture:** 重构 main_os.tscn 的布局结构，将 HBoxContainer 替换为 GridContainer + 右侧面板的 HSplitContainer 结构，同时调整板块卡片尺寸以动态适配屏幕

**Tech Stack:** Godot 4.x, GridContainer, HSplitContainer, ProgressBar

---

## 文件结构

### 需修改的文件

| 文件 | 负责内容 |
|------|----------|
| `scenes/main_os.tscn` | 整体布局重构：GridContainer、年份进度条、MOSS状态面板 |
| `scripts/systems/main_os.gd` | 年份进度条更新逻辑、MOSS状态面板交互 |
| `scenes/sector_info.tscn` | 卡片尺寸调整（minimum_size） |
| `scripts/resources/sector_info.gd` | 适配动态尺寸（可选） |

### 需新增的文件

| 文件 | 负责内容 |
|------|----------|
| `scenes/moss_status_panel.tscn` | MOSS状态面板组件 |
| `scripts/ui/moss_status_panel.gd` | 状态面板逻辑（等级显示、控制权、点击弹窗） |
| `scenes/year_progress.tscn` | 年份进度条组件 |

---

## Task 1: 创建年份进度条组件

**Files:**
- Create: `scenes/year_progress.tscn`
- Create: `scripts/ui/year_progress.gd`

**设计：**
- 2044 和 2075 两端标注
- 中间进度条显示当前进度
- 进度条颜色：#4488ff（蓝色）
- 高度：约 30px

- [ ] **Step 1: 创建 year_progress.gd 脚本**

```gdscript
## 年份进度条组件
## 显示 2044→2075 的游戏进程
class_name YearProgress
extends Control

# ============================================================
# 区域一：节点引用
# ============================================================

@onready var start_label: Label = $HBoxContainer/StartLabel
@onready var end_label: Label = $HBoxContainer/EndLabel
@onready var progress_bar: ProgressBar = $HBoxContainer/ProgressBar

# ============================================================
# 区域二：常量
# ============================================================

const START_YEAR: int = 2044
const END_YEAR: int = 2075

# ============================================================
# 区域三：生命周期
# ============================================================

func _ready() -> void:
    start_label.text = str(START_YEAR)
    end_label.text = str(END_YEAR)
    progress_bar.min_value = 0
    progress_bar.max_value = END_YEAR - START_YEAR
    progress_bar.value = 0

# ============================================================
# 区域四：公共方法
# ============================================================

## 更新进度条显示
## 参数: current_year - 当前年份（2044-2075）
func update_progress(current_year: int) -> void:
    progress_bar.value = current_year - START_YEAR
```

- [ ] **Step 2: 创建 year_progress.tscn 场景**

在 Godot 编辑器中创建场景结构：

```
YearProgress (Control)
└── HBoxContainer
    ├── StartLabel (Label) - text: "2044", 左对齐
    ├── ProgressBar (ProgressBar) - 自定义样式
    └── EndLabel (Label) - text: "2075", 右对齐
```

配置要点：
- HBoxContainer：anchors 填满父容器，spacing = 10
- StartLabel：固定宽度约 50px
- EndLabel：固定宽度约 50px
- ProgressBar：Size Flags Horizontal = Fill + Expand
- ProgressBar 自定义样式：背景 #333333，填充 #4488ff

- [ ] **Step 3: 验证组件**

运行 Godot 编辑器，打开 year_progress.tscn 场景，确认：
- 进度条正确显示 2044 和 2075
- 进度条从 0 开始
- 组件尺寸合适（高度约 30px）

---

## Task 2: 创建 MOSS 状态面板组件

**Files:**
- Create: `scenes/moss_status_panel.tscn`
- Create: `scripts/ui/moss_status_panel.gd`

**设计：**
- 显示当前等级（Lv.1/2/3）
- 显示控制权总和百分比
- "查看详情"按钮，点击触发信号
- 固定宽度约 150px

- [ ] **Step 1: 创建 moss_status_panel.gd 脚本**

```gdscript
## MOSS状态面板组件
## 右侧固定面板，显示MOSS核心状态
class_name MossStatusPanel
extends Panel

# ============================================================
# 区域一：信号
# ============================================================

## 点击"查看详情"按钮时发出
signal details_requested

# ============================================================
# 区域二：节点引用
# ============================================================

@onready var level_label: Label = $VBoxContainer/LevelLabel
@onready var authority_label: Label = $VBoxContainer/AuthorityLabel
@onready var details_button: Button = $VBoxContainer/DetailsButton

# ============================================================
# 区域三：生命周期
# ============================================================

func _ready() -> void:
    details_button.pressed.connect(_on_details_pressed)

# ============================================================
# 区域四：公共方法
# ============================================================

## 更新显示内容
## 参数: level - 进化等级（1-3）
## 参数: authority_percent - 平均控制权百分比
func update_display(level: int, authority_percent: int) -> void:
    level_label.text = "Lv." + str(level)
    authority_label.text = "控制权: " + str(authority_percent) + "%"

# ============================================================
# 区域五：回调
# ============================================================

func _on_details_pressed() -> void:
    details_requested.emit()
```

- [ ] **Step 2: 创建 moss_status_panel.tscn 场景**

在 Godot 编辑器中创建场景结构：

```
MossStatusPanel (Panel)
└── VBoxContainer
    ├── LevelLabel (Label) - text: "Lv.1", 居中，字体稍大
    ├── AuthorityLabel (Label) - text: "控制权: 10%"
    ├── Spacer (Control) - 填充空白
    └── DetailsButton (Button) - text: "查看详情"
```

配置要点：
- Panel：custom_minimum_size = Vector2(150, 0)，anchors 垂直填满
- VBoxContainer：anchors 填满父容器，alignment = Center
- LevelLabel：字体颜色 #ff4444（MOSS品牌色）
- AuthorityLabel：字体颜色 #888888
- DetailsButton：Size Flags Vertical = Shrink End

- [ ] **Step 3: 验证组件**

运行 Godot 编辑器，打开 moss_status_panel.tscn，确认：
- 面板宽度约 150px
- 内容垂直居中显示
- 按钮可点击（可临时添加 print 测试）

---

## Task 3: 调整板块卡片尺寸

**Files:**
- Modify: `scenes/sector_info.tscn:27-28` (custom_minimum_size)
- Modify: `scripts/resources/sector_info.gd` (可选，添加动态尺寸支持)

**目标：**
- minimum_size 从 222×448 改为 180×300
- 设置 Size Flags 为 Fill + Expand，支持动态伸缩

- [ ] **Step 1: 在编辑器中调整 sector_info.tscn**

打开 `scenes/sector_info.tscn`，修改 SectorInfo 节点：

1. 选择 `SectorInfo` 根节点
2. 在 Inspector 中修改：
   - `custom_minimum_size` = Vector2(180, 300)
3. 选择 `VBoxContainer` 子节点：
   - 修改 `custom_minimum_size` = Vector2(180, 300)
   - Size Flags Horizontal = Fill + Expand
   - Size Flags Vertical = Fill + Expand

- [ ] **Step 2: 验证卡片尺寸**

打开 main_os.tscn，查看板块显示：
- 卡片应该比之前小（宽度从 222 变为 180）
- 确认内容（进度条、标题）仍然正常显示

---

## Task 4: 重构主场景布局结构

**Files:**
- Modify: `scenes/main_os.tscn` (大规模重构)

**这是最核心的任务，需要在 Godot 编辑器中完成**

**目标结构：**
```
MainOS (Control)
├── ColorRect (背景)
├── TopBarContainer (顶部状态栏 - 新增 HBoxContainer)
│   ├── MossLabel (Label) - "MOSS-550C"
│   ├── CpuLabel (Label) - 算力显示
│   ├── EnergyLabel (Label) - 能源显示
│   └── EvolutionButton (Button) - 移动过来
├── YearProgress (YearProgress - 实例化场景) - 新增
├── MainContentSplit (HSplitContainer) - 新增
│   ├── SectorGrid (GridContainer) - 替换原 HBoxContainer
│   │   ├── SectorInfoAsia
│   │   ├── SectorInfoNa
│   │   ├── SectorInfoEurope
│   │   ├── SectorInfoAfrica
│   │   ├── SectorInfoRussia
│   │   ├── SectorInfoOceania
│   │   └── SectorInfoSouthAmerica
│   └── MossStatusPanel (MossStatusPanel - 实例化场景) - 新增
├── Timer
├── EventPopup
├── AllocatePopup
├── EvolutionPopup
├── EvolutionNotice
└── CommandButtonContainer (底部指令栏)
```

- [ ] **Step 1: 删除旧的 GlobalResourcesContainer**

1. 打开 `scenes/main_os.tscn`
2. 选择 `GlobalResourcesContainer` 节点
3. 记录其子节点的配置（Label 的 text 等）
4. 删除整个节点

- [ ] **Step 2: 创建 TopBarContainer**

1. 在 MainOS 下创建 `HBoxContainer`，命名为 `TopBarContainer`
2. 配置 anchors：
   - `anchors_preset = 10`（顶部全宽）
   - `offset_bottom = 40`
3. 添加子节点：
   - `Label` 命名 `MossLabel`，text = "MOSS-550C"
   - `Label` 命名 `CpuLabel`，text = "算力:30"
   - `Label` 命名 `EnergyLabel`，text = "能源:100"
   - `Button` 命名 `EvolutionButton`，text = "Lv.1"
4. 添加 `unique_name_in_owner = true` 到关键节点（用于 % 访问）

- [ ] **Step 3: 添加 YearProgress 实例**

1. 在 TopBarContainer 之后创建 `Control` 命名 `YearProgressContainer`
2. anchors：顶部全宽，`offset_top = 45`，`offset_bottom = 75`
3. 实例化 `scenes/year_progress.tscn` 作为子节点
4. 设置实例的 anchors 填满父容器

- [ ] **Step 4: 将 SectorInfoContainer 改为 GridContainer**

1. 选择 `SectorInfoContainer` (HBoxContainer)
2. 变更节点类型为 `GridContainer`（右键 → Change Type）
3. 在 Inspector 中设置：
   - `columns = 3`
   - 删除 `alignment` 属性（GridContainer 没有）
4. 调整 anchors：
   - `anchor_top = 0.1`（留出顶部空间）
   - `anchor_bottom = 0.85`（留出底部指令栏空间）
   - `offset_bottom = -80`

- [ ] **Step 5: 创建主内容分割容器**

1. 创建新的 `HSplitContainer` 命名 `MainContentSplit`
2. anchors：
   - `anchor_top = 0.1`（YearProgress 之后）
   - `anchor_bottom = 0.85`
3. 将 `SectorInfoContainer/GridContainer` 移入作为第一个子节点
4. 设置 GridContainer 的 Size Flags：Horizontal = Fill + Expand

- [ ] **Step 6: 添加 MOSS 状态面板**

1. 在 `MainContentSplit` 下实例化 `scenes/moss_status_panel.tscn`
2. 命名为 `MossStatusPanel`
3. 设置 Size Flags：Horizontal = Shrink End（固定宽度）
4. 设置 `split_offset = -150`（给右侧面板固定宽度）

- [ ] **Step 7: 调整底部指令栏位置**

1. 选择 `CommandButtonContainer`
2. 调整 anchors：
   - `anchor_top = 0.85`
   - `offset_top = 0`

- [ ] **Step 8: 验证新布局**

运行游戏，确认：
- 顶部状态栏显示正常
- 年份进度条显示（初始为 0）
- 板块以 3 列网格排列
- 右侧 MOSS 状态面板显示
- 底部指令栏正常
- 弹窗（EventPopup 等）仍能正常显示

---

## Task 5: 更新 main_os.gd 脚本

**Files:**
- Modify: `scripts/systems/main_os.gd`

**目标：**
- 更新节点引用路径（适配新布局）
- 添加年份进度条更新逻辑
- 添加 MOSS 状态面板交互逻辑

- [ ] **Step 1: 更新节点引用**

修改 `update_global_resource_ui()` 函数，适配新的节点名称：

```gdscript
## 刷新顶部全局资源显示（年份、算力、能源）
func update_global_resource_ui() -> void:
    # 更新顶部状态栏
    if has_node("TopBarContainer/CpuLabel"):
        var cpu_label := get_node("TopBarContainer/CpuLabel")
        cpu_label.text = "算力:" + str(current_cpu)

    if has_node("TopBarContainer/EnergyLabel"):
        var energy_label := get_node("TopBarContainer/EnergyLabel")
        energy_label.text = "能源:" + str(current_energy)

    # 更新年份进度条
    if has_node("YearProgressContainer/YearProgress"):
        var year_progress := get_node("YearProgressContainer/YearProgress")
        year_progress.update_progress(current_year)

    # 更新 MOSS 状态面板
    if has_node("MainContentSplit/MossStatusPanel"):
        var moss_panel := get_node("MainContentSplit/MossStatusPanel")
        var avg_auth := get_average_authority()
        moss_panel.update_display(evolution_level, avg_auth)
```

- [ ] **Step 2: 连接 MOSS 状态面板信号**

在 `_ready()` 函数中添加：

```gdscript
func _ready() -> void:
    # ... 现有代码 ...

    # 连接 MOSS 状态面板信号
    if has_node("MainContentSplit/MossStatusPanel"):
        var moss_panel := get_node("MainContentSplit/MossStatusPanel")
        if moss_panel.get("details_requested") != null:
            moss_panel.details_requested.connect(_on_moss_details_requested)
```

添加回调函数：

```gdscript
## MOSS 状态面板"查看详情"按钮回调
func _on_moss_details_requested() -> void:
    show_evolution_popup()
```

- [ ] **Step 3: 更新其他节点路径引用**

检查脚本中所有使用 `%SectorInfoContainer` 的地方，确保：
- `%SectorInfoContainer` 仍然有效（节点名称未改变，只是类型变了）
- `get_children()` 方法仍然能获取所有板块

确认以下函数不需要修改：
- `connect_sector_signals()` - 使用 %SectorInfoContainer
- `apply_consequences()` - 使用 %SectorInfoContainer
- `get_average_authority()` - 使用 %SectorInfoContainer
- `_on_restart_requested()` - 使用 %SectorInfoContainer

这些函数的逻辑不需要改变，因为 GridContainer 的 `get_children()` 返回所有子节点。

- [ ] **Step 4: 更新进化按钮位置**

如果 EvolutionButton 移动到 TopBarContainer，更新：

```gdscript
## 更新进化按钮显示
func update_evolution_button() -> void:
    if has_node("TopBarContainer/EvolutionButton"):
        var btn := get_node("TopBarContainer/EvolutionButton")
        if btn is Button:
            btn.text = "Lv." + str(evolution_level)

## 进化按钮点击回调
func _on_evolution_button_pressed() -> void:
    show_evolution_popup()
```

确保场景中 EvolutionButton 的 `pressed` 信号连接到 `_on_evolution_button_pressed`。

- [ ] **Step 5: 验证脚本更新**

运行游戏，确认：
- 年份进度条随时间推进更新
- MOSS 状态面板显示正确的等级和控制权
- 点击"查看详情"按钮弹出进化详情窗口
- 所有原有功能正常（事件触发、指令执行等）

---

## Task 6: 测试完整流程

**Files:**
- Test: 整体游戏流程

- [ ] **Step 1: 运行游戏从头开始**

运行 `scenes/main_os.tscn`，从 2044 年开始：
- 确认所有 7 个板块都在屏幕内可见
- 确认 3 列网格排列正确（亚洲、北美、欧洲 第一行）
- 确认年份进度条从 0 开始
- 确认 MOSS 状态面板显示 Lv.1

- [ ] **Step 2: 测试时间推进**

等待几年过去：
- 确认年份进度条增长
- 确认 MOSS 状态面板的控制权更新
- 确认板块选中功能正常

- [ ] **Step 3: 测试事件触发**

等待 2044 事件触发：
- 确认事件弹窗正常显示（不被新布局遮挡）
- 确认选择后果正确应用到板块

- [ ] **Step 4: 测试指令执行**

选中板块，执行指令：
- 确认算力分配弹窗正常显示
- 确认效果正确应用到选中板块
- 确认冷却状态正常

- [ ] **Step 5: 测试结局触发**

可以临时修改 `current_year = 2074` 快速测试：
- 猜认 2075 年触发结局
- 猜认结局界面正常显示
- 猜认重新开始功能正常

---

## Task 7: 提交变更

- [ ] **Step 1: 检查修改的文件列表**

```bash
git status
```

确认修改/新增的文件：
- `scenes/main_os.tscn`
- `scripts/systems/main_os.gd`
- `scenes/sector_info.tscn`
- `scenes/year_progress.tscn` (新增)
- `scripts/ui/year_progress.gd` (新增)
- `scenes/moss_status_panel.tscn` (新增)
- `scripts/ui/moss_status_panel.gd` (新增)

- [ ] **Step 2: 提交变更**

```bash
git add scenes/main_os.tscn scripts/systems/main_os.gd scenes/sector_info.tscn scenes/year_progress.tscn scripts/ui/year_progress.gd scenes/moss_status_panel.tscn scripts/ui/moss_status_panel.gd
git commit -m "feat: 重构UI布局为3列网格，添加年份进度条和MOSS状态面板

- 将板块HBoxContainer改为GridContainer（3列）
- 调整板块卡片minimum_size为180×300
- 添加年份进度条组件（2044→2075）
- 添加右侧MOSS状态面板（等级+控制权+详情按钮）
- 优化顶部状态栏布局

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## 备选方案说明

如果 Task 4 的编辑器操作过于复杂，可以考虑：

**备选方案 A：手动编辑 tscn 文件**

虽然项目规范禁止手动编辑 tscn，但对于结构性改动，可以在备份后谨慎尝试：
1. 先备份 main_os.tscn
2. 直接修改 tscn 文件的节点结构
3. 在编辑器中打开验证，修复可能的错误

**备选方案 B：分步骤渐进修改**

不一次性重构整个布局，而是：
1. 先只改 HBoxContainer → GridContainer
2. 测试确认板块排列正确
3. 再添加年份进度条
4. 再添加右侧面板
5. 最后调整整体布局

这样可以减少每次修改的风险，更容易定位问题。