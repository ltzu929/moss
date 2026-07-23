## 项目卫生测试
## 验证废弃文件不会回归，并确认保留场景仍可加载
extends Node

# ============================================================
# 常量
# ============================================================

const OBSOLETE_PATHS: Array[String] = [
	"res://scenes/evolution_notice.tscn",
	"res://scenes/evolution_popup.tscn",
	"res://scenes/moss_status_panel.tscn",
	"res://scripts/ui/moss_status_panel.gd",
	"res://scripts/ui/moss_status_panel.gd.uid",
	"res://data/sector_ueg.tres",
	"res://data/sector_russia.tres",
]

const RETAINED_SCENES: Array[String] = [
	"res://scenes/allocate_popup.tscn",
	"res://scenes/command_button.tscn",
	"res://scenes/decision_archive_panel.tscn",
	"res://scenes/event_popup.tscn",
	"res://scenes/game_over.tscn",
	"res://scenes/main_os.tscn",
	"res://scenes/sector_info.tscn",
	"res://scenes/technology_node_card.tscn",
	"res://scenes/technology_screen.tscn",
	"res://scenes/year_progress.tscn",
]

# ============================================================
# 测试状态
# ============================================================

var _failed: int = 0

# ============================================================
# 测试入口
# ============================================================

## 执行废弃路径和场景加载检查
func _ready() -> void:
	for path in OBSOLETE_PATHS:
		_assert_true(
			not FileAccess.file_exists(path),
			"废弃路径不应存在：%s" % path
		)

	for scene_path in RETAINED_SCENES:
		var scene := load(scene_path) as PackedScene
		_assert_true(scene != null, "场景应可加载：%s" % scene_path)

	print("[MOSS-HYGIENE] 完成，失败断言：%d" % _failed)
	await get_tree().create_timer(0.2).timeout
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
