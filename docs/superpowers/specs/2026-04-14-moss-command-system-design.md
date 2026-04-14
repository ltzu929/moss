# MOSS指令系统设计文档

> **目标**：实现阶段二 - MOSS指令系统，让玩家能主动操作板块。

---

## 需求概要

| 项目 | 决定 |
|------|------|
| 指令数量 | 2个（算力分配、系统接管），概率预测暂不实现 |
| 触发机制 | 冷却机制，每个指令独立冷却 |
| 目标选择 | 针对单个板块 |
| 交互方式 | 先点击板块选中，再点击指令按钮执行 |
| 冷却时间 | 算力分配3年，系统接管5年 |
| 算力恢复 | 每年恢复5点 |

---

## 文件结构

新增文件：

```
res://
├── data/
│   └── commands/
│       ├── command_allocate.tres   # 算力分配指令配置
│       └── command_takeover.tres   # 系统接管指令配置
├── scripts/
│   ├── resources/
│   │   └── command_data.gd         # 指令数据类
│   └── ui/
│       └── command_button.gd       # 指令按钮脚本
│       └── allocate_popup.gd       # 算力分配子选择弹窗
└── scenes/
    ├── command_button.tscn         # 指令按钮场景
    └── allocate_popup.tscn         # 算力分配选择弹窗
```

修改文件：
- `scripts/systems/main_os.gd` - 添加指令系统逻辑、冷却管理、算力恢复、选中状态
- `scripts/resources/sector_info.gd` - 添加选中状态高亮显示
- `scenes/main_os.tscn` - 添加指令按钮容器

---

## 数据类设计

### CommandData 类

```gdscript
class_name CommandData
extends Resource

@export_group("基础信息")
@export var command_name: String = "指令名称"
@export var description: String = "指令描述"

@export_group("消耗")
@export var cpu_cost: int = 0
@export var energy_cost: int = 0

@export_group("效果")
@export var order_delta: int = 0
@export var hope_delta: int = 0
@export var authority_delta: int = 0

@export_group("冷却")
@export var cooldown_years: int = 3
```

### 指令配置数值

| 指令 | cpu_cost | energy_cost | order_delta | hope_delta | authority_delta | cooldown |
|------|----------|-------------|-------------|------------|-----------------|----------|
| 算力分配 | 20 | 0 | +15（可选） | +15（可选） | 0 | 3 |
| 系统接管 | 30 | 20 | 0 | 0 | +10 | 5 |

注：算力分配的效果需要玩家在子选择弹窗中选择"提升秩序"或"提升希望"。

---

## 核心逻辑设计

### main_os.gd 新增状态变量

```gdscript
var selected_sector: SectorInfo = null  # 当前选中的板块
var command_cooldowns: Dictionary = {}  # 各指令冷却剩余年数 {"算力分配": 0, "系统接管": 2}
var available_commands: Array[CommandData]  # 从磁盘加载的指令列表
```

### 新增核心函数

| 函数名 | 功能 |
|--------|------|
| `load_commands_from_disk()` | 从 res://data/commands/ 加载指令配置 |
| `select_sector(sector)` | 设置选中板块，更新高亮显示 |
| `deselect_sector()` | 清除选中状态 |
| `execute_command(cmd)` | 执行指令：检查条件，应用效果，启动冷却 |
| `update_cooldowns()` | 每年调用，减少冷却计数 |
| `is_command_available(cmd)` | 检查指令是否可执行 |
| `get_command_availability_reason(cmd)` | 返回不可执行原因（用于tooltip） |

### 冷却机制流程

1. 执行指令时：`command_cooldowns[cmd.command_name] = cmd.cooldown_years`
2. 每年在 `_on_timer_timeout` 中调用 `update_cooldowns()`
3. `update_cooldowns()` 遍历冷却字典，每个值减1（最小为0）
4. 冷却值为0时，指令可再次执行

### 算力恢复

在 `_on_timer_timeout` 中添加：
```gdscript
current_cpu += 5  # 每年算力恢复5点
current_cpu = mini(current_cpu, 100)  # 上限100
```

---

## UI交互设计

### 板块选中显示

在 `sector_info.gd` 中：
- 新增 `is_selected: bool` 属性
- `set_selected(value)` 函数：修改面板边框颜色（选中时高亮）
- 点击板块时发出 `sector_clicked` 信号

### 指令按钮状态

| 状态 | 显示 | Tooltip |
|------|------|---------|
| 可用 | 正常颜色 | "消耗: X算力 Y能源" |
| 冷却中 | 灰色disabled | "冷却中（剩余X年）" |
| 资源不足 | 灰色disabled | "算力不足（需要X）" 或 "能源不足（需要X）" |
| 未选中板块 | 灰色disabled | "请先选择板块" |

### 交互流程

```
玩家点击板块 → sector_clicked信号 → main_os.select_sector()
                ↓
板块高亮显示，selected_sector记录
                ↓
玩家点击指令按钮 → 检查可用性
                ↓
    ├─ 不可用 → tooltip已显示原因，无操作
    └─ 可用 →
        ├─ 算力分配 → 弹出allocate_popup选择秩序/希望
        │           → 应用效果
        └─ 系统接管 → 直接应用效果
                ↓
消耗资源，启动冷却，刷新UI
```

---

## 错误处理

| 场景 | 处理方式 |
|------|----------|
| 未选中板块 | Button disabled + tooltip |
| 资源不足 | Button disabled + tooltip显示缺少数量 |
| 冷却中 | Button disabled + tooltip显示剩余年数 |
| 板块数值溢出 | SectorData.clamp_values() 自动限制0-100 |

---

## 实现顺序

1. 创建 `CommandData` 数据类
2. 创建指令配置文件（.tres）
3. 修改 `sector_info.gd` 添加选中功能
4. 修改 `main_os.gd` 添加指令系统逻辑
5. 创建 `command_button.gd` 和场景
6. 创建 `allocate_popup.gd` 和场景
7. 在 `main_os.tscn` 中添加指令按钮容器
8. 测试完整流程