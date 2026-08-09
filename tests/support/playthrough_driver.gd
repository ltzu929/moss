## 三条路线的自动驾驶、真实弹窗响应和运行时状态跟踪。
class_name PlaythroughDriver
extends RefCounted

const TEST_TIMER_INTERVAL: float = 0.05

var _main_os: Control = null
var _route_id: String = ""
var _route_config: Dictionary = {}
var _route_catalog: PlaythroughRouteCatalog = null
var _assertions: PlaythroughAssertions = null
var _reporter: PlaythroughReporter = null
var _get_command: Callable
var _request_situation_node: Callable
var _request_situation_approach: Callable
var _toggle_time_control: Callable

var _game_ended: bool = false
var _last_tracked_year: int = 2044
var _last_tracked_month: int = 1
var _event_log: Dictionary = {}
var _event_popup_responding: bool = false
var _alloc_popup_responding: bool = false
var _seen_situation_ids: Array[String] = []
var _technology_plan_index: int = 0
var _technology_blocked_node: String = ""
var _route_command_count: int = 0


func configure(
	main_os: Control,
	route_id: String,
	route_config: Dictionary,
	route_catalog: PlaythroughRouteCatalog,
	assertions: PlaythroughAssertions,
	reporter: PlaythroughReporter,
	get_command: Callable,
	request_situation_node: Callable,
	request_situation_approach: Callable,
	toggle_time_control: Callable
) -> void:
	_main_os = main_os
	_route_id = route_id
	_route_config = route_config
	_route_catalog = route_catalog
	_assertions = assertions
	_reporter = reporter
	_get_command = get_command
	_request_situation_node = request_situation_node
	_request_situation_approach = request_situation_approach
	_toggle_time_control = toggle_time_control


func set_game_ended(value: bool) -> void:
	_game_ended = value


func has_pending_popup_response() -> bool:
	return _event_popup_responding or _alloc_popup_responding


func get_event_log() -> Dictionary:
	return _event_log


func get_seen_situation_ids() -> Array[String]:
	return _seen_situation_ids


func get_route_command_count() -> int:
	return _route_command_count


func setup_auto_responders() -> void:
	_reporter.write_log("[ OK ] 自动响应器就绪（ polling 模式）")


func record_initial_state() -> void:
	_reporter.write_log("初始状态:")
	_reporter.write_log("  日期: %04d.%02d" % [_main_os.current_year, _main_os.current_month])
	_reporter.write_log("  算力: %d" % _main_os.current_cpu)
	_reporter.write_log("  能源: %d" % _main_os.current_energy)
	_reporter.write_log("  最大算力: %d" % _main_os.max_cpu)
	_reporter.write_log("  恢复率: %d" % _main_os.cpu_recovery_rate)
	_reporter.write_log("  科技阶段: %d" % _main_os.technology_stage_level)
	_reporter.write_log("  平均控制权: %d" % _main_os.get_average_authority())


func drive_route_technology() -> void:
	if _main_os == null or _game_ended or is_route_modal_active():
		return
	var technology := _main_os.get_node("%TechnologySystem") as TechnologySystem
	var technology_nodes: Array = _route_config.get("technology_nodes", [])
	if _technology_plan_index >= technology_nodes.size():
		return
	if technology.get_available_points() <= 0:
		return

	var node_id := str(technology_nodes[_technology_plan_index])
	if not technology.can_activate(node_id):
		if _technology_blocked_node != node_id:
			_technology_blocked_node = node_id
			_assertions.assert_true(
				false,
				"路线科技节点应在协议点到账时可激活：%s" % node_id,
				"route_technology"
			)
		return

	var activated := technology.activate(node_id)
	_assertions.assert_true(
		activated,
		"路线应通过真实接口激活科技：%s" % node_id,
		"route_technology"
	)
	if activated:
		_technology_plan_index += 1
		_technology_blocked_node = ""
		_reporter.write_log("  [TECH] 路线 %s 激活 %s" % [_route_id, node_id])


## 在无模态窗口时执行路线解锁的真实指令，依靠生产冷却控制频率。
func drive_route_command() -> void:
	if _main_os == null or _game_ended or is_route_modal_active():
		return
	if _main_os.current_year < int(_route_config.get("command_start_year", 9999)):
		return

	var command_id := str(_route_config.get("command_id", ""))
	if command_id.is_empty():
		return
	var command := _get_command.call(command_id) as CommandData
	if command == null:
		return

	if _main_os.command_requires_selected_sector(command):
		var target := find_route_command_target(command)
		if target == null:
			return
		_main_os.select_sector(target)

	if not _main_os.is_command_available(command):
		return
	if not _main_os.execute_command(command):
		_assertions.assert_true(
			false,
			"已判定可用的路线指令应成功结算：%s" % command_id,
			"route_command"
		)
		return

	if _main_os.command_requires_selected_sector(command):
		_main_os.apply_command_effect(command)
	else:
		_main_os.apply_special_command_effect(command)
	_main_os.update_command_buttons()
	_route_command_count += 1
	_reporter.write_log(
		"  [COMMAND] 路线 %s 第%d次执行 %s"
		% [_route_id, _route_command_count, command_id]
	)


func find_route_command_target(command: CommandData) -> SectorInfo:
	var technology := _main_os.get_node("%TechnologySystem") as TechnologySystem
	var allow_zero_authority := technology.has_tag("human_core")
	var best_target: SectorInfo = null
	var best_social_score := 1000000
	var workspace := _main_os.get_node("MainLayout/StrategicWorkspace") as StrategicWorkspace
	for sector_node in workspace.get_sector_nodes():
		var sector := sector_node as SectorInfo
		if sector == null or sector.data_card == null:
			continue
		var projected_authority := sector.data_card.authority + command.authority_delta
		if not allow_zero_authority and projected_authority < 5:
			continue
		var social_score := sector.data_card.order + sector.data_card.hope
		if social_score < best_social_score:
			best_target = sector
			best_social_score = social_score
	return best_target


func is_route_modal_active() -> bool:
	if _event_popup_responding or _alloc_popup_responding:
		return true
	if _main_os.is_situation_auto_paused():
		return true
	for node_path in ["%EventPopup", "%AllocatePopup"]:
		var modal := _main_os.get_node(node_path) as Control
		if modal != null and modal.visible:
			return true
	return false


## 为完整通关选择每项局势的地方方案、首个节点，并处理自动暂停。
func poll_situations() -> void:
	var snapshots: Array[Dictionary] = _main_os.get_situation_snapshots()
	for snapshot in snapshots:
		var instance_id := str(snapshot.get("instance_id", ""))
		if instance_id not in _seen_situation_ids:
			_seen_situation_ids.append(instance_id)
			_reporter.write_log("发现随机局势: %s" % str(snapshot.get("title", "")))
		var node: Dictionary = snapshot.get("node", {})
		if bool(node.get("pending", false)):
			var node_options: Array = node.get("options", [])
			var preferred_node_index := mini(
				int(_route_config.get("situation_node_choice", 0)),
				node_options.size() - 1
			)
			var ordered_node_indices: Array[int] = []
			if preferred_node_index >= 0:
				ordered_node_indices.append(preferred_node_index)
			for index in range(node_options.size()):
				if index != preferred_node_index:
					ordered_node_indices.append(index)
			for index in ordered_node_indices:
				var option: Dictionary = node_options[index]
				if (
					_main_os.current_cpu >= int(option.get("cpu_cost", 0))
					and _main_os.current_energy >= int(option.get("energy_cost", 0))
				):
					_request_situation_node.call(
						instance_id,
						str(option.get("option_id", ""))
					)
					break
			continue
		if str(snapshot.get("approach_id", "")) != "":
			continue
		var approaches: Array = snapshot.get("approaches", [])
		if approaches.is_empty():
			continue
		var approach_index := mini(
			int(_route_config.get("situation_approach", 0)),
			approaches.size() - 1
		)
		_request_situation_approach.call(
			instance_id,
			str(approaches[approach_index].get("approach_id", ""))
		)

	if _main_os.is_situation_auto_paused():
		_toggle_time_control.call()


func poll_popups() -> void:
	if _main_os == null or _game_ended:
		return
	if not _event_popup_responding:
		var event_popup: PanelContainer = _main_os.get_node("%EventPopup")
		if event_popup != null and event_popup.visible:
			_event_popup_responding = true
			respond_to_event_popup(event_popup)
	if not _alloc_popup_responding:
		var alloc_popup: AllocatePopup = _main_os.get_node("%AllocatePopup")
		if alloc_popup != null and alloc_popup.visible:
			_alloc_popup_responding = true
			respond_to_alloc_popup(alloc_popup)


func respond_to_event_popup(event_popup: PanelContainer) -> void:
	await _main_os.get_tree().process_frame
	await _main_os.get_tree().process_frame

	var year: int = _main_os.current_year
	var month: int = _main_os.current_month
	var title: String = ""
	if event_popup.has_node("%EventTitle"):
		title = event_popup.get_node("%EventTitle").text
	var date_key := "%04d.%02d" % [year, month]
	var event_key := "%s:%s" % [date_key, title]
	var desired_index := _route_catalog.get_event_choice_index(
		_route_config,
		_main_os,
		title,
		year,
		month
	)
	_event_log[event_key] = {
		"year": year,
		"month": month,
		"event_title": title,
		"desired_index": desired_index,
	}
	var option_list := event_popup.get_node("%OptionList") as VBoxContainer
	var option_buttons: Array[Node] = option_list.get_children()
	var selected_index := -1
	if desired_index >= 0 and desired_index < option_buttons.size():
		var preferred_button := option_buttons[desired_index] as Button
		if preferred_button != null and not preferred_button.disabled:
			selected_index = desired_index
		else:
			_assertions.assert_true(
				false,
				"路线目标方案必须真实可点击：%s / 选项%d" % [title, desired_index],
				"route_event_choice"
			)
	else:
		_assertions.assert_true(
			false,
			"应能从稳定事件契约定位路线方案：%s" % title,
			"route_event_choice"
		)
	if selected_index == -1:
		for index in range(option_buttons.size()):
			var candidate := option_buttons[index] as Button
			if candidate != null and not candidate.disabled:
				selected_index = index
				break

	_assertions.assert_true(
		selected_index != -1,
		"事件弹窗必须至少提供一个真实可点击方案：%s" % title,
		"event_playability"
	)
	if selected_index == -1:
		event_popup.option_selected.emit(0)
		event_popup.hide()
	else:
		_reporter.write_log(
			"  [EVENT] 日期=%s 自动点击选项 %d (%s)"
			% [date_key, selected_index, title]
		)
		_event_log[event_key]["selected_index"] = selected_index
		(option_buttons[selected_index] as Button).pressed.emit()
	_event_popup_responding = false


func respond_to_alloc_popup(alloc_popup: AllocatePopup) -> void:
	await _main_os.get_tree().process_frame
	await _main_os.get_tree().process_frame
	_reporter.write_log("  [ALLOCATE] 自动选择：秩序")
	alloc_popup.choice_selected.emit("order")
	alloc_popup.hide()
	_alloc_popup_responding = false


func track_date() -> void:
	var current_year: int = _main_os.current_year
	var current_month: int = _main_os.current_month
	if current_year == _last_tracked_year and current_month == _last_tracked_month:
		return
	var avg_auth: int = _main_os.get_average_authority()
	_reporter.write_log("日期 %04d.%02d->%04d.%02d | CPU=%d 能源=%d 控制权=%d" % [
		_last_tracked_year,
		_last_tracked_month,
		current_year,
		current_month,
		_main_os.current_cpu,
		_main_os.current_energy,
		avg_auth,
	])
	_last_tracked_year = current_year
	_last_tracked_month = current_month
