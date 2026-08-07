import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

from tools import run_godot_tests


class TestSelectionTests(unittest.TestCase):
    def test_all_suite_contains_each_registered_scene_once(self) -> None:
        selected = run_godot_tests.select_test_specs("all")

        self.assertEqual(len(selected), 28)
        self.assertEqual(
            len({spec.scene for spec in selected}),
            len(selected),
        )

    def test_suite_and_scene_filters_must_agree(self) -> None:
        with self.assertRaisesRegex(ValueError, "do not belong"):
            run_godot_tests.select_test_specs(
                "contracts",
                ["tests/time_system_test.tscn"],
            )

    def test_unknown_scene_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "Unregistered"):
            run_godot_tests.select_test_specs(
                "all",
                ["tests/missing_test.tscn"],
            )


class LogGateTests(unittest.TestCase):
    def test_unexpected_godot_errors_are_reported(self) -> None:
        output = (
            "Godot Engine\n"
            "ERROR: Invalid call. Nonexistent function.\n"
            "SCRIPT ERROR: Parse Error: Unexpected token.\n"
            "[FAIL] 业务断言失败\n"
            "[ERROR] 测试流程错误\n"
        )

        errors = run_godot_tests.find_unexpected_errors(output)

        self.assertEqual(len(errors), 4)

    def test_only_exact_missing_godot_ai_errors_are_allowed(self) -> None:
        known = (
            "ERROR: Failed loading resource: "
            "res://addons/godot_ai/runtime/game_helper.gd.\n"
        )
        similar_but_unknown = (
            "ERROR: Failed loading resource: "
            "res://addons/godot_ai/runtime/other_helper.gd.\n"
        )

        self.assertEqual(
            run_godot_tests.find_unexpected_errors(
                known,
                allow_missing_godot_ai=True,
            ),
            [],
        )
        self.assertEqual(
            run_godot_tests.find_unexpected_errors(
                similar_but_unknown,
                allow_missing_godot_ai=True,
            ),
            [similar_but_unknown.strip()],
        )

    def test_missing_terminal_marker_fails_a_zero_exit_scene(self) -> None:
        spec = run_godot_tests.TestSpec(
            "tests/example.tscn",
            "domain",
            "headless",
            ("[MOSS-EXAMPLE] 完成，失败断言：0",),
        )
        command_result = run_godot_tests.CommandResult(
            exit_code=0,
            output="Godot Engine\n",
            duration_seconds=0.1,
        )

        result = run_godot_tests.evaluate_scene_result(
            spec,
            command_result,
        )

        self.assertEqual(result.status, "failed")
        self.assertIn("missing_terminal_marker", result.failure_reasons)

    def test_scene_allows_only_registered_missing_godot_ai_errors(self) -> None:
        spec = run_godot_tests.TestSpec(
            "tests/example.tscn",
            "domain",
            "headless",
            ("[MOSS-EXAMPLE] 完成，失败断言：0",),
        )
        command_result = run_godot_tests.CommandResult(
            exit_code=0,
            output=(
                "ERROR: Failed to instantiate an autoload, can't load from "
                "path: res://addons/godot_ai/runtime/game_helper.gd.\n"
                "[MOSS-EXAMPLE] 完成，失败断言：0\n"
            ),
            duration_seconds=0.1,
        )

        result = run_godot_tests.evaluate_scene_result(
            spec,
            command_result,
        )

        self.assertEqual(result.status, "passed")
        self.assertEqual(result.unexpected_errors, [])

    def test_memory_limit_failure_is_reported(self) -> None:
        spec = run_godot_tests.TestSpec(
            "tests/example.tscn",
            "domain",
            "headless",
            ("[MOSS-EXAMPLE] 完成，失败断言：0",),
        )
        command_result = run_godot_tests.CommandResult(
            exit_code=125,
            output="Process memory limit exceeded.\n",
            duration_seconds=0.1,
            memory_limit_exceeded=True,
            peak_memory_bytes=128 * 1024 * 1024,
        )

        result = run_godot_tests.evaluate_scene_result(spec, command_result)

        self.assertEqual(result.status, "failed")
        self.assertIn("memory_limit_exceeded", result.failure_reasons)
        self.assertEqual(result.peak_memory_mb, 128.0)


class CommandAndReportTests(unittest.TestCase):
    def test_linux_display_mode_forces_supported_xvfb_renderer(self) -> None:
        with (
            mock.patch.object(
                run_godot_tests.platform,
                "system",
                return_value="Linux",
            ),
            mock.patch.dict(run_godot_tests.os.environ, {"DISPLAY": ":99"}),
        ):
            arguments = run_godot_tests.test_args_for_mode("display")

        self.assertIsNotNone(arguments)
        self.assertIn("--rendering-method", arguments)
        self.assertIn("gl_compatibility", arguments)

    def test_silent_command_is_terminated_on_timeout(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            result = run_godot_tests.run_command(
                [
                    sys.executable,
                    "-c",
                    "import time; time.sleep(2)",
                ],
                Path(temporary_directory),
                0.1,
                echo=False,
            )

        self.assertTrue(result.timed_out)
        self.assertEqual(result.exit_code, 124)

    @unittest.skipUnless(
        run_godot_tests.platform.system() in ("Windows", "Linux"),
        "Process memory sampling is implemented on Windows and Linux.",
    )
    def test_memory_hungry_command_is_terminated_before_timeout(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            result = run_godot_tests.run_command(
                [
                    sys.executable,
                    "-c",
                    (
                        "import time; "
                        "payload = bytearray(64 * 1024 * 1024); "
                        "time.sleep(2)"
                    ),
                ],
                Path(temporary_directory),
                5,
                echo=False,
                memory_limit_mb=32,
            )

        self.assertTrue(result.memory_limit_exceeded)
        self.assertFalse(result.timed_out)
        self.assertEqual(result.exit_code, 125)
        self.assertIn("memory limit", result.output.lower())

    def test_json_report_contains_machine_readable_summary(self) -> None:
        scene_result = run_godot_tests.SceneResult(
            scene="tests/example.tscn",
            suite="domain",
            mode="headless",
            status="passed",
            exit_code=0,
            duration_seconds=0.25,
            timed_out=False,
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            report_path = Path(temporary_directory) / "report.json"
            run_godot_tests.write_json_report(
                report_path,
                suite="domain",
                import_results=[{
                    "phase": "validation",
                    "exit_code": 0,
                    "duration_seconds": 0.1,
                    "timed_out": False,
                    "unexpected_errors": [],
                }],
                scene_results=[scene_result],
                total_duration_seconds=0.5,
            )
            payload = json.loads(report_path.read_text(encoding="utf-8"))

        self.assertEqual(payload["status"], "passed")
        self.assertEqual(payload["summary"], {
            "total": 1,
            "passed": 1,
            "failed": 0,
        })

    def test_github_summary_contains_import_and_scene_peak_memory(self) -> None:
        scene_result = run_godot_tests.SceneResult(
            scene="tests/example.tscn",
            suite="domain",
            mode="headless",
            status="passed",
            exit_code=0,
            duration_seconds=0.25,
            timed_out=False,
            peak_memory_mb=256.0,
        )
        import_results = [
            {
                "phase": "bootstrap",
                "exit_code": 0,
                "duration_seconds": 0.1,
                "timed_out": False,
                "memory_limit_exceeded": False,
                "peak_memory_mb": 128.5,
                "unexpected_errors": [],
            },
            {
                "phase": "validation",
                "exit_code": 0,
                "duration_seconds": 0.2,
                "timed_out": False,
                "memory_limit_exceeded": False,
                "peak_memory_mb": 132.0,
                "unexpected_errors": [],
            },
        ]

        with tempfile.TemporaryDirectory() as temporary_directory:
            summary_path = Path(temporary_directory) / "summary.md"
            with mock.patch.dict(
                run_godot_tests.os.environ,
                {"GITHUB_STEP_SUMMARY": str(summary_path)},
            ):
                run_godot_tests.append_github_summary(
                    "domain",
                    import_results,
                    [scene_result],
                    0.5,
                )
            summary = summary_path.read_text(encoding="utf-8")

        self.assertIn("#### Import phases", summary)
        self.assertIn("| `bootstrap` | passed | 0.100s | 128.5 MiB |", summary)
        self.assertIn("| `validation` | passed | 0.200s | 132.0 MiB |", summary)
        self.assertIn("#### Test scenes", summary)
        self.assertIn(
            "| `tests/example.tscn` | headless | passed | 0.250s | "
            "256.0 MiB |",
            summary,
        )


if __name__ == "__main__":
    unittest.main()
