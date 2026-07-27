## 独立测试场景共享基类。
## 统一失败计数和基础断言输出，业务测试只维护自身契约。
extends Node

var _failed: int = 0


## 断言条件成立，并将失败同步到场景退出码。
func _assert_true(value: bool, message: String) -> void:
	if value:
		print("[ OK ] " + message)
		return
	_failed += 1
	push_error("[FAIL] " + message)


## 断言实际值与期望值相等。
func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_assert_true(
		actual == expected,
		"%s（期望=%s，实际=%s）" % [message, str(expected), str(actual)]
	)
