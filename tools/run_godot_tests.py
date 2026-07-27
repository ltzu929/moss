import argparse
from dataclasses import asdict, dataclass, field
import json
import os
import platform
from pathlib import Path
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
from typing import Iterable, Sequence


DEFAULT_IMPORT_TIMEOUT_SECONDS = 180
DEFAULT_TEST_TIMEOUT_SECONDS = 90
VALID_SUITES = ("contracts", "domain", "ui", "playthrough")


@dataclass(frozen=True)
class TestSpec:
    scene: str
    suite: str
    mode: str
    required_markers: tuple[str, ...]


@dataclass
class CommandResult:
    exit_code: int
    output: str
    duration_seconds: float
    timed_out: bool = False


@dataclass
class SceneResult:
    scene: str
    suite: str
    mode: str
    status: str
    exit_code: int
    duration_seconds: float
    timed_out: bool
    missing_markers: list[str] = field(default_factory=list)
    unexpected_errors: list[str] = field(default_factory=list)
    failure_reasons: list[str] = field(default_factory=list)


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
        "tests/event_state_test.tscn",
        "domain",
        "headless",
        ("[MOSS-EVENT-STATE] 完成，失败断言：0",),
    ),
    TestSpec(
        "tests/decision_history_test.tscn",
        "ui",
        "display",
        ("[MOSS-DECISION-HISTORY] 完成，失败断言：0",),
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
        "tests/ui_layout_1080p_test.tscn",
        "ui",
        "display",
        ("[MOSS-UI-LAYOUT-1080P] 完成，失败断言：0",),
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
        ("[MOSS-TEST] 失败: 0", "[MOSS-TEST] === 测试结束 ==="),
    ),
]


ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
KNOWN_GODOT_AI_ERROR_FRAGMENTS = (
    "Attempt to open script 'res://addons/godot_ai/runtime/game_helper.gd' "
    "resulted in error 'File not found'",
    "Failed loading resource: res://addons/godot_ai/runtime/game_helper.gd",
    "Failed to create an autoload, can't load from UID or path: "
    "res://addons/godot_ai/runtime/game_helper.gd",
    "Failed to instantiate an autoload, can't load from path: "
    "res://addons/godot_ai/runtime/game_helper.gd",
)


def find_godot(godot_arg: str | None) -> str | None:
    if godot_arg:
        return godot_arg

    godot_bin = os.environ.get("GODOT_BIN")
    if godot_bin:
        return godot_bin

    for command_name in ("godot", "godot4"):
        if shutil.which(command_name):
            return command_name

    return None


def _stream_reader(
    stream,
    output_queue: queue.Queue[str | None],
) -> None:
    try:
        for line in iter(stream.readline, ""):
            output_queue.put(line)
    finally:
        stream.close()
        output_queue.put(None)


def run_command(
    command: Sequence[str],
    project_root: Path,
    timeout_seconds: int | float,
    *,
    echo: bool = True,
) -> CommandResult:
    started = time.monotonic()
    try:
        process = subprocess.Popen(
            list(command),
            cwd=project_root,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
    except FileNotFoundError:
        message = f"Godot executable not found: {command[0]}"
        if echo:
            print(message, file=sys.stderr, flush=True)
        return CommandResult(127, message + "\n", 0.0)

    assert process.stdout is not None
    output_queue: queue.Queue[str | None] = queue.Queue()
    reader = threading.Thread(
        target=_stream_reader,
        args=(process.stdout, output_queue),
        daemon=True,
    )
    reader.start()

    output_lines: list[str] = []
    stream_finished = False
    timed_out = False
    while process.poll() is None or not stream_finished:
        elapsed = time.monotonic() - started
        if process.poll() is None and elapsed > timeout_seconds:
            timed_out = True
            process.kill()

        try:
            line = output_queue.get(timeout=0.05)
        except queue.Empty:
            continue

        if line is None:
            stream_finished = True
            continue

        output_lines.append(line)
        if echo:
            print(line, end="", flush=True)

    reader.join(timeout=1.0)
    exit_code = process.wait()
    duration = time.monotonic() - started
    if timed_out:
        exit_code = 124
        timeout_message = (
            f"Command timed out after {timeout_seconds}s: {' '.join(command)}"
        )
        output_lines.append(timeout_message + "\n")
        if echo:
            print(timeout_message, file=sys.stderr, flush=True)

    return CommandResult(
        exit_code=exit_code,
        output="".join(output_lines),
        duration_seconds=duration,
        timed_out=timed_out,
    )


def _normalized_log_line(line: str) -> str:
    return ANSI_ESCAPE_RE.sub("", line).strip()


def is_known_godot_ai_error(line: str) -> bool:
    return any(fragment in line for fragment in KNOWN_GODOT_AI_ERROR_FRAGMENTS)


def find_unexpected_errors(
    output: str,
    *,
    allow_missing_godot_ai: bool = False,
) -> list[str]:
    errors: list[str] = []
    for raw_line in output.splitlines():
        line = _normalized_log_line(raw_line)
        if not line:
            continue

        is_failure_line = (
            "ERROR:" in line
            or "SCRIPT ERROR:" in line
            or "Parse Error:" in line
            or "[FAIL]" in line
            or "[ERROR]" in line
            or "[FATAL]" in line
        )
        if not is_failure_line:
            continue
        if allow_missing_godot_ai and is_known_godot_ai_error(line):
            continue
        errors.append(line)
    return errors


def select_test_specs(
    suite: str,
    scenes: Iterable[str] | None = None,
) -> list[TestSpec]:
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


def test_args_for_mode(mode: str) -> list[str] | None:
    if mode == "headless":
        return ["--headless", "--path", "."]

    if mode != "display":
        raise ValueError(f"Unsupported test mode: {mode}")

    system_name = platform.system()
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
        if not os.environ.get("DISPLAY"):
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


def evaluate_scene_result(
    spec: TestSpec,
    command_result: CommandResult,
) -> SceneResult:
    missing_markers = [
        marker
        for marker in spec.required_markers
        if marker not in command_result.output
    ]
    unexpected_errors = find_unexpected_errors(
        command_result.output,
        allow_missing_godot_ai=True,
    )
    failure_reasons: list[str] = []
    if command_result.timed_out:
        failure_reasons.append("timeout")
    if command_result.exit_code != 0:
        failure_reasons.append(f"exit_code={command_result.exit_code}")
    if missing_markers:
        failure_reasons.append("missing_terminal_marker")
    if unexpected_errors:
        failure_reasons.append("unexpected_error_log")

    return SceneResult(
        scene=spec.scene,
        suite=spec.suite,
        mode=spec.mode,
        status="passed" if not failure_reasons else "failed",
        exit_code=command_result.exit_code,
        duration_seconds=round(command_result.duration_seconds, 3),
        timed_out=command_result.timed_out,
        missing_markers=missing_markers,
        unexpected_errors=unexpected_errors,
        failure_reasons=failure_reasons,
    )


def write_json_report(
    report_path: Path,
    *,
    suite: str,
    import_results: list[dict],
    scene_results: list[SceneResult],
    total_duration_seconds: float,
) -> None:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    imports_passed = bool(import_results) and all(
        result["exit_code"] == 0
        and not result["timed_out"]
        and not result["unexpected_errors"]
        for result in import_results
    )
    tests_passed = bool(scene_results) and all(
        result.status == "passed" for result in scene_results
    )
    payload = {
        "suite": suite,
        "status": "passed" if imports_passed and tests_passed else "failed",
        "total_duration_seconds": round(total_duration_seconds, 3),
        "imports": import_results,
        "tests": [asdict(result) for result in scene_results],
        "summary": {
            "total": len(scene_results),
            "passed": sum(
                result.status == "passed" for result in scene_results
            ),
            "failed": sum(
                result.status == "failed" for result in scene_results
            ),
        },
    }
    report_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def append_github_summary(
    suite: str,
    scene_results: list[SceneResult],
    total_duration_seconds: float,
) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return

    failed = sum(result.status == "failed" for result in scene_results)
    lines = [
        f"### Godot test suite: `{suite}`",
        "",
        "| Scene | Mode | Status | Duration |",
        "| --- | --- | --- | ---: |",
    ]
    for result in scene_results:
        lines.append(
            f"| `{result.scene}` | {result.mode} | {result.status} | "
            f"{result.duration_seconds:.3f}s |"
        )
    lines.extend([
        "",
        f"Total: {len(scene_results) - failed} passed, {failed} failed, "
        f"{total_duration_seconds:.3f}s.",
        "",
    ])
    with Path(summary_path).open("a", encoding="utf-8") as summary_file:
        summary_file.write("\n".join(lines))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run registered Godot tests.")
    parser.add_argument("--godot", help="Path to Godot executable")
    parser.add_argument(
        "--suite",
        choices=("all", *VALID_SUITES),
        default="all",
        help="Run one test suite (default: all)",
    )
    parser.add_argument(
        "--scene",
        action="append",
        default=[],
        help="Run one registered scene; may be repeated",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List registered test scenes without running Godot",
    )
    parser.add_argument(
        "--report-json",
        type=Path,
        help="Write a machine-readable JSON test report",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress passing child-process logs and print runner summaries",
    )
    parser.add_argument(
        "--import-timeout",
        type=int,
        default=DEFAULT_IMPORT_TIMEOUT_SECONDS,
        help="Project import timeout in seconds (default: 180)",
    )
    parser.add_argument(
        "--test-timeout",
        type=int,
        default=DEFAULT_TEST_TIMEOUT_SECONDS,
        help="Per-scene timeout in seconds (default: 90)",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.import_timeout <= 0 or args.test_timeout <= 0:
        parser.error("Timeout values must be positive integers.")

    try:
        selected_specs = select_test_specs(args.suite, args.scene)
    except ValueError as error:
        parser.error(str(error))

    if args.list:
        for spec in selected_specs:
            print(f"{spec.suite}\t{spec.mode}\t{spec.scene}")
        return 0

    if not selected_specs:
        parser.error("No test scenes selected.")

    project_root = Path(__file__).resolve().parents[1]
    godot = find_godot(args.godot)
    if not godot:
        print(
            "Godot executable not found. Provide it with --godot, GODOT_BIN, "
            "or PATH command 'godot'/'godot4'.",
            file=sys.stderr,
            flush=True,
        )
        return 1

    started = time.monotonic()
    print(f"Using Godot: {godot}", flush=True)
    print(
        f"Selected suite: {args.suite} ({len(selected_specs)} scene(s))",
        flush=True,
    )

    import_results: list[dict] = []
    print("Bootstrapping project import cache...", flush=True)
    bootstrap_result = run_command(
        [godot, "--headless", "--editor", "--path", ".", "--quit"],
        project_root,
        args.import_timeout,
        echo=not args.quiet,
    )
    import_results.append(
        {
            "phase": "bootstrap",
            "exit_code": bootstrap_result.exit_code,
            "duration_seconds": round(bootstrap_result.duration_seconds, 3),
            "timed_out": bootstrap_result.timed_out,
            "unexpected_errors": [],
        }
    )
    if bootstrap_result.exit_code != 0:
        print(
            "Project bootstrap import failed with exit code "
            f"{bootstrap_result.exit_code}.",
            flush=True,
        )
        if args.report_json:
            write_json_report(
                args.report_json,
                suite=args.suite,
                import_results=import_results,
                scene_results=[],
                total_duration_seconds=time.monotonic() - started,
            )
        return bootstrap_result.exit_code

    print("Validating a second clean project import...", flush=True)
    validation_result = run_command(
        [godot, "--headless", "--editor", "--path", ".", "--quit"],
        project_root,
        args.import_timeout,
        echo=not args.quiet,
    )
    validation_errors = find_unexpected_errors(
        validation_result.output,
        allow_missing_godot_ai=True,
    )
    import_results.append(
        {
            "phase": "validation",
            "exit_code": validation_result.exit_code,
            "duration_seconds": round(validation_result.duration_seconds, 3),
            "timed_out": validation_result.timed_out,
            "unexpected_errors": validation_errors,
        }
    )
    if validation_result.exit_code != 0 or validation_errors:
        print("Project validation import failed strict log checks.", flush=True)
        for error in validation_errors:
            print(f"- {error}", flush=True)
        if args.report_json:
            write_json_report(
                args.report_json,
                suite=args.suite,
                import_results=import_results,
                scene_results=[],
                total_duration_seconds=time.monotonic() - started,
            )
        return 1

    scene_results: list[SceneResult] = []
    for spec in selected_specs:
        print(
            f"Running {spec.scene} "
            f"(suite={spec.suite}, mode={spec.mode})...",
            flush=True,
        )
        command_args = test_args_for_mode(spec.mode)
        if command_args is None:
            scene_result = SceneResult(
                scene=spec.scene,
                suite=spec.suite,
                mode=spec.mode,
                status="failed",
                exit_code=1,
                duration_seconds=0.0,
                timed_out=False,
                failure_reasons=["display_environment_unavailable"],
            )
        else:
            command_result = run_command(
                [godot, *command_args, spec.scene],
                project_root,
                args.test_timeout,
                echo=not args.quiet,
            )
            scene_result = evaluate_scene_result(spec, command_result)

        scene_results.append(scene_result)
        if scene_result.status == "passed":
            print(
                f"PASSED {spec.scene} in "
                f"{scene_result.duration_seconds:.3f}s.",
                flush=True,
            )
            continue

        print(
            f"FAILED {spec.scene}: "
            f"{', '.join(scene_result.failure_reasons)}.",
            flush=True,
        )
        for marker in scene_result.missing_markers:
            print(f"- Missing marker: {marker}", flush=True)
        for error in scene_result.unexpected_errors:
            print(f"- Unexpected error: {error}", flush=True)

    total_duration = time.monotonic() - started
    append_github_summary(args.suite, scene_results, total_duration)
    if args.report_json:
        write_json_report(
            args.report_json,
            suite=args.suite,
            import_results=import_results,
            scene_results=scene_results,
            total_duration_seconds=total_duration,
        )
        print(f"JSON report: {args.report_json}", flush=True)

    failed_results = [
        result for result in scene_results if result.status == "failed"
    ]
    print(
        "Summary: "
        f"{len(scene_results) - len(failed_results)} passed, "
        f"{len(failed_results)} failed, "
        f"{total_duration:.3f}s total.",
        flush=True,
    )
    if failed_results:
        return 1

    print("All selected Godot tests passed.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
