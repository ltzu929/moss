# MOSS模拟器 - AI协作入口

## 项目概述

这是一个基于 Godot 4.x 的策略模拟游戏，玩家扮演 MOSS AI 管理人类文明。

## 快速了解

- 引擎：Godot 4.x，脚本语言为 GDScript。
- 主场景：`scenes/main_os.tscn`。
- 主控制器：`scripts/systems/main_os.gd`，当前承担主循环、事件、指令、进化、胜负判定等核心逻辑。
- 核心循环：2044→2075 年逐年推进，事件弹窗会暂停 Timer 并等待玩家选择，随后更新资源、冷却、进化和结局。
- 自动化播放测试：`tests/test_runner.tscn` + `tests/test_runner.gd`，详见 `docs/dev/测试指南.md`。


## 全局工作原则

1. 技术细节优先查阅 `docs/`，不要把专题内容继续堆回根 `CLAUDE.md`。
2. 游戏数据优先使用 `.tres` 资源文件，避免在代码中硬编码可配置内容。
3. 可以手动编辑 `.tscn` 场景文件；但是场景结构最好通过 Godot MCP 工具调整。
4. 注释、调试信息、UI 文本、事件数据使用中文；代码标识符使用英文。
5. 修改 GDScript 前先查 `docs/dev/代码规范.md`；修改主循环、信号或数据类前先查 `docs/dev/技术架构.md`。
6. 声称完成前必须按 `docs/dev/测试指南.md` 做对应验证。

## 文档查阅索引

| 任务类型 | 先查阅 |
|---------|--------|
| 当前版本目标和阶段进度 | `docs/dev/开发流程.md` |
| 目录结构和关键文件职责 | `docs/dev/项目结构.md` |
| GDScript 代码风格、类型、注释 | `docs/dev/代码规范.md` |
| 主循环、弹窗信号、数据类 | `docs/dev/技术架构.md` |
| 自动化播放测试 | `docs/dev/测试指南.md` |
| Godot/GDScript LSP 配置 | `docs/dev/开发环境.md` |
| 数值设计或平衡调整 | `docs/design/数值设计.md` |
| UI 交互设计 | `docs/design/UI交互规范.md` |
| 事件、台词、结局内容 | `docs/design/游戏内容规范.md` |
| 世界观总览 | `docs/lore/世界观.md` |
| 资料来源和设定分级 | `docs/lore/世界观资料来源与设定分级.md` |
| 2044-2075 时间线素材 | `docs/lore/流浪地球：2044-2075灾难编年史.md` |
| 历史 checklist / 旧计划 | `docs/archive/` |

## docs 目录分类

```text
docs/
├── dev/          # 工程实现、架构、测试、开发流程
├── design/       # 数值、UI、内容写作规范
├── lore/         # 世界观、资料来源、时间线素材
└── superpower/   # 历史specs/plans
```

## 项目结构总览

详见 `docs/dev/项目结构.md`。根目录只保留总览：

```text
res://
├── data/      # .tres 数据资源
├── scripts/   # resources / systems / ui / utils
├── scenes/    # Godot 场景文件
├── tests/     # 自动化播放测试
├── docs/      # 项目文档与设计资料
└── assets/    # 资源素材
```
