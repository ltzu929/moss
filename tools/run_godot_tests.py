import argparse
import os
import platform
from pathlib import Path
import shutil
import subprocess
import sys


DEFAULT_IMPORT_TIMEOUT_SECONDS = 180
DEFAULT_TEST_TIMEOUT_SECONDS = 90


TEST_SCENES = [
    ("tests/project_hygiene_test.tscn", "headless"),
    ("tests/project_conventions_test.tscn", "headless"),
    ("tests/resource_isolation_test.tscn", "headless"),
    ("tests/development_log_test.tscn", "headless"),
    ("tests/technology_system_test.tscn", "headless"),
    ("tests/command_system_test.tscn", "headless"),
    ("tests/time_system_test.tscn", "headless"),
    ("tests/event_state_test.tscn", "headless"),
    ("tests/event_playability_test.tscn", "headless"),
    ("tests/decision_history_test.tscn", "display"),
    ("tests/mid_event_resource_test.tscn", "headless"),
    ("tests/technology_gameplay_test.tscn", "headless"),
    ("tests/technology_ending_test.tscn", "headless"),
    ("tests/technology_ui_test.tscn", "display"),
    ("tests/world_map_view_test.tscn", "headless"),
    ("tests/test_runner.tscn", "headless"),
]


def find_godot(godot_arg):
    if godot_arg:
        return godot_arg

    godot_bin = os.environ.get("GODOT_BIN")
    if godot_bin:
        return godot_bin

    for command_name in ("godot", "godot4"):
        if shutil.which(command_name):
            return command_name

    return None


def run_godot(godot, args, project_root, timeout_seconds):
    command = [godot, *args]
    try:
        return subprocess.run(
            command,
            cwd=project_root,
            timeout=timeout_seconds,
        ).returncode
    except subprocess.TimeoutExpired:
        print(
            f"Godot command timed out after {timeout_seconds}s: {' '.join(command)}",
            file=sys.stderr,
            flush=True,
        )
        return 124
    except FileNotFoundError:
        print(f"Godot executable not found: {godot}", file=sys.stderr, flush=True)
        return 127


def test_args_for_mode(mode):
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
            "--audio-driver",
            "Dummy",
            "--resolution",
            "1920x1080",
            "--path",
            ".",
        ]

    return ["--audio-driver", "Dummy", "--resolution", "1920x1080", "--path", "."]


def main():
    parser = argparse.ArgumentParser(description="Run all Godot tests.")
    parser.add_argument("--godot", help="Path to Godot executable")
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
    args = parser.parse_args()
    if args.import_timeout <= 0 or args.test_timeout <= 0:
        parser.error("Timeout values must be positive integers.")

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

    print(f"Using Godot: {godot}", flush=True)

    print("Importing project...", flush=True)
    exit_code = run_godot(
        godot,
        ["--headless", "--editor", "--path", ".", "--quit"],
        project_root,
        args.import_timeout,
    )
    if exit_code != 0:
        print(f"Project import failed with exit code {exit_code}.", flush=True)
        return exit_code

    failed = []
    for scene, mode in TEST_SCENES:
        print(f"Running {scene} ({mode})...", flush=True)
        command_args = test_args_for_mode(mode)
        if command_args is None:
            failed.append((scene, 1))
            continue
        exit_code = run_godot(
            godot,
            [*command_args, scene],
            project_root,
            args.test_timeout,
        )
        if exit_code != 0:
            print(f"FAILED {scene} with exit code {exit_code}.", flush=True)
            failed.append((scene, exit_code))
        else:
            print(f"PASSED {scene} with exit code 0.", flush=True)

    if failed:
        print("Godot tests failed:", flush=True)
        for scene, code in failed:
            print(f"- {scene}: exit code {code}", flush=True)
        return 1

    print("All Godot tests passed.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
