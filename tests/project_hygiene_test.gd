## 项目卫生测试
## 验证废弃文件不会回归，并确认 scenes 目录中的场景均可加载
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

const SCENE_DIRECTORY: String = "res://scenes/"

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

	var scene_files := DirAccess.get_files_at(SCENE_DIRECTORY)
	scene_files.sort()
	var scene_count := 0
	for file_name in scene_files:
		if not file_name.ends_with(".tscn"):
			continue
		scene_count += 1
		var scene_path := SCENE_DIRECTORY + file_name
		var scene := load(scene_path) as PackedScene
		_assert_true(scene != null, "场景应可加载：%s" % scene_path)
	_assert_true(scene_count > 0, "scenes 目录应至少包含一个场景")

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
