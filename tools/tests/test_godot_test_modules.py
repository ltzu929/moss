import contextlib
from dataclasses import asdict
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tools import godot_process
from tools import godot_test_catalog
from tools import godot_test_evaluator
from tools import godot_test_reporter
from tools import run_godot_tests


EXPECTED_REGISTRY = (
    ("tests/project_hygiene_test.tscn", "contracts", "headless"),
    ("tests/project_conventions_test.tscn", "contracts", "headless"),
    ("tests/event_playability_test.tscn", "contracts", "headless"),
    ("tests/mid_event_resource_test.tscn", "contracts", "headless"),
    ("tests/base_resource_contract_test.tscn", "contracts", "headless"),
    ("tests/content_identity_contract_test.tscn", "contracts", "headless"),
    ("tests/resource_isolation_test.tscn", "domain", "headless"),
    ("tests/development_log_test.tscn", "domain", "headless"),
    ("tests/technology_system_test.tscn", "domain", "headless"),
    ("tests/command_system_test.tscn", "domain", "headless"),
    ("tests/time_system_test.tscn", "domain", "headless"),
    ("tests/situation_system_test.tscn", "domain", "headless"),
    ("tests/situation_algorithm_test.tscn", "domain", "headless"),
    ("tests/event_state_test.tscn", "domain", "headless"),
    ("tests/event_resolution_test.tscn", "domain", "headless"),
    ("tests/event_writeback_test.tscn", "domain", "headless"),
    ("tests/branch_event_test.tscn", "domain", "headless"),
    ("tests/event_narrative_baseline_test.tscn", "domain", "headless"),
    ("tests/ending_history_baseline_test.tscn", "domain", "headless"),
    ("tests/decision_history_test.tscn", "ui", "display"),
    ("tests/technology_ui_test.tscn", "ui", "display"),
    ("tests/situation_ui_test.tscn", "ui", "display"),
    ("tests/action_log_ui_test.tscn", "ui", "display"),
    ("tests/ui_layout_1080p_test.tscn", "ui", "display"),
    ("tests/world_map_view_test.tscn", "ui", "headless"),
    ("tests/technology_gameplay_test.tscn", "playthrough", "headless"),
    ("tests/technology_ending_test.tscn", "playthrough", "headless"),
    ("tests/test_runner.tscn", "playthrough", "headless"),
    ("tests/test_runner_managed.tscn", "playthrough", "headless"),
    (
        "tests/test_runner_human_autonomy.tscn",
        "playthrough",
        "headless",
    ),
)


class RegistryAndBoundaryTests(unittest.TestCase):
    def test_registry_order_and_modes_are_frozen(self) -> None:
        actual = tuple(
            (spec.scene, spec.suite, spec.mode)
            for spec in godot_test_catalog.TEST_SPECS
        )

        self.assertEqual(actual, EXPECTED_REGISTRY)

    def test_runner_preserves_legacy_exports_from_focused_modules(self) -> None:
        self.assertIs(
            run_godot_tests.TestSpec,
            godot_test_catalog.TestSpec,
        )
        self.assertIs(
            run_godot_tests.CommandResult,
            godot_process.CommandResult,
        )
        self.assertIs(
            run_godot_tests.SceneResult,
            godot_test_evaluator.SceneResult,
        )
        self.assertIs(
            run_godot_tests.evaluate_scene_result,
            godot_test_evaluator.evaluate_scene_result,
        )
        self.assertIs(
            run_godot_tests.run_command,
            godot_process.run_command,
        )
        self.assertIs(
            run_godot_tests.write_json_report,
            godot_test_reporter.write_json_report,
        )

    def test_cli_list_uses_registry_without_resolving_godot(self) -> None:
        output = io.StringIO()
        with (
            mock.patch.object(
                run_godot_tests,
                "find_godot",
                side_effect=AssertionError("--list must not resolve Godot"),
            ),
            contextlib.redirect_stdout(output),
        ):
            exit_code = run_godot_tests.main(["--suite", "domain", "--list"])

        self.assertEqual(exit_code, 0)
        lines = output.getvalue().splitlines()
        self.assertEqual(len(lines), 13)
        self.assertEqual(
            lines[0],
            "domain\theadless\ttests/resource_isolation_test.tscn",
        )
        self.assertEqual(
            lines[-1],
            "domain\theadless\ttests/ending_history_baseline_test.tscn",
        )

    def test_main_keeps_two_phase_import_before_scene_execution(self) -> None:
        spec = godot_test_catalog.TEST_SPECS[0]
        command_results = [
            run_godot_tests.CommandResult(0, "", 0.1),
            run_godot_tests.CommandResult(0, "", 0.1),
            run_godot_tests.CommandResult(
                0,
                spec.required_markers[0] + "\n",
                0.1,
            ),
        ]
        output = io.StringIO()
        with (
            mock.patch.object(
                run_godot_tests,
                "find_godot",
                return_value="godot",
            ),
            mock.patch.object(
                run_godot_tests,
                "run_command",
                side_effect=command_results,
            ) as run_mock,
            contextlib.redirect_stdout(output),
        ):
            exit_code = run_godot_tests.main([
                "--scene",
                spec.scene,
                "--quiet",
            ])

        self.assertEqual(exit_code, 0)
        self.assertEqual(run_mock.call_count, 3)
        commands = [call.args[0] for call in run_mock.call_args_list]
        self.assertEqual(
            commands[:2],
            [
                ["godot", "--headless", "--editor", "--path", ".", "--quit"],
                ["godot", "--headless", "--editor", "--path", ".", "--quit"],
            ],
        )
        self.assertEqual(
            commands[2],
            ["godot", "--headless", "--path", ".", spec.scene],
        )


class ReportProtocolTests(unittest.TestCase):
    def test_json_report_schema_and_utf8_are_frozen(self) -> None:
        scene_result = run_godot_tests.SceneResult(
            scene="tests/example.tscn",
            suite="domain",
            mode="headless",
            status="passed",
            exit_code=0,
            duration_seconds=0.25,
            timed_out=False,
            missing_markers=["完成，失败断言：0"],
        )
        import_results = [{
            "phase": "validation",
            "exit_code": 0,
            "duration_seconds": 0.1,
            "timed_out": False,
            "memory_limit_exceeded": False,
            "peak_memory_mb": 128.5,
            "unexpected_errors": [],
        }]
        with tempfile.TemporaryDirectory() as temporary_directory:
            report_path = Path(temporary_directory) / "report.json"
            godot_test_reporter.write_json_report(
                report_path,
                suite="domain",
                import_results=import_results,
                scene_results=[scene_result],
                total_duration_seconds=0.5,
            )
            raw_report = report_path.read_text(encoding="utf-8")
            payload = json.loads(raw_report)

        self.assertEqual(
            set(payload),
            {
                "suite",
                "status",
                "total_duration_seconds",
                "imports",
                "tests",
                "summary",
            },
        )
        self.assertEqual(
            set(payload["tests"][0]),
            set(asdict(scene_result)),
        )
        self.assertIn("完成，失败断言：0", raw_report)
        self.assertNotIn("\\u5b8c", raw_report)


if __name__ == "__main__":
    unittest.main()
