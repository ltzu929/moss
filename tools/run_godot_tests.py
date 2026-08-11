"""CLI orchestration for the registered Godot test scenes.

The stable implementation lives in four focused modules.  The imports below
intentionally preserve the historical ``tools.run_godot_tests`` API for local
callers and CI while the CLI remains the project-facing entry point.
"""

import argparse
import os
from pathlib import Path
import platform
import sys
import time
from typing import Sequence


if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


from tools.godot_process import (  # noqa: E402
    DEFAULT_MEMORY_LIMIT_MB,
    CommandResult,
    _WindowsProcessMemoryCountersEx,
    _read_process_memory_bytes,
    _stream_reader,
    find_godot,
    run_command,
)
from tools.godot_test_catalog import (  # noqa: E402
    TEST_SPECS,
    VALID_SUITES,
    TestSpec,
    select_test_specs,
    test_args_for_mode as _test_args_for_mode,
)
from tools.godot_test_evaluator import (  # noqa: E402
    ANSI_ESCAPE_RE,
    KNOWN_GODOT_AI_ERROR_FRAGMENTS,
    SceneResult,
    build_import_result,
    evaluate_scene_result,
    find_unexpected_errors,
    import_result_failed,
    is_known_godot_ai_error,
    _normalized_log_line,
)
from tools.godot_test_reporter import (  # noqa: E402
    append_github_summary,
    write_json_report,
)


DEFAULT_IMPORT_TIMEOUT_SECONDS = 180
DEFAULT_TEST_TIMEOUT_SECONDS = 90


def test_args_for_mode(mode: str) -> list[str] | None:
    """Compatibility wrapper retaining the old patchable module globals."""
    return _test_args_for_mode(
        mode,
        system_name=platform.system(),
        display_available=bool(os.environ.get("DISPLAY")),
    )


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
    import_results.append(build_import_result("bootstrap", bootstrap_result))
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
        build_import_result(
            "validation",
            validation_result,
            unexpected_errors=validation_errors,
        )
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
