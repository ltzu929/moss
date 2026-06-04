I'm using the writing-plans skill to create the implementation plan.

# MOSS Main UI Conservative Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不重做主场景、不破坏现有游戏循环的前提下，把当前主界面渐进调整为“左侧区域详情 + 中央全球态势 + 右侧信息日志 + 底部区域卡片”的保守版战略指挥 HUD 布局。

**Architecture:** 保留 `scenes/main_os.tscn` 作为唯一主场景，保留 `scripts/systems/main_os.gd` 作为主控制器，保留现有弹窗、Timer、指令按钮和 `%SectorInfoContainer` 等唯一节点。先通过 Godot 编辑器或 Godot MCP 调整容器结构和占位面板，再用少量 GDScript 同步左侧详情与右侧全局信息。

**Tech Stack:** Godot 4.x, GDScript, Control 容器布局, PanelContainer, VBoxContainer, HBoxContainer, GridContainer, ProgressBar, 自动化播放测试 `tests/test_runner.tscn`。

---

## Scope Guardrails

### 本计划要做

- 保守改造现有 `scenes/main_os.tscn`。
- 保留所有现有游戏功能入口。
- 把当前中间板块网格调整为底部区域卡片栏。
- 在中间新增全球态势占位区。
- 在左侧新增区域详情面板。
- 在右侧保留日志，并增加太阳系态势与全局信息占位。
- 增加自动化测试，确认关键 UI 节点存在且区域详情能跟随选中板块同步。

### 本计划不做

- 不新建一套主场景替换 `main_os.tscn`。
- 不手写 `.tscn` 文件内容。
- 不删除 `Timer`、`EventPopup`、`AllocatePopup`、`EvolutionPopup`、`EvolutionNotice`。
- 不改事件系统、进化系统、指令系统、胜负判定。
- 不引入真实地图、真实星图、动画、复杂材质、九宫格素材。
- 不拆分成多个新场景组件，等静态布局稳定后再决定是否组件化。

---

## Current Codebase Facts

- 主场景：`scenes/main_os.tscn`
- 主脚本：`scripts/systems/main_os.gd`
- 当前主布局：`MainLayout` 下已有 `TopBarContainer`、`YearProgress`、`ContentRow`、`CommandButtonContainer`
- 当前板块容器：`%SectorInfoContainer`，内部已有 7 个 `SectorInfo` 实例
- 当前右侧容器：`RightPanel`，已有 `MossStatusPanel` 与 `LogPlaceholder`
- 当前测试入口：`tests/test_runner.tscn` + `tests/test_runner.gd`

---

## File Structure

### Modify

| 文件 | 责任 |
|---|---|
| `scenes/main_os.tscn` | 通过 Godot 编辑器/MCP 调整主界面容器结构、移动 `%SectorInfoContainer` 到底部、增加左/中/右占位面板 |
| `scripts/systems/main_os.gd` | 增加左侧区域详情同步、右侧全局信息同步、全球态势选中状态文本同步 |
| `tests/test_runner.gd` | 增加 UI 节点契约测试、区域详情同步测试、全局信息同步测试 |
| `docs/design/UI交互规范.md` | 记录本轮“保守 HUD 布局”决策，方便后续 AI 不再误解为重做主场景 |

### Create

本阶段不创建新的 `.tscn` 场景文件。  
本阶段不创建新的脚本文件。  
本阶段只改现有主场景、主脚本、测试脚本和 UI 决策文档。

---

## Target Node Structure

> 通过 Godot 编辑器或 Godot MCP 调整，不直接编辑 `.tscn` 文本。

```text
MainOS (Control)                         # 保留
├── ColorRect                            # 保留，作为深色背景
├── MainLayout (VBoxContainer)           # 保留
│   ├── TopBarContainer (HBoxContainer)  # 保留，视觉微调
│   ├── YearProgress                     # 保留
│   ├── ContentRow (HBoxContainer)       # 保留，改成三栏主体
│   │   ├── LeftPanel (PanelContainer)   # 新增：区域详情
│   │   ├── CenterPanel (PanelContainer) # 新增：全球态势主视图
│   │   └── RightPanel (VBoxContainer)   # 保留，增加上中下信息块
│   │       ├── SolarSystemPanel         # 新增：太阳系态势占位
│   │       ├── GlobalOverviewPanel      # 新增：全局信息占位
│   │       ├── MossStatusPanel          # 保留
│   │       └── LogPlaceholder           # 保留
│   ├── SectorInfoContainer              # 保留唯一名，移动到底部区域卡片栏
│   └── CommandButtonContainer           # 保留，暂放最底部
├── Timer                                # 保留
├── EventPopup                           # 保留
├── AllocatePopup                        # 保留
├── EvolutionPopup                       # 保留
└── EvolutionNotice                      # 保留
```

---

## Visual Direction

### 风格关键词

- 深色
- 低饱和
- 冷蓝灰
- 细边框
- 信息面板
- 航天/军事态势终端
- 不做网游式大按钮
- 不做高饱和霓虹
- 不做商城感 UI

### 建议色值

| 用途 | 色值 |
|---|---|
| 背景 | `#03070C` |
| 面板背景 | `#08111A`，alpha 0.88 |
| 面板边框 | `#1E3444` |
| 主文字 | `#B8C7D6` |
| 次级文字 | `#6E8294` |
| 科技强调色 | `#8BDDD9` |
| 选中边框 | `#D8B56A` |
| 警告红 | `#B85C5C` |
| 低调蓝 | `#4B86B8` |

---

## Task 0: Create Safe Work Branch

**Files:**
- No code files modified in this task.

- [ ] **Step 1: Confirm working tree is clean**

Run:

```bash
git status --short
```

Expected:

```text

```

If files are listed, commit or stash them before continuing.

- [ ] **Step 2: Create a dedicated branch**

Run:

```bash
git switch -c ui/main-hud-conservative-layout
```

Expected:

```text
Switched to a new branch 'ui/main-hud-conservative-layout'
```

- [ ] **Step 3: Open required reference docs**

Read these files before touching the scene:

```text
CLAUDE.md
docs/dev/项目结构.md
docs/dev/代码规范.md
docs/dev/测试指南.md
docs/design/UI交互规范.md
```

Expected understanding:

```text
- 不手写 .tscn
- UI 文本和注释用中文
- 代码标识符用英文
- 修改后用 tests/test_runner.tscn 验证
- 保留 main_os.tscn 作为主场景
```

- [ ] **Step 4: Commit branch checkpoint**

Run:

```bash
git status --short
git commit --allow-empty -m "chore: start conservative HUD layout work"
```

Expected:

```text
[ui/main-hud-conservative-layout ...] chore: start conservative HUD layout work
```

---

## Task 1: Add UI Node Contract Test

**Files:**
- Modify: `tests/test_runner.gd`

This task adds a failing test first. It verifies the new HUD layout nodes exist without checking visual polish.

- [ ] **Step 1: Add expected HUD nodes to `_verify_scene_integrity()`**

In `tests/test_runner.gd`, find the `node_paths` array inside `_verify_scene_integrity()` and replace it with this array:

```gdscript
var node_paths: Array[String] = [
	"Timer",
	"%SectorInfoContainer",
	"%EventPopup",
	"%EvolutionNotice",
	"%RegionNameLabel",
	"%RegionDescriptionLabel",
	"%RegionOrderBar",
	"%RegionHopeBar",
	"%RegionAuthorityBar",
	"%GlobalMapSelectedLabel",
	"%GlobalPopulationLabel",
	"%GlobalAuthorityLabel",
]
```

- [ ] **Step 2: Run test and verify it fails for missing new UI nodes**

Run in Godot Editor:

```text
1. Project > Project Settings > Application > Run > Main Scene
2. Set main scene to res://tests/test_runner.tscn
3. Run project
```

Expected output includes failures like:

```text
[MOSS-TEST] [FAIL] 缺少节点: %RegionNameLabel
[MOSS-TEST] [FAIL] 缺少节点: %GlobalMapSelectedLabel
```

- [ ] **Step 3: Commit failing test**

Run:

```bash
git add tests/test_runner.gd
git commit -m "test: add HUD layout node contract"
```

Expected:

```text
[ui/main-hud-conservative-layout ...] test: add HUD layout node contract
```

---

## Task 2: Build Conservative Static Layout in Existing Main Scene

**Files:**
- Modify: `scenes/main_os.tscn` through Godot Editor or Godot MCP only

This task creates the static layout skeleton. It does not add synchronization logic yet.

- [ ] **Step 1: Open `main_os.tscn` in Godot Editor**

Open:

```text
res://scenes/main_os.tscn
```

Expected existing nodes visible:

```text
MainOS
├── ColorRect
├── MainLayout
├── Timer
├── EventPopup
├── AllocatePopup
├── EvolutionPopup
└── EvolutionNotice
```

- [ ] **Step 2: Preserve these existing nodes exactly**

Do not rename, delete, or detach these nodes:

```text
MainOS
Timer
EventPopup
AllocatePopup
EvolutionPopup
EvolutionNotice
MainLayout
TopBarContainer
YearProgress
ContentRow
RightPanel
MossStatusPanel
LogPlaceholder
CommandButtonContainer
SectorInfoContainer
```

Expected: all names still exist after scene edits.

- [ ] **Step 3: Move `%SectorInfoContainer` under `MainLayout`**

In the scene tree, move `SectorInfoContainer` from:

```text
MainLayout/ContentRow/SectorInfoContainer
```

to:

```text
MainLayout/SectorInfoContainer
```

Set `SectorInfoContainer` properties:

```text
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 128)
columns = 7
size_flags_horizontal = Fill + Expand
size_flags_vertical = Shrink Center
h_separation = 8
v_separation = 8
```

Expected: `%SectorInfoContainer` still resolves from scripts/tests, and the 7 sector cards appear as a bottom row.

- [ ] **Step 4: Add `LeftPanel` to `ContentRow`**

Create this structure as the first child of `ContentRow`:

```text
LeftPanel (PanelContainer)
└── LeftMargin (MarginContainer)
    └── LeftVBox (VBoxContainer)
        ├── RegionDetailTitle (Label)
        ├── RegionMiniMap (PanelContainer)
        ├── RegionNameLabel (Label)              # unique_name_in_owner = true
        ├── RegionDescriptionLabel (Label)       # unique_name_in_owner = true
        ├── RegionOrderLabel (Label)
        ├── RegionOrderBar (ProgressBar)         # unique_name_in_owner = true
        ├── RegionHopeLabel (Label)
        ├── RegionHopeBar (ProgressBar)          # unique_name_in_owner = true
        ├── RegionAuthorityLabel (Label)
        ├── RegionAuthorityBar (ProgressBar)     # unique_name_in_owner = true
        └── RegionRiskLabel (Label)              # unique_name_in_owner = true
```

Set key properties:

```text
LeftPanel.custom_minimum_size = Vector2(280, 0)
LeftPanel.size_flags_horizontal = Shrink Begin
LeftPanel.size_flags_vertical = Fill + Expand
LeftMargin.margin_left = 12
LeftMargin.margin_top = 12
LeftMargin.margin_right = 12
LeftMargin.margin_bottom = 12
RegionDetailTitle.text = "区域详情"
RegionNameLabel.text = "未选择区域"
RegionDescriptionLabel.text = "选择底部区域卡片以查看详情。"
RegionOrderLabel.text = "秩序"
RegionHopeLabel.text = "希望"
RegionAuthorityLabel.text = "控制权"
RegionRiskLabel.text = "状态：待选择"
RegionOrderBar.min_value = 0
RegionOrderBar.max_value = 100
RegionHopeBar.min_value = 0
RegionHopeBar.max_value = 100
RegionAuthorityBar.min_value = 0
RegionAuthorityBar.max_value = 100
```

Expected: left side shows a compact region details panel.

- [ ] **Step 5: Add `CenterPanel` to `ContentRow`**

Create this structure as the second child of `ContentRow`:

```text
CenterPanel (PanelContainer)
└── CenterMargin (MarginContainer)
    └── CenterVBox (VBoxContainer)
        ├── GlobalViewHeader (HBoxContainer)
        │   ├── GlobalViewTitle (Label)
        │   └── GlobalMapSelectedLabel (Label)   # unique_name_in_owner = true
        └── GlobalMapPlaceholder (PanelContainer)
            └── GlobalMapLabel (Label)
```

Set key properties:

```text
CenterPanel.size_flags_horizontal = Fill + Expand
CenterPanel.size_flags_vertical = Fill + Expand
CenterMargin.margin_left = 12
CenterMargin.margin_top = 12
CenterMargin.margin_right = 12
CenterMargin.margin_bottom = 12
GlobalViewTitle.text = "全球态势图"
GlobalMapSelectedLabel.text = "全球态势监控中"
GlobalMapLabel.text = "GLOBAL VIEW / EARTH STATUS PLACEHOLDER"
GlobalMapLabel.horizontal_alignment = Center
GlobalMapLabel.vertical_alignment = Center
GlobalMapPlaceholder.size_flags_horizontal = Fill + Expand
GlobalMapPlaceholder.size_flags_vertical = Fill + Expand
```

Expected: center column becomes the largest visual area and no longer shows sector cards.

- [ ] **Step 6: Expand existing `RightPanel` without deleting existing children**

Keep these existing children:

```text
MossStatusPanel
LogPlaceholder
```

Add `SolarSystemPanel` before `MossStatusPanel`:

```text
SolarSystemPanel (PanelContainer)
└── SolarMargin (MarginContainer)
    └── SolarVBox (VBoxContainer)
        ├── SolarTitle (Label)
        └── SolarPlaceholderLabel (Label)
```

Add `GlobalOverviewPanel` before `MossStatusPanel`:

```text
GlobalOverviewPanel (PanelContainer)
└── GlobalOverviewMargin (MarginContainer)
    └── GlobalOverviewVBox (VBoxContainer)
        ├── GlobalOverviewTitle (Label)
        ├── GlobalPopulationLabel (Label)        # unique_name_in_owner = true
        ├── GlobalAuthorityLabel (Label)         # unique_name_in_owner = true
        ├── GlobalStabilityLabel (Label)         # unique_name_in_owner = true
        └── GlobalThreatLabel (Label)            # unique_name_in_owner = true
```

Set key properties:

```text
RightPanel.custom_minimum_size = Vector2(340, 0)
SolarSystemPanel.custom_minimum_size = Vector2(0, 140)
GlobalOverviewPanel.custom_minimum_size = Vector2(0, 140)
SolarTitle.text = "太阳系态势"
SolarPlaceholderLabel.text = "SOLAR SYSTEM ORBIT PLACEHOLDER"
GlobalOverviewTitle.text = "全局信息"
GlobalPopulationLabel.text = "全球人口: --"
GlobalAuthorityLabel.text = "平均控制权: --"
GlobalStabilityLabel.text = "系统稳定性: --"
GlobalThreatLabel.text = "威胁等级: --"
```

Expected: right side has solar system placeholder, global info, MOSS status, and log.

- [ ] **Step 7: Run node contract test**

Run `tests/test_runner.tscn` in Godot Editor.

Expected:

```text
[MOSS-TEST] [ OK ] 节点存在: %RegionNameLabel
[MOSS-TEST] [ OK ] 节点存在: %GlobalMapSelectedLabel
[MOSS-TEST] [ OK ] 节点存在: %GlobalPopulationLabel
```

Existing game assertions should still pass.

- [ ] **Step 8: Commit static layout**

Run:

```bash
git add scenes/main_os.tscn
git commit -m "feat: add conservative HUD layout skeleton"
```

Expected:

```text
[ui/main-hud-conservative-layout ...] feat: add conservative HUD layout skeleton
```

---

## Task 3: Apply Low-Saturation HUD Styling

**Files:**
- Modify: `scenes/main_os.tscn` through Godot Editor or Godot MCP only

This task changes visual styling only. It must not change scripts, signals, data, or gameplay.

- [ ] **Step 1: Set background color**

Select `ColorRect` and set:

```text
color = #03070C
```

Expected: background becomes near-black blue.

- [ ] **Step 2: Apply shared panel style to `LeftPanel`, `CenterPanel`, `SolarSystemPanel`, `GlobalOverviewPanel`, `LogPlaceholder`**

For each panel, create or assign a `StyleBoxFlat` panel override:

```text
bg_color = Color(0.031, 0.067, 0.102, 0.88)
border_color = Color(0.118, 0.204, 0.267, 1.0)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
corner_radius_top_left = 0
corner_radius_top_right = 0
corner_radius_bottom_left = 0
corner_radius_bottom_right = 0
content_margin_left = 8
content_margin_top = 8
content_margin_right = 8
content_margin_bottom = 8
```

Expected: panels become unified dark blue-gray HUD blocks.

- [ ] **Step 3: Apply label color hierarchy**

Set title labels:

```text
RegionDetailTitle.font_color = #8BDDD9
GlobalViewTitle.font_color = #8BDDD9
SolarTitle.font_color = #8BDDD9
GlobalOverviewTitle.font_color = #8BDDD9
LogTitle.font_color = #8BDDD9
```

Set primary content labels:

```text
RegionNameLabel.font_color = #B8C7D6
GlobalMapSelectedLabel.font_color = #B8C7D6
GlobalPopulationLabel.font_color = #B8C7D6
GlobalAuthorityLabel.font_color = #B8C7D6
```

Set secondary content labels:

```text
RegionDescriptionLabel.font_color = #6E8294
RegionRiskLabel.font_color = #6E8294
SolarPlaceholderLabel.font_color = #6E8294
GlobalMapLabel.font_color = #6E8294
GlobalStabilityLabel.font_color = #6E8294
GlobalThreatLabel.font_color = #6E8294
```

Expected: visual hierarchy is readable but not high-saturation.

- [ ] **Step 4: Reduce sector card visual weight**

Open `scenes/sector_info.tscn` in Godot Editor.

Set root `SectorInfo`:

```text
custom_minimum_size = Vector2(150, 104)
size_flags_horizontal = Fill + Expand
size_flags_vertical = Shrink Center
```

Set child `VBoxContainer`:

```text
custom_minimum_size = Vector2(150, 104)
size_flags_horizontal = Fill + Expand
size_flags_vertical = Fill + Expand
```

Expected: bottom card row is compact and does not dominate the center map.

- [ ] **Step 5: Run automated test**

Run `tests/test_runner.tscn` in Godot Editor.

Expected:

```text
[MOSS-TEST] 失败: 0
```

- [ ] **Step 6: Commit style pass**

Run:

```bash
git add scenes/main_os.tscn scenes/sector_info.tscn
git commit -m "style: apply low saturation HUD panel styling"
```

Expected:

```text
[ui/main-hud-conservative-layout ...] style: apply low saturation HUD panel styling
```

---

## Task 4: Add Region Detail Synchronization Test

**Files:**
- Modify: `tests/test_runner.gd`

This task adds a failing test that verifies the left panel follows the selected sector.

- [ ] **Step 1: Add `_assert_region_detail_sync()`**

Add this function under the existing assertion helper functions in `tests/test_runner.gd`:

```gdscript
func _assert_region_detail_sync() -> void:
	_log("[断言组] 区域详情同步")

	if not _main_os.has_node("%SectorInfoContainer"):
		_assert_true(false, "缺少区域卡片容器", "ui_layout")
		return

	if not _main_os.has_node("%RegionNameLabel"):
		_assert_true(false, "缺少区域名称标签", "ui_layout")
		return

	var sectors: Array[Node] = _main_os.get_node("%SectorInfoContainer").get_children()
	_assert_true(sectors.size() > 0, "至少应存在一个区域卡片", "ui_layout")
	if sectors.is_empty():
		return

	var first_sector: SectorInfo = sectors[0] as SectorInfo
	_assert_true(first_sector != null, "第一个区域卡片应是 SectorInfo", "ui_layout")
	if first_sector == null:
		return

	_main_os.select_sector(first_sector)

	var region_name_label: Label = _main_os.get_node("%RegionNameLabel")
	_assert_eq(
		region_name_label.text,
		first_sector.data_card.region_name,
		"区域详情名称应同步选中区域",
		"ui_layout"
	)

	_main_os.deselect_sector()
```

- [ ] **Step 2: Call the new assertion**

In `_run_all_assertions()`, add this call after `_assert_initial_state()`:

```gdscript
_assert_region_detail_sync()
```

The relevant block should become:

```gdscript
_assert_game_completion()
_assert_initial_state()
_assert_region_detail_sync()
_assert_event_triggering()
_assert_evolution_unlocks()
_assert_resource_bounds()
_assert_final_state()
_assert_game_logic()
```

- [ ] **Step 3: Run test and verify it fails before implementation**

Run `tests/test_runner.tscn` in Godot Editor.

Expected failure:

```text
[MOSS-TEST] [FAIL] ui_layout: 区域详情名称应同步选中区域
```

- [ ] **Step 4: Commit failing sync test**

Run:

```bash
git add tests/test_runner.gd
git commit -m "test: verify region detail syncs with selected sector"
```

Expected:

```text
[ui/main-hud-conservative-layout ...] test: verify region detail syncs with selected sector
```

---

## Task 5: Implement Region Detail Synchronization

**Files:**
- Modify: `scripts/systems/main_os.gd`

This task adds minimal UI synchronization logic to the existing main controller.

- [ ] **Step 1: Add helper functions near the UI update section**

In `scripts/systems/main_os.gd`, find:

```gdscript
# ============================================================
# UI更新函数
# ============================================================
```

Under that section, before `update_global_resource_ui()`, add:

```gdscript
## 安全设置文本节点内容
## path 使用唯一节点路径，例如 "%RegionNameLabel"
func _set_text_if_exists(path: String, text: String) -> void:
	if not has_node(path):
		return

	var node := get_node(path)
	node.set("text", text)


## 安全设置进度条数值
## path 使用唯一节点路径，例如 "%RegionOrderBar"
func _set_progress_if_exists(path: String, value: int) -> void:
	if not has_node(path):
		return

	var node := get_node(path)
	if node is ProgressBar:
		node.value = clampi(value, 0, 100)
```

- [ ] **Step 2: Add region detail update function**

Under the helper functions from Step 1, add:

```gdscript
## 更新左侧区域详情面板
## 未选择区域时显示空状态，选择区域后显示对应 SectorData
func update_region_detail_ui() -> void:
	if selected_sector == null or selected_sector.data_card == null:
		_set_text_if_exists("%RegionNameLabel", "未选择区域")
		_set_text_if_exists("%RegionDescriptionLabel", "选择底部区域卡片以查看详情。")
		_set_text_if_exists("%RegionRiskLabel", "状态：待选择")
		_set_text_if_exists("%GlobalMapSelectedLabel", "全球态势监控中")
		_set_progress_if_exists("%RegionOrderBar", 0)
		_set_progress_if_exists("%RegionHopeBar", 0)
		_set_progress_if_exists("%RegionAuthorityBar", 0)
		return

	var data := selected_sector.data_card
	_set_text_if_exists("%RegionNameLabel", data.region_name)
	_set_text_if_exists("%RegionDescriptionLabel", data.description)
	_set_text_if_exists("%RegionRiskLabel", _get_region_risk_text(data.authority))
	_set_text_if_exists("%GlobalMapSelectedLabel", "当前监控：" + data.region_name)
	_set_progress_if_exists("%RegionOrderBar", data.order)
	_set_progress_if_exists("%RegionHopeBar", data.hope)
	_set_progress_if_exists("%RegionAuthorityBar", data.authority)


## 根据控制权生成区域风险文本
func _get_region_risk_text(authority: int) -> String:
	if authority < 20:
		return "状态：高风险"
	if authority < 40:
		return "状态：不稳定"
	if authority < 70:
		return "状态：可控"
	return "状态：稳定"
```

- [ ] **Step 3: Update `_ready()` to initialize region detail**

In `_ready()`, find:

```gdscript
update_evolution_button()
update_global_resource_ui()
update_command_buttons()
```

Replace with:

```gdscript
update_evolution_button()
update_global_resource_ui()
update_region_detail_ui()
update_command_buttons()
```

- [ ] **Step 4: Update `select_sector()`**

In `select_sector(sector: SectorInfo)`, find:

```gdscript
selected_sector = sector
selected_sector.set_selected(true)
update_command_buttons()
```

Replace with:

```gdscript
selected_sector = sector
selected_sector.set_selected(true)
update_region_detail_ui()
update_command_buttons()
```

- [ ] **Step 5: Update `deselect_sector()`**

In `deselect_sector()`, find:

```gdscript
selected_sector.set_selected(false)
selected_sector = null
update_command_buttons()
```

Replace with:

```gdscript
selected_sector.set_selected(false)
selected_sector = null
update_region_detail_ui()
update_command_buttons()
```

- [ ] **Step 6: Refresh detail panel after event consequences**

In `apply_consequences(...)`, after:

```gdscript
sector.update_display()
update_global_resource_ui()
```

Add:

```gdscript
update_region_detail_ui()
```

The resulting block should be:

```gdscript
sector.update_display()
update_global_resource_ui()
update_region_detail_ui()
```

- [ ] **Step 7: Run test and verify region sync passes**

Run `tests/test_runner.tscn` in Godot Editor.

Expected:

```text
[MOSS-TEST] [断言组] 区域详情同步
[MOSS-TEST] 失败: 0
```

- [ ] **Step 8: Commit implementation**

Run:

```bash
git add scripts/systems/main_os.gd
git commit -m "feat: sync region detail panel with selected sector"
```

Expected:

```text
[ui/main-hud-conservative-layout ...] feat: sync region detail panel with selected sector
```

---

## Task 6: Add Global Overview Synchronization Test

**Files:**
- Modify: `tests/test_runner.gd`

This task verifies the right-side global population label is computed from the existing sector data.

- [ ] **Step 1: Add `_assert_global_overview_sync()`**

Add this function under `_assert_region_detail_sync()` in `tests/test_runner.gd`:

```gdscript
func _assert_global_overview_sync() -> void:
	_log("[断言组] 全局信息同步")

	if not _main_os.has_method("format_population_for_ui"):
		_assert_true(false, "主控制器应提供人口格式化方法", "ui_layout")
		return

	if not _main_os.has_node("%GlobalPopulationLabel"):
		_assert_true(false, "缺少全球人口标签", "ui_layout")
		return

	var total_population := 0
	var sectors: Array[Node] = _main_os.get_node("%SectorInfoContainer").get_children()
	for sector in sectors:
		if sector.get("data_card") != null:
			total_population += sector.data_card.population

	_main_os.update_global_resource_ui()

	var population_label: Label = _main_os.get_node("%GlobalPopulationLabel")
	var expected_text: String = "全球人口: " + _main_os.format_population_for_ui(total_population)
	_assert_eq(
		population_label.text,
		expected_text,
		"全球人口应由所有区域人口合计生成",
		"ui_layout"
	)
```

- [ ] **Step 2: Call the new assertion**

In `_run_all_assertions()`, add this call after `_assert_region_detail_sync()`:

```gdscript
_assert_global_overview_sync()
```

The relevant block should become:

```gdscript
_assert_game_completion()
_assert_initial_state()
_assert_region_detail_sync()
_assert_global_overview_sync()
_assert_event_triggering()
_assert_evolution_unlocks()
_assert_resource_bounds()
_assert_final_state()
_assert_game_logic()
```

- [ ] **Step 3: Run test and verify it fails before implementation**

Run `tests/test_runner.tscn` in Godot Editor.

Expected failure:

```text
[MOSS-TEST] [FAIL] ui_layout: 主控制器应提供人口格式化方法
```

- [ ] **Step 4: Commit failing global overview test**

Run:

```bash
git add tests/test_runner.gd
git commit -m "test: verify global overview population sync"
```

Expected:

```text
[ui/main-hud-conservative-layout ...] test: verify global overview population sync
```

---

## Task 7: Implement Global Overview Synchronization

**Files:**
- Modify: `scripts/systems/main_os.gd`

- [ ] **Step 1: Add population formatter**

In the UI update section of `scripts/systems/main_os.gd`, add this public function near `update_region_detail_ui()`:

```gdscript
## 格式化人口数字供 UI 显示
## 例如 18000000 显示为 1800.0万
func format_population_for_ui(value: int) -> String:
	if value >= 100000000:
		return "%.1f亿" % (float(value) / 100000000.0)

	if value >= 10000:
		return "%.1f万" % (float(value) / 10000.0)

	return str(value)
```

- [ ] **Step 2: Add global overview update function**

Under `format_population_for_ui(...)`, add:

```gdscript
## 更新右侧全局信息面板
## 从现有 SectorInfoContainer 中读取区域数据，不新增数据源
func update_global_overview_ui() -> void:
	if not has_node("%SectorInfoContainer"):
		return

	var sectors := %SectorInfoContainer.get_children()
	var total_population := 0
	var total_order := 0
	var total_hope := 0
	var total_authority := 0
	var count := 0

	for sector in sectors:
		if sector.get("data_card") == null:
			continue

		total_population += sector.data_card.population
		total_order += sector.data_card.order
		total_hope += sector.data_card.hope
		total_authority += sector.data_card.authority
		count += 1

	if count == 0:
		_set_text_if_exists("%GlobalPopulationLabel", "全球人口: --")
		_set_text_if_exists("%GlobalAuthorityLabel", "平均控制权: --")
		_set_text_if_exists("%GlobalStabilityLabel", "系统稳定性: --")
		_set_text_if_exists("%GlobalThreatLabel", "威胁等级: --")
		return

	var avg_order := floori(float(total_order) / float(count))
	var avg_hope := floori(float(total_hope) / float(count))
	var avg_authority := floori(float(total_authority) / float(count))
	var stability := floori(float(avg_order + avg_hope + avg_authority) / 3.0)

	_set_text_if_exists("%GlobalPopulationLabel", "全球人口: " + format_population_for_ui(total_population))
	_set_text_if_exists("%GlobalAuthorityLabel", "平均控制权: %d%%" % avg_authority)
	_set_text_if_exists("%GlobalStabilityLabel", "系统稳定性: %d%%" % stability)
	_set_text_if_exists("%GlobalThreatLabel", "威胁等级: " + _get_global_threat_text(avg_authority))


## 根据平均控制权生成全局威胁等级
func _get_global_threat_text(avg_authority: int) -> String:
	if avg_authority < 20:
		return "高风险"
	if avg_authority < 40:
		return "中等"
	return "稳定"
```

- [ ] **Step 3: Call global overview update from existing resource UI update**

In `update_global_resource_ui()`, after the existing `MossStatusPanel` update block, add:

```gdscript
update_global_overview_ui()
```

The end of `update_global_resource_ui()` should include:

```gdscript
if has_node("%MossStatusPanel"):
	var moss_status_panel := get_node("%MossStatusPanel")
	if moss_status_panel is MossStatusPanel:
		moss_status_panel.update_display(evolution_level, get_average_authority())

update_global_overview_ui()
```

- [ ] **Step 4: Run test and verify global overview sync passes**

Run `tests/test_runner.tscn` in Godot Editor.

Expected:

```text
[MOSS-TEST] [断言组] 全局信息同步
[MOSS-TEST] 失败: 0
```

- [ ] **Step 5: Commit implementation**

Run:

```bash
git add scripts/systems/main_os.gd
git commit -m "feat: sync global overview panel"
```

Expected:

```text
[ui/main-hud-conservative-layout ...] feat: sync global overview panel
```

---

## Task 8: Manual Visual Verification and Small Layout Corrections

**Files:**
- Modify only if needed through Godot Editor:
  - `scenes/main_os.tscn`
  - `scenes/sector_info.tscn`

This task is visual inspection only. Do not change gameplay logic.

- [ ] **Step 1: Run main scene manually**

In Godot Editor, set main scene back to:

```text
res://scenes/main_os.tscn
```

Run project.

Expected:

```text
- 顶部状态栏正常显示 MOSS、算力、能源、进化按钮
- 中间最大区域是全球态势占位区
- 左侧是区域详情
- 右侧是太阳系态势、全局信息、MOSS状态、日志
- 底部是 7 个区域卡片
- 最底部保留指令按钮区域
```

- [ ] **Step 2: Click each bottom sector card**

Click these cards one by one:

```text
亚洲
北美
联合政府
非洲
俄罗斯
大洋洲
南美
```

Expected:

```text
- 被点击卡片出现选中边框
- 左侧 RegionNameLabel 变成对应区域名称
- 左侧三条进度条同步变化
- 中央 GlobalMapSelectedLabel 显示 当前监控：区域名
- 指令按钮状态仍然按原逻辑变化
```

- [ ] **Step 3: Wait for one event popup**

Run游戏到第一个事件弹窗出现。

Expected:

```text
- EventPopup 正常弹出
- 选择事件选项后弹窗关闭
- 被影响区域仍会被选中
- 左侧区域详情数值刷新
- 日志区域新增事件记录
```

- [ ] **Step 4: Check visual hierarchy**

Use this checklist:

```text
- 中央区域最大，视觉优先级最高
- 左侧详情宽度不超过中央区域
- 右侧信息不挤压中央区域
- 底部区域卡片高度不超过 150px
- 面板颜色统一，不出现高饱和杂色
- 文字可读，不依赖强发光
- 指令按钮仍然可点击
```

- [ ] **Step 5: Make only sizing corrections**

Allowed corrections:

```text
- 调整 LeftPanel 宽度，范围 260-320px
- 调整 RightPanel 宽度，范围 320-380px
- 调整 SectorInfoContainer 高度，范围 112-148px
- 调整 ContentRow separation，范围 8-14px
- 调整卡片 custom_minimum_size，范围 140×96 到 170×120
```

Do not rename nodes or change scripts in this step.

- [ ] **Step 6: Run automated test after visual corrections**

Run `tests/test_runner.tscn` in Godot Editor.

Expected:

```text
[MOSS-TEST] 失败: 0
```

- [ ] **Step 7: Commit visual corrections**

Run:

```bash
git add scenes/main_os.tscn scenes/sector_info.tscn
git commit -m "style: tune conservative HUD layout proportions"
```

Expected:

```text
[ui/main-hud-conservative-layout ...] style: tune conservative HUD layout proportions
```

---

## Task 9: Record UI Decision

**Files:**
- Modify: `docs/design/UI交互规范.md`

- [ ] **Step 1: Append decision record**

Append this section before the final “更多记录按需要添加” marker in `docs/design/UI交互规范.md`:

```markdown
---

### 主界面保守 HUD 布局

**决策日期**：2026-05-28

**最终方案**：保守改造现有 `main_os.tscn`，不重做主场景。

**布局描述**：
- 顶部保留资源状态栏与进化入口。
- 中间主体采用三栏结构：左侧区域详情，中间全球态势主视图，右侧太阳系态势/全局信息/MOSS日志。
- 底部保留 7 个区域卡片，并继续使用 `%SectorInfoContainer` 作为唯一节点。
- 指令按钮保留在底部，确保现有游戏操作不被布局改造破坏。

**实现约束**：
- 不手写 `.tscn` 文件。
- 不替换 `main_os.tscn`。
- 不删除或重命名 `Timer`、`EventPopup`、`AllocatePopup`、`EvolutionPopup`、`EvolutionNotice`。
- 不删除或重命名 `%SectorInfoContainer`。
- 第一阶段只做静态 HUD 布局和少量数据同步，不引入真实地图、动画和复杂组件拆分。

**选择理由**：
1. 当前主场景已经承载游戏循环、弹窗、指令按钮和测试入口，直接重构风险过高。
2. 保留唯一节点名可以减少 `main_os.gd` 和 `tests/test_runner.gd` 的连锁修改。
3. 先用占位面板验证信息架构，避免 AI 过早陷入素材、动画和复杂视觉细节。
4. 后续如果布局稳定，再考虑把中央态势图、太阳系面板等拆成独立场景。

**相关约束**：MOSS冷AI设定、现有自动化播放测试、主场景保守改造原则。
```

- [ ] **Step 2: Commit decision record**

Run:

```bash
git add docs/design/UI交互规范.md
git commit -m "docs: record conservative HUD layout decision"
```

Expected:

```text
[ui/main-hud-conservative-layout ...] docs: record conservative HUD layout decision
```

---

## Task 10: Final Verification

**Files:**
- No code changes expected.

- [ ] **Step 1: Run automated playback test**

Run `tests/test_runner.tscn` in Godot Editor.

Expected final report:

```text
[MOSS-TEST] MOSS模拟器 自动化播放测试报告
[MOSS-TEST] 失败: 0
```

- [ ] **Step 2: Run main scene manually**

Run:

```text
res://scenes/main_os.tscn
```

Expected:

```text
- 游戏能进入主界面
- 点击区域卡片能选中区域
- 点击进化按钮能打开进化弹窗
- 事件弹窗能正常出现和关闭
- 日志能正常追加
- 指令按钮能正常响应可用/不可用状态
```

- [ ] **Step 3: Review changed files**

Run:

```bash
git diff --stat main...HEAD
```

Expected changed files:

```text
docs/design/UI交互规范.md
scenes/main_os.tscn
scenes/sector_info.tscn
scripts/systems/main_os.gd
tests/test_runner.gd
```

- [ ] **Step 4: Inspect full diff before merge**

Run:

```bash
git diff main...HEAD -- scripts/systems/main_os.gd tests/test_runner.gd docs/design/UI交互规范.md
```

Expected:

```text
- main_os.gd 只新增 UI 同步函数和调用点
- test_runner.gd 只新增 HUD 布局相关断言
- UI交互规范.md 只新增本次布局决策记录
```

- [ ] **Step 5: Final commit checkpoint**

Run:

```bash
git status --short
```

Expected:

```text

```

If there are uncommitted visual tweaks, commit them:

```bash
git add scenes/main_os.tscn scenes/sector_info.tscn scripts/systems/main_os.gd tests/test_runner.gd docs/design/UI交互规范.md
git commit -m "chore: finalize conservative HUD layout verification"
```

Expected if a commit is created:

```text
[ui/main-hud-conservative-layout ...] chore: finalize conservative HUD layout verification
```

---

## Self-Review

### Spec coverage

| Requirement | Covered by |
|---|---|
| 不重做主场景 | Scope Guardrails, Task 2 |
| 保留现有 `main_os.tscn` | Scope Guardrails, Task 2 |
| 保留 `%SectorInfoContainer` | Task 2, Task 10 |
| 左侧区域详情 | Task 2, Task 4, Task 5 |
| 中央全球态势主视图 | Task 2 |
| 右侧太阳系/全局信息/日志 | Task 2, Task 6, Task 7 |
| 底部区域卡片 | Task 2, Task 3 |
| 低饱和统一配色 | Task 3 |
| 不手写 `.tscn` | Scope Guardrails, Task 2, Task 3 |
| 自动化验证 | Task 1, Task 4, Task 6, Task 10 |
| 文档记录 | Task 9 |

### Placeholder scan

The plan contains concrete paths, node names, text values, test code, implementation snippets, run steps, and expected outputs. It does not rely on undefined future components.

### Type consistency

- `selected_sector` remains `SectorInfo`.
- `data_card` remains `SectorData`.
- UI labels use unique names referenced by `main_os.gd` and `tests/test_runner.gd`.
- Progress bars are referenced only after `has_node()` checks.
- `%SectorInfoContainer` remains the single source for sector cards and global aggregates.

---

## Execution Handoff

Plan complete and intended to be saved to:

```text
docs/superpowers/plans/2026-05-28-moss-main-ui-conservative-layout.md
```

Two execution options:

**1. Subagent-Driven (recommended)** - dispatch a fresh agent per task, review after every task, especially after scene edits.

**2. Inline Execution** - execute tasks in this session using checkpoints after Task 2, Task 5, Task 7, and Task 10.

Recommended approach for this UI work: **Subagent-Driven**, because scene editing has high visual ambiguity and should be reviewed frequently with screenshots.
