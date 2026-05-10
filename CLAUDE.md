# MOSS模拟器 - 项目开发指南

## 项目概述

这是一个基于 Godot 4.x 的策略模拟游戏，玩家扮演 MOSS AI 管理人类文明。

**第一版本目标**: 完成 MOSS 阵营核心循环，实现可玩原型。

---

## 代码规范

### 命名规范

| 类型 | 规范 | 示例 |
|------|------|------|
| 类名 | PascalCase | `SectorData`, `GameEvent` |
| 函数名 | snake_case | `load_events_from_disk()` |
| 变量名 | snake_case | `current_year`, `avg_authority` |
| 常量 | CONST_CASE | `MAX_YEAR = 2075` |
| 信号 | snake_case | `game_ended` |
| 节点名称 | PascalCase | `SectorInfoAsia` |

### 代码组织顺序

每个 GDScript 文件按以下顺序组织：

```
1. class_name 定义（如有）
2. 信号定义区域
3. 导出变量区域 (@export)
4. 常量/枚举区域
5. 成员变量区域
6. 生命周期函数 (_ready, _process 等)
7. 公共函数
8. 私有函数/回调函数
```

### 区域分隔注释

使用 `# === 区域名 ===` 分隔不同功能区域（不加编号）：

```gdscript
# ============================================================
# 信号定义
# ============================================================

signal game_ended(result: String)
```

### 注释规范

- **文档注释**: 使用 `##` 开头，描述函数用途和参数
- **普通注释**: 使用 `#` 开头，解释单行逻辑
- **语言**: 注释统一使用 **中文**

```gdscript
## 计算所有板块的平均控制权
## 返回: 平均值（整数），无板块时返回0
func get_average_authority() -> int:
	# 遍历所有板块累加控制权
	...
```

### 类型标注

- 函数参数和返回值必须标注类型
- 变量声明必须标注类型（使用 `:=` 推断或显式声明）

```gdscript
# 推荐
var current_year: int = 2044
var path := "res://data/events/"

# 不推荐
var current_year = 2044  # 类型不明确
```

### 语言偏好

| 部分 | 语言 |
|------|------|
| 注释 | 中文 |
| 调试信息 (print/push_error) | 中文 |
| UI文本 | 中文 |
| 代码标识符（函数名、变量名） | 英文 |
| 事件数据（.tres文件内容） | 中文 |

---

## 文件结构

```
res://
├── data/
│   ├── sector_*.tres     # 板块数据 (.tres) - 7个板块
│   ├── commands/         # 指令配置 (.tres)
│   ├── events/           # 事件数据 (.tres) - 6个活动编年史事件
│   └── evolution/        # 进化能力数据 (.tres)
├── scripts/
│   ├── resources/        # 数据类 (Resource)
│   ├── systems/          # 核心系统脚本
│   ├── ui/               # 界面逻辑
│   └── utils/            # 工具函数
├── scenes/
│   ├── main_os.tscn      # 主场景（3列网格 + 右侧面板布局）
│   ├── event_popup.tscn
│   ├── sector_info.tscn
│   ├── year_progress.tscn     # 年份进度条
│   ├── moss_status_panel.tscn # MOSS状态面板
│   └── game_over.tscn
├── tests/
│   ├── test_runner.gd    # 自动化播放测试脚本（33项断言）
│   └── test_runner.tscn  # 测试场景（实例化main_os并加速运行）
├── docs/                 # 文档目录
│   ├── 开发流程.md
│   ├── 数值设计.md       # 数值决策框架
│   ├── UI交互规范.md     # UI决策框架
│   ├── 决策流程.md       # 决策流程
│   └── ui-mockup/        # UI mockup
└── assets/
```

---

## 开发流程

详见 `docs/开发流程.md`，当前处于 **阶段四：事件内容** 完成阶段，已开始阶段六的自动化测试基础设施。

**已完成**:
- 阶段一：核心骨架 ✅
- 阶段二：MOSS指令系统 ✅
- 阶段三：MOSS进化系统 ✅
- 阶段四：事件内容填充 ✅
- 自动化播放测试基础设施 ✅（33项断言全部通过）

**待完成**:
- 阶段五：情感打磨
- 阶段六：整合测试（主要逻辑已完成，待UI/体验测试）

---

## 核心架构

### main_os.gd 游戏循环

游戏主控制器 `scripts/systems/main_os.gd` (~1270行) 负责所有核心逻辑：

**游戏循环** (`_on_timer_timeout`):
1. 检查事件（匹配 `current_year`，暂停Timer，`await` 玩家选择）
2. 年份+1，能源+10，CPU+恢复率（上限max_cpu）
3. 更新冷却、检查进化、更新UI
4. 胜负判定

**关键暂停点**（await）:
- 事件弹窗：`await %EventPopup.option_selected`
- 算力分配：`await %AllocatePopup.choice_selected`
- 进化通知：`await %EvolutionNotice.notice_confirmed`
- 危机预测也复用 EvolutionNotice

**初始值常量**: year=2044, cpu=30, energy=100, max_cpu=100, recovery=10

**结局判定**: avg_authority≤0→失败; year≥2075→coexistence(≥50) 或 domination(<50)

**已知行为**: 2075年事件不会触发，因为 `check_game_end()` 在年份递增后执行，游戏在year=2075时已结束。

### 信号接口

| 弹窗 | 信号 | 参数 |
|------|------|------|
| EventPopup | `option_selected` | `index: int` |
| EventPopup | `popup_event` | `event, current_energy` |
| AllocatePopup | `choice_selected` | `choice: String` ("order"/"hope"/"") |
| AllocatePopup | `popup_allocate` | `cmd, region_name` |
| EvolutionPopup | `purchase_requested` | `evolution: EvolutionData` |
| EvolutionNotice | `notice_confirmed` | 无 |

### 数据类

| 类 | 关键属性 |
|-----|---------|
| GameEvent | event_title, event_time(int), event_region, event_description, options:Array[EventOption] |
| EventOption | button_text, order_delta, hope_delta, authority_delta, energy_cost |
| SectorData | region_name, order(0-100), hope(0-100), authority(0-100), population, is_locked; clamp_values() |
| CommandData | command_name, cpu_cost, energy_cost, cooldown_years, is_allocate_type |
| EvolutionData | ability_id, is_passive, cpu_threshold, authority_threshold, purchase_cpu_cost, cooldown_reduction, max_cpu_bonus, recovery_bonus |

---

## 测试

### 自动化播放测试

项目包含自动化播放测试（`tests/test_runner.gd` + `tests/test_runner.tscn`），通过加速Timer和自动响应弹窗信号驱动游戏完整播放。

**运行方式**: 在Godot编辑器中将主场景设为 `tests/test_runner.tscn`，然后运行项目。

**测试架构**:
- 实例化 `main_os.tscn` 作为子节点
- 停止Timer→设置0.05s间隔→启动加速循环
- `_process()` 中轮询弹窗可见性，自动发出响应信号
- 两帧 `await` 确保 `_on_timer_timeout` 中await已注册后再发信号
- **必须手动 `popup.hide()`**：直接 `emit()` 信号不触发弹窗内置的 `hide()` 处理器

**验证项** (33项断言):
- 场景节点完整性、初始状态、事件触发时序
- 进化解锁、资源边界约束、最终状态、结局类型

**GDScript测试陷阱**:
- `const` 不支持带类型的数组和字典（如 `const X: Array[int]`），改用 `var`
- `$Timer` 在代码中用 `get_node("Timer")` 访问，`^Timer`（唯一名）的 `has_node()` 需用 `"Timer"` 而非 `"^Timer"`
- 信号 `emit()` 绕过弹窗自带的 `_on_button_pressed` → `hide()` 流程，必须手动隐藏
- `visibility_changed` 信号在连续弹窗场景不可靠，改用 `_process()` 轮询

---

## GDScript 4.x 注意事项

### 与其他语言的差异

1. **常量类型限制**: `const` 只支持基础类型和未类型化数组/字典。复杂类型用 `var` + 类型标注:
   ```gdscript
   # 错误 - GDScript不支持
   const INITIAL_AUTHORITIES: Dictionary = {"亚洲": 24, "北美": 26}

   # 正确 - 用var替代
   var _initial_authorities: Dictionary = {"亚洲": 24, "北美": 26}
   ```

2. **节点路径**: `has_node()` 不支持 `^` 唯一名前缀，使用 `"Timer"` 而非 `"^Timer"`:
   ```gdscript
   # 错误
   has_node("^Timer")  # 返回false

   # 正确
   has_node("Timer")     # 通过节点名
   has_node("%UniqueName")  # 通过唯一名（在场景树中）
   ```

3. **信号emit与UI联动**: 直接 `emit()` 信号不触发UI节点的内置回调（如隐藏弹窗）。必须手动 `popup.hide()` 以免弹窗残留导致重复触发。

4. **协程与await**: `await get_tree().process_frame` 等待一帧。连续弹窗场景需等待2帧确保上一级 `await` 注册完成。

5. **Resource类型检查**: 使用 `is` 而非类型转换检查 `.tres` 加载的资源:
   ```gdscript
   # 推荐
   if event is GameEvent:
       all_events.append(event)

   # 不推荐
   if event as GameEvent:  # 可能返回null但不报错
   ```

---

## 开发工具配置

### GDScript LSP

项目已配置 GDScript Language Server，提供实时类型检查和诊断。

**配置位置**:
- 全局: `~/.config/opencode/oh-my-opencode.jsonc` → `lsp.gdscript`
- 项目: `opencode.json` → `lsp.gdscript`

**LSP 桥接**: 使用 `godot-lsp-stdio-bridge`（npx自动安装），将 Godot 编辑器的 TCP LSP（端口6005）桥接为 stdio 协议。

**前置条件**:
- Godot 编辑器必须打开项目（LSP 服务随编辑器运行）
- 配置文件中 `command: ["npx", "-y", "godot-lsp-stdio-bridge"]`

**可用功能**:
- ✅ `lsp_diagnostics` - 实时类型检查和错误诊断
- ⚠️ `lsp_symbols`/`lsp_goto_definition`/`lsp_find_references` - 可能需要编辑器先索引项目

---

## 注意事项

1. **数据驱动**: 优先使用 .tres 资源文件存储数据，方便编辑器配置
2. **类型安全**: 使用 `is` 检查类型，避免运行时错误
3. **错误处理**: 使用 `push_error()` 和 `push_warning()` 而非 `print()`
4. **避免编辑 tscn**: 场景文件让编辑器生成，手动修改易出错
5. **信号emit注意**: 直接emit信号不触发UI内置回调，需手动处理弹窗隐藏等副作用
6. **Timer控制**: 游戏循环中有多处 `timer.stop()` + `await` + `timer.start()` 模式，测试时需确保Timer恢复
