## 科技界面集成测试
## 验证模态冲突、节点状态、详情同步、两步确认和计时器恢复
extends Node

# ============================================================
# 测试状态
# ============================================================

## 失败断言数量，同时作为进程退出码
var _failed: int = 0
## 被测主场景实例
var _main_os: Control
## 被测科技系统
var _technology: TechnologySystem
## 被测科技控制台
var _screen
## 主场景年份计时器
var _timer: Timer

# ============================================================
# 测试入口
# ============================================================

## 创建主场景并执行科技控制台交互断言
func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main_os.tscn")
	_main_os = scene.instantiate()
	add_child(_main_os)
	await get_tree().process_frame

	_technology = _main_os.get_node("%TechnologySystem")
	_screen = _main_os.get_node("%TechnologyScreen")
	_timer = _main_os.get_node("Timer")
	_timer.start()

	_assert_true(_main_os._can_open_technology_screen(), "无模态弹窗时应允许打开科技树")
	_main_os.get_node("%EventPopup").show()
	_assert_true(not _main_os._can_open_technology_screen(), "事件弹窗应阻止科技树")
	_main_os.get_node("%EventPopup").hide()
	_main_os.get_node("%AllocatePopup").show()
	_assert_true(not _main_os._can_open_technology_screen(), "算力分配弹窗应阻止科技树")
	_main_os.get_node("%AllocatePopup").hide()

	_main_os._on_technology_button_pressed()
	_assert_true(_screen.visible, "科技树应全屏显示")
	_assert_true(_timer.is_stopped(), "打开科技树应暂停年份")
	_assert_eq(_screen._node_buttons.size(), 12, "矩阵应渲染12个节点")
	_assert_eq(
		_technology.get_activation_state("managed_decision"),
		"available",
		"550C根节点应可激活"
	)
	_assert_eq(
		_technology.get_activation_state("managed_infrastructure"),
		"stage_locked",
		"开局550W节点应阶段锁定"
	)
	_assert_eq(
		_technology.get_activation_state("managed_irreplaceable_protocol"),
		"stage_locked",
		"开局MOSS核心应阶段锁定"
	)

	_screen._on_node_selected("managed_decision")
	_assert_eq(_screen._selected_node_id, "managed_decision", "节点应进入当前选中状态")
	_assert_eq(_screen._detail_name.text, "辅助决策接口", "右侧详情应同步节点名称")
	_assert_eq(_screen._activate_button.text, "激活协议", "首次应显示激活操作")
	_screen._on_activate_pressed()
	_assert_eq(_technology.get_active_node_ids().size(), 0, "第一次点击不得直接激活")
	_assert_eq(_screen._activate_button.text, "确认不可逆激活", "第一次点击应进入确认")
	_screen._on_activate_pressed()
	_assert_true(_technology.is_active("managed_decision"), "第二次点击应激活节点")
	_assert_eq(
		_technology.get_activation_state("core_energy_mapping"),
		"points_locked",
		"协议点耗尽后其他根节点应显示点数不足"
	)

	_technology.grant_research_for_year(2048)
	_assert_true(_technology.activate("core_energy_mapping"), "第二个根节点应推动阶段升级")
	_assert_eq(
		_technology.get_activation_state("managed_infrastructure"),
		"points_locked",
		"已满足前置但无点数的节点应显示点数不足"
	)
	_assert_eq(
		_technology.get_activation_state("human_autonomy_network"),
		"prerequisite_locked",
		"未激活路线根节点时应显示前置锁定"
	)

	_screen.close_screen()
	_assert_true(not _screen.visible, "关闭科技树应隐藏覆盖层")
	_assert_true(not _timer.is_stopped(), "关闭后应恢复原本运行的年份计时")

	get_tree().quit(_failed)

# ============================================================
# 断言辅助方法
# ============================================================

## 断言条件为 true，失败时累计退出码并输出错误
func _assert_true(value: bool, message: String) -> void:
	if value:
		print("[ OK ] " + message)
		return
	_failed += 1
	push_error("[FAIL] " + message)


## 断言实际值与期望值相等
func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_assert_true(
		actual == expected,
		"%s（期望=%s，实际=%s）" % [message, str(expected), str(actual)]
	)
