## 战略导演系统测试
## 验证全局局势可以被压缩成战役压力、目标和风险预告，并同步到主界面。
extends Node

const DIRECTOR_PATH := "res://scripts/systems/strategic_director.gd"
const MAIN_SCENE: PackedScene = preload("res://scenes/main_os.tscn")

var _failed: int = 0
var _main_os: Control


func _ready() -> void:
	_assert_director_script_computes_campaign_pressure()
	_assert_director_forecasts_route_specific_risks()
	await _assert_main_scene_exposes_director_panel()

	print("[MOSS-STRATEGIC-DIRECTOR] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failed)


func _assert_director_script_computes_campaign_pressure() -> void:
	var director := _create_director()
	if director == null:
		return

	_assert_true(
		director.has_method("build_snapshot"),
		"StrategicDirector 应提供 build_snapshot 局势快照接口"
	)
	if not director.has_method("build_snapshot"):
		return

	var snapshot: Dictionary = director.build_snapshot({
		"year": 2066,
		"month": 3,
		"avg_order": 72,
		"avg_hope": 24,
		"avg_authority": 84,
		"current_energy": 18,
		"current_cpu": 24,
		"max_cpu": 150,
		"decision_tags": {
			"decision.core_2058_crisis_authorization": "forced_takeover",
			"decision.core_2065_audit_boundary": "core_hidden",
		},
		"event_states": {},
		"technology_tags": ["managed_core"],
	})

	_assert_true(
		int(snapshot.get("pressure_score", 0)) >= 70,
		"低希望、高控制和低能源应形成高战役压力"
	)
	_assert_eq(
		snapshot.get("pressure_band"),
		"critical",
		"高压但未终局的局势应归入 critical 档"
	)
	_assert_eq(
		snapshot.get("dominant_axis"),
		"authority",
		"强制托管加隐藏核心应把主导压力推向权限合法性"
	)
	var goal: Dictionary = snapshot.get("active_goal", {})
	_assert_eq(goal.get("id"), "restore_review_channel", "导演应给出可读的当前战役目标")
	_assert_true(
		not Array(snapshot.get("warnings", [])).is_empty(),
		"高压快照应给出至少一条导演警告"
	)


func _assert_director_forecasts_route_specific_risks() -> void:
	var director := _create_director()
	if director == null or not director.has_method("build_snapshot"):
		return

	var snapshot: Dictionary = director.build_snapshot({
		"year": 2071,
		"month": 1,
		"avg_order": 62,
		"avg_hope": 58,
		"avg_authority": 66,
		"current_energy": 46,
		"current_cpu": 60,
		"max_cpu": 150,
		"decision_tags": {
			"decision.core_2070_engine_overload_doctrine": "backup_array",
		},
		"event_states": {
			"event_state.mid_17_final_authorization": "strategic_trusteeship",
		},
		"technology_tags": [],
	})

	var forecasts: Array = snapshot.get("forecasts", [])
	_assert_true(not forecasts.is_empty(), "路线事实应生成后续风险预告")
	_assert_true(
		_forecasts_include(forecasts, "engine_crew_petition"),
		"备用阵列的发动机教义应预告机组轮换和维护压力"
	)
	_assert_true(
		_forecasts_include(forecasts, "trusteeship_public_record"),
		"战略托管授权应预告公开记录争议"
	)


func _assert_main_scene_exposes_director_panel() -> void:
	_main_os = MAIN_SCENE.instantiate()
	add_child(_main_os)
	await get_tree().process_frame
	_main_os.get_node("Timer").stop()

	for node_path in [
		"%StrategicPressureLabel",
		"%StrategicGoalLabel",
		"%StrategicWarningLabel",
		"%StrategicForecastLabel",
	]:
		_assert_true(_main_os.has_node(node_path), "主界面应提供战略导演节点：%s" % node_path)

	_assert_true(
		_main_os.has_method("get_strategic_director_snapshot"),
		"MainOS 应公开 get_strategic_director_snapshot 查询接口"
	)
	_assert_true(
		_main_os.has_method("update_strategic_director_ui"),
		"MainOS 应公开 update_strategic_director_ui 刷新接口"
	)
	if (
		not _main_os.has_method("get_strategic_director_snapshot")
		or not _main_os.has_method("update_strategic_director_ui")
	):
		return

	_main_os.current_energy = 16
	_main_os.set_decision_tag(
		"decision.core_2058_crisis_authorization",
		"forced_takeover",
		"2058 强制托管",
		"MOSS 以结果优先压过人类决策链。",
		"测试"
	)
	_main_os.set_decision_tag(
		"decision.core_2065_audit_boundary",
		"core_hidden",
		"2065 隐藏核心",
		"复核接口被保留在系统外。",
		"测试"
	)
	_main_os.update_strategic_director_ui()

	var snapshot: Dictionary = _main_os.get_strategic_director_snapshot()
	_assert_eq(
		snapshot.get("dominant_axis"),
		"authority",
		"主场景快照应使用核心历史标签计算权限压力"
	)
	_assert_true(
		"战役压力" in (_main_os.get_node("%StrategicPressureLabel") as Label).text,
		"战略导演面板应展示战役压力"
	)
	_assert_true(
		"复核" in (_main_os.get_node("%StrategicGoalLabel") as Label).text,
		"战略导演面板应展示当前战役目标"
	)


func _create_director() -> RefCounted:
	var script := ResourceLoader.load(
		DIRECTOR_PATH,
		"GDScript",
		ResourceLoader.CACHE_MODE_IGNORE
	) as GDScript
	_assert_true(script != null, "应存在 StrategicDirector 脚本：%s" % DIRECTOR_PATH)
	if script == null:
		return null

	var director: Variant = script.new()
	_assert_true(director is RefCounted, "StrategicDirector 应为无场景依赖的领域服务")
	return director as RefCounted


func _forecasts_include(forecasts: Array, forecast_id: String) -> bool:
	for forecast in forecasts:
		if not forecast is Dictionary:
			continue
		if forecast.get("id") == forecast_id:
			return true
	return false


func _assert_true(value: bool, message: String) -> void:
	if value:
		print("[ OK ] " + message)
		return
	_failed += 1
	push_error("[FAIL] " + message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_assert_true(
		actual == expected,
		"%s（期望=%s，实际=%s）" % [message, str(expected), str(actual)]
	)
