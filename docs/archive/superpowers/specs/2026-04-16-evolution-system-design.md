# MOSS进化系统设计文档

## 概述

阶段三：MOSS进化系统，实现玩家能力成长机制。

**设计日期**: 2026-04-16

---

## 核心设计决策

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 触发条件 | 双重阈值（算力 + 控制权） | 增加策略深度，单一阈值过于简单 |
| 解锁方式 | 混合模式（被动自动 + 指令购买） | 被动增益自动生效有成就感，新指令购买增加决策 |
| 检查时机 | 每年一次，集成时间循环 | 与现有系统统一，实现简单 |
| UI形式 | 进化按钮 + 弹窗面板 | 科技树在弹窗内展示，不占用主界面空间 |
| 视觉反馈 | 弹窗庆祝 | 强调重要时刻，让玩家确认解锁内容 |
| 形态命名 | 功能描述（初始 → 进化 → 终极） | 直观易懂，适合新玩家 |

---

## 形态定义

### Level 1: 初始形态
- **起始状态**: 游戏开始时默认
- **基础能力**: 算力分配、系统接管（已有）

### Level 2: 进化形态
- **解锁条件**: 算力 ≥ 60 + 平均控制权 ≥ 30
- **效果**: 解锁新被动增益和可购买指令

### Level 3: 终极形态
- **解锁条件**: 算力 ≥ 85 + 平均控制权 ≥ 50
- **效果**: 继承所有已解锁能力，解锁终极指令

---

## 自动解锁能力（被动增益）

达到阈值立即生效，无需玩家操作。

| 能力名称 | 触发条件 | 效果 |
|----------|----------|------|
| 冷却缩减 | 算力 ≥ 60 | 所有指令冷却时间 -1年 |
| 算力上限突破 | 平均控制权 ≥ 50 | 算力上限 100 → 150 |
| 恢复速度提升 | 算力 ≥ 80 | 每年算力恢复 +5（原5→10） |

---

## 手动购买指令（消耗资源）

玩家主动消耗资源解锁新指令，增加策略决策。

| 指令名称 | 购买消耗 | 效果 | 冷却 |
|----------|----------|------|------|
| 能源转换 | 30算力 | 解锁指令: 20能源 → 10算力 | 2年 |
| 全局接管 | 50算力 + 20能源 | 解锁指令: 对所有板块执行系统接管（效果减半） | 5年 |
| 危机预测 | 40算力 | 解锁能力: 预览未来5年将发生的事件 | 无冷却，被动信息 |

---

## UI设计

### 主界面
- 顶部资源栏旁新增"进化"按钮
- 按钮显示当前形态等级（如 "Lv.2"）
- 有新解锁时按钮闪烁提示

### 进化弹窗
点击进化按钮打开弹窗，包含：
- 当前形态显示
- 已解锁能力列表
- 自动解锁进度条（算力/控制权进度）
- 可购买能力卡片（显示消耗和效果）

### 进化通知弹窗
自动解锁触发时弹出：
- 标题："进化解锁！"
- 显示解锁的具体能力
- 确认按钮关闭

---

## 实现架构

### 新增文件

```
scripts/
├── resources/
│   └── evolution_data.gd      # 进化能力数据类
├── ui/
│   ├── evolution_popup.gd     # 进化详情弹窗
│   └── evolution_notice.gd    # 进化通知弹窗

scenes/
├── evolution_popup.tscn       # 进化详情弹窗场景
├── evolution_notice.tscn      # 进化通知弹窗场景
```

### 修改文件

```
scripts/systems/main_os.gd
├── 新增变量
│   ├── evolution_level: int = 1           # 当前进化等级(1-3)
│   ├── unlocked_passives: Array[String]   # 已解锁的被动能力ID
│   ├── unlocked_commands: Array[String]   # 已购买解锁的指令ID
│   ├── max_cpu: int = 100                 # 算力上限（可突破到150）
│   ├── cpu_recovery_rate: int = 5         # 算力恢复速率
│   ├── cooldown_reduction: int = 0        # 冷却缩减值
│
├── 新增函数
│   ├── check_evolution_unlocks()          # 每年检查自动解锁
│   ├── purchase_evolution_command()       # 购买解锁指令
│   ├── get_evolution_progress()           # 获取解锁进度（用于UI）
│   ├── trigger_evolution_notice()         # 触发进化通知弹窗
│
└── 修改函数
    └── _on_timer_timeout()                # 添加进化检查调用
    └── update_cooldowns()                 # 应用冷却缩减

scenes/main_os.tscn
└── 新增节点: EvolutionButton (Button)
```

---

## 数据类设计

### EvolutionData (Resource)

```gdscript
class_name EvolutionData
extends Resource

# 基础信息
@export var ability_id: String          # 能力唯一标识
@export var ability_name: String        # 显示名称
@export var description: String         # 描述文本

# 解锁类型
@export var is_passive: bool = true     # true=自动解锁, false=手动购买

# 自动解锁条件
@export var cpu_threshold: int = 0      # 算力阈值
@export var authority_threshold: int = 0 # 控制权阈值

# 手动购买消耗
@export var purchase_cpu_cost: int = 0  # 购买消耗算力
@export var purchase_energy_cost: int = 0 # 购买消耗能源

# 解锁效果
@export var cooldown_reduction: int = 0  # 冷却缩减值
@export var max_cpu_bonus: int = 0       # 算力上限加成
@export var recovery_bonus: int = 0      # 恢复速率加成
@export var unlocks_command: String = "" # 解锁的指令名称
```

---

## 时间循环集成

`_on_timer_timeout()` 修改后流程：

```
1. 检查事件触发
2. 年份递增 (+1)
3. 算力恢复 (apply recovery_rate)
4. 能源恢复 (+10)
5. 冷却更新 (apply cooldown_reduction)
6. ✨ 进化解锁检查 ← 新增
7. 更新UI
8. 胜负判定
```

---

## 边缘情况处理

1. **进化等级跳级**: 理论上不可能，阈值递增设计保证顺序
2. **购买指令时资源不足**: UI显示不可用状态，点击无效
3. **重复购买**: 已解锁指令不显示在购买列表
4. **恢复速度溢出**: 算力恢复后仍受上限限制
5. **游戏重置**: 进化状态需在 `_on_restart_requested()` 中重置

---

## 后续优化建议

1. **难度关联**: 不同难度使用不同阈值（简单模式阈值降低）
2. **进化动画**: 添加屏幕特效增强仪式感
3. **能力组合提示**: 推荐不同进化路线搭配策略

---

## 测试要点

1. 验证阈值触发时机正确（每年检查）
2. 验证被动能力效果正确应用
3. 验证购买指令消耗和冷却正确
4. 验证UI进度条显示准确
5. 验证游戏重置后进化状态清空
6. 验证弹窗交互流畅无卡顿