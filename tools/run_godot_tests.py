import argparse
import ctypes
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
DEFAULT_MEMORY_LIMIT_MB = 4096
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
    memory_limit_exceeded: bool = False
    peak_memory_bytes: int = 0


@dataclass
class SceneResult:
    scene: str
    suite: str
    mode: str
    status: str
    exit_code: int
    duration_seconds: float
    timed_out: bool
    memory_limit_exceeded: bool = False
    peak_memory_mb: float = 0.0
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


class _WindowsProcessMemoryCountersEx(ctypes.Structure):
    _fields_ = [
        ("cb", ctypes.c_ulong),
        ("page_fault_count", ctypes.c_ulong),
        ("peak_working_set_size", ctypes.c_size_t),
        ("working_set_size", ctypes.c_size_t),
        ("quota_peak_paged_pool_usage", ctypes.c_size_t),
        ("quota_paged_pool_usage", ctypes.c_size_t),
        ("quota_peak_non_paged_pool_usage", ctypes.c_size_t),
        ("quota_non_paged_pool_usage", ctypes.c_size_t),
        ("pagefile_usage", ctypes.c_size_t),
        ("peak_pagefile_usage", ctypes.c_size_t),
        ("private_usage", ctypes.c_size_t),
    ]


def _read_process_memory_bytes(process: subprocess.Popen[str]) -> int:
    if process.poll() is not None:
        return 0

    system_name = platform.system()
    if system_name == "Windows":
        process_handle = getattr(process, "_handle", None)
        if process_handle is None:
            return 0
        counters = _WindowsProcessMemoryCountersEx()
        counters.cb = ctypes.sizeof(counters)
        get_process_memory_info = ctypes.windll.psapi.GetProcessMemoryInfo
        succeeded = get_process_memory_info(
            ctypes.c_void_p(int(process_handle)),
            ctypes.byref(counters),
            counters.cb,
        )
        return int(counters.private_usage) if succeeded else 0

    if system_name == "Linux":
        try:
            status = Path(f"/proc/{process.pid}/status").read_text(
                encoding="utf-8"
            )
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            return 0
        for line in status.splitlines():
            if line.startswith("VmRSS:"):
                return int(line.split()[1]) * 1024

    return 0


def run_command(
    command: Sequence[str],
    project_root: Path,
    timeout_seconds: int | float,
    *,
    echo: bool = True,
    memory_limit_mb: int = DEFAULT_MEMORY_LIMIT_MB,
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
    memory_limit_exceeded = False
    peak_memory_bytes = 0
    memory_limit_bytes = memory_limit_mb * 1024 * 1024
    while process.poll() is None or not stream_finished:
        elapsed = time.monotonic() - started
        if process.poll() is None and not memory_limit_exceeded:
            memory_bytes = _read_process_memory_bytes(process)
            peak_memory_bytes = max(peak_memory_bytes, memory_bytes)
            if (
                memory_limit_bytes > 0
                and memory_bytes > memory_limit_bytes
            ):
                memory_limit_exceeded = True
                process.kill()
        if (
            process.poll() is None
            and not memory_limit_exceeded
            and elapsed > timeout_seconds
        ):
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
    elif memory_limit_exceeded:
        exit_code = 125
        peak_memory_mb = peak_memory_bytes / (1024 * 1024)
        memory_message = (
            f"Command exceeded memory limit of {memory_limit_mb} MiB "
            f"(peak {peak_memory_mb:.1f} MiB): {' '.join(command)}"
        )
        output_lines.append(memory_message + "\n")
        if echo:
            print(memory_message, file=sys.stderr, flush=True)

    return CommandResult(
        exit_code=exit_code,
        output="".join(output_lines),
        duration_seconds=duration,
        timed_out=timed_out,
        memory_limit_exceeded=memory_limit_exceeded,
        peak_memory_bytes=peak_memory_bytes,
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
    if command_result.memory_limit_exceeded:
        failure_reasons.append("memory_limit_exceeded")
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
        memory_limit_exceeded=command_result.memory_limit_exceeded,
        peak_memory_mb=round(
            command_result.peak_memory_bytes / (1024 * 1024),
            1,
        ),
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
        and not result.get("memory_limit_exceeded", False)
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
    import_results: list[dict],
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
        "#### Import phases",
        "",
        "| Phase | Status | Duration | Peak memory |",
        "| --- | --- | ---: | ---: |",
    ]
    for result in import_results:
        import_failed = (
            result.get("exit_code", 1) != 0
            or result.get("timed_out", False)
            or result.get("memory_limit_exceeded", False)
            or bool(result.get("unexpected_errors", []))
        )
        status = "failed" if import_failed else "passed"
        lines.append(
            f"| `{result.get('phase', 'unknown')}` | {status} | "
            f"{float(result.get('duration_seconds', 0.0)):.3f}s | "
            f"{float(result.get('peak_memory_mb', 0.0)):.1f} MiB |"
        )
    lines.extend([
        "",
        "#### Test scenes",
        "",
        "| Scene | Mode | Status | Duration | Peak memory |",
        "| --- | --- | --- | ---: | ---: |",
    ])
    for result in scene_results:
        lines.append(
            f"| `{result.scene}` | {result.mode} | {result.status} | "
            f"{result.duration_seconds:.3f}s | {result.peak_memory_mb:.1f} MiB |"
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
    parser.add_argument(
        "--memory-limit-mb",
        type=int,
        default=DEFAULT_MEMORY_LIMIT_MB,
        help=(
            "Per-process memory limit in MiB; 0 disables the guard "
            "(default: 4096)"
        ),
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.import_timeout <= 0 or args.test_timeout <= 0:
        parser.error("Timeout values must be positive integers.")
    if args.memory_limit_mb < 0:
        parser.error("Memory limit must be zero or a positive integer.")

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
    if args.memory_limit_mb > 0:
        print(
            f"Per-process memory limit: {args.memory_limit_mb} MiB",
            flush=True,
        )

    import_results: list[dict] = []
    print("Bootstrapping project import cache...", flush=True)
    bootstrap_result = run_command(
        [godot, "--headless", "--editor", "--path", ".", "--quit"],
        project_root,
        args.import_timeout,
        echo=not args.quiet,
        memory_limit_mb=args.memory_limit_mb,
    )
    import_results.append(
        {
            "phase": "bootstrap",
            "exit_code": bootstrap_result.exit_code,
            "duration_seconds": round(bootstrap_result.duration_seconds, 3),
            "timed_out": bootstrap_result.timed_out,
            "memory_limit_exceeded": (
                bootstrap_result.memory_limit_exceeded
            ),
            "peak_memory_mb": round(
                bootstrap_result.peak_memory_bytes / (1024 * 1024),
                1,
            ),
            "unexpected_errors": [],
        }
    )
    if bootstrap_result.exit_code != 0:
        print(
            "Project bootstrap import failed with exit code "
            f"{bootstrap_result.exit_code}.",
            flush=True,
        )
        bootstrap_duration = time.monotonic() - started
        append_github_summary(
            args.suite,
            import_results,
            [],
            bootstrap_duration,
        )
        if args.report_json:
            write_json_report(
                args.report_json,
                suite=args.suite,
                import_results=import_results,
                scene_results=[],
                total_duration_seconds=bootstrap_duration,
            )
        return bootstrap_result.exit_code

    print("Validating a second clean project import...", flush=True)
    validation_result = run_command(
        [godot, "--headless", "--editor", "--path", ".", "--quit"],
        project_root,
        args.import_timeout,
        echo=not args.quiet,
        memory_limit_mb=args.memory_limit_mb,
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
            "memory_limit_exceeded": (
                validation_result.memory_limit_exceeded
            ),
            "peak_memory_mb": round(
                validation_result.peak_memory_bytes / (1024 * 1024),
                1,
            ),
            "unexpected_errors": validation_errors,
        }
    )
    if validation_result.exit_code != 0 or validation_errors:
        print("Project validation import failed strict log checks.", flush=True)
        for error in validation_errors:
            print(f"- {error}", flush=True)
        validation_duration = time.monotonic() - started
        append_github_summary(
            args.suite,
            import_results,
            [],
            validation_duration,
        )
        if args.report_json:
            write_json_report(
                args.report_json,
                suite=args.suite,
                import_results=import_results,
                scene_results=[],
                total_duration_seconds=validation_duration,
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
                memory_limit_mb=args.memory_limit_mb,
            )
            scene_result = evaluate_scene_result(spec, command_result)

        scene_results.append(scene_result)
        if scene_result.status == "passed":
            print(
                f"PASSED {spec.scene} in "
                f"{scene_result.duration_seconds:.3f}s "
                f"(peak {scene_result.peak_memory_mb:.1f} MiB).",
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
    append_github_summary(
        args.suite,
        import_results,
        scene_results,
        total_duration,
    )
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
