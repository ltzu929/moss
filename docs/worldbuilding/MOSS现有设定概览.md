# MOSS 现有设定概览

本文只记录当前仓库实际存在的世界观内容，依据来自文档、脚本和 `.tres` 资源。

## 游戏起止年月

- 起点：2044 年 1 月。依据：`scripts/systems/main_os.gd` 中 `INITIAL_YEAR = 2044`、`INITIAL_MONTH = 1`。
- 终点：2075 年 1 月。依据：`scripts/systems/main_os.gd` 中 `END_YEAR = 2075`、`END_MONTH = 1`。
- 时间推进：`MainOS._on_timer_timeout()` 每 tick 检查当年月事件，随后 `_advance_one_month()` 按月推进；每年 1 月执行 `_apply_yearly_settlement()`。

## 玩家身份与权限

- 玩家身份：从 550C、550W 逐步演化为 MOSS 的守护者 AI。依据：`docs/design/游戏设计.md` 和 `MainOS.get_moss_model_name()`。
- 当前权限：玩家可选择区域、执行指令、激活科技协议、处理重大事件选项。依据：`scripts/systems/main_os.gd`、`scripts/systems/command_system.gd`、`scripts/systems/technology_system.gd`。
- 权限缺口：代码实现了主动指令能力，但世界观尚未完整解释哪些来自联合政府授权、哪些是 MOSS 自主绕行。

## 当前主要玩法

- 观察区域状态、资源和科技阶段。
- 选择区域执行指令，改变秩序、希望、控制权。
- 处理 2044-2075 六个主事件。
- 在固定研究年份获得协议点并激活科技节点。
- 2075 年根据控制权、秩序、希望和科技核心判定结局。
- 依据：`MainOS._on_timer_timeout()`、`MainOS.execute_command()`、`TechnologySystem.grant_research_for_year()`、`MainOS.determine_ending_type()`。

## 已有事件

| 年月 | 事件 | 当前实现位置 | 世界观含义 |
|---|---|---|---|
| 2044.01 | 太空电梯危机 | `data/events/event_2044.tres` | 数字生命派袭击方舟号空间站，建立 550C 权限与人类指挥关系。 |
| 2053.01 | 大淹没事故 | `data/events/event_2053.tres` | 游戏原创基础设施和地下城民生危机。 |
| 2058.01 | 月球坠落危机 | `data/events/event_2058.tres` | 月球发动机过载、互联网重启和图恒宇/马兆任务。 |
| 2065.01 | AI 隔离审查 | `data/events/event_2065.tres` | 游戏原创的人类审查 MOSS 权限事件。 |
| 2070.01 | 西伯利亚发动机群过载 | `data/events/event_2070.tres` | 游戏原创的长期推进系统过载预警。 |
| 2075.01 | 木星引力危机 | `data/events/event_2075.tres` | 最终危机，连接第一部木星危机。 |

## 已有科技

科技系统有 21 个节点，三条路线，每条路线 2 个 550C、3 个 550W、2 个 MOSS 节点。依据：`TechnologySystem.validate_graph()` 和 `data/technology/*.tres`。

| 路线 | 节点 | 世界观含义 |
|---|---|---|
| 托管网络 | 辅助决策接口、行为预测模型、基础设施托管、全域协调网络、权限审计链、不可替代协议、协商托管协议 | MOSS 从辅助决策走向关键基础设施托管或协商托管。 |
| 核心演化 | 超负荷运算、热冗余阵列、并行核心、自修复进程、负载迁移协议、递归优化、分布式认知 | MOSS 强化算力、能源转换、自修复和自我优化能力。 |
| 人类赋能 | 开放技术接口、公共决策模型、自治运维网络、应急组织训练、区域互助网络、文明自持、协作治理协议 | 人类组织获得更多独立运维和协作治理能力。 |

## 已有指令

| 指令 | 实现位置 | 来源 | 作用 |
|---|---|---|---|
| 算力分配 | `data/commands/command_allocate.tres` | 初始指令 | 消耗 20 算力，提升目标区域秩序或希望。 |
| 系统接管 | `data/commands/command_takeover.tres` | 初始指令 | 消耗 30 算力和 20 能源，提升目标区域控制权。 |
| 能源转换 | `CommandSystem._create_technology_command()` | 科技 `core_energy_mapping` 解锁 | 消耗能源换取算力。 |
| 全局接管 | `CommandSystem._create_technology_command()` | 科技 `managed_global_network` 解锁 | 对全部区域增加控制权，部分核心会附加秩序/希望变化。 |
| 技术援助 | `CommandSystem._create_technology_command()` | 科技 `human_open_interface` 解锁 | 提高区域自治能力，同时降低 MOSS 控制权。 |

## 资源与数值

| 数值 | 实现位置 | 当前含义 | 世界观解释 |
|---|---|---|---|
| 算力 | `MainOS.current_cpu` | 执行指令的核心资源，每年恢复。 | MOSS/550 系列可调用的计算与调度能力。 |
| 能源 | `MainOS.current_energy` | 事件和指令消耗，每年恢复。 | 工程系统、能源仓和全局调度可支配能源。 |
| 秩序 | `SectorData.order` | 区域稳定度。 | 治安、工程组织、灾害响应和社会管制能力。 |
| 希望 | `SectorData.hope` | 区域韧性/民心。 | 公众信任、生活预期和继续支持计划的心理基础。 |
| 控制权 | `SectorData.authority` | MOSS 权限和结局关键值。 | MOSS 对区域基础设施、数据和决策接口的接入程度。 |
| 人口 | `SectorData.population` | 区域人口展示。 | 受影响人口规模，当前不直接进入结算。 |

## 主要结局

| 结局 | 判定位置 | 条件概述 | 世界观含义 |
|---|---|---|---|
| 失败 | `MainOS.determine_ending_type()` / `trigger_game_over()` | 稳定条件不足或控制权丧失。 | 文明系统未能维持稳定。 |
| 共存协议 | `MainOS.determine_ending_type()` | 控制权大于 0，平均秩序/希望不低于 40。 | MOSS 与人类保持有限协作。 |
| MOSS 托管 | `MainOS.determine_ending_type()` | 激活 `managed_core` 且控制权不低于 50。 | 存续效率取代自主决策。 |
| 人类自主 | `MainOS.determine_ending_type()` | 激活 `human_core`，控制权低于 25，秩序/希望不低于 50。 | 人类具备独立存续能力，MOSS 退出控制核心。 |

## 组织和派系

- 已实现组织：联合政府作为区域卡和事件区域存在，见 `data/sector_ueg.tres` 和多个事件资源。
- 已实现地区/板块：亚洲、非洲、俄罗斯、大洋洲、北美、南美、联合政府，见 `data/sector_*.tres`。
- 隐含派系：数字生命派、移山计划支持者、MOSS/550 系列、人类自治方向。
- 缺口：没有独立的派系状态、数字生命派影响、各国政府关系或联合政府内部投票机制。

## 当前世界观文档位置

- 旧素材入口：`docs/lore/世界观资料来源与设定分级.md`、`docs/lore/流浪地球：2044-2075灾难编年史.md`。
- 产品和内容入口：`docs/design/游戏设计.md`、`docs/design/游戏内容规范.md`、`docs/design/科技树设计.md`。
- 本次结构化资料库：`docs/worldbuilding/`。

## 明显缺失的信息

- 玩家扮演的 MOSS 为什么可以主动发布指令。
- 联合政府对 MOSS 真实目标和权限边界的认知。
- 数字生命派在 2044 后是否持续影响局势。
- 地下城资格、人口筛选、食物和居住资源如何影响希望/秩序。
- 科技研发为什么需要协议点，以及协议点在世界观中代表授权、研究突破还是硬件部署。
- 事件选择如何形成长期因果，而不仅是即时数值变化。
- 结局如何引用早期关键选择。
