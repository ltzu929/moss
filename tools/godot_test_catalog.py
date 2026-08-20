"""Registered Godot test scenes and command-line selection helpers."""

import os
import platform
import sys
from dataclasses import dataclass
from typing import Iterable


VALID_SUITES = ("contracts", "domain", "ui", "playthrough")


@dataclass(frozen=True)
class TestSpec:
    scene: str
    suite: str
    mode: str
    required_markers: tuple[str, ...]


TEST_SPECS = [
    TestSpec(
        "tests/project_hygiene_test.tscn",
        "contracts",
        "headless",
        ("[MOSS-HYGIENE] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/project_conventions_test.tscn",
        "contracts",
        "headless",
        ("[MOSS-CONVENTIONS] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/event_playability_test.tscn",
        "contracts",
        "headless",
        ("[MOSS-EVENT-PLAYABILITY] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/mid_event_resource_test.tscn",
        "contracts",
        "headless",
        ("[MOSS-MID-EVENTS] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/base_resource_contract_test.tscn",
        "contracts",
        "headless",
        ("[MOSS-BASE-RESOURCES] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/content_identity_contract_test.tscn",
        "contracts",
        "headless",
        ("[MOSS-CONTENT-IDENTITY] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/resource_isolation_test.tscn",
        "domain",
        "headless",
        ("[MOSS-RESOURCE-ISOLATION] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/development_log_test.tscn",
        "domain",
        "headless",
        ("[MOSS-DEVELOPMENT-LOG] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/technology_system_test.tscn",
        "domain",
        "headless",
        ("[MOSS-TECH-SYSTEM] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/command_system_test.tscn",
        "domain",
        "headless",
        ("[MOSS-COMMAND-SYSTEM] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/time_system_test.tscn",
        "domain",
        "headless",
        ("[MOSS-TIME-SYSTEM] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/situation_system_test.tscn",
        "domain",
        "headless",
        ("[MOSS-SITUATION-SYSTEM] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/situation_algorithm_test.tscn",
        "domain",
        "headless",
        ("[MOSS-SITUATION-ALGORITHMS] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/event_state_test.tscn",
        "domain",
        "headless",
        ("[MOSS-EVENT-STATE] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/event_resolution_test.tscn",
        "domain",
        "headless",
        ("[MOSS-EVENT-RESOLUTION] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/event_writeback_test.tscn",
        "domain",
        "headless",
        ("[MOSS-EVENT-WRITEBACK] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/branch_event_test.tscn",
        "domain",
        "headless",
        ("[MOSS-BRANCH-EVENTS] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/event_narrative_baseline_test.tscn",
        "domain",
        "headless",
        ("[MOSS-EVENT-NARRATIVE-BASELINE] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/ending_history_baseline_test.tscn",
        "domain",
        "headless",
        ("[MOSS-ENDING-HISTORY-BASELINE] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/decision_history_store_test.tscn",
        "domain",
        "headless",
        ("[MOSS-DECISION-HISTORY-STORE] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/event_narrative_matrix_test.tscn",
        "domain",
        "headless",
        ("[MOSS-EVENT-NARRATIVE-MATRIX] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/ending_history_test.tscn",
        "domain",
        "headless",
        ("[MOSS-ENDING-HISTORY] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/save_system_test.tscn",
        "domain",
        "headless",
        ("[MOSS-SAVE-SYSTEM] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/decision_archive_ui_test.tscn",
        "ui",
        "display",
        ("[MOSS-DECISION-ARCHIVE-UI] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/technology_ui_test.tscn",
        "ui",
        "display",
        ("[MOSS-TECH-UI] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/situation_ui_test.tscn",
        "ui",
        "display",
        ("[MOSS-SITUATION-UI] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/action_log_ui_test.tscn",
        "ui",
        "display",
        ("[MOSS-ACTION-LOG-UI] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/ui_layout_1080p_test.tscn",
        "ui",
        "display",
        ("[MOSS-UI-LAYOUT-1080P] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/app_menu_ui_test.tscn",
        "ui",
        "display",
        ("[MOSS-APP-MENU-UI] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/world_map_view_test.tscn",
        "ui",
        "headless",
        ("[WORLD-MAP-TEST] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/technology_gameplay_test.tscn",
        "playthrough",
        "headless",
        ("[MOSS-TECH-GAMEPLAY] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/technology_ending_test.tscn",
        "playthrough",
        "headless",
        ("[MOSS-TECH-ENDING] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/test_runner.tscn",
        "playthrough",
        "headless",
        (
            "[MOSS-ROUTE:mixed] 完成，失败断言：0",
            "[MOSS-TEST] === 测试结束 ===",
        ),
    ),
    TestSpec(
        "tests/test_runner_managed.tscn",
        "playthrough",
        "headless",
        ("[MOSS-ROUTE:managed] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/test_runner_human_autonomy.tscn",
        "playthrough",
        "headless",
        ("[MOSS-ROUTE:human_autonomy] 完成，失败断言：0",),
    ),
]


def select_test_specs(
    suite: str,
    scenes: Iterable[str] | None = None,
) -> list[TestSpec]:
    """Return registered scenes in frozen registry order."""
    if suite != "all" and suite not in VALID_SUITES:
        raise ValueError(f"Unsupported suite: {suite}")

    requested_scenes = list(scenes or [])
    known_by_scene = {spec.scene: spec for spec in TEST_SPECS}
    unknown_scenes = [
        scene for scene in requested_scenes if scene not in known_by_scene
    ]
    if unknown_scenes:
        raise ValueError(
            "Unregistered test scene(s): " + ", ".join(unknown_scenes)
        )

    selected = [
        spec for spec in TEST_SPECS if suite == "all" or spec.suite == suite
    ]
    if requested_scenes:
        requested = set(requested_scenes)
        selected = [spec for spec in selected if spec.scene in requested]
        missing_from_suite = [
            scene
            for scene in requested_scenes
            if scene not in {spec.scene for spec in selected}
        ]
        if missing_from_suite:
            raise ValueError(
                "Scene(s) do not belong to selected suite "
                f"'{suite}': {', '.join(missing_from_suite)}"
            )
    return selected


def test_args_for_mode(
    mode: str,
    *,
    system_name: str | None = None,
    display_available: bool | None = None,
) -> list[str] | None:
    """Build the unchanged Godot command suffix for a registered test mode."""
    if mode == "headless":
        return ["--headless", "--path", "."]

    if mode != "display":
        raise ValueError(f"Unsupported test mode: {mode}")

    system_name = system_name or platform.system()
    if system_name == "Windows":
        return [
            "--display-driver",
            "windows",
            "--audio-driver",
            "Dummy",
            "--resolution",
            "1920x1080",
            "--path",
            ".",
        ]

    if system_name == "Linux":
        if display_available is None:
            display_available = bool(os.environ.get("DISPLAY"))
        if not display_available:
            print(
                "Display-backed Godot tests require DISPLAY on Linux. "
                "Run this command through xvfb-run in CI.",
                file=sys.stderr,
                flush=True,
            )
            return None
        return [
            "--display-driver",
            "x11",
            "--rendering-method",
            "gl_compatibility",
            "--audio-driver",
            "Dummy",
            "--resolution",
            "1920x1080",
            "--path",
            ".",
        ]

    return [
        "--audio-driver",
        "Dummy",
        "--resolution",
        "1920x1080",
        "--path",
        ".",
    ]
