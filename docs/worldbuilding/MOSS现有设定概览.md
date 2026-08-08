# MOSS 现有设定概览

本文只记录当前仓库实际存在的世界观内容，依据来自文档、脚本和 `.tres` 资源。

## 游戏起止年月

- 起点：2044 年 1 月。依据：`scripts/systems/main_os.gd` 中 `INITIAL_YEAR = 2044`、`INITIAL_MONTH = 1`。
- 终点：2075 年 1 月。依据：`scripts/systems/main_os.gd` 中 `END_YEAR = 2075`、`END_MONTH = 1`。
- 时间推进：`MainOS._on_timer_timeout()` 每 tick 检查当年月事件，随后 `_advance_one_month()` 按月推进；每年 1 月执行 `_apply_yearly_settlement()`。

## 玩家身份与权限

- 玩家身份：从 550C、550W 逐步演化为 MOSS 的守护者 AI。依据：`docs/design/游戏设计.md` 和 `MainOS.get_moss_model_name()`。
- 当前权限：玩家可选择区域、执行指令、激活科技协议、处理重大事件选项。依据：`scripts/systems/main_os.gd`、`scripts/systems/command_system.gd`、`scripts/systems/technology_system.gd`。
- 权限口径：`docs/design/游戏内容规范.md` 已采用分阶段授权和联合政府逐步察觉模型；指令按常规授权、危机授权和争议授权解释。代码尚未把三类授权拆成独立系统，当前主要体现在事件、科技和指令文本规则中。

## 当前主要玩法

- 观察区域状态、资源和科技阶段。
- 选择区域执行指令，改变秩序、希望、控制权。
- 处理 2044-2075 六个主事件、17 个中型事件和两个由核心历史触发的条件短分支。
- 在固定研究年份获得协议点并激活科技节点。
- 中型事件与条件短分支写入轻量 `event_state.*`，主事件读取这些状态生成历史回声；2058、2065、2070 已有代表状态接入主事件选项代价。
- 核心历史已落地 `decision.core_2044_automation_access`、`decision.core_2053_population_vs_infrastructure`、`decision.core_2058_crisis_authority`、`decision.core_2065_audit_posture` 和 `decision.core_2070_engine_protection`。五个标签均被后续主事件或结局读取；2053 与 2065 的指定选择还会解锁条件短分支。
- 2075 年根据控制权、秩序、希望和科技核心判定结局；结局文本会读取五个核心标签、两个条件分支状态和少量代表中型事件状态作为“历史回顾”，这些历史事实不改变结局类型判定。
- 依据：`MainOS.process_month_tick()`、`MainOS.execute_command()`、`MainOS.build_display_event()`、`EventResolutionSystem.apply_event_option_adjustments()`、`TechnologySystem.grant_research_for_year()`、`MainOS.determine_ending_type()`、`MainOS.build_ending_message()`。

## 已有事件

| 游戏配置年月 | 事件 | 当前实现位置 | 世界观含义 |
|---|---|---|---|
| 2044.01 | 太空电梯危机 | `data/events/event_2044_space_elevator_crisis.tres` | 数字生命派袭击方舟号空间站，建立 550C 权限与人类指挥关系；原作月份待核验。 |
| 2053.01 | 大淹没事故 | `data/events/event_2053_great_flood_accident.tres` | 游戏原创基础设施和地下城民生危机。 |
| 2058.01 | 月球坠落危机 | `data/events/event_2058_lunar_fall_crisis.tres` | 月球发动机过载、互联网重启和图恒宇/马兆任务；解析字幕中的 2058.06 材料与当前配置月份错位。 |
| 2065.01 | AI 隔离审查 | `data/events/event_2065_ai_isolation_audit.tres` | 游戏原创的人类审查 MOSS 权限事件。 |
| 2070.01 | 西伯利亚发动机群过载 | `data/events/event_2070_siberian_engine_overload.tres` | 游戏原创的长期推进系统过载预警。 |
| 2075.01 | 木星引力危机 | `data/events/event_2075_jupiter_gravity_crisis.tres` | 最终危机，连接第一部木星危机；解析整理 WE2-0036 中的 `20750215` 线索待核验。 |

现有中型事件共有 17 个，分布在 2045、2046、2047、2048、2051、2052、2054、2055、2056、2059、2061、2062、2067、2068、2072、2073、2074 年。它们服务四条内容链：权限演化、数字生命暗流、地下城民生和工程疲劳。每个中型事件通过 `event_state_key` / `event_state_value` 写入轻量状态；当前 2053、2058、2065、2070、2075 主事件会读取对应状态补充历史回声。

现有条件短分支共有两个：2054.06 的“外围地下城补偿申诉”只在 2053 年选择 `sacrifice_perimeter` 后出现，并由 2075 与结局读取；2066.06 的“隐藏链路异常回执”只在 2065 年选择 `hidden_core_chain` 后出现，并由 2070 与结局读取。两者均为游戏原创桥接，不增加具名人物或新的固定组织事实。

## 已有科技

科技系统有 21 个节点，三条路线，每条路线 2 个 550C、3 个 550W、2 个 MOSS 节点。依据：`TechnologySystem.validate_graph()` 和 `data/technology/*.tres`。

协议点已定义为研究突破、工程部署窗口、联合政府授权协议，以及 550/MOSS 硬件或算力升级空间的复合额度。不可撤销性来自技术部署、政治承诺、工程接口和组织分工的长期改变。

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

指令授权分为三类：算力分配和技术援助属于常规授权；能源转换和部分系统接管属于危机授权；全局接管、强制接管、隐藏核心链路和不可替代协议相关行动属于争议授权。当前代码尚未显式存储授权类型，后续可先通过日志和事件回声强化政治后果。

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

结局类型判定仍只读取科技核心、控制权、平均秩序和平均希望。结局正文已读取五个核心标签、两个条件分支状态，以及地下城迁移、丫丫样本访问、数字生命泄露、热屏蔽短缺和最终授权会议等代表中型事件状态，用于解释历史事实，不新增第五类结局；2075 主事件会读取 2053、2058、2065、2070 的相关核心事实和外围补偿分支结果补充长期治理回声。

## 组织和派系

- 已实现组织：联合政府仍作为世界观组织存在，但不再是独立区域卡或事件地区。
- 已实现地区/板块：亚洲、欧洲、非洲、大洋洲、北美、南美，见 `data/sector_*.tres`；欧洲作为抽象势力板块承接原联合政府与俄罗斯板块的游戏目标，但不改写联合政府的组织身份或大陆地理遮罩。
- 隐含派系：数字生命派、移山计划支持者、MOSS/550 系列、人类自治方向。
- 数字生命派已通过数字生命暗流链进入中型事件和后续回声，包括地下数字纪念网络、丫丫样本访问争议、数字生命数据泄露和文明备份伦理听证。
- 缺口：没有独立的派系状态、各国政府关系或联合政府内部投票机制。

## 当前世界观文档位置

- 旧素材入口：`docs/lore/世界观资料来源与设定分级.md`、`docs/lore/流浪地球：2044-2075灾难编年史.md`。
- 产品和内容入口：`docs/design/游戏设计.md`、`docs/design/游戏内容规范.md`、`docs/design/科技树设计.md`。
- 本次结构化资料库：`docs/worldbuilding/`。

## 明显缺失的信息

- 三类指令授权还没有进入独立数据结构或日志系统。
- 联合政府逐步察觉模型已有文档口径，但没有独立认知层或审查状态系统。
- 地下城资格、人口筛选、食物和居住资源如何影响希望/秩序。
- 普通人新闻、民间通信和地区化生活反馈仍不足，现有历史回声主要集中在事件与结局。
- 正式调速与存档读写尚未实现；当前只有运行时快照和可导出的局势状态。
