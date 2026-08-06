"""content identity audit tool 的单元测试。"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools import audit_content_identity as audit


class MappingTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        (self.root / "data" / "events").mkdir(parents=True)
        (self.root / "data").mkdir(exist_ok=True)
        regions = {
            "asia": "亚洲",
            "north_america": "北美",
            "europe": "欧洲",
            "africa": "非洲",
            "south_america": "南美",
            "oceania": "大洋洲",
        }
        for region_id, region_name in regions.items():
            (self.root / "data" / f"sector_{region_id}.tres").write_text(
                '[resource]\nregion_id = "%s"\nregion_name = "%s"\n'
                % (region_id, region_name),
                encoding="utf-8",
            )

    def test_collect_mapping_preserves_event_and_option_order(self) -> None:
        event = """[resource]
event_id = "event_sample"
event_title = "示例事件"
event_region = "asia"
required_decision_tag_key = ""
required_decision_tag_value = ""

[sub_resource type="Resource" id="Option_1"]
option_id = "option_01"
button_text = "第一个方案"
decision_tag_key = "decision.sample"
decision_tag_value = "known"

[sub_resource type="Resource" id="Option_2"]
option_id = "option_02"
button_text = "第二个方案"
"""
        (self.root / "data" / "events" / "event_sample.tres").write_text(
            event, encoding="utf-8"
        )
        mapping = audit.collect_mapping(self.root)

        self.assertEqual(mapping["events"][0]["event_id"], "event_sample")
        self.assertEqual(
            [option["option_id"] for option in mapping["events"][0]["options"]],
            ["option_01", "option_02"],
        )
        self.assertEqual(
            mapping["events"][0]["options"][0]["decision_tag_key"],
            "decision.sample",
        )
        self.assertEqual(
            mapping["decision_tag_writes"],
            [
                {
                    "path": "res://data/events/event_sample.tres",
                    "event_id": "event_sample",
                    "option_index": 0,
                    "option_id": "option_01",
                    "decision_tag_key": "decision.sample",
                    "decision_tag_value": "known",
                }
            ],
        )
        sectors = {sector["path"]: sector for sector in mapping["sectors"]}
        self.assertEqual(sectors["res://data/sector_asia.tres"]["region_id"], "asia")
        self.assertEqual(audit.validate_mapping(mapping), [])

    def test_cli_writes_and_compares_mapping_baseline(self) -> None:
        (self.root / "data" / "events" / "event_sample.tres").write_text(
            '[resource]\nevent_id = "event_sample"\nevent_title = "示例事件"\n'
            'event_region = "asia"\n',
            encoding="utf-8",
        )
        baseline = self.root / "fixtures" / "content_identity_baseline.json"

        self.assertEqual(
            audit.main(
                ["--write-baseline", str(baseline)],
                root=self.root,
            ),
            0,
        )
        self.assertEqual(
            audit.main(["--baseline", str(baseline)], root=self.root),
            0,
        )
        self.assertEqual(json.loads(baseline.read_text(encoding="utf-8"))["schema_version"], 1)

    def test_validate_mapping_rejects_path_id_mismatch(self) -> None:
        event = self.root / "data" / "events" / "event_sample.tres"
        event.write_text(
            '[resource]\nevent_id = "event_sample"\nevent_title = "示例事件"\n'
            'event_region = "asia"\n',
            encoding="utf-8",
        )
        mapping = audit.collect_mapping(self.root)
        mapping["events"][0]["event_id"] = "event_other"

        errors = audit.validate_mapping(mapping)

        self.assertIn("事件 ID 与资源路径错配", "\n".join(errors))

    def test_validate_mapping_rejects_dangling_decision_tag_key_and_value(self) -> None:
        event = self.root / "data" / "events" / "event_sample.tres"
        event.write_text(
            '[resource]\nevent_id = "event_sample"\nevent_title = "示例事件"\n'
            'event_region = "asia"\n'
            '\n[sub_resource type="Resource" id="Option_1"]\n'
            'option_id = "option_01"\nbutton_text = "第一个方案"\n'
            'decision_tag_key = "decision.sample"\n'
            'decision_tag_value = "known"\n',
            encoding="utf-8",
        )

        cases = (
            (
                "decision.missing",
                "known",
                "条件分支引用的决策标签键不存在",
            ),
            (
                "decision.sample",
                "missing",
                "条件分支引用的决策标签值不存在",
            ),
        )
        for branch_key, branch_value, expected_message in cases:
            with self.subTest(branch_key=branch_key, branch_value=branch_value):
                mapping = audit.collect_mapping(self.root)
                mapping["events"][0]["required_decision_tag_key"] = branch_key
                mapping["events"][0]["required_decision_tag_value"] = branch_value
                errors = audit.validate_mapping(mapping)
                self.assertIn(expected_message, "\n".join(errors))


class UsageClassificationTests(unittest.TestCase):
    def test_classifies_the_five_identity_use_categories(self) -> None:
        cases = {
            ("data/events/sample.tres", 'event_title = "标题"'): "display_only",
            ("scripts/systems/main_os.gd", "triggered_events.append(event_key)"): "runtime_identity",
            ("data/events/sample.tres", 'event_state_key = "state.key"'): "condition",
            ("tests/sample_test.gd", 'assert event_title == "标题"'): "log_or_test",
            ("data/events/sample.tres", 'event_region = "亚洲"'): "data_reference",
        }
        for (path, line), category in cases.items():
            with self.subTest(path=path, line=line):
                usage = audit.classify_usage(path, line)
                self.assertIsNotNone(usage)
                self.assertEqual(usage["category"], category)

    def test_classifies_real_runtime_consumers_by_function_scope(self) -> None:
        project_root = Path(__file__).resolve().parents[2]
        usages = audit.scan_usage(project_root)
        expectations = {
            "_get_event_trigger_key": "event_id",
            "_get_event_option": "option_id",
            "_find_sector_by_id": "region_id",
        }
        for function_name, field in expectations.items():
            with self.subTest(function_name=function_name):
                matches = [
                    usage
                    for usage in usages
                    if usage["function_scope"] == function_name
                    and field in usage["fields"]
                ]
                self.assertTrue(matches, f"未扫描到 {function_name} 的 {field} 使用")
                self.assertTrue(
                    all(usage["category"] == "runtime_identity" for usage in matches),
                    matches,
                )


if __name__ == "__main__":
    unittest.main()
