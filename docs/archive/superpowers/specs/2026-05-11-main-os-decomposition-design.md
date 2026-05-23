# main_os.gd 解耦设计

## Context

`scripts/systems/main_os.gd` 有1271行，承担了6-7个不同职责：游戏状态管理、进化系统、指令系统、事件处理、板块管理、胜负判定、日志UI。文件过大导致难以维护和理解。

**目标**：将游戏逻辑提取为独立的 RefCounted 类，main_os 只负责 UI 协调和信号转发。不改场景文件、不改信号接口、测试无需修改。

**预期效果**：main_os 从1271行降到约450-500行，4个新文件约600行纯逻辑代码。

---

## 架构

```
main_os.gd (UI协调层, ~450-500行)
  ├── GameState (共享状态, ~40行)
  ├── EvolutionManager (进化逻辑, ~180行)
  ├── CommandManager (指令逻辑, ~100行)
  └── ActionLogManager (日志逻辑, ~80行)
```

所有 Manager 是 `RefCounted` 子类，不依赖场景树，由 main_os 在 `_ready()` 中创建。

---

## 模块设计

### 1. GameState

**文件**: `scripts/systems/game_state.gd`

共享游戏状态容器，所有 Manager 通过参数接收。

**属性**:
- `current_year: int = 2044`
- `current_cpu: int = 30`
- `current_energy: int = 100`
- `is_game_over: bool = false`
- `max_cpu: int = 100`
- `cpu_recovery_rate: int = 10`
- `cooldown_reduction: int = 0`

**常量**: `INITIAL_YEAR`, `INITIAL_CPU`, `INITIAL_ENERGY`, `INITIAL_MAX_CPU`, `INITIAL_CPU_RECOVERY_RATE`

**方法**: `reset() -> void`

### 2. EvolutionManager

**文件**: `scripts/systems/evolution_manager.gd`

进化系统全部逻辑，不依赖UI节点。

**属性**:
- `evolution_level: int = 1`
- `unlocked_passives: Array[String] = []`
- `unlocked_evolution_commands: Array[String] = []`
- `all_evolutions: Array[EvolutionData] = []`

**常量**: `COMMAND_ENERGY_CONVERT`, `COMMAND_GLOBAL_TAKEOVER`, `COMMAND_CRISIS_PREDICT`

**方法**:

| 方法 | 说明 | 返回值 |
|------|------|--------|
| `load_from_disk()` | 从 res://data/evolution/ 加载 .tres | void |
| `check_unlocks(game_state, get_avg_authority: Callable)` | 检查被动能力解锁条件 | `UnlockResult`（见下） |
| `apply_effect(evolution, game_state)` | 应用进化效果到 game_state | void |
| `update_level()` | 根据已解锁被动数更新等级 | void |
| `can_purchase(evolution, game_state)` | 检查购买条件 | bool |
| `purchase(evolution, game_state)` | 执行购买，返回新指令 | CommandData? |
| `create_evolution_command(evolution)` | 根据进化数据创建运行时指令 | CommandData? |
| `requires_selected_sector(cmd)` | 判断指令是否需选中板块 | bool |
| `get_progress(game_state, get_avg_authority: Callable)` | 获取进化进度（用于UI） | Dictionary |
| `reset()` | 重置进化状态 | void |

**UnlockResult**: 内部类或简单 Dictionary `{ "unlocked_any": bool, "unlocked_names": Array[String] }`

**提取自 main_os 的函数映射**:
- `load_evolutions_from_disk()` → `load_from_disk()`
- `check_evolution_unlocks()` 逻辑部分 → `check_unlocks()`
- `apply_evolution_effect()` → `apply_effect()`
- `update_evolution_level()` → `update_level()`
- `purchase_evolution_command()` → `purchase()`
- `create_evolution_command()` → 同名
- `command_requires_selected_sector()` → `requires_selected_sector()`
- `get_evolution_progress()` → `get_progress()`

### 3. CommandManager

**文件**: `scripts/systems/command_manager.gd`

指令系统逻辑，不依赖UI节点。

**属性**:
- `available_commands: Array[CommandData] = []`
- `command_cooldowns: Dictionary = {}`

**方法**:

| 方法 | 说明 | 返回值 |
|------|------|--------|
| `load_from_disk()` | 从 res://data/commands/ 加载 .tres | void |
| `execute(cmd, game_state)` | 扣除资源、设置冷却（含冷却缩减） | bool |
| `is_available(cmd, game_state, has_selected_sector)` | 检查可用性 | bool |
| `get_unavailable_reason(cmd, game_state, has_selected_sector)` | 获取不可用原因 | String |
| `update_cooldowns()` | 减少所有冷却计数 | void |
| `add_command(cmd)` | 添加新指令 | void |
| `has_command_named(name)` | 检查指令是否存在 | bool |
| `reset()` | 清空并重载 | void |

**提取自 main_os 的函数映射**:
- `load_commands_from_disk()` → `load_from_disk()`
- `execute_command()` → `execute()`
- `update_cooldowns()` → 同名
- `is_command_available()` → `is_available()`
- `get_command_unavailable_reason()` → `get_unavailable_reason()`
- `has_command_named()` → 同名

### 4. ActionLogManager

**文件**: `scripts/systems/action_log_manager.gd`

日志数据管理，不依赖UI节点。打字机动画效果保留在 main_os。

**信号**: `entry_added(entry: Dictionary)`

**属性**:
- `action_log: Array[Dictionary] = []`
- `ACTION_LOG_LIMIT: int = 24`

**方法**:

| 方法 | 说明 | 返回值 |
|------|------|--------|
| `record_action(year, kind, title, message)` | 记录日志条目，发出 entry_added | void |
| `append_signed_change(lines, label, delta)` | 追加带符号的变化值到 lines | void |
| `log_command_result(cmd, cooldowns)` | 记录指令执行结果 | void |
| `get_log()` | 返回日志副本 | Array[Dictionary] |
| `reset()` | 清空日志 | void |

**提取自 main_os 的函数映射**:
- `get_action_log()` → `get_log()`
- `record_action()` → `record_action(year, kind, title, message)`（year 改为参数传入）
- `append_signed_change()` → 同名
- `log_command_result()` → `log_command_result(cmd, cooldowns)`（不再依赖 main_os 属性）

---

## main_os.gd 重构后的结构

main_os 保留以下职责（约450-500行）：

### 保留的成员变量
- `game_state: GameState` — 共享状态实例
- `evolution_mgr: EvolutionManager` — 进化管理器
- `command_mgr: CommandManager` — 指令管理器
- `log_mgr: ActionLogManager` — 日志管理器
- `selected_sector: SectorInfo` — 选中的板块（UI状态）
- `initial_sector_states: Dictionary` — 板块初始状态
- `end_screen_instance: Control` — 结局界面实例
- 打字机队列状态 (`_typewriter_queue`, `_typewriter_active`)
- `triggered_events: Array[String]` — 已触发事件
- `all_events: Array[GameEvent]` — 事件列表

### 保留的函数区域

1. **初始化** (`_ready`) — 创建 manager 实例，连接信号
2. **游戏循环** (`_on_timer_timeout`) — 调 manager + await UI
3. **板块管理** — connect_sector_signals, select_sector, deselect_sector, _on_sector_clicked, cache/restore_sector_states
4. **事件后果** — apply_consequences（遍历sector节点，调log_mgr记录）
5. **UI更新** — update_global_resource_ui, update_command_buttons, get_moss_model_name
6. **指令按钮** — setup_command_buttons
7. **弹窗回调** — _on_command_button_pressed, show_evolution_popup, _on_purchase_requested 等
8. **打字机日志UI** — _add_log_entry_to_ui, _start_typewriter 等
9. **结局界面** — check_game_end, trigger_game_over, trigger_ending, show_end_screen
10. **重启** — _on_restart_requested（调各 manager.reset()）

### 属性转发

为保持测试兼容，main_os 保留以下属性的读写，转发到 game_state：
- `current_year` → `game_state.current_year`
- `current_cpu` → `game_state.current_cpu`
- `current_energy` → `game_state.current_energy`
- `is_game_over` → `game_state.is_game_over`
- `max_cpu` → `game_state.max_cpu`
- `cpu_recovery_rate` → `game_state.cpu_recovery_rate`
- `cooldown_reduction` → `game_state.cooldown_reduction`
- `evolution_level` → `evolution_mgr.evolution_level`
- `unlocked_passives` → `evolution_mgr.unlocked_passives`
- `unlocked_evolution_commands` → `evolution_mgr.unlocked_evolution_commands`
- `all_evolutions` → `evolution_mgr.all_evolutions`
- `available_commands` → `command_mgr.available_commands`
- `command_cooldowns` → `command_mgr.command_cooldowns`
- `action_log` → `log_mgr.action_log`

使用 GDScript 的 `set`/`get` 或直接访问实现转发。

---

## 数据流

### 游戏循环（_on_timer_timeout）

```
1. 检查事件 → 遍历 all_events，await EventPopup
   → apply_consequences() → log_mgr.record_action()
2. 年份+1，能源+10 → game_state.current_year++, game_state.current_energy+=10
   算力恢复 → game_state.current_cpu = mini(cpu + rate, max_cpu)
3. command_mgr.update_cooldowns()
4. evolution_mgr.check_unlocks(game_state, get_average_authority)
   → 如果有解锁，显示 EvolutionNotice (await)
5. update_global_resource_ui(), update_command_buttons()
6. check_game_end()
```

### 指令执行（_on_command_button_pressed）

```
1. command_mgr.is_available(cmd, game_state, selected_sector != null)
2. 算力分配: await AllocatePopup → command_mgr.execute() → apply_command_effect()
   其他指令: command_mgr.execute() → apply_command_effect() 或 apply_special_command_effect()
3. log_mgr.log_command_result() (通过 entry_added 触发打字机)
4. update UI
```

### 进化购买（_on_purchase_requested）

```
1. evolution_mgr.can_purchase(evolution, game_state)
2. evolution_mgr.purchase(evolution, game_state) → 返回新 CommandData
3. 如果成功: command_mgr.add_command(new_cmd) → setup_command_buttons()
4. update UI
```

### 重启（_on_restart_requested）

```
1. game_state.reset()
2. evolution_mgr.reset()
3. command_mgr.reset() → 重新 load_from_disk()
4. log_mgr.reset()
5. restore_sector_states()
6. update UI, start Timer
```

---

## 新增文件清单

| 文件 | 类型 | 约行数 |
|------|------|--------|
| `scripts/systems/game_state.gd` | RefCounted | ~40 |
| `scripts/systems/evolution_manager.gd` | RefCounted | ~180 |
| `scripts/systems/command_manager.gd` | RefCounted | ~100 |
| `scripts/systems/action_log_manager.gd` | RefCounted | ~80 |

## 修改文件清单

| 文件 | 变化 |
|------|------|
| `scripts/systems/main_os.gd` | 从1271行重构为~450-500行 |

## 不变的文件

- 所有场景文件 (.tscn)
- 所有 UI 脚本 (scripts/ui/*)
- 所有资源类 (scripts/resources/*)
- 测试脚本 (tests/test_runner.gd)

---

## 验证方案

1. **运行现有测试**: 将主场景设为 test_runner.tscn 并运行，33项断言应全部通过
2. **手动播放测试**: 从2044到2075完整流程，验证事件触发、指令执行、进化解锁、结局判定
3. **回归检查**: 对比重构前后以下行为一致：
   - 初始状态（year=2044, cpu=30, energy=100）
   - 事件触发时序和后果
   - 指令冷却和可用性判断
   - 进化解锁条件和购买流程
   - 结局判定逻辑
