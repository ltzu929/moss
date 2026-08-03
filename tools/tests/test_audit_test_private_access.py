"""tools/audit_test_private_access.py 的单元测试。

覆盖：三类私有访问识别、全部豁免规则、链式访问、字典 .get 不误报、
--fail-on-new / --require-zero 两种门禁模式、基线写入/读取往返一致。
测试使用 tempfile 自建样例 .gd 文件，不依赖真实 tests/ 内容。
"""

import json
import tempfile
import unittest
from pathlib import Path

from tools import audit_test_private_access as audit


class ExtractAccessesTests(unittest.TestCase):
    """纯代码段的访问提取（extract_accesses 单测）。"""

    def test_direct_member_attribute_and_method(self) -> None:
        self.assertEqual(
            audit.extract_accesses_from_code("obj._foo"),
            [("_foo", "direct_member")],
        )
        self.assertEqual(
            audit.extract_accesses_from_code("obj._foo()"),
            [("_foo", "direct_member")],
        )

    def test_engine_callback_kind(self) -> None:
        self.assertEqual(
            audit.extract_accesses_from_code("_main_os._on_timer_timeout()"),
            [("_on_timer_timeout", "engine_callback")],
        )
        self.assertEqual(
            audit.extract_accesses_from_code("panel._unhandled_input(event)"),
            [("_unhandled_input", "engine_callback")],
        )
        self.assertEqual(
            audit.extract_accesses_from_code("panel._draw()"),
            [("_draw", "engine_callback")],
        )

    def test_engine_callback_set_members(self) -> None:
        for name in ("_ready", "_process", "_physics_process", "_input", "_draw"):
            self.assertEqual(
                audit.extract_accesses_from_code(f"obj.{name}()"),
                [(name, "engine_callback")],
            )
        self.assertEqual(
            audit.extract_accesses_from_code("obj._on_anything()"),
            [("_on_anything", "engine_callback")],
        )

    def test_dynamic_get_set_call(self) -> None:
        self.assertEqual(
            audit.extract_accesses_from_code('obj.get("_situation_auto_paused")'),
            [("_situation_auto_paused", "dynamic_get")],
        )
        self.assertEqual(
            audit.extract_accesses_from_code('obj.set("_hp", 10)'),
            [("_hp", "dynamic_set")],
        )
        self.assertEqual(
            audit.extract_accesses_from_code('obj.call("_run")'),
            [("_run", "dynamic_call")],
        )
        # 多参数与括号内空白
        self.assertEqual(
            audit.extract_accesses_from_code('obj.call("_run", 1, 2)'),
            [("_run", "dynamic_call")],
        )
        self.assertEqual(
            audit.extract_accesses_from_code('obj.call( "_run" )'),
            [("_run", "dynamic_call")],
        )

    def test_self_and_super_exempted(self) -> None:
        self.assertEqual(audit.extract_accesses_from_code("self._foo"), [])
        self.assertEqual(audit.extract_accesses_from_code("self._foo()"), [])
        self.assertEqual(audit.extract_accesses_from_code("self . _foo"), [])
        self.assertEqual(
            audit.extract_accesses_from_code("super._write_heartbeat_slot()"),
            [],
        )

    def test_dictionary_get_with_plain_key_not_reported(self) -> None:
        self.assertEqual(audit.extract_accesses_from_code('d.get("text")'), [])
        self.assertEqual(audit.extract_accesses_from_code('d.get("normal_key")'), [])

    def test_chained_access_reports_private_link_only(self) -> None:
        self.assertEqual(
            audit.extract_accesses_from_code(
                "var h = _main_os._development_log.read_latest_heartbeat()"
            ),
            [("_development_log", "direct_member")],
        )

    def test_indexed_dictionary_get_does_not_double_report(self) -> None:
        # 字符串参数 "text" 不以 _ 开头：只报 _typewriter_queue 直接访问
        self.assertEqual(
            audit.extract_accesses_from_code(
                'str(_main_os._typewriter_queue[0].get("text", ""))'
            ),
            [("_typewriter_queue", "direct_member")],
        )


class ScanFileTests(unittest.TestCase):
    """整文件扫描（scan_file）测试：覆盖注释与字符串豁免。"""

    def _scan(self, content: str) -> list[tuple[str, str]]:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "sample_test.gd"
            path.write_text(content, encoding="utf-8")
            return audit.scan_file(path)

    def test_exempts_comments_and_strings_and_bare_names(self) -> None:
        content = (
            "# obj._foo 注释里的访问\n"
            'var s = "obj._foo 双引号字符串"\n'
            "var t = 'obj._bar 单引号字符串'\n"
            'var u = """obj._baz 三引号字符串"""\n'
            "func run():\n"
            "\t_helper()\n"
            "\tself._own()\n"
            "\tsuper._parent()\n"
        )
        self.assertEqual(self._scan(content), [])

    def test_hash_inside_string_is_not_comment(self) -> None:
        content = (
            'var msg = "text # 字符串里的 # 不是注释"  # 真注释\n'
            "var x = obj._foo\n"
        )
        self.assertEqual(
            self._scan(content),
            [("_foo", "direct_member")],
        )

    def test_triple_quoted_string_spans_lines(self) -> None:
        content = (
            'var doc = """\n'
            "obj._foo 第一行（在字符串里）\n"
            "# 三引号里的 # 不是注释\n"
            "obj._bar 第二行（在字符串里）\n"
            '"""\n'
            "obj._real()\n"
        )
        self.assertEqual(
            self._scan(content),
            [("_real", "direct_member")],
        )

    def test_escaped_quotes_inside_string(self) -> None:
        content = (
            'var s = "obj._foo \\" obj._bar"\n'
            "obj._real()\n"
        )
        self.assertEqual(
            self._scan(content),
            [("_real", "direct_member")],
        )

    def test_engine_callback_via_file_scan(self) -> None:
        content = "_main_os._on_timer_timeout()\npanel._unhandled_input(ev)\n"
        self.assertEqual(
            self._scan(content),
            [("_on_timer_timeout", "engine_callback"),
             ("_unhandled_input", "engine_callback")],
        )

    def test_dynamic_access_via_file_scan(self) -> None:
        content = (
            "if bool(_main_os.get(\"_situation_auto_paused\")):\n"
            "\t_main_os.call(\"_load_editor_preview_states\")\n"
        )
        self.assertEqual(
            self._scan(content),
            [("_situation_auto_paused", "dynamic_get"),
             ("_load_editor_preview_states", "dynamic_call")],
        )

    def test_multiline_dynamic_call_via_file_scan(self) -> None:
        # 跨行调用：call( 在行尾，字符串参数在下一行
        content = (
            "var rect = obj.call(\n"
            "    \"_private_method\"\n"
            ")\n"
        )
        self.assertEqual(
            self._scan(content),
            [("_private_method", "dynamic_call")],
        )

    def test_multiline_dynamic_get_with_plain_key_not_reported(self) -> None:
        content = (
            "var v = d.get(\n"
            "    \"key\"\n"
            ")\n"
        )
        self.assertEqual(self._scan(content), [])

    def test_multiline_dynamic_call_with_plain_arg_not_reported(self) -> None:
        content = (
            "var v = obj.call(\n"
            "    some_var\n"
            ")\n"
        )
        self.assertEqual(self._scan(content), [])

    def test_multiline_stringname_dynamic_call_via_file_scan(self) -> None:
        # 跨行 + StringName 字面量组合
        content = (
            "var v = obj.call(\n"
            "    &\"_private_method\"\n"
            ")\n"
        )
        self.assertEqual(
            self._scan(content),
            [("_private_method", "dynamic_call")],
        )

    def test_multiline_dynamic_call_with_comment_line(self) -> None:
        # 注释行分隔：call( 与字符串参数之间夹着注释
        content = (
            "var v = obj.call(\n"
            "    # 通过私有接口构造测试状态\n"
            "    \"_private_method\"\n"
            ")\n"
        )
        self.assertEqual(
            self._scan(content),
            [("_private_method", "dynamic_call")],
        )

    def test_multiline_dynamic_call_with_blank_line(self) -> None:
        # 空行分隔：call( 与字符串参数之间夹着空行
        content = (
            "var v = obj.call(\n"
            "\n"
            "    \"_private_method\"\n"
            ")\n"
        )
        self.assertEqual(
            self._scan(content),
            [("_private_method", "dynamic_call")],
        )

    def test_multiline_dynamic_call_abandoned_on_plain_code(self) -> None:
        # 跨行后遇到非字符串内容：放弃，不报
        content = (
            "var v = obj.call(\n"
            "    # 注释行不打断\n"
            "    some_var\n"
            ")\n"
        )
        self.assertEqual(self._scan(content), [])

    def test_bare_dynamic_call_exempted(self) -> None:
        # 无显式接收者的裸 get/set/call 等价于 self 调用，与裸名 _helper() 一致
        content = (
            'call("_test_helper")\n'
            'get("_test_state")\n'
            'set("_test_state", true)\n'
            "var x = call(\"_assigned\")\n"
        )
        self.assertEqual(self._scan(content), [])
        # 对照：带接收者的动态调用仍报告
        self.assertEqual(
            audit.extract_accesses_from_code('obj.call("_test_helper")'),
            [("_test_helper", "dynamic_call")],
        )

    def test_bare_dynamic_call_with_preceding_dot_in_line(self) -> None:
        # 同行前面有其他点号（node.value）不影响裸调用判定：仍视为 self
        content = (
            "_assert_eq(node.value, call(\"_test_helper\"))\n"
            "_assert_eq(node.value, get(\"_test_state\"))\n"
        )
        self.assertEqual(self._scan(content), [])
        # 对照：方法名紧邻点号才算有接收者，仍报告
        self.assertEqual(
            audit.extract_accesses_from_code(
                '_assert_eq(node.value, obj.call("_test_helper"))'
            ),
            [("_test_helper", "dynamic_call")],
        )
        # 对照：self 动态调用即使同行有其他点号也豁免
        self.assertEqual(
            audit.extract_accesses_from_code(
                '_assert_eq(node.value, self.call("_test_helper"))'
            ),
            [],
        )

    def test_stringname_dynamic_call_reported(self) -> None:
        self.assertEqual(
            audit.extract_accesses_from_code('obj.call(&"_private_method")'),
            [("_private_method", "dynamic_call")],
        )
        self.assertEqual(
            audit.extract_accesses_from_code('obj.get( &"_state" )'),
            [("_state", "dynamic_get")],
        )

    def test_self_and_super_dynamic_call_exempted(self) -> None:
        self.assertEqual(
            audit.extract_accesses_from_code('self.call("_test_helper")'),
            [],
        )
        self.assertEqual(
            audit.extract_accesses_from_code('super.call("_parent_helper")'),
            [],
        )
        self.assertEqual(
            audit.extract_accesses_from_code('self . get("_own_field")'),
            [],
        )
        # 对照：非 self/super 接收者仍报告
        self.assertEqual(
            audit.extract_accesses_from_code('_main_os.call("_test_helper")'),
            [("_test_helper", "dynamic_call")],
        )


class CliTests(unittest.TestCase):
    """CLI 门禁模式与基线往返测试（tempfile 自建目录）。"""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.tests = self.root / "tests"
        self.tests.mkdir()

    def _write(self, rel: str, content: str) -> Path:
        path = self.tests / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def _baseline(self) -> Path:
        return self.root / "baseline.json"

    def test_write_baseline_then_fail_on_new_passes(self) -> None:
        self._write("a_test.gd", "var x = obj._foo\n")
        baseline = self._baseline()
        self.assertEqual(
            audit.main(["--write-baseline", str(baseline)], tests_dir=self.tests),
            0,
        )
        self.assertEqual(
            audit.main(["--baseline", str(baseline), "--fail-on-new"], tests_dir=self.tests),
            0,
        )

    def test_fail_on_new_rejects_new_entry(self) -> None:
        self._write("a_test.gd", "var x = obj._foo\n")
        baseline = self._baseline()
        audit.main(["--write-baseline", str(baseline)], tests_dir=self.tests)
        self._write("b_test.gd", "var y = obj._bar()\n")
        self.assertEqual(
            audit.main(["--baseline", str(baseline), "--fail-on-new"], tests_dir=self.tests),
            1,
        )

    def test_fail_on_new_rejects_grown_count(self) -> None:
        self._write("a_test.gd", "var x = obj._foo\n")
        baseline = self._baseline()
        audit.main(["--write-baseline", str(baseline)], tests_dir=self.tests)
        self._write("a_test.gd", "var x = obj._foo\nvar y = obj._foo\n")
        self.assertEqual(
            audit.main(["--baseline", str(baseline), "--fail-on-new"], tests_dir=self.tests),
            1,
        )

    def test_require_zero_passes_empty_directory(self) -> None:
        self.assertEqual(
            audit.main(["--require-zero"], tests_dir=self.tests),
            0,
        )

    def test_require_zero_fails_with_access(self) -> None:
        self._write("a_test.gd", "var x = obj._foo\n")
        self.assertEqual(
            audit.main(["--require-zero"], tests_dir=self.tests),
            1,
        )

    def test_baseline_write_read_round_trip(self) -> None:
        self._write("a_test.gd", "var x = obj._foo\nvar y = obj._foo\n")
        baseline = self._baseline()
        self.assertEqual(
            audit.main(["--write-baseline", str(baseline)], tests_dir=self.tests),
            0,
        )
        data = json.loads(baseline.read_text(encoding="utf-8"))
        self.assertEqual(
            data,
            [{"path": "a_test.gd", "member": "_foo",
              "kind": "direct_member", "count": 2}],
        )
        loaded = audit.load_baseline(baseline)
        self.assertEqual(loaded, {("a_test.gd", "_foo", "direct_member"): 2})

    def test_fail_on_new_without_baseline_is_argument_error(self) -> None:
        with self.assertRaises(SystemExit) as ctx:
            audit.main(["--fail-on-new"], tests_dir=self.tests)
        self.assertEqual(ctx.exception.code, 2)

    def test_fail_on_new_and_require_zero_are_mutually_exclusive(self) -> None:
        with self.assertRaises(SystemExit) as ctx:
            audit.main(
                ["--fail-on-new", "--require-zero"],
                tests_dir=self.tests,
            )
        self.assertEqual(ctx.exception.code, 2)

    def test_write_baseline_conflicts_with_gates(self) -> None:
        # 写基线不得与门禁同时执行：否则可用当前状态覆盖基线再自比通过
        baseline = self._baseline()
        with self.assertRaises(SystemExit) as ctx:
            audit.main(
                ["--write-baseline", str(baseline), "--fail-on-new"],
                tests_dir=self.tests,
            )
        self.assertEqual(ctx.exception.code, 2)
        with self.assertRaises(SystemExit) as ctx:
            audit.main(
                ["--write-baseline", str(baseline), "--require-zero"],
                tests_dir=self.tests,
            )
        self.assertEqual(ctx.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
