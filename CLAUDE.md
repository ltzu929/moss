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

使用 `# === 区域名 ===` 分隔不同功能区域：

```gdscript
# ============================================================
# 区域一：信号定义
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
│   ├── sectors/          # 板块数据 (.tres) - 7个板块
│   ├── commands/         # 指令配置 (.tres)
│   ├── events/           # 事件数据 (.tres) - 4个核心事件
│   └── evolution/        # 进化能力数据 (.tres)
├── scripts/
│   ├── resources/        # 数据类 (Resource)
│   ├── systems/          # 核心系统脚本
│   ├── ui/               # 界面逻辑
│   └── utils/            # 工具函数
├── scenes/
│   ├── main_os.tscn      # 主场景（3列网格布局）
│   ├── event_popup.tscn
│   ├── sector_info.tscn
│   ├── year_progress.tscn     # 年份进度条
│   ├── moss_status_panel.tscn # MOSS状态面板
│   └── game_over.tscn
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

详见 `docs/开发流程.md`，当前处于 **阶段四：事件内容** 完成阶段。

**已完成**:
- 阶段一：核心骨架 ✅
- 阶段二：MOSS指令系统 ✅
- 阶段三：MOSS进化系统 ✅
- 阶段四：事件内容填充 ✅

**待完成**:
- 阶段五：情感打磨
- 阶段六：整合测试

---

## 注意事项

1. **数据驱动**: 优先使用 .tres 资源文件存储数据，方便编辑器配置
2. **类型安全**: 使用 `is` 检查类型，避免运行时错误
3. **错误处理**: 使用 `push_error()` 和 `push_warning()` 而非 `print()`
4. **避免编辑 tscn**: 场景文件让编辑器生成，手动修改易出错
